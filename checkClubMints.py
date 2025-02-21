#!/usr/bin/env python3
# Copyright (C) 2024 Soccerverse Ltd

"""
This script queries for minted club influence in the ClubMinter
and also from the GSP, and checks that they match.
"""

import jsonrpclib
from web3 import Web3

import argparse
import json
import logging
import os.path
import sys

################################################################################

class MintBalanceChecker:
  """
  Worker class to handle the checking.
  """

  def __init__ (self, rpcUrl, gspUrl, clubMinter):
    logging.basicConfig (stream=sys.stderr, level=logging.INFO)
    self.log = logging.getLogger ("")

    self.w3 = Web3 (Web3.HTTPProvider (args.eth_rpc_url))
    self.log.info ("Connected to chain %d" % self.w3.eth.chain_id)

    self.gsp = jsonrpclib.ServerProxy (gspUrl)

    self.minter = self.getContract ("ClubMinter", clubMinter)
    self.log.info ("Using ClubMinter at %s" % self.minter.address)

  def getContract (self, nm, addr):
    """
    Loads an ABI file and instantiates the contract instance
    for this ABI and the given address.
    """

    baseDir = os.path.dirname (os.path.abspath (__file__))
    abiDir = os.path.join (baseDir, "out", f"{nm}.sol")
    abiFile = os.path.join (abiDir, f"{nm}.json")
    with open (abiFile, "rt") as f:
      data = json.load (f)

    return self.w3.eth.contract (abi=data["abi"], address=addr)

  def checkClub (self, clubId):
    """
    Checks balances for one club.
    """

    minted = self.minter.functions.sharesMinted (clubId).call ()

    balances = self.gsp.get_share_owners (share={"club": clubId})["data"]
    gspTotal = 0
    for b in balances:
      gspTotal += b["num"]

    if minted != gspTotal:
      self.log.error ("Club %d: minted %d vs %d in GSP"
                        % (clubId, minted, gspTotal))
    else:
      self.log.debug ("Club %d: minted %d" % (clubId, minted))

  def checkAll (self):
    """
    Checks all clubs.
    """

    allClubs = self.gsp.get_club_ids ()["data"]
    for c in allClubs:
      self.checkClub (c["club_id"])
    self.log.info ("Checked %d clubs" % len (allClubs))

################################################################################

if __name__ == "__main__":
  desc = "Checks minted club influence between contract and GSP"
  parser = argparse.ArgumentParser (description=desc)
  parser.add_argument ("--eth_rpc_url", default="https://polygon-rpc.com",
                       help="URL for the EVM JSON-RPC interface to use")
  parser.add_argument ("--gsp_rpc_url",
                       default="https://services.soccerverse.com/gsp",
                       help="URL for the GSP JSON-RPC interface to use")
  parser.add_argument ("--club_minter",
                       default="0xeEE0d855112b71Dc68d72053594Af03F92C586Ae",
                       help="Contract address of the ClubMinter")
  args = parser.parse_args ()

  checker = MintBalanceChecker (args.eth_rpc_url, args.gsp_rpc_url,
                                args.club_minter)
  checker.checkAll ()
