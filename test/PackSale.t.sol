// SPDX-License-Identifier: MIT
// Copyright (C) 2024-2025 Soccerverse Ltd

pragma solidity ^0.8.19;

import "./SaleTest.sol";
import "./TestSanctionsList.sol";
import "./Utils.sol";
import "../src/Config.sol";

contract PackSaleTest is SaleTest
{

  address public constant buyer = address (101);

  uint public constant balance = 1000;
  uint public immutable allShares;
  uint public immutable paymentBaseUnit;

  constructor ()
  {
    vm.label (buyer, "buyer");

    allShares = cm.shareSupply ();
    paymentBaseUnit = 10**usdc.decimals ();

    vm.startPrank (supply);
    usdc.transfer (buyer, balance);
    vm.stopPrank ();

    vm.prank (buyer);
    usdc.approve (address (ps), type (uint256).max);

    vm.startPrank (admin);
    cm.grantRole (cm.MINTER_ROLE (), admin);
    /* By default, we configure the payee as payee.  In tests that want to
       check other situations (such as no payee configured), we overwrite
       this explicitly.  */
    ps.setPayee (payee);
    vm.stopPrank ();
  }

  /**
   * @dev Helper function to check that the clubIndices mapping in the
   * PackSale contract is consistent.
   */
  function checkClubIndices () internal view
  {
    uint[] memory clubs = ps.getAllClubs ();
    for (uint i = 0; i < clubs.length; ++i)
      assertEq (ps.clubIndices (clubs[i]), i + 1);
  }

  /**
   * @dev Mints shares of the given club ID until only the desired amount
   * is left to mint.  Assumes we are pranking with the admin account already.
   */
  function setSharesLeft (uint clubId, uint desired) internal
  {
    uint cur = cm.sharesAvailable (clubId);
    assertGe (cur, desired);
    cm.mintShares (clubId, cur - desired, "receiver");
    assertEq (cm.sharesAvailable (clubId), desired);
  }

  /* ************************************************************************ */

  function test_setPayee () public
  {
    vm.startPrank (buyer);
    vm.expectRevert (Utils.missingRoleError (buyer, ps.CONFIGURE_ROLE ()));
    ps.setPayee (buyer);

    assertEq (ps.payee (), payee);

    vm.startPrank (admin);
    vm.expectEmit (address (ps));
    emit PackSale.PayeeChanged (buyer);
    ps.setPayee (buyer);
    assertEq (ps.payee (), buyer);

    vm.expectEmit (address (ps));
    emit PackSale.PayeeChanged (address (0));
    ps.setPayee (address (0));
    assertEq (ps.payee (), address (0));
  }

  function test_configure () public
  {
    vm.prank (admin);
    ps.configure (1, 3, 2);

    vm.startPrank (buyer);
    vm.expectRevert (Utils.missingRoleError (buyer, ps.CONFIGURE_ROLE ()));
    ps.configure (2, 3, 4);

    assertEq (ps.secondaryClubs (), 1);
    assertEq (ps.numSharesPrimary (), 3);
    assertEq (ps.numSharesSecondary (), 2);

    vm.startPrank (admin);
    ps.configure (5, 4, 3);

    assertEq (ps.secondaryClubs (), 5);
    assertEq (ps.numSharesPrimary (), 4);
    assertEq (ps.numSharesSecondary (), 3);
  }

  function test_setRefBonus () public
  {
    assertEq (ps.refBonusBps (), 0);
    assertEq (ps.refBonusSeconds (), 0);

    vm.startPrank (buyer);
    vm.expectRevert (Utils.missingRoleError (buyer, ps.CONFIGURE_ROLE ()));
    ps.setRefBonus (100, 5);

    vm.startPrank (admin);

    ps.setRefBonus (10, 5);
    assertEq (ps.refBonusBps (), 10);
    assertEq (ps.refBonusSeconds (), 5);

    ps.setRefBonus (2000000, 100);
    assertEq (ps.refBonusBps (), 2000000);
    assertEq (ps.refBonusSeconds (), 100);

    ps.setRefBonus (0, 0);
    assertEq (ps.refBonusBps (), 0);
    assertEq (ps.refBonusSeconds (), 0);
  }

  function test_setSmcMintRate () public
  {
    assertEq (ps.smcMintedPerUsd (), 0);

    vm.prank (admin);
    ps.setSmcMintRate (1000);

    vm.startPrank (buyer);
    vm.expectRevert (Utils.missingRoleError (buyer, ps.CONFIGURE_ROLE ()));
    ps.setSmcMintRate (100);

    assertEq (ps.smcMintedPerUsd (), 1000);
  }

  function test_setPricing () public
  {
    PackSale.PricingStep[] memory pricing = new PackSale.PricingStep[] (2);
    pricing[0] = PackSale.PricingStep (1000, 10);
    pricing[1] = PackSale.PricingStep (500, 20);

    vm.prank (admin);
    ps.setPricing (pricing);
    assertEq (ps.totalSharesAvailable (), 1500);

    pricing = new PackSale.PricingStep[] (1);
    pricing[0] = PackSale.PricingStep (100, 5);
    vm.startPrank (buyer);
    vm.expectRevert (Utils.missingRoleError (buyer, ps.CONFIGURE_ROLE ()));
    ps.setPricing (pricing);

    PackSale.PricingStep[] memory actualPricing = ps.getPricing ();
    assertEq (actualPricing.length, 2);
    assertEq (actualPricing[0].num, 1000);
    assertEq (actualPricing[0].price, 10);
    assertEq (actualPricing[1].num, 500);
    assertEq (actualPricing[1].price, 20);

    vm.startPrank (admin);
    ps.setPricing (pricing);
    assertEq (ps.totalSharesAvailable (), 100);

    actualPricing = ps.getPricing ();
    assertEq (actualPricing.length, 1);
    assertEq (actualPricing[0].num, 100);
    assertEq (actualPricing[0].price, 5);

    pricing = new PackSale.PricingStep[] (2);
    pricing[0] = PackSale.PricingStep (allShares, 100);
    pricing[1] = PackSale.PricingStep (1, 1000);

    vm.expectRevert ("more shares configured in pricing than are available");
    ps.setPricing (pricing);
  }

  function test_addClub () public
  {
    vm.prank (admin);
    ps.addClub (100);

    vm.startPrank (buyer);
    vm.expectRevert (Utils.missingRoleError (buyer, ps.CONFIGURE_ROLE ()));
    ps.addClub (101);

    vm.startPrank (admin);
    ps.addClub (90);
    ps.addClub (110);

    vm.expectRevert ("club is already configured");
    ps.addClub (100);

    uint[] memory clubs = ps.getAllClubs ();
    assertEq (clubs.length, 3);
    assertEq (clubs[0], 100);
    assertEq (clubs[1], 90);
    assertEq (clubs[2], 110);

    checkClubIndices ();
  }

  function test_addClubs () public
  {
    uint[] memory clubs = new uint[] (3);
    clubs[0] = 10;
    clubs[1] = 30;
    clubs[2] = 20;

    vm.prank (admin);
    ps.addClubs (clubs);

    clubs = new uint[] (2);
    clubs[0] = 100;
    clubs[1] = 200;
    vm.startPrank (buyer);
    vm.expectRevert (Utils.missingRoleError (buyer, ps.CONFIGURE_ROLE ()));
    ps.addClubs (clubs);

    clubs = ps.getAllClubs ();
    assertEq (clubs.length, 3);
    assertEq (clubs[0], 10);
    assertEq (clubs[1], 30);
    assertEq (clubs[2], 20);

    checkClubIndices ();
  }

  function test_getClubsSlice () public
  {
    assertEq (ps.getNumClubs (), 0);
    uint[] memory clubs = ps.getClubsSlice (0, 10);
    assertEq (clubs.length, 0);
    clubs = ps.getClubsSlice (5, 10);
    assertEq (clubs.length, 0);

    vm.startPrank (admin);
    ps.addClub (100);
    ps.addClub (101);
    ps.addClub (102);
    ps.addClub (103);

    assertEq (ps.getNumClubs (), 4);

    clubs = ps.getClubsSlice (0, 10);
    assertEq (clubs.length, 4);
    assertEq (clubs[0], 100);
    assertEq (clubs[1], 101);
    assertEq (clubs[2], 102);
    assertEq (clubs[3], 103);

    clubs = ps.getClubsSlice (0, 2);
    assertEq (clubs.length, 2);
    assertEq (clubs[0], 100);
    assertEq (clubs[1], 101);

    clubs = ps.getClubsSlice (2, 3);
    assertEq (clubs.length, 2);
    assertEq (clubs[0], 102);
    assertEq (clubs[1], 103);
  }

  function test_removeClub () public
  {
    vm.startPrank (admin);
    ps.addClub (100);
    ps.addClub (101);
    ps.addClub (102);
    ps.addClub (103);
    ps.addClub (104);

    /* Removing at the end and in the middle follows different code paths,
       so we do both.  */
    ps.removeClub (104);
    ps.removeClub (102);

    vm.expectRevert ("the club does not exist");
    ps.removeClub (42);

    vm.startPrank (buyer);
    vm.expectRevert (Utils.missingRoleError (buyer, ps.CONFIGURE_ROLE ()));
    ps.removeClub (103);

    uint[] memory clubs = ps.getAllClubs ();
    assertEq (clubs.length, 3);
    assertEq (clubs[0], 100);
    assertEq (clubs[1], 101);
    assertEq (clubs[2], 103);

    checkClubIndices ();
  }

  function test_unpauseClubSales () public
  {
    vm.startPrank (admin);
    ps.configure (1, 1, 1);
    setPricing (allShares, 10);
    ps.addClub (100);
    ps.addClub (101);
    ps.addClub (102);
    ps.addClub (103);
    ps.addClub (104);

    setSharesLeft (101, 0);
    setSharesLeft (102, 0);
    setSharesLeft (103, 0);
    setSharesLeft (104, 0);

    /* There is no explicit way to pause club sales, so we go via the
       minting process for it.  */
    PackSale.PackMint memory data = ps.preview (100, 1);
    assertEq (data.soldOut.length, 4);
    assertEq (data.soldOut[0] + data.soldOut[1] + data.soldOut[2]
                + data.soldOut[3],
              101 + 102 + 103 + 104);
    vm.startPrank (buyer);
    ps.mint (data, "receiver");

    uint[] memory clubs = ps.getPausedClubs ();
    assertEq (clubs.length, 4);
    assertEq (clubs[0] + clubs[1] + clubs[2] + clubs[3], 101 + 102 + 103 + 104);

    clubs = ps.getAllClubs ();
    assertEq (clubs.length, 1);
    assertEq (clubs[0], 100);
    checkClubIndices ();

    vm.expectRevert (Utils.missingRoleError (buyer, ps.CONFIGURE_ROLE ()));
    ps.unpauseClubSales (3);

    vm.startPrank (admin);
    ps.unpauseClubSales (3);

    assertEq (ps.getPausedClubs ().length, 1);
    assertEq (ps.getAllClubs ().length, 4);
    checkClubIndices ();

    ps.unpauseClubSales (3);

    assertEq (ps.getPausedClubs ().length, 0);
    clubs = ps.getAllClubs ();
    assertEq (clubs.length, 5);
    assertEq (clubs[0], 100);
    assertEq (clubs[1] + clubs[2] + clubs[3] + clubs[4], 101 + 102 + 103 + 104);
    checkClubIndices ();
  }

  function test_onlyRoleCanUpdateSeed () public
  {
    vm.prank (admin);
    ps.updateSeed ();

    vm.startPrank (buyer);
    vm.expectRevert (Utils.missingRoleError (buyer, ps.UPDATE_SEED_ROLE ()));
    ps.updateSeed ();
  }

  function test_pauseUnpause () public
  {
    assertFalse (ps.paused ());

    vm.startPrank (buyer);
    vm.expectRevert (Utils.missingRoleError (buyer, ps.CONFIGURE_ROLE ()));
    ps.pause ();

    vm.startPrank (admin);
    ps.pause ();
    assertTrue (ps.paused ());

    /* While paused, it should not be possible to mint, but it should be
       possible to update the configuration.  */
    ps.configure (1, 3, 2);
    setPricing (allShares, 10);
    ps.addClub (10);
    ps.addClub (30);
    ps.addClub (20);
    ps.removeClub (20);

    assertEq (ps.secondaryClubs (), 1);
    assertEq (ps.numSharesPrimary (), 3);
    assertEq (ps.numSharesSecondary (), 2);
    assertEq (ps.getAllClubs ().length, 2);

    PackSale.PackMint memory data = ps.preview (10, 1);
    vm.startPrank (buyer);

    vm.expectRevert ("Pausable: paused");
    ps.mint (data, "receiver");

    vm.expectRevert (Utils.missingRoleError (buyer, ps.CONFIGURE_ROLE ()));
    ps.unpause ();

    vm.startPrank (admin);
    ps.unpause ();
    assertFalse (ps.paused ());

    vm.startPrank (buyer);
    ps.mint (data, "receiver");
    assertEq (cm.sharesMinted (10), 3);
    assertEq (cm.sharesMinted (30), 2);
  }

  /* ************************************************************************ */

  function test_sharesAvailable () public
  {
    vm.startPrank (admin);

    PackSale.PricingStep[] memory pricing = new PackSale.PricingStep[] (3);
    pricing[0] = PackSale.PricingStep (100, 1);
    pricing[1] = PackSale.PricingStep (0, 5);
    pricing[2] = PackSale.PricingStep (20, 10);
    ps.setPricing (pricing);

    cm.mintShares (10, 50, "receiver");
    cm.mintShares (20, 200, "receiver");

    assertEq (ps.sharesAvailable (10), 70);
    assertEq (ps.sharesAvailable (20), 0);
    assertEq (ps.sharesAvailable (30), 120);
  }

  function test_sharesToGive () public
  {
    vm.startPrank (admin);
    setPricing (100, 1);
    cm.mintShares (10, 50, "receiver");

    assertEq (ps.sharesToGive (10, 0), 0);
    assertEq (ps.sharesToGive (10, 10), 10);
    assertEq (ps.sharesToGive (10, 50), 50);
    assertEq (ps.sharesToGive (10, 1000), 50);
  }

  function test_costOfNextShares () public
  {
    vm.startPrank (admin);

    PackSale.PricingStep[] memory pricing = new PackSale.PricingStep[] (3);
    pricing[0] = PackSale.PricingStep (10, 1);
    pricing[1] = PackSale.PricingStep (0, 5);
    pricing[2] = PackSale.PricingStep (5, 10);
    ps.setPricing (pricing);

    for (uint minted = 0; minted <= 15; ++minted)
      {
        uint cost = 0;
        for (uint num = 0; num <= 15 - minted; ++num)
          {
            assertEq (ps.costOfNextShares (10, num), cost);
            if (minted + num < 10)
              cost += 1;
            else
              cost += 10;
          }

        cm.mintShares (10, 1, "receiver");
      }

    vm.expectRevert ("not enough shares available");
    ps.costOfNextShares (10, 1);
    vm.expectRevert ("not enough shares available");
    ps.costOfNextShares (42, 16);

    cm.mintShares (10, 100, "receiver");
    assertEq (ps.costOfNextShares (10, 0), 0);
    vm.expectRevert ("not enough shares available");
    ps.costOfNextShares (10, 1);
  }

  function test_smcToMintForPayment () public
  {
    assertEq (ps.smcToMintForPayment (paymentBaseUnit), 0);

    vm.startPrank (admin);
    ps.setSmcMintRate (10);
    assertEq (ps.smcToMintForPayment (0), 0);
    assertEq (ps.smcToMintForPayment (1), 0);
    assertEq (ps.smcToMintForPayment (paymentBaseUnit), 10);
    assertEq (ps.smcToMintForPayment (paymentBaseUnit / 10), 1);
    assertEq (ps.smcToMintForPayment (paymentBaseUnit * 2), 20);

    ps.setSmcMintRate (paymentBaseUnit);
    assertEq (ps.smcToMintForPayment (0), 0);
    assertEq (ps.smcToMintForPayment (1), 1);
    assertEq (ps.smcToMintForPayment (10), 10);
  }

  /* ************************************************************************ */

  function test_getMaxPacksWhenMintingIsNotPossible () public
  {
    vm.startPrank (admin);

    /* The club is not available.  */
    ps.configure (1, 3, 2);
    setPricing (allShares, 10);
    ps.addClub (100);
    assertEq (ps.getMaxPacks (42), 0);

    /* Clubs assigned, but no shares set to be given out.  */
    assertGt (ps.getMaxPacks (100), 0);
    ps.configure (1, 0, 2);
    assertEq (ps.getMaxPacks (100), 0);

    /* Minting is paused.  */
    ps.configure (1, 3, 2);
    ps.pause ();
    assertEq (ps.getMaxPacks (100), 0);
    ps.unpause ();
    assertGt (ps.getMaxPacks (100), 0);

    /* No payee configured.  */
    ps.setPayee (address (0));
    assertEq (ps.getMaxPacks (100), 0);
    ps.setPayee (buyer);
    assertGt (ps.getMaxPacks (100), 0);
  }

  function test_getMaxPacksAvailableShares () public
  {
    vm.startPrank (admin);
    ps.configure (1, 3, 2);
    setPricing (allShares, 10);
    ps.addClub (100);
    ps.addClub (101);

    /* In all cases, we set the secondary club's available shares to zero,
       which should not matter at all.  */
    setSharesLeft (101, 0);

    /* At least one full pack left.  */
    setSharesLeft (100, 302);
    assertEq (ps.getMaxPacks (100), 100);
    setSharesLeft (100, 6);
    assertEq (ps.getMaxPacks (100), 2);
    setSharesLeft (100, 5);
    assertEq (ps.getMaxPacks (100), 1);
    setSharesLeft (100, 3);
    assertEq (ps.getMaxPacks (100), 1);

    /* Some shares left, but not enough for what to give out.  */
    setSharesLeft (100, 2);
    assertEq (ps.getMaxPacks (100), 1);

    /* No shares are available of the primary club.  */
    setSharesLeft (100, 0);
    assertEq (ps.getMaxPacks (100), 0);

    /* Available shares from the pricing curve.  */
    ps.addClub (102);
    setPricing (100, 1);
    assertEq (ps.getMaxPacks (102), 33);
  }

  /* ************************************************************************ */

  function test_previewInputsWrong () public
  {
    vm.startPrank (admin);
    ps.configure (1, 3, 2);
    setPricing (allShares, 10);
    ps.addClub (100);
    ps.addClub (101);
    /* No shares are available for secondary club, but that should not matter
       for this test.  */
    setSharesLeft (101, 0);

    /* Club is not part of the tier.  */
    vm.expectRevert ("primary club is not part of this tier");
    ps.preview (42, 1);

    /* No packs requested.  */
    vm.expectRevert ("no shares to give out in the primary club");
    ps.preview (100, 0);

    /* No shares to give out by config.  */
    ps.configure (1, 0, 2);
    vm.expectRevert ("no shares to give out in the primary club");
    ps.preview (100, 1);
    ps.configure (1, 3, 2);
    ps.preview (100, 1);

    /* If the club is near sold out, only one pack may be requested.  */
    setSharesLeft (100, 2);
    vm.expectRevert ("primary club is near sold out, only one pack can be bought");
    ps.preview (100, 2);
    /* This will still work.  */
    ps.preview (100, 1);

    /* Club is sold out completely.  */
    setSharesLeft (100, 0);
    vm.expectRevert ("no shares to give out in the primary club");
    ps.preview (100, 1);

    /* No shares available by pricing.  */
    ps.addClub (102);
    setPricing (100, 10);
    cm.mintShares (102, 100, "receiver");
    vm.expectRevert ("no shares to give out in the primary club");
    ps.preview (102, 1);
    setPricing (101, 10);
    ps.preview (102, 1);
  }

  function test_previewBasicMint () public
  {
    vm.startPrank (admin);
    ps.addClub (100);
    ps.addClub (101);
    ps.addClub (102);

    /* Preview is possible with paused contract.  */
    ps.pause ();

    /* Only primary club to give out.  */
    ps.configure (0, 3, 2);
    setPricing (allShares, 10);
    PackSale.PackMint memory data = ps.preview (100, 2);
    assertEq (data.cost, 60);
    assertEq (data.shares.length, 1);
    assertEq (data.shares[0].clubId, 100);
    assertEq (data.shares[0].numShares, 6);
    assertEq (data.soldOut.length, 0);

    ps.configure (2, 3, 0);
    data = ps.preview (100, 2);
    assertEq (data.cost, 60);
    assertEq (data.shares.length, 1);
    assertEq (data.shares[0].clubId, 100);
    assertEq (data.shares[0].numShares, 6);
    assertEq (data.soldOut.length, 0);

    /* Secondary clubs given out, too.  This is deterministic as we give
       actually out all available clubs.  */
    ps.configure (2, 3, 2);
    data = ps.preview (100, 2);
    assertEq (data.cost, 10 * 2 * (3 + 2 * 2));
    assertEq (data.shares.length, 3);
    assertEq (data.shares[0].clubId, 100);
    assertEq (data.shares[0].numShares, 6);
    assertEq (data.shares[1].numShares, 4);
    assertEq (data.shares[2].numShares, 4);
    assertEq (data.shares[1].clubId + data.shares[2].clubId, 101 + 102);
    assertEq (data.soldOut.length, 0);
  }

  function test_previewIncludesSmcMint () public
  {
    vm.startPrank (admin);
    ps.addClub (100);
    ps.addClub (101);
    ps.configure (1, 3, 2);
    setPricing (allShares, 10);

    PackSale.PackMint memory data = ps.preview (100, 2);
    assertEq (data.cost, 100);
    assertEq (data.smcMint, 0);

    ps.setSmcMintRate (paymentBaseUnit);
    data = ps.preview (100, 2);
    assertEq (data.cost, 100);
    assertEq (data.smcMint, 100);
  }

  function test_previewPricingCurve () public
  {
    vm.startPrank (admin);
    ps.configure (1, 3, 2);
    ps.addClub (100);
    ps.addClub (101);
    cm.mintShares (101, 5, "receiver");

    PackSale.PricingStep[] memory pricing = new PackSale.PricingStep[] (3);
    pricing[0] = PackSale.PricingStep (10, 0);
    pricing[1] = PackSale.PricingStep (10, 100);
    pricing[2] = PackSale.PricingStep (10, 200);
    ps.setPricing (pricing);

    PackSale.PackMint memory data = ps.preview (100, 8);
    assertEq (data.shares.length, 2);
    assertEq (data.shares[0].clubId, 100);
    assertEq (data.shares[0].numShares, 24);
    assertEq (data.shares[1].clubId, 101);
    assertEq (data.shares[1].numShares, 16);

    uint primaryCost = 10 * 0 + 10 * 100 + 4 * 200;
    uint secondaryCost = 5 * 0 + 10 * 100 + 1 * 200;
    assertEq (data.cost, primaryCost + secondaryCost);
  }

  function test_previewMintingOutBasedOnShareCap () public
  {
    vm.startPrank (admin);
    ps.configure (1, 3, 2);
    setPricing (allShares, 10);
    ps.addClub (100);
    ps.addClub (101);

    /* Secondary club is near minted out, so we will just give
       what we can for it.  */
    setSharesLeft (101, 4);
    PackSale.PackMint memory data = ps.preview (100, 5);
    assertEq (data.cost, 10 * (5 * 3 + 4));
    assertEq (data.shares.length, 2);
    assertEq (data.shares[0].clubId, 100);
    assertEq (data.shares[0].numShares, 15);
    assertEq (data.shares[1].clubId, 101);
    assertEq (data.shares[1].numShares, 4);
    assertEq (data.soldOut.length, 1);
    assertEq (data.soldOut[0], 101);

    /* Secondary club is minted out completely.  */
    setSharesLeft (101, 0);
    data = ps.preview (100, 5);
    assertEq (data.cost, 10 * 5 * 3);
    assertEq (data.shares.length, 1);
    assertEq (data.shares[0].clubId, 100);
    assertEq (data.shares[0].numShares, 15);

    /* Primary club is near minted out.  */
    setSharesLeft (100, 2);
    data = ps.preview (100, 1);
    assertEq (data.cost, 10 * 2);
    assertEq (data.shares.length, 1);
    assertEq (data.shares[0].clubId, 100);
    assertEq (data.shares[0].numShares, 2);
  }

  function test_previewMintingOutBasedOnPricing () public
  {
    vm.startPrank (admin);
    ps.configure (1, 3, 2);
    setPricing (100, 10);
    ps.addClub (100);
    ps.addClub (101);

    /* Secondary club has only one share available, so it will mint out.  */
    cm.mintShares (101, 99, "receiver");
    PackSale.PackMint memory data = ps.preview (100, 1);
    assertEq (data.shares.length, 2);
    assertEq (data.shares[0].clubId, 100);
    assertEq (data.shares[0].numShares, 3);
    assertEq (data.shares[1].clubId, 101);
    assertEq (data.shares[1].numShares, 1);
    assertEq (data.soldOut.length, 1);
    assertEq (data.soldOut[0], 101);
  }

  function test_previewSmallListOfSecondaryClubs () public
  {
    /* If we request more secondary clubs than there are clubs available,
       it should still work fine.  */
    vm.startPrank (admin);
    ps.configure (20, 3, 2);
    setPricing (allShares, 10);
    ps.addClub (100);
    ps.addClub (101);
    ps.addClub (102);
    setSharesLeft (101, 0);

    PackSale.PackMint memory data = ps.preview (100, 1);
    assertEq (data.shares.length, 2);
    assertEq (data.shares[0].clubId, 100);
    assertEq (data.shares[0].numShares, 3);
    assertEq (data.shares[1].clubId, 102);
    assertEq (data.shares[1].numShares, 2);
    assertEq (data.soldOut.length, 1);
    assertEq (data.soldOut[0], 101);
  }

  function test_previewAppliesPseudoRandomisation () public
  {
    vm.startPrank (admin);
    ps.configure (1, 1, 1);
    setPricing (allShares, 10);
    for (uint i = 100; i < 1000; ++i)
      ps.addClub (i);

    PackSale.PackMint memory data1 = ps.preview (100, 1);
    PackSale.PackMint memory data1p = ps.preview (100, 2);
    assertEq (data1.shares[1].clubId, data1p.shares[1].clubId);
    PackSale.PackMint memory data2 = ps.preview (101, 1);
    assertNotEq (data1.shares[1].clubId, data2.shares[1].clubId);

    assertTrue (ps.isPackMintCurrent (data1));
    /* Make sure we actually change the block (hash) before bumping the seed
       (which is otherwise not done in the test environment.  */
    vm.roll (block.number + 1);
    ps.updateSeed ();
    assertFalse (ps.isPackMintCurrent (data1));

    PackSale.PackMint memory data3 = ps.preview (100, 1);
    assertNotEq (data1.shares[1].clubId, data3.shares[1].clubId);
  }

  function test_isPackMintCurrent () public
  {
    vm.startPrank (admin);
    ps.configure (1, 3, 2);
    ps.setSmcMintRate (paymentBaseUnit);
    setPricing (allShares, 10);
    ps.addClub (100);
    ps.addClub (101);

    PackSale.PackMint memory data = ps.preview (100, 2);
    assertTrue (ps.isPackMintCurrent (data));

    /* Cost changed.  */
    setPricing (allShares, 15);
    assertFalse (ps.isPackMintCurrent (data));
    setPricing (allShares, 10);
    assertTrue (ps.isPackMintCurrent (data));

    /* SMC mint changed.  */
    ps.setSmcMintRate (0);
    assertFalse (ps.isPackMintCurrent (data));
    ps.setSmcMintRate (paymentBaseUnit * 2);
    assertFalse (ps.isPackMintCurrent (data));
    ps.setSmcMintRate (paymentBaseUnit);
    assertTrue (ps.isPackMintCurrent (data));

    /* Length of shares array changed.  */
    ps.configure (0, 3, 2);
    assertFalse (ps.isPackMintCurrent (data));
    ps.configure (1, 3, 2);
    assertTrue (ps.isPackMintCurrent (data));

    /* Club ID replaced in shares array.  */
    ps.removeClub (101);
    ps.addClub (200);
    assertFalse (ps.isPackMintCurrent (data));
    ps.removeClub (200);
    ps.addClub (101);
    assertTrue (ps.isPackMintCurrent (data));

    /* Number of shares is changed.  */
    ps.configure (1, 5, 2);
    assertFalse (ps.isPackMintCurrent (data));
    ps.configure (1, 3, 2);
    assertTrue (ps.isPackMintCurrent (data));
    ps.configure (1, 3, 1);
    assertFalse (ps.isPackMintCurrent (data));
    ps.configure (1, 3, 2);
    assertTrue (ps.isPackMintCurrent (data));
  }

  /* ************************************************************************ */

  function test_mintFailsIfNotCurrent () public
  {
    vm.startPrank (admin);
    ps.configure (0, 7, 2);
    setPricing (allShares, 10);
    ps.addClub (100);

    PackSale.PackMint memory data = ps.preview (100, 3);
    ps.configure (0, 8, 2);

    vm.startPrank (buyer);
    vm.expectRevert ("provided PackMint data is no longer valid");
    ps.mint (data, "receiver");

    assertEq (usdc.balanceOf (buyer), balance);
    assertEq (cm.sharesMinted (100), 0);
  }

  function test_mintFailsIfPaymentFails () public
  {
    vm.startPrank (admin);
    ps.configure (0, 1, 0);
    setPricing (allShares, balance);
    ps.addClub (100);

    vm.startPrank (buyer);
    PackSale.PackMint memory data = ps.preview (100, 2);
    vm.expectRevert ("ERC20: transfer amount exceeds balance");
    ps.mint (data, "receiver");

    usdc.approve (address (ps), 1);
    data = ps.preview (100, 1);
    vm.expectRevert ("ERC20: insufficient allowance");
    ps.mint (data, "receiver");

    assertEq (cm.sharesMinted (100), 0);

    usdc.approve (address (ps), balance);
    ps.mint (data, "receiver");
    assertEq (cm.sharesMinted (100), 1);
  }

  function test_mintFailsIfNoPayee () public
  {
    vm.startPrank (admin);
    ps.configure (0, 7, 0);
    setPricing (allShares, 10);
    ps.addClub (100);
    ps.setPayee (address (0));

    vm.startPrank (buyer);
    PackSale.PackMint memory data = ps.preview (100, 2);
    vm.expectRevert ("no payee configured");
    ps.mint (data, "receiver");
  }

  function test_mintTakesPayment () public
  {
    vm.startPrank (admin);
    ps.configure (0, 7, 0);
    setPricing (allShares, 10);
    ps.addClub (100);

    vm.startPrank (buyer);
    PackSale.PackMint memory data = ps.preview (100, 3);
    ps.mint (data, "receiver");

    assertEq (usdc.balanceOf (buyer), balance - 10 * 3 * 7);
    assertEq (usdc.balanceOf (payee), 10 * 3 * 7);

    assertEq (cm.sharesMinted (100), 3 * 7);
  }

  function test_mintFreePack () public
  {
    vm.startPrank (admin);
    ps.configure (0, 1, 0);
    setPricing (allShares, 0);
    ps.addClub (100);

    vm.startPrank (buyer);
    PackSale.PackMint memory data = ps.preview (100, 10);
    ps.mint (data, "receiver");

    assertEq (usdc.balanceOf (buyer), balance);
    assertEq (usdc.balanceOf (payee), 0);

    assertEq (cm.sharesMinted (100), 10);
  }

  function test_mintGivesAllClubsFromPreview () public
  {
    vm.startPrank (admin);
    ps.configure (2, 7, 5);
    setPricing (allShares, 10);
    ps.addClub (100);
    ps.addClub (101);
    ps.addClub (102);

    vm.startPrank (buyer);
    PackSale.PackMint memory data = ps.preview (100, 3);
    ps.mint (data, "receiver");

    assertEq (cm.sharesMinted (100), 3 * 7);
    assertEq (cm.sharesMinted (101), 3 * 5);
    assertEq (cm.sharesMinted (102), 3 * 5);
  }

  function test_mintSmcToClub () public
  {
    vm.startPrank (admin);
    ps.configure (1, 5, 1);
    ps.setSmcMintRate (paymentBaseUnit);
    setPricing (allShares, 10);
    ps.addClub (100);
    ps.addClub (101);

    string[] memory path = new string[] (3);
    path[0] = "cmd";
    path[1] = "mint";
    path[2] = "clubsmc";

    vm.startPrank (buyer);
    PackSale.PackMint memory data = ps.preview (100, 3);
    assertEq (data.smcMint, 180);
    /* Two moves for minting the shares are emitted before this one,
       so we have a nonce delta of 2.  */
    expectMove ("g", Config.GAME_ID, 2, path, '{"c":100,"n":180}');
    ps.mint (data, "receiver");

    data = ps.preview (101, 2);
    assertEq (data.smcMint, 120);
    expectMove ("g", Config.GAME_ID, 2, path, '{"c":101,"n":120}');
    ps.mint (data, "receiver");
  }

  function test_mintPausesSoldOutClubs () public
  {
    vm.startPrank (admin);
    ps.configure (3, 7, 5);
    setPricing (allShares, 10);
    ps.addClub (100);
    ps.addClub (101);
    ps.addClub (102);
    ps.addClub (103);

    /* The config tries to pick three secondary clubs, which means that all
       three will be tried.  One is fully sold out, one will be sold out
       afterwards, and one will not be sold out and just included in the
       previewed pack.  */
    setSharesLeft (102, 0);
    setSharesLeft (103, 2);

    vm.startPrank (buyer);
    PackSale.PackMint memory data = ps.preview (100, 1);
    assertEq (data.shares.length, 3);
    assertEq (data.soldOut.length, 2);
    assertEq (data.soldOut[0] + data.soldOut[1], 102 + 103);

    ps.mint (data, "receiver");

    uint[] memory clubs = ps.getAllClubs ();
    assertEq (clubs.length, 2);
    assertEq (clubs[0], 100);
    assertEq (clubs[1], 101);
    checkClubIndices ();

    clubs = ps.getPausedClubs ();
    assertEq (clubs.length, 2);
    assertEq (clubs[0] + clubs[1], 102 + 103);
  }

  /* ************************************************************************ */

  function test_referralBonus () public
  {
    vm.startPrank (admin);
    ps.configure (1, 100, 10);
    setPricing (allShares, 0);
    ps.addClub (100);
    ps.addClub (101);
    ps.setRefBonus (ps.refBonusBase () / 10, 1000);
    ref.trySetReferrer ("receiver", "referrer");

    /* We check the actual moves to ensure that the referrer is correctly
       given the shares, and not e.g. some other name.  */
    string[] memory path = new string[] (3);
    path[0] = "cmd";
    path[1] = "mint";
    path[2] = "shares";
    expectMove ("g", Config.GAME_ID, 0, path,
                '{"s":{"club":100},"r":"receiver","n":1000}');
    expectMove ("g", Config.GAME_ID, 1, path,
                '{"s":{"club":101},"r":"receiver","n":100}');
    expectMove ("g", Config.GAME_ID, 2, path,
                '{"s":{"club":100},"r":"referrer","n":100}');

    /* Referrer gets 10%.  */
    PackSale.PackMint memory data = ps.preview (100, 10);
    ps.mint (data, "receiver");
    assertEq (cm.sharesMinted (100), 1100);
    assertEq (cm.sharesMinted (101), 100);

    /* Referrer bonus is rounded down to zero.  */
    ps.setRefBonus (1, 1000);
    ps.mint (data, "receiver");
    assertEq (cm.sharesMinted (100), 2100);
    assertEq (cm.sharesMinted (101), 200);
  }

  function test_referralBonusSoldOutClubs () public
  {
    uint cap = 1000;

    vm.startPrank (admin);
    ps.configure (1, 100, 10);
    setPricing (cap, 0);
    ps.addClub (100);
    ps.addClub (101);
    ps.setRefBonus (ps.refBonusBase () / 10, 1000);
    ref.trySetReferrer ("receiver", "referrer");

    cm.mintShares (100, cap - 102, "reserved");

    /* The referrer gets only 2 remaining shares.  */
    vm.startPrank (buyer);
    PackSale.PackMint memory data = ps.preview (100, 1);
    ps.mint (data, "receiver");
    assertEq (cm.sharesMinted (100), cap);
    assertEq (cm.sharesMinted (101), 10);

    /* The club should have been paused.  */
    uint[] memory paused = ps.getPausedClubs ();
    assertEq (paused.length, 1);
    assertEq (paused[0], 100);
  }

  function test_referralBonusTimeLimit () public
  {
    vm.startPrank (admin);
    ps.configure (1, 100, 10);
    setPricing (allShares, 0);
    ps.addClub (100);
    ps.addClub (101);
    ps.setRefBonus (ps.refBonusBase () / 10, 1000);
    ref.trySetReferrer ("receiver", "referrer");

    /* Referrer still gets a bonus.  */
    skip (900);
    vm.startPrank (buyer);
    PackSale.PackMint memory data = ps.preview (100, 10);
    ps.mint (data, "receiver");
    assertEq (cm.sharesMinted (100), 1100);
    assertEq (cm.sharesMinted (101), 100);

    /* Bonus is no longer given.  */
    skip (200);
    ps.mint (data, "receiver");
    assertEq (cm.sharesMinted (100), 2100);
    assertEq (cm.sharesMinted (101), 200);
  }

  /* ************************************************************************ */

  function test_incrementsPurchaseTracker () public
  {
    vm.startPrank (admin);
    ps.configure (0, 10, 0);
    setPricing (allShares, 2);
    ps.addClub (100);

    vm.startPrank (buyer);
    PackSale.PackMint memory data = ps.preview (100, 3);
    ps.mint (data, "receiver");

    data = ps.preview (100, 1);
    vm.expectEmit (address (pt));
    emit PurchaseTracker.TotalIncremented (buyer, "receiver", 20);
    ps.mint (data, "receiver");

    assertEq (pt.getData (buyer).total, 80);
    assertEq (pt.getData ("receiver").total, 80);
  }

  function test_sanctionsConfiguration () public
  {
    TestSanctionsList sl = new TestSanctionsList ();

    vm.startPrank (admin);
    ps.setSanctionsList (sl);
    ps.setKycThreshold (123);

    vm.startPrank (buyer);
    vm.expectRevert (Utils.missingRoleError (buyer, ps.CONFIGURE_ROLE ()));
    ps.setSanctionsList (ISanctionsList (address (0)));
    vm.expectRevert (Utils.missingRoleError (buyer, ps.CONFIGURE_ROLE ()));
    ps.setKycThreshold (1000);

    assertTrue (ps.sanctionsList () == sl);
    assertEq (ps.kycThreshold (), 123);
  }

  function test_checkPurchaseApprovalSanctions () public
  {
    address sanctioned = address (ripemd160 ("sanctioned"));

    TestSanctionsList sl = new TestSanctionsList ();
    sl.setSanctioned (sanctioned);

    vm.prank (admin);
    ps.setSanctionsList (sl);

    assertTrue (ps.checkPurchaseApproval (buyer, "domob", 100)
                  == PackSale.ApprovalCheckResult.Ok);
    assertTrue (ps.checkPurchaseApproval (sanctioned, "domob", 100)
                  == PackSale.ApprovalCheckResult.Sanctioned);

    /* It is possible to disable the sanctions screening entirely by
       setting the oracle to the zero address.  */
    vm.prank (admin);
    ps.setSanctionsList (ISanctionsList (address (0)));
    assertTrue (ps.checkPurchaseApproval (sanctioned, "domob", 100)
                  == PackSale.ApprovalCheckResult.Ok);
  }

  function test_checkPurchaseApprovalKycThreshold () public
  {
    vm.startPrank (admin);

    ps.setKycThreshold (100);
    pt.overwrite (buyer, 50);
    /* The account name is not used and so it should not matter
       if the total is already beyond the threshold.  */
    pt.overwrite ("domob", 200);

    assertTrue (ps.checkPurchaseApproval (buyer, "domob", 49)
                  == PackSale.ApprovalCheckResult.Ok);
    assertTrue (ps.checkPurchaseApproval (buyer, "domob", 50)
                  == PackSale.ApprovalCheckResult.KycNeeded);

    pt.setApproved (buyer, true);
    assertTrue (ps.checkPurchaseApproval (buyer, "domob", 200)
                  == PackSale.ApprovalCheckResult.Ok);
  }

  function test_purchaseChecksApproval () public
  {
    TestSanctionsList sl = new TestSanctionsList ();

    vm.startPrank (admin);
    ps.configure (0, 10, 0);
    setPricing (allShares, 2);
    ps.addClub (100);
    ps.setSanctionsList (sl);

    vm.startPrank (buyer);
    PackSale.PackMint memory data = ps.preview (100, 3);
    ps.mint (data, "receiver");

    sl.setSanctioned (buyer);
    vm.expectRevert ("not allowed to purchase");
    ps.mint (data, "receiver");
  }

  /* ************************************************************************ */

}
