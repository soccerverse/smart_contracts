// SPDX-License-Identifier: MIT
// Copyright (C) 2024 Soccerverse Ltd

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @dev Minimal token that has its initial supply minted to
 * a given address on construction and can be used as token for testing.
 */
contract TestToken is ERC20
{

  constructor (address owner, uint supply)
    ERC20 ("Wrapped CHI", "WCHI")
  {
    _mint (owner, supply);
  }

  /**
   * @dev We use non-standard decimals like WCHI and USDC.
   */
  function decimals ()
      public view virtual override returns (uint8)
  {
    return 8;
  }

}
