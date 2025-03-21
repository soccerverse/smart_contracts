#!/usr/bin/env python3
# Copyright (C) 2025 Soccerverse Ltd

"""
Python module for constructing the subpaths used as swapping data for
concrete routes in SwapperV2V3.
"""

import const

import eth_abi
from eth_abi.packed import encode_packed
from web3 import Web3

################################################################################

# String representing the eth_abi type for a subpath.
typeString = "(address,address,address,bytes)"

class Constructor:
  """
  Helper class to construct the Subpath[] swapping data for a particular
  route in SwapperV2V3.
  """

  def __init__ (self, inputToken):
    self.currentToken = inputToken
    self.subpaths = []

  def addV2 (self, *path):
    """
    Adds a Uniswap V2 segment along the given path.  The entries of path
    should be the token addresses extending on from the last token (or the
    original inputToken given in the constructor).
    """

    fullPath = [self.currentToken] + list (path)
    encodedPath = eth_abi.encode (["address[]"], [fullPath])

    self.subpaths.append ((
      const.UNISWAP_V2,
      const.ZERO_ADDRESS,
      const.ZERO_ADDRESS,
      encodedPath,
    ))

    self.currentToken = path[-1]

  def addV3 (self, *path):
    """
    Adds a Uniswap V3 segment along the given path, which is a list of
    "(fee, token), (fee, token), ..." pairs, with fee being in 1e-6 units
    (1/100th of a bip).  The last (or initial) token is assumed to be the
    original input for the path.
    """

    encodedPath = encode_packed (["address"], [self.currentToken])
    for fee, token in path:
      encodedPath += encode_packed (["uint24", "address"], [fee, token])

    self.subpaths.append ((
      const.ZERO_ADDRESS,
      const.UNISWAP_V3_ROUTER,
      const.UNISWAP_V3_QUOTER,
      encodedPath,
    ))

    self.currentToken = path[-1][1]

  def encode (self):
    """
    Returns the full subpath constructed so far in encoded form.
    """

    return eth_abi.encode ([f"{typeString}[]"], [self.subpaths])

def decode (enc):
  """
  Decodes an encoded Subpath[] array back to the individual parts.
  """

  (parts,) = eth_abi.decode ([f"{typeString}[]"], enc)

  return [
    (
      Web3.to_checksum_address (p[0]),
      Web3.to_checksum_address (p[1]),
      Web3.to_checksum_address (p[2]),
      p[3],
    )
    for p in parts
  ]

################################################################################

# As the main routine, we construct a particular subpath and print the
# associated data.  This can be used to construct the paths we want to
# hardcode in the frontend.

if __name__ == "__main__":
  c = Constructor (const.WCHI)
  c.addV2 (const.WETH)
  c.addV3 ((500, const.USDC))
  print ("0x" + c.encode ().hex ())
