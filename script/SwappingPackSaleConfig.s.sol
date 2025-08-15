
// SPDX-License-Identifier: MIT
// Copyright (C) 2024-2025 Soccerverse Ltd

pragma solidity ^0.8.19;

import "./PackSaleConfig.sol";
import "./PolygonConfig.sol";
import "../src/SwappingPackSale.sol";

import { Script } from "forge-std/Script.sol";

/**
 * @dev This is the script to set or update the configuration of the
 * pack sale for all tiers.
 */
contract SwappingPackSaleConfigScript is Script
{

  /**
   * @dev Data about one tranche for sale in each of the tiers.
   */
  struct Tranche
  {

    /** @dev Amount of influence for sale in the tranche.  */
    uint amount;

    /** @dev Price as percentage of base price.  */
    uint basePricePercent;

  }

  /**
   * @dev While we match minter addresses to tiers from the ClubMinter,
   * we use this to map tier names to the index of the minter (per the
   * PackSaleConfig.getMinters() array).  The value is the actual
   * index +1, so we can differentiate it from an unset value.
   */
  mapping (string => uint) public tierIndices;

  /**
   * @dev Matches the minters (MINTER_ROLE) from ClubMinter to the tiers
   * we have in the PackSaleConfig, and returns the array of minter addresses
   * in the order of PackSaleConfig.getMinters().
   */
  function getTierMinters ()
      internal returns (SwappingPackSale[] memory res)
  {
    string[] memory tiers = PackSaleConfig.getTiers ();
    for (uint i = 0; i < tiers.length; ++i)
      tierIndices[tiers[i]] = i + 1;

    bytes32 minterRole = PackSaleConfig.cm.MINTER_ROLE ();
    uint numMinters = PackSaleConfig.cm.getRoleMemberCount (minterRole);
    require (numMinters == tiers.length, "mismatch in number of minters");

    res = new SwappingPackSale[] (numMinters);
    for (uint i = 0; i < numMinters; ++i)
      {
        address addr = PackSaleConfig.cm.getRoleMember (minterRole, i);
        SwappingPackSale cur = SwappingPackSale (payable (addr));

        uint index = tierIndices[cur.tier ()];
        require (index > 0, "mismatch in minter names");
        res[index - 1] = cur;
      }
  }

  function run () public
  {
    uint256 privkey = vm.envUint ("PRIVKEY");

    SwappingPackSale[] memory minters = getTierMinters ();

    uint[] memory basePrices = new uint[] (5);
    basePrices[0] = 100000;
    basePrices[1] =  55000;
    basePrices[2] =  20000;
    basePrices[3] =   6500;
    basePrices[4] =   2000;
    require (minters.length == basePrices.length, "wrong number of minters");

    Tranche[] memory tranches = new Tranche[] (15);
    tranches[0] = Tranche (10_000, 100);
    tranches[1] = Tranche (20_000, 125);
    tranches[2] = Tranche (20_000, 150);
    tranches[3] = Tranche (20_000, 200);
    tranches[4] = Tranche (20_000, 300);
    tranches[5] = Tranche (20_000, 400);
    tranches[6] = Tranche (20_000, 500);
    tranches[7] = Tranche (20_000, 600);
    tranches[8] = Tranche (20_000, 700);
    tranches[9] = Tranche (20_000, 1_000);
    tranches[10] = Tranche (20_000, 1_200);
    tranches[11] = Tranche (20_000, 1_400);
    tranches[12] = Tranche (20_000, 1_600);
    tranches[13] = Tranche (20_000, 1_800);
    tranches[14] = Tranche (20_000, 2_000);

    uint kycThreshold = 10_000 * (10**PolygonConfig.usdc.decimals ());

    for (uint i = 0; i < minters.length; ++i)
      {
        SwappingPackSale ps = minters[i];
        require (ps.paused (), "PackSale is not paused");

        vm.startBroadcast (privkey);

        ps.configure (6, 40, 10);
        ps.setPayee (0xa21E73B36845a1cB710a53e0792154BF4Ca97bB8);
        /* We start off with unlimited referral bonus to cover referrals
           from before launch.  We may later enable a time limit.  */
        ps.setRefBonus (500, 1_000_000_000);
        ps.setSmcMintRate (500_0000);
        ps.setSanctionsList (PolygonConfig.sanctions);
        ps.setKycThreshold (kycThreshold);

        PackSale.PricingStep[] memory pricing
            = new PackSale.PricingStep[] (tranches.length);
        for (uint j = 0; j < tranches.length; ++j)
          {
            uint price = basePrices[i] * tranches[j].basePricePercent / 100;
            pricing[j] = PackSale.PricingStep (tranches[j].amount, price);
          }
        ps.setPricing (pricing);

        /* Adding clubs must be done after deployment, most likely by
           an external script processing a CSV export.  When that is done,
           the contract can be unpaused.  */

        vm.stopBroadcast ();
      }
  }

}
