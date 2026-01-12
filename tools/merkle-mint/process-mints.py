#!/usr/bin/env python3

"""
Script to process and execute mints from a MintSet through a deployed
MerkleInfluenceMinter contract.
"""

import argparse
import json
import logging
import os
import pickle
from pathlib import Path

from eth_account import Account
from web3 import Web3

def main ():
  parser = argparse.ArgumentParser (
      description="Process mints through MerkleInfluenceMinter contract")
  parser.add_argument ("--mintset", required=True,
                       help="File with pickled MintSet instance")
  parser.add_argument ("--rpc_url", required=True,
                       help="JSON-RPC URL for EVM blockchain node")
  parser.add_argument ("--contract", required=True,
                       help="Address of deployed MerkleInfluenceMinter contract")
  parser.add_argument ("--batch_size", type=int, default=100,
                       help="Batch size for processing")
  parser.add_argument ("--max_gas", type=int, default=200,
                       help="Maximum gas price in Gwei")
  parser.add_argument ("--prio_gas", type=int, default=35,
                       help="Priority gas in Gwei ")
  args = parser.parse_args ()

  logging.basicConfig (level=logging.INFO, format="%(message)s")

  w3 = Web3 (Web3.HTTPProvider (args.rpc_url))
  if not w3.is_connected ():
    logging.error ("Failed to connect to RPC endpoint")
    return 1

  chain_id = w3.eth.chain_id
  logging.info (f"Connected to chain ID: {chain_id}")

  script_dir = Path (__file__).parent
  abi_path = script_dir / "../../out/MerkleInfluenceMinter.sol/MerkleInfluenceMinter.json"
  with open (abi_path, "r") as f:
    contract_json = json.load (f)
    contract_abi = contract_json["abi"]

  contract = w3.eth.contract (address=args.contract, abi=contract_abi)

  with open (args.mintset, "rb") as f:
    mintSet = pickle.load (f)

  contract_root = contract.functions.rootHash ().call ()
  if mintSet.rootHash != contract_root:
    logging.error (f"Root hash mismatch!")
    logging.error (f"  MintSet:  {mintSet.rootHash.hex ()}")
    logging.error (f"  Contract: {contract_root.hex ()}")
    return 1

  logging.info (f"Root hash matches: {mintSet.rootHash.hex ()}")

  privkey = os.environ.get ("PRIVKEY")
  if not privkey:
    logging.error ("PRIVKEY environment variable not set")
    return 1

  account = Account.from_key (privkey)
  logging.info (f"Using operator address: {account.address}")

  total_mints = len (mintSet.mints)
  logging.info (f"Total mints in set: {total_mints}")

  for batch_start in range (0, total_mints, args.batch_size):
    batch_end = min (batch_start + args.batch_size, total_mints)
    batch = mintSet.mints[batch_start:batch_end]

    logging.info (f"Processing batch {batch_start}-{batch_end - 1}...")

    mint_data_batch = [
      (m.clubId, m.num, m.receiver)
      for m in batch
    ]
    done_flags = contract.functions.checkDoneBatch (mint_data_batch).call ()

    pending_mints = []
    for i, done in enumerate (done_flags):
      if not done:
        mint_index = batch_start + i
        proof = mintSet.getProof (mint_index)
        pending_mints.append ((batch[i], proof))

    if not pending_mints:
      logging.info (f"  All mints in batch already done, skipping")
      continue

    logging.info (f"  {len (pending_mints)} mints pending in batch")

    batch_data = [
      {
        "mint": (m.clubId, m.num, m.receiver),
        "proof": proof
      }
      for m, proof in pending_mints
    ]

    nonce = w3.eth.get_transaction_count (account.address)
    max_fee = w3.to_wei (args.max_gas, "gwei")
    priority_fee = w3.to_wei (args.prio_gas, "gwei")

    tx = contract.functions.executeBatch (batch_data).build_transaction ({
      "from": account.address,
      "nonce": nonce,
      "maxFeePerGas": max_fee,
      "maxPriorityFeePerGas": priority_fee,
      "chainId": chain_id,
    })

    signed_tx = account.sign_transaction (tx)
    tx_hash = w3.eth.send_raw_transaction (signed_tx.raw_transaction)
    logging.info (f"  Sent {len (pending_mints)} mints, txid: {tx_hash.hex ()}")

    receipt = w3.eth.wait_for_transaction_receipt (tx_hash)
    if receipt["status"] == 1:
      logging.info (f"  Transaction confirmed in block {receipt['blockNumber']}")
    else:
      logging.error (f"  Transaction failed!")
      return 1

  logging.info ("All batches processed successfully")
  return 0

if __name__ == "__main__":
  exit (main ())
