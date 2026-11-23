#!/usr/bin/env python3

# Script to batch-mint Soccerverse vouchers (SVV) to a list of addresses
# or names (which will be resolved to their owners as addresses first).
#
# The script keeps track of the current "state" in an SQLite database,
# so that it can resume operations if crashed or interrupted half-way through
# the batch, and thus can work fine also for very large numbers of addresses,
# such as for the SVV airdrop.
#
# Each transaction is tracked as a batch in the state database.  A batch is
# recorded as "unknown" before it is sent, and only marked "broadcast" once
# the node accepted it.  If the script is interrupted in between, a restart
# re-broadcasts the exact same signed transaction (same hash and nonce), so
# it can never issue a second mint.
#
# The recommended way to use this script is to first build up the database
# (state) of what to mint, with calls like this:
#
#   vouchers.py --state state.sqlite --addresses addr.txt --amount 10
#   vouchers.py --state state.sqlite --addresses addr2.txt --amount 20
#   vouchers.py --state state.sqlite --names names.txt --amount 10
#
# Afterwards, run the script with --execute (but not anymore adding to the
# batch of mints) to process the database:
#
#   vouchers.py --state state.sqlite --execute

import config
from minter import Web3Base

import web3
from web3.exceptions import (
  TimeExhausted,
  TransactionIndexingInProgress,
  TransactionNotFound,
)
from w3multicall.multicall import W3Multicall

import argparse
from contextlib import contextmanager
import csv
from decimal import Decimal
import json
import logging
import sqlite3
import sys

################################################################################

class State:
  """
  Wrapper around the state database that keeps track of planned mints and
  the submission status of their batches.
  """

  def __init__ (self, db, filename):
    self.log = logging.getLogger ()
    self.log.info ("Using state database file %s" % filename)

    self.db = db
    self.cur = self.db.cursor ()

    self.cur.execute ("""
      CREATE TABLE IF NOT EXISTS `mints` (
        `id` INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        `address` TEXT NOT NULL,
        `amount` INTEGER NOT NULL,
        `txid` TEXT NULL
      )
    """)
    self.cur.execute ("""
      CREATE INDEX IF NOT EXISTS `mints_by_txid`
          ON `mints` (`txid`, `id`);
    """)
    self.cur.execute ("""
      CREATE TABLE IF NOT EXISTS `batches` (
        `txid` TEXT NOT NULL PRIMARY KEY,
        `nonce` INTEGER NOT NULL,
        `raw_tx` TEXT NOT NULL,
        `status` TEXT NOT NULL
      )
    """)
    self.commit ()

  def commit (self):
    self.db.commit ()

  def addMint (self, addr, amount):
    self.cur.execute ("""
      INSERT INTO `mints`
        (`address`, `amount`)
        VALUES (?, ?)
    """, (addr, amount))

  def setTxid (self, rowId, txid):
    self.cur.execute ("""
      UPDATE `mints`
        SET `txid` = ?
        WHERE `id` = ?
    """, (txid, rowId))

  def removeTxid (self, txid):
    self.cur.execute ("""
      UPDATE `mints`
        SET `txid` = NULL
        WHERE `txid` = ?
    """, (txid, ))

  def addBatch (self, txid, nonce, rawTx):
    self.cur.execute ("""
      INSERT INTO `batches`
        (`txid`, `nonce`, `raw_tx`, `status`)
        VALUES (?, ?, ?, 'unknown')
    """, (txid, nonce, rawTx))

  def setBatchStatus (self, txid, status):
    self.cur.execute ("""
      UPDATE `batches`
        SET `status` = ?
        WHERE `txid` = ?
    """, (status, txid))

  def fetchBatches (self):
    res = self.cur.execute ("""
      SELECT `txid`, `nonce`, `raw_tx`, `status`
        FROM `batches`
        ORDER BY `nonce`, `txid`
    """)

    return [
      {"txid": txid, "nonce": nonce, "raw_tx": rawTx, "status": status}
      for (txid, nonce, rawTx, status) in res
    ]

  def fetchMints (self):
    res = self.cur.execute ("""
      SELECT `id`, `address`, `amount`, `txid`
        FROM `mints`
        ORDER BY `id`
    """)

    return [
      {"id": rowId, "address": addr, "amount": amount, "txid": txid}
      for (rowId, addr, amount, txid) in res
    ]

@contextmanager
def openState (filename):
  db = sqlite3.connect (filename)
  try:
    yield State (db, filename)
  finally:
    db.close ()

################################################################################

class VoucherMinter (Web3Base):
  """
  Minter class that handles the minting of SVV vouchers.
  """

  def __init__ (self, rpcUrl):
    super ().__init__ (rpcUrl)

    with open ("SVVMinter.json", "rt") as f:
      data = json.load (f)
    self.minter = self.w3.eth.contract (address=config.SVV_MINTER,
                                        abi=data["abi"])
    self.log.info ("Using SVVMinter at %s" % self.minter.address)

    with open ("PackVoucher.json", "rt") as f:
      data = json.load (f)
    svvAddr = self.minter.functions.svv ().call ()
    voucher = self.w3.eth.contract (address=svvAddr, abi=data["abi"])
    self.log.info ("Using PackVoucher at %s" % voucher.address)
    self.decimals = voucher.functions.decimals ().call ()

    with open ("XayaDelegation.json", "rt") as f:
      data = json.load (f)
    delAddr = self.cm.functions.delegator ().call ()
    delegator = self.w3.eth.contract (address=delAddr, abi=data["abi"])

    with open ("IXayaAccounts.json", "rt") as f:
      data = json.load (f)
    accAddr = delegator.functions.accounts ().call ()
    self.accounts = self.w3.eth.contract (address=accAddr, abi=data["abi"])
    self.log.info ("Using XayaAccounts at %s" % self.accounts.address)

    self.setupAccount ()
    # Check the remaining budget on the SVVMinter contract.
    remaining = self.minter.functions \
        .addressMintLimit (self.acc.address).call ()
    value = Decimal (remaining) / 10**self.decimals
    self.log.info ("Remaining mint capacity: %.2f USD" % value)

  def addAddresses (self, state, filename, amount):
    cnt = 0
    with open (filename, "rt") as f:
      for addr in f:
        addr = addr.strip ()
        if not self.w3.is_address (addr):
          raise RuntimeError ("invalid address: %s" % addr)
        addr = self.w3.to_checksum_address (addr)
        state.addMint (addr, amount)
        cnt += 1
    state.commit ()
    self.log.info ("Scheduled %d addresses from %s" % (cnt, filename))

  def _resolveNames (self, names):
    """
    Resolves a list of names to their owner addresses via on-chain multicall.
    Returns {name: address} for successfully resolved names.
    Non-existent names are omitted from the result (with a warning logged).
    """
    resolved = {}
    multicallBatch = 1000
    for i in range (0, len (names), multicallBatch):
      batch = names[i : i + multicallBatch]
      self.log.info (f"Processing names {i} to {i + len (batch) - 1}...")

      mc = W3Multicall (self.w3)
      for nm in batch:
        mc.add (W3Multicall.Call (self.accounts.address,
                                  "tokenIdForName(string,string)(uint256)",
                                  ["p", nm]))
      tokenIds = mc.call ()

      mc = W3Multicall (self.w3)
      for tid in tokenIds:
        mc.add (W3Multicall.Call (self.accounts.address,
                                  "exists(uint256)(bool)",
                                  tid))
      exists = mc.call ()

      mc = W3Multicall (self.w3)
      name_order = []
      for (nm, tid, ex) in zip (batch, tokenIds, exists):
        if ex:
          mc.add (W3Multicall.Call (self.accounts.address,
                                    "ownerOf(uint256)(address)",
                                    tid))
          name_order.append (nm)
        else:
          self.log.warning (f"Name does not exist: {nm}")
      owners = mc.call ()

      for nm, o in zip (name_order, owners):
        addr = self.w3.to_checksum_address (o)
        resolved[nm] = addr

    return resolved

  def addNames (self, state, filename, amount):
    names = []
    with open (filename, "rt") as f:
      for nm in f:
        names.append (nm.strip ("\n"))

    resolved = self._resolveNames (names)

    for nm in names:
      addr = resolved.get (nm)
      if addr is not None:
        state.addMint (addr, amount)

    state.commit ()
    self.log.info ("Scheduled %d names from %s" % (len (names), filename))

  def addCSV (self, state, filename):
    rows = []
    with open (filename, "rt") as f:
      for row in csv.DictReader (f):
        name = row["name"].strip ()
        amount = int (row["amount"])
        rows.append ((name, amount))

    names = [r[0] for r in rows]
    resolved = self._resolveNames (names)

    cnt = 0
    for name, amount in rows:
      addr = resolved.get (name)
      if addr is not None:
        state.addMint (addr, amount)
        cnt += 1

    state.commit ()
    self.log.info ("Scheduled %d CSV entries from %s" % (cnt, filename))

  def _fetchReceipt (self, txid):
    """
    Returns the receipt for the given transaction, or None if it is not
    available (yet).
    """

    try:
      return self.w3.eth.get_transaction_receipt (txid)
    except (TransactionNotFound, TransactionIndexingInProgress):
      return None

  def _waitReceipt (self, txid):
    """
    Waits for the receipt of a transaction.  If it is still pending after
    the timeout, an error is logged and the exception is re-raised; the
    persisted batch state is left untouched so that reconciliation can
    continue on the next run.
    """

    try:
      return self.w3.eth.wait_for_transaction_receipt (txid)
    except TimeExhausted:
      self.log.error (f"Transaction {txid} is still pending; re-run later "
                      "to continue reconciliation")
      raise

  def _applyReceipt (self, state, txid, receipt):
    """
    Records the outcome of a transaction receipt in the state database.
    A reverted batch has its mints unassigned again, so they can be retried
    safely (a revert mints nothing).
    """

    if receipt["status"] == 1:
      state.setBatchStatus (txid, "confirmed")
    else:
      self.log.warning ("Transaction %s reverted, retrying" % txid)
      state.setBatchStatus (txid, "failed")
      state.removeTxid (txid)
    state.commit ()

  def _reconcileBatches (self, state):
    """
    Resolves all batches whose submission is not yet fully settled.

    In particular, an "unknown" batch may or may not have reached the
    network.  If its receipt is not available, the exact same signed
    transaction is re-broadcast.  Its hash and nonce are unchanged, so this
    can never lead to a second mint.
    """

    for b in state.fetchBatches ():
      txid = b["txid"]
      status = b["status"]

      if status == "confirmed":
        continue
      if status == "failed":
        # The mint rows of a failed batch are already unassigned.
        continue

      if status not in ("unknown", "broadcast"):
        raise RuntimeError (f"Unknown batch status {status} for tx {txid}")
      self.log.debug (f"Checking tx {txid} ({status})...")

      receipt = self._fetchReceipt (txid)
      if receipt is not None:
        self._applyReceipt (state, txid, receipt)
        continue

      self.log.info (f"Re-broadcasting {status} tx {txid}")
      try:
        self.w3.eth.send_raw_transaction (bytes.fromhex (b["raw_tx"]))
      except Exception as exc:
        # The transaction may already be known (or even mined).  In that
        # case we simply keep waiting for its receipt.
        self.log.warning (f"Re-broadcast of {txid} failed: {exc}")

      receipt = self._waitReceipt (txid)
      self._applyReceipt (state, txid, receipt)

  def execute (self, state):
    # First resolve all batches that were already recorded but not yet fully
    # settled.  This makes the submission state of interrupted batches
    # explicit and avoids creating a second transaction for them.
    self.log.info ("Reconciling outstanding batches...")
    self._reconcileBatches (state)

    # Now collect all mints that are not assigned to any batch yet.  Mints
    # of confirmed batches keep their txid and are not processed again.
    todo = [m for m in state.fetchMints () if m["txid"] is None]
    self.log.info ("%d mints need to be executed" % len (todo))

    # Reconciliation may have advanced the account nonce, e.g. by confirming
    # re-broadcast transactions.
    self.nonce = self.w3.eth.get_transaction_count (self.acc.address)

    # For those that are to be done, execute them batch by batch.
    while todo:
      cur = todo[:config.BATCH_SIZE]
      todo = todo[config.BATCH_SIZE:]

      ops = [
        {"to": m["address"], "amount": 10**self.decimals * m["amount"]}
        for m in cur
      ]
      tx = self.signTx (self.minter.functions.batchMint (ops))
      txid = tx["hash"].hex ()
      rawTx = tx.raw_transaction

      # Record the batch as explicitly unknown before it is sent.  If we are
      # interrupted from here on, restart will reconcile the exact same
      # signed transaction instead of creating a new mint.
      state.addBatch (txid, self.nonce, rawTx.hex ())
      for m in cur:
        state.setTxid (m["id"], txid)
      state.commit ()

      try:
        self.w3.eth.send_raw_transaction (rawTx)
      except Exception as exc:
        self.log.error (f"Sending batch {txid} failed: {exc}")
        self.log.error ("Its submission state remains unknown; re-run the "
                        "script to reconcile it without minting twice")
        raise

      state.setBatchStatus (txid, "broadcast")
      state.commit ()
      self.nonce += 1
      self.log.info ("  sent %s" % txid)

      receipt = self._waitReceipt (txid)
      self._applyReceipt (state, txid, receipt)
      if receipt["status"] != 1:
        raise RuntimeError ("Transaction %s reverted" % txid)

################################################################################

if __name__ == "__main__":
  parser = argparse.ArgumentParser ()
  parser.add_argument ("--eth_rpc_url", required=True,
                       help="JSON-RPC endpoint for the EVM chain")
  parser.add_argument ("--state", required=True,
                       help="Filename for SQLite database storing state")
  parser.add_argument ("--addresses", required=False,
                       help="File with list of addresses to add to mint")
  parser.add_argument ("--names", required=False,
                       help="File with list of names to add to mint")
  parser.add_argument ("--csv", required=False,
                       help="CSV file with name and amount columns to add to mint")
  parser.add_argument ("--amount", type=int, required=False,
                       help="Amount (in USD equivalent) to mint")
  parser.add_argument ("--execute", action="store_true",
                       help="Execute mint transactions from state")
  args = parser.parse_args ()

  hasAddresses = (args.addresses is not None)
  hasNames = (args.names is not None)
  hasCSV = (args.csv is not None)

  if hasCSV and (hasAddresses or hasNames or args.amount is not None):
    sys.exit ("--csv may not be combined with --addresses, --names, or --amount")
  if (hasAddresses or hasNames) and args.amount is None:
    sys.exit ("--amount must be set if --addresses or --names is set")

  minter = VoucherMinter (args.eth_rpc_url)

  with openState (args.state) as state:
    if hasCSV:
      minter.addCSV (state, args.csv)
    if hasAddresses:
      minter.addAddresses (state, args.addresses, args.amount)
    if hasNames:
      minter.addNames (state, args.names, args.amount)
    if args.execute:
      minter.execute (state)
