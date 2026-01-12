#!/usr/bin/env python3

"""
Script to build a Merkle tree for club influence airdrops based on
existing share balances in the GSP state database.
"""

import argparse
import pickle
import sqlite3

from prover import MintData, MintSet

# Percentage of existing balance to airdrop
AIRDROP_PERCENTAGE = 0.10

def main ():
  parser = argparse.ArgumentParser (
      description="Build Merkle tree for club influence airdrop")
  parser.add_argument ("--db", required=True,
                       help="SQLite database file with GSP state")
  parser.add_argument ("--dump", required=False,
                       help="Optional file to save pickled MintSet")
  args = parser.parse_args ()

  with sqlite3.connect (args.db) as conn:
    cursor = conn.cursor ()

    cursor.execute ("""
      SELECT `share_id`, `name`, `num`
        FROM share_balances
        WHERE share_type = 'club'
        ORDER BY `name`, `share_id`
    """)

    mints = []
    for clubId, receiver, num in cursor:
      airdropAmount = int (num * AIRDROP_PERCENTAGE)
      if airdropAmount > 0:
        mints.append (MintData (clubId, airdropAmount, receiver))

  mintSet = MintSet (mints)

  print (f"Merkle tree entries: {len (mints)}")
  print (f"Root hash: {mintSet.rootHash.hex ()}")

  if args.dump:
    with open (args.dump, "wb") as f:
      pickle.dump (mintSet, f)

if __name__ == "__main__":
  main ()
