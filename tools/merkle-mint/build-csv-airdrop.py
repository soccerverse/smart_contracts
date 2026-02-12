#!/usr/bin/env python3

"""
Script to build a Merkle tree for club influence airdrops based on
a CSV file with club influence data.
"""

import argparse
import csv
import pickle

from prover import MintData, MintSet

def main ():
  parser = argparse.ArgumentParser (
      description="Build Merkle tree for club influence airdrop from CSV")
  parser.add_argument ("--csv", required=True,
                       help="CSV file with club influence data")
  parser.add_argument ("--receiver", required=True,
                       help="Receiver account name for all mints")
  parser.add_argument ("--dump", required=False,
                       help="Optional file to save pickled MintSet")
  args = parser.parse_args ()

  # Dictionary to accumulate influence per club ID
  clubInfluence = {}
  
  with open (args.csv, "rt") as csvfile:
    reader = csv.DictReader (csvfile)
    for row in reader:
      clubId = int (row["club_id"])
      influence = int (row["influence"])
      
      if clubId in clubInfluence:
        clubInfluence[clubId] += influence
      else:
        clubInfluence[clubId] = influence

  # Create mint data for each club with total influence
  mints = []
  for clubId, totalInfluence in clubInfluence.items ():
    if totalInfluence > 0:
      mints.append (MintData(clubId, totalInfluence, args.receiver))

  mintSet = MintSet (mints)

  print (f"Merkle tree entries: {len(mints)}")
  print (f"Root hash: {mintSet.rootHash.hex()}")

  if args.dump:
    with open (args.dump, "wb") as f:
      pickle.dump (mintSet, f)

if __name__ == "__main__":
  main ()
