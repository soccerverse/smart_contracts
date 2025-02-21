// SPDX-License-Identifier: MIT
// Copyright (C) 2024 Soccerverse Ltd

pragma solidity ^0.8.19;

import "../src/ISanctionsList.sol";

/**
 * @dev Mock implementation of ISanctionsList, where we can just set
 * sanctioned addresses manually.
 */
contract TestSanctionsList is ISanctionsList
{

  /** @dev All sanctioned addresses.  */
  mapping (address => bool) public sanctioned;

  /**
   * @dev Sets an address as sanctioned.
   */
  function setSanctioned (address addr) public
  {
    sanctioned[addr] = true;
  }

  function isSanctioned (address addr)
      public view override returns (bool)
  {
    return sanctioned[addr];
  }

}
