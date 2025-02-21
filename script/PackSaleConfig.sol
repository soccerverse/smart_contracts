
// SPDX-License-Identifier: MIT
// Copyright (C) 2024 Soccerverse Ltd

pragma solidity ^0.8.19;

import "../src/ClubMinter.sol";
import "../src/PurchaseTracker.sol";
import "../src/ReferralTracker.sol";

/**
 * @dev Helper library defining basic configuration for the pack sale.
 */
library PackSaleConfig
{

  /** @dev Address of the ClubMinter used.  */
  ClubMinter public constant cm
      = ClubMinter (0xeEE0d855112b71Dc68d72053594Af03F92C586Ae);

  /** @dev Address of the PurchaseTracker used.  */
  PurchaseTracker public constant pt
      = PurchaseTracker (0x879E44f2025cAd323f8F1C7C28F672F5f3f92304);

  /** @dev Address of the ReferralTracker used.  */
  ReferralTracker public constant ref
      = ReferralTracker (0x329612BB11Eea1Ea5065993DC32b41C86D6068c2);

  /**
   * @dev Returns the list of tiers we have.
   */
  function getTiers ()
      internal pure returns (string[] memory res)
  {
    res = new string[] (5);
    res[0] = "tier 1";
    res[1] = "tier 2";
    res[2] = "tier 3";
    res[3] = "tier 4";
    res[4] = "tier 5";
  }

}
