#!/usr/bin/env python3
# Copyright (C) 2024 Soccerverse Ltd

"""
This script configures the clubs associated with the PackSale contracts
based on a CSV file that ties club IDs to tiers.  The contracts for each tier
are auto-detected based on the authorised minters in the ClubMinter.
"""

from eth_account import Account
from web3 import Web3

import argparse
import csv
import json
import logging
import os
import os.path
import sys


# Specify the expected tier names in the contracts and the associated
# value of the "tier" column in CSV.
tiers = {
  "tier 1": 1,
  "tier 2": 2,
  "tier 3": 3,
  "tier 4": 4,
  "tier 5": 5,
}


def loadAbi (nm):
  baseDir = os.path.dirname (os.path.abspath (__file__))
  abiDir = os.path.join (baseDir, "out", f"{nm}.sol")
  abiFile = os.path.join (abiDir, f"{nm}.json")
  with open (abiFile, "rt") as f:
    data = json.load (f)
  return data["abi"]


class TxSender:
  """
  Helper class for sending transactions with our admin account.
  """

  def __init__ (self, log, w3, key, gasConfig):
    self.log = log
    self.w3 = w3
    self.acc = Account.from_key (key)
    self.gasConfig = gasConfig

    # We take care of incrementing the original nonce ourselves, to ensure
    # we don't run into issues with the RPC endpoint not updating immediately
    # after a transaction is confirmed.
    self.nonce = w3.eth.get_transaction_count (self.acc.address)

  def sendTransaction (self, call):
    gas = call.estimate_gas ({"from": self.acc.address})
    tx = call.build_transaction ({
      "chainId": self.w3.eth.chain_id,
      "gas": gas,
      "type": 2,
      "maxFeePerGas": w3.to_wei (self.gasConfig["max"], "gwei"),
      "maxPriorityFeePerGas": w3.to_wei (self.gasConfig["prio"], "gwei"),
      "nonce": self.nonce,
    })
    self.nonce += 1

    signed = self.acc.sign_transaction (tx)
    txid = self.w3.eth.send_raw_transaction (signed.rawTransaction)
    self.log.info ("  sending %s..." % txid.hex ())
    self.w3.eth.wait_for_transaction_receipt (txid)


class PackSaleConfigurator:
  """
  This class implements the logic to configure a PackSale instance.
  """

  def __init__ (self, log, w3, addr, sender):
    self.log = log
    self.w3 = w3
    self.sender = sender

    self.packSale = w3.eth.contract (address=addr, abi=loadAbi ("PackSale"))

    self.tierName = self.packSale.functions.tier ().call ()
    self.log.info ("Using PackSale contract at %s for '%s'"
                      % (self.packSale.address, self.tierName))
    if not self.tierName in tiers:
      log.fatal ("Unexpected tier name: '%s'" % self.tierName)
      sys.exit ()
    self.tierValue = str (tiers[self.tierName])

    self.allClubs = set (self.packSale.functions.getAllClubs ().call ())

    role = self.packSale.functions.CONFIGURE_ROLE ().call ()
    addr = self.sender.acc.address
    if not self.packSale.functions.hasRole (role, addr).call ():
      log.fatal ("Private key for %s does not have CONFIGURE_ROLE %s" % addr)
      sys.exit ()

    if not self.packSale.functions.paused ().call ():
      log.fatal ("PackSale contract is not paused")
      sys.exit ()

  def removeClubs (self, clubs):
    """
    Removes all clubs from the given list that are currently on this contract.
    """

    for c in clubs:
      if c in self.allClubs:
        log.info ("Removing club %d from '%s'..." % (c, self.tierName))
        self.sender.sendTransaction (self.packSale.functions.removeClub (c))

    self.allClubs = self.packSale.functions.getAllClubs ().call ()

  def addClubs (self, clubs, batchSize):
    """
    Adds all clubs from the given list to the contract.
    """

    toAdd = []
    for c in clubs:
      if c not in self.allClubs:
        toAdd.append (c)

    if len (toAdd) > 0:
      self.log.info ("Adding %d clubs to '%s'..."
                        % (len (toAdd), self.tierName))

      while len (toAdd) > 0:
        batch = toAdd[:batchSize]
        self.sender.sendTransaction (self.packSale.functions.addClubs (batch))
        toAdd = toAdd[batchSize:]

    self.allClubs = self.packSale.functions.getAllClubs ().call ()


if __name__ == "__main__":
  desc = "Initialises the PackSale contracts from a CSV"
  parser = argparse.ArgumentParser (description=desc)
  parser.add_argument ("--eth_rpc_url", required=True,
                       help="URL for the EVM JSON-RPC interface to use")
  parser.add_argument ("--clubminter", required=True,
                       help="The ClubMinter contract address to use")
  parser.add_argument ("--clubcsv", required=True,
                       help="CSV file with club data (mapping to tiers)")
  parser.add_argument ("--addbatchsize", type=int, default=100,
                       help="Number of clubs to add in one transaction")
  parser.add_argument ("--gasprice", type=int, default=150,
                       help="Total gas price in GWei to use")
  parser.add_argument ("--priogas", type=int, default=31,
                       help="Maximum priority gas in GWei to use")
  args = parser.parse_args ()

  logging.basicConfig (stream=sys.stderr, level=logging.INFO)
  log = logging.getLogger ("")

  key = os.getenv ("PRIVKEY")
  if key is None:
    raise RuntimeError (
        "private key must be specified in the PRIVKEY environment variable")

  w3 = Web3 (Web3.HTTPProvider (args.eth_rpc_url))
  log.info ("Connected to chain %d" % w3.eth.chain_id)

  gasConfig = {"max": args.gasprice, "prio": args.priogas}
  sender = TxSender (log, w3, key, gasConfig)

  # Start by detecting the sales contracts from the minter.
  minter = w3.eth.contract (address=args.clubminter, abi=loadAbi ("ClubMinter"))
  minterRole = minter.functions.MINTER_ROLE ().call ()
  numMinters = minter.functions.getRoleMemberCount (minterRole).call ()
  if numMinters != len (tiers):
    log.fatal ("Mismatch between tiers and all authorised minters")
    sys.exit ()
  allMinters = [
    minter.functions.getRoleMember (minterRole, i).call ()
    for i in range (0, numMinters)
  ]

  salesContracts = {}
  tierValueToName = {}
  for m in allMinters:
    config = PackSaleConfigurator (log, w3, m, sender)
    if config.tierName in salesContracts:
      log.fatal ("Tier name '%s' is duplicated among minters" % config.tierName)
      sys.exit ()
    salesContracts[config.tierName] = config
    tierValueToName[config.tierValue] = config.tierName
  assert len (salesContracts) == len (tiers)

  # Read the list of all clubs and associated tiers.
  clubsForTier = {}
  allClubs = set ()
  with open (args.clubcsv, newline="") as csvfile:
    reader = csv.DictReader (csvfile)
    for row in reader:
      clubId = int (row["club_id"])
      if clubId in allClubs:
        log.fatal ("Duplicated club: %d" % clubId)
        sys.exit ()
      allClubs.add (clubId)
      tierValue = str (row["tier"])
      tierName = tierValueToName[tierValue]
      if tierName not in clubsForTier:
        clubsForTier[tierName] = set ()
      clubsForTier[tierName].add (clubId)

  # Process all the clubs and tiers.
  for tierName, clubs in clubsForTier.items ():
    log.info ("Tier '%s' has %d clubs" % (tierName, len (clubs)))
    for t, c in salesContracts.items ():
      if t != tierName:
        c.removeClubs (clubs)
    salesContracts[tierName].addClubs (clubs, args.addbatchsize)
