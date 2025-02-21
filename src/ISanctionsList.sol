// SPDX-License-Identifier: MIT
// Copyright (C) 2024 Soccerverse Ltd

pragma solidity ^0.8.19;

/**
 * @dev Interface for on-chain sanctions screening.  This is based on
 * Chainalysis' sanctions oracle, see:
 * https://go.chainalysis.com/chainalysis-oracle-docs.html
 */
interface ISanctionsList
{

  /**
   * @dev Returns true if an address is sanctioned and should not
   * be allowed to purchase packs.
   */
  function isSanctioned (address addr)
      external view returns (bool);

}
