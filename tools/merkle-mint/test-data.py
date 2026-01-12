#!/usr/bin/env python3

# Simple script that uses the prover.py logic to build up a small Merkle tree
# for testing purposes.  We use the output of this script also for the data
# in the Solidity unit tests for MerkleInfluenceMinter.

import prover

mints = [
  prover.MintData (42, 5, "domob"),
  prover.MintData (42, 10, "andy"),
  prover.MintData (100, 1, "domob"),
]

mintSet = prover.MintSet (mints)
print (f"Root hash: {mintSet.rootHash.hex ()}")

for i in range (len (mints)):
  m = mints[i]
  print (f"Mint #{i}: {m.clubId}, {m.num}, {m.receiver}")
  proof = mintSet.getProof (i)
  proofStr = "\n  ".join ([p.hex () for p in proof])
  print (f"  {proofStr}")
