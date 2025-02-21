// SPDX-License-Identifier: MIT
// Copyright (C) 2024 Soccerverse Ltd

pragma solidity ^0.8.19;

/**
 * @dev A simple library implementing logic for a bit vector (consisting
 * of uint256 words) that starts with all false and can get bits set
 * incrementally and checked, all in memory.  We use this as part of
 * the pack sale to keep track of club IDs that have been tried already
 * while choosing secondary clubs.
 */
library BoolSet
{

  /** @dev Bits per word (uint256).  */
  uint private constant BITS_PER_WORD = 256;

  /**
   * @dev The underlying type holding the data for the bit vector.
   */
  struct Type
  {
    
    /** @dev The actual words in use.  */
    uint256[] words;

    /** @dev Total length (in bits) of the vector.  */
    uint length;

  }

  /**
   * @dev Creates a new vector with the given size and all false.
   */
  function create (uint len)
      internal pure returns (Type memory res)
  {
    res.length = len;
    res.words = new uint256[] ((len + BITS_PER_WORD - 1) / BITS_PER_WORD);
  }

  /**
   * @dev Helper function to compute the word and bit mask (inside the word)
   * for a given absolute index into a bit vector.
   */
  function getIndices (Type memory self, uint ind)
      private pure returns (uint wordIndex, uint256 bitMask)
  {
    require (ind < self.length, "index out of bounds");
    wordIndex = ind / BITS_PER_WORD;
    uint bitIndex = ind % BITS_PER_WORD;
    bitMask = (1 << bitIndex);
  }

  /**
   * @dev Sets the flag of the given index to true.
   */
  function setTrue (Type memory self, uint ind) internal pure
  {
    (uint wordIndex, uint256 bitMask) = getIndices (self, ind);
    self.words[wordIndex] |= bitMask;
  }

  /**
   * @dev Checks if the given flag is set.
   */
  function get (Type memory self, uint ind) internal pure returns (bool)
  {
    (uint wordIndex, uint256 bitMask) = getIndices (self, ind);
    return (self.words[wordIndex] & bitMask) > 0;
  }

}
