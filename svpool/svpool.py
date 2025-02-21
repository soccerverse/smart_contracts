#!/usr/bin/env python3
# Copyright (C) 2023-2024 Soccerverse Ltd

"""
This is a Python script for running the trading-pool bot for Democrit
on Soccerverse.
"""

import poolbot

from eth_account import Account
from web3 import Web3

import argparse
import json
import logging
import os
import sys
import time


class Checker (poolbot.VaultChecker):
  """
  VaultChecker instance used for Soccerverse.
  """

  def __init__ (self, endpoint):
    super ().__init__ (endpoint)

  def check (self, controller, vaultId):
    with self.withRpc () as rpc:
      data = rpc.get_vaults (controller=controller, ids=[vaultId])
      # Note that there is no need to verify the GSP being up-to-date,
      # since the checkpoint will ensure that the signed check is only
      # valid on the right chain history.  As long as the GSP does not
      # implement wrong rules, nothing else can go wrong here.
      [vault] = data["data"]
      if vault["exists"]:
        return True, vault["checkpoint"]
      return False, None

  def getGspState (self):
    with self.withRpc () as rpc:
      return rpc.getnullstate ()


def getLoadAbi (forgeOut):
  """
  Helper function to construct the closure for loading ABIs for the
  poolbot.  It accepts the base directory where Forge puts the build
  artefacts ("out") as argument.
  """

  def loadAbi (nm):
    filename = os.path.join (forgeOut, f"{nm}.sol", f"{nm}.json")
    with open (filename, "rt") as f:
      data = json.load (f)
    return data["abi"]

  return loadAbi


if __name__ == "__main__":
  desc = "Runs a JSON-RPC server for signing Soccerverse Democrit vaults"
  parser = argparse.ArgumentParser (description=desc)
  parser.add_argument ("--port", required=True, type=int,
                       help="Port to listen on for JSON-RPC connections")
  parser.add_argument ("--host", default="0.0.0.0",
                       help="Host to listen on for JSON-RPC connections")
  parser.add_argument ("--eth_rpc_url", required=True,
                       help="URL for the EVM JSON-RPC interface to use")
  parser.add_argument ("--gsp_rpc_url", required=True,
                       help="URL for the Soccerverse JSON-RPC interface to use")
  parser.add_argument ("--democrit_address", required=True,
                       help="The Democrit contract address to use")
  parser.add_argument ("--operator", required=True,
                       help="The pool operator's account name")
  parser.add_argument ("--forgeout", required=True,
                       help="Path to Forge's 'out' directory with ABIs")
  args = parser.parse_args ()

  logging.basicConfig (stream=sys.stderr, level=logging.INFO)
  log = logging.getLogger ("")

  key = os.getenv ("PRIVKEY")
  if key is None:
    raise RuntimeError (
        "private key must be specified in the PRIVKEY environment variable")
  acc = Account.from_key (key)
  log.info ("Using address %s to sign for pool %s"
              % (acc.address, args.operator))

  w3 = Web3 (Web3.HTTPProvider (args.eth_rpc_url))
  log.info ("Connected to chain %d" % w3.eth.chain_id)
  log.info ("Signing for Democrit contract at %s" % args.democrit_address)

  checker = Checker (args.gsp_rpc_url)
  state = checker.getGspState ()
  log.info ("GSP is %s at block %d on chain %s"
              % (state["state"], state["height"], state["chain"]))

  signer = poolbot.Signer (w3, getLoadAbi (args.forgeout),
                           args.democrit_address, args.operator, key)
  srv = poolbot.VaultCheckServer (checker, signer)

  with srv.run ((args.host, args.port)):
    while True:
      time.sleep (0.1)
