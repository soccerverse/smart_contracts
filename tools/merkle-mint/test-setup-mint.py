#!/usr/bin/env python3

"""
Script to set up a testing environment by deploying a MerkleInfluenceMinter
contract on a forked chain (using Foundry's anvil).
"""

import argparse
import json
import os

from jsonrpclib import ServerProxy
from web3 import Web3
from web3.middleware import ExtraDataToPOAMiddleware

def main ():
  parser = argparse.ArgumentParser (
      description="Deploy MerkleInfluenceMinter for testing")
  parser.add_argument ("--rpc_url", required=True,
                       help="JSON-RPC endpoint of the local blockchain node")
  parser.add_argument ("--club_minter", required=True,
                       help="Address of the deployed ClubMinter contract")
  parser.add_argument ("--root_hash", required=True,
                       help="Root hash of the Merkle tree (hex without 0x)")
  args = parser.parse_args ()

  w3 = Web3 (Web3.HTTPProvider (args.rpc_url))
  w3.middleware_onion.inject (ExtraDataToPOAMiddleware, layer=0)

  rpc = ServerProxy (args.rpc_url)

  abi_path = os.path.join (
      os.path.dirname (__file__),
      "../../out/MerkleInfluenceMinter.sol/MerkleInfluenceMinter.json")

  with open (abi_path, "r") as f:
    contract_json = json.load (f)

  abi = contract_json["abi"]
  bytecode = contract_json["bytecode"]["object"]

  # Get the first account (unlocked in anvil)
  accounts = w3.eth.accounts
  if not accounts:
    raise RuntimeError ("No accounts available")
  deployer = accounts[0]

  # Deploy the contract
  MerkleInfluenceMinter = w3.eth.contract (abi=abi, bytecode=bytecode)
  tx_hash = MerkleInfluenceMinter.constructor (
      args.club_minter, bytes.fromhex (args.root_hash)
  ).transact ()

  rpc.evm_mine ()
  receipt = w3.eth.wait_for_transaction_receipt (tx_hash)
  contract_address = receipt["contractAddress"]

  print (f"MerkleInfluenceMinter deployed at: {contract_address}")

  # Load ClubMinter contract
  club_minter_abi_path = os.path.join (
      os.path.dirname (__file__),
      "../../out/ClubMinter.sol/ClubMinter.json")

  with open (club_minter_abi_path, "r") as f:
    club_minter_json = json.load (f)

  club_minter_abi = club_minter_json["abi"]
  club_minter = w3.eth.contract (address=args.club_minter, abi=club_minter_abi)

  # Get one admin address
  default_admin_role = club_minter.functions.DEFAULT_ADMIN_ROLE ().call ()
  admin_count = club_minter.functions.getRoleMemberCount (default_admin_role).call ()
  if admin_count == 0:
    raise RuntimeError ("No admin found for ClubMinter")
  admin_address = club_minter.functions.getRoleMember (default_admin_role, 0).call ()

  print (f"Using admin address: {admin_address}")

  # Fund the admin address with ETH for gas
  rpc.anvil_setBalance (admin_address, hex (10 ** 18))

  # Grant MINTER_ROLE to the deployed contract by impersonating the admin
  rpc.anvil_impersonateAccount (admin_address)
  minter_role = club_minter.functions.MINTER_ROLE ().call ()
  grant_tx = club_minter.functions.grantRole (
      minter_role, contract_address
  ).transact ({"from": admin_address})

  rpc.evm_mine ()
  w3.eth.wait_for_transaction_receipt (grant_tx)

  print (f"Granted MINTER_ROLE to {contract_address}")

  # Turn on interval mining for the test
  rpc.evm_setIntervalMining (1)
  print (f"Started interval mining")

if __name__ == "__main__":
  main ()
