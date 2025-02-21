// SPDX-License-Identifier: MIT
// Copyright (C) 2024 Soccerverse Ltd

pragma solidity ^0.8.19;

import "./MinterTest.sol";
import "./TestSwapProvider.sol";
import "./TestToken.sol";

import "../src/PurchaseTracker.sol";
import "../src/ReferralTracker.sol";
import "../src/SwappingPackSale.sol";

/**
 * @dev A test contract that sets up all that is required for testing
 * pack sale related things, in particular, the basic Xaya environment
 * as well as a club minter and swapping pack sale contract (plus a fake
 * USDC test token).
 */
abstract contract SaleTest is MinterTest
{

  address public constant payee = address (100);

  ERC20 public immutable usdc;
  TestSwapProvider public immutable swapper;
  PurchaseTracker public immutable pt;
  ReferralTracker public immutable ref;
  SwappingPackSale public immutable ps;

  constructor ()
  {
    vm.label (payee, "payee");

    usdc = new TestToken (supply, 1e6 * 1e8);

    vm.startPrank (supply);
    swapper = new TestSwapProvider (usdc, supply);
    usdc.approve (address (swapper), type (uint256).max);

    vm.startPrank (admin);
    pt = new PurchaseTracker ();
    pt.grantRole (pt.APPROVER_ROLE (), admin);
    ref = new ReferralTracker ();
    ref.grantRole (ref.SET_REFERRER_ROLE (), admin);
    ps = new SwappingPackSale (usdc, cm, pt, ref, "test", address (0),
                               IWETH (address (weth)), swapper);
    ps.grantRole (ps.CONFIGURE_ROLE (), admin);
    ps.grantRole (ps.UPDATE_SEED_ROLE (), admin);
    cm.grantRole (cm.MINTER_ROLE (), address (ps));
    pt.grantRole (pt.INCREMENT_TOTAL_ROLE (), address (ps));

    vm.stopPrank ();
  }

  /**
   * @dev Helper function to set the pricing with one batch.
   */
  function setPricing (uint num, uint price) internal
  {
    PackSale.PricingStep[] memory steps = new PackSale.PricingStep[] (1);
    steps[0] = PackSale.PricingStep (num, price);
    ps.setPricing (steps);
  }

}
