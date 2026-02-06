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

import argparse
from contextlib import contextmanager
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
    # Check that we are LIMITED_MINTER_ROLE on the voucher contract.
    role = self.voucher.functions.LIMITED_MINTER_ROLE ().call ()
    if not self.voucher.functions.hasRole (role, self.acc.address).call ():
      raise RuntimeError ("Worker address is not LIMITED_MINTER_ROLE")

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

  def addNames (self, state, filename, amount):
    cnt = 0
    with open (filename, "rt") as f:
      for nm in f:
        nm = nm.strip ("\n")
        tokenId = self.accounts.functions.tokenIdForName ("p", nm).call ()
        try:
          owner = self.accounts.functions.ownerOf (tokenId).call ()
        except web3.exceptions.ContractLogicError:
          raise RuntimeError ("invalid name: %s" % nm)
        state.addMint (owner, amount)
        cnt += 1
    state.commit ()
    self.log.info ("Scheduled %d names from %s" % (cnt, filename))

  def execute (self, state):
    # Go through all mints in the database.  Those that don't yet have a txid
    # are to be done.  For those that have one, try to wait for the transaction
    # to get it confirmed (if pending), and check if it succeeded or failed.
    self.log.info ("Checking status of outstanding mints...")
    allMints = state.fetchMints ()
    todo = []
    failed = set ()
    for m in allMints:
      if m["txid"] is None:
        todo.append (m)
      else:
        receipt = self.w3.eth.wait_for_transaction_receipt (m["txid"])
        if receipt["status"] != 1:
          if m["txid"] not in failed:
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
  parser.add_argument ("--amount", type=int, required=False,
                       help="Amount (in USD equivalent) to mint")
  parser.add_argument ("--execute", action="store_true",
                       help="Execute mint transactions from state")
  args = parser.parse_args ()

  hasAddresses = (args.addresses is not None)
  hasNames = (args.names is not None)
  if (hasAddresses or hasNames) and args.amount is None:
    sys.exit ("--amount must be set if --addresses or --names is set")

  minter = VoucherMinter (args.eth_rpc_url)

  with openState (args.state) as state:
    if hasAddresses:
      minter.addAddresses (state, args.addresses, args.amount)
    if hasNames:
      minter.addNames (state, args.names, args.amount)
    if args.execute:
      minter.execute (state)
