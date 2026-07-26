#!/usr/bin/env python3

# Script to batch-mint Soccerverse vouchers (SVV) to a list of addresses
# or names (which will be resolved to their owners as addresses first).
#
# The script keeps track of the current "state" in an SQLite database,
# so that it can resume operations if crashed or interrupted half-way through
# the batch, and thus can work fine also for very large numbers of addresses,
# such as for the SVV airdrop.
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
  their transaction status.
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

    with open ("PackVoucher.json", "rt") as f:
      data = json.load (f)
    self.voucher = self.w3.eth.contract (address=config.PACK_VOUCHER,
                                         abi=data["abi"])
    self.log.info ("Using PackVoucher at %s" % self.voucher.address)
    self.decimals = self.voucher.functions.decimals ().call ()

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
    # Check that we are LIMITED_MINTER_ROLE on the voucher contract
    # or TOKEN_ADMIN_ROLE.
    roles = [
      self.voucher.functions.LIMITED_MINTER_ROLE ().call (),
      self.voucher.functions.TOKEN_ADMIN_ROLE ().call (),
    ]
    ok = False
    for r in roles:
      if self.voucher.functions.hasRole (r, self.acc.address).call ():
        ok = True
    if not ok:
      raise RuntimeError ("Worker address has no minting role")

    remaining = self.voucher.functions.mintLimitRemaining ().call ()
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

  def execute (self, state):
    # Go through all mints in the database.  Those that don't yet have a txid
    # are to be done.  For those that have one, try to wait for the transaction
    # to get it confirmed (if pending), and check if it succeeded or failed.
    self.log.info ("Checking status of outstanding mints...")
    allMints = state.fetchMints ()
    todo = []
    failed = set ()
    success = set ()
    for m in allMints:
      if m["txid"] is None:
        todo.append (m)
      elif m["txid"] in failed:
        todo.append (m)
      elif m["txid"] in success:
        pass
      else:
        self.log.debug (f"Checking tx {m['txid']}...")
        receipt = self.w3.eth.wait_for_transaction_receipt (m["txid"])
        if receipt["status"] == 1:
          success.add (m["txid"])
        else:
          failed.add (m["txid"])
          self.log.warning ("Transaction %s reverted, retrying" % m["txid"])
          state.removeTxid (m["txid"])
          todo.append (m)
    state.commit ()

    # For those that are to be done, execute them batch by batch.
    self.log.info ("%d mints need to be executed" % len (todo))
    while todo:
      cur = todo[:config.BATCH_SIZE]
      todo = todo[config.BATCH_SIZE:]

      ops = [
        {"to": m["address"], "amount": 10**self.decimals * m["amount"]}
        for m in cur
      ]
      tx = self.signTx (self.voucher.functions.batchMint (ops))
      txid = tx["hash"].hex ()

      for m in cur:
        state.setTxid (m["id"], txid)
      state.commit ()
      self.w3.eth.send_raw_transaction (tx.raw_transaction)
      self.nonce += 1
      self.log.info ("  sent %s" % txid)
      receipt = self.w3.eth.wait_for_transaction_receipt (txid)
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
