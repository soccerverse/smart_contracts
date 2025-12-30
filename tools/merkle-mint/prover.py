"""
This Python module implements logic to build Merkle trees of influence
mints, and provide proofs for mints so we can use the MerkleInfluenceMinter
contract.
"""

from web3 import Web3

class MintData:
  """
  Simple class holding the data for one influence mint.
  """

  def __init__ (self, clubId, num, receiver):
    self.clubId = clubId
    self.num = num
    self.receiver = receiver

  def hash (self):
    """
    Computes and returns the hash value of this mint, equivalent to
    the mintHash function in MerkleInfluenceMinter.  This hash is used
    to check for duplicates and also for the Merkle leafs.
    """

    return Web3.solidity_keccak (
        ["bytes1", "uint256", "uint256", "string"],
        ["0x00", self.clubId, self.num, self.receiver])

class MerkleTree:
  """
  Base implementation of a Merkle tree that matches our smart contract,
  i.e. OpenZeppelin's MerkleProof library.
  """

  def __init__ (self, leafs):
    # Extend the leaf hashes to a power of two, using all zeros as padding.
    nextPowerOfTwo = 1
    while nextPowerOfTwo < len (leafs):
      nextPowerOfTwo <<= 1
    leafs.extend ([b"\0" * 32] * (nextPowerOfTwo - len (leafs)))

    self.levels = [leafs]

    # Compute the next tree levels until we reach the root.
    while True:
      lastLevel = self.levels[-1]
      if len (lastLevel) == 1:
        break
      pairs = [
        (lastLevel[i], lastLevel[i + 1])
        for i in range (0, len (lastLevel), 2)
      ]
      nextLevel = list (map (self.hashPair, pairs))
      self.levels.append (nextLevel)

    [self.root] = self.levels[-1]

  @staticmethod
  def hashPair (pair):
    """
    Computes the Merkle parent hash for a pair of node hashes.  The nodes
    are ordered as per OpenZeppelin's MerkleProof library.
    """

    (a, b) = pair

    if a < b:
      return Web3.keccak (a + b)

    return Web3.keccak (b + a)

  def getProof (self, index):
    """
    Computes and returns the Merkle proof required for the leaf with
    the given index in the tree.  The proof is returned as array of bytes32
    hashes, as expected by the MerkleProof contract.
    """

    proof = []
    for lvl in self.levels[:-1]:
      if index % 2 == 0:
        proof.append (lvl[index + 1])
      else:
        proof.append (lvl[index - 1])
      index >>= 1

    return proof

class MintSet:
  """
  The main class representing a set of mints with the underlying Merkle
  tree and logic to get proofs for submitting the mints.
  """

  def __init__ (self, mints):
    self.mints = mints

    # Enforce that no mint is duplicated, and in fact, there are no
    # two mints for any club and receiver.  The amounts should be summed up
    # for them into a single mint.
    clubs = {}
    for m in self.mints:
      if m.clubId not in clubs:
        clubs[m.clubId] = set ()
      if m.receiver in clubs[m.clubId]:
        raise RuntimeError (
            f"duplicate mint for club {m.clubId} and receiver '{m.receiver}'")
      clubs[m.clubId].add (m.receiver)

    self.merkle = MerkleTree ([m.hash () for m in mints])

  @property
  def rootHash (self):
    return self.merkle.root

  def getProof (self, index):
    return self.merkle.getProof (index)
