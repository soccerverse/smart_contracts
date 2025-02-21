// SPDX-License-Identifier: MIT
// Copyright (C) 2025 Soccerverse Ltd

pragma solidity ^0.8.19;

import "./SaleTest.sol";
import "./Utils.sol";
import "../src/PackVoucher.sol";

contract PackVoucherTest is SaleTest
{

  address public constant tokenAdmin = address (101);
  address public constant minter = address (102);
  address public constant burner = address (103);
  address public constant buyer = address (104);

  PackVoucher public immutable t;

  constructor ()
  {
    vm.label (tokenAdmin, "token admin");
    vm.label (minter, "limited minter");
    vm.label (burner, "burner");
    vm.label (buyer, "buyer");

    vm.startPrank (admin);

    t = new PackVoucher ("Voucher", "PV", cm, usdc);
    t.grantRole (t.TOKEN_ADMIN_ROLE (), tokenAdmin);
    t.grantRole (t.LIMITED_MINTER_ROLE (), minter);
    t.grantRole (t.BURNER_ROLE (), burner);
    cm.grantRole (cm.MINTER_ROLE (), address (t));

    /* Apply a basic configuration for the underlying PackSale.  */
    ps.configure (0, 1, 0);
    setPricing (100, 10);
    ps.addClub (100);

    vm.stopPrank ();
  }

  /* ************************************************************************ */

  function test_pausing () public
  {
    vm.startPrank (tokenAdmin);
    t.mint (buyer, 1000);

    vm.startPrank (buyer);
    vm.expectRevert (Utils.missingRoleError (buyer, t.DEFAULT_ADMIN_ROLE ()));
    t.pause ();

    assertFalse (t.paused ());

    vm.startPrank (admin);
    t.pause ();

    vm.startPrank (buyer);
    vm.expectRevert (Utils.missingRoleError (buyer, t.DEFAULT_ADMIN_ROLE ()));
    t.unpause ();

    assertTrue (t.paused ());

    PackSale.PackMint memory data = ps.preview (100, 3);
    vm.expectRevert ("Pausable: paused");
    t.redeem (ps, data, "domob");

    vm.startPrank (admin);
    t.unpause ();
    assertFalse (t.paused ());
  }

  function test_tokenDecimals () public view
  {
    uint8 dec = t.decimals ();
    assertNotEq (dec, 18);
    assertEq (dec, usdc.decimals ());
  }

  function test_transfersNotPossible () public
  {
    vm.prank (tokenAdmin);
    t.mint (buyer, 1000);

    vm.prank (buyer);
    vm.expectPartialRevert (PackVoucher.TransferIsNotPossible.selector);
    t.transfer (minter, 10);

    vm.prank (buyer);
    t.approve (tokenAdmin, 1000);
    vm.prank (tokenAdmin);
    vm.expectPartialRevert (PackVoucher.TransferIsNotPossible.selector);
    t.transferFrom (buyer, minter, 10);

    assertEq (t.balanceOf (buyer), 1000);
  }

  /* ************************************************************************ */

  function test_adminMintAndBurn () public
  {
    /* The token admin can mint and burn freely.  */
    vm.startPrank (tokenAdmin);
    t.mint (buyer, 100);
    assertEq (t.balanceOf (buyer), 100);
    t.burnFrom (buyer, 10);
    assertEq (t.balanceOf (buyer), 90);

    /* Minting will not affect the limit set.  */
    t.setMintLimit (1000);
    t.mint (buyer, 20);
    assertEq (t.balanceOf (buyer), 110);
    assertEq (t.mintLimitRemaining (), 1000);
  }

  function test_burn () public
  {
    vm.startPrank (tokenAdmin);
    t.mint (buyer, 200);

    vm.startPrank (minter);
    vm.expectPartialRevert (PackVoucher.NotAllowedToBurn.selector);
    t.burnFrom (buyer, 10);

    vm.startPrank (buyer);
    t.burnFrom (buyer, 20);

    vm.startPrank (burner);
    t.burnFrom (buyer, 30);

    assertEq (t.balanceOf (buyer), 150);
  }

  function test_batchBurn () public
  {
    vm.startPrank (tokenAdmin);
    t.mint (buyer, 100);
    t.mint (minter, 100);

    PackVoucher.BurnOp[] memory ops = new PackVoucher.BurnOp[] (3);
    ops[0].from = buyer;
    ops[0].amount = 10;
    ops[1].from = minter;
    ops[1].amount = 20;
    ops[2].from = buyer;
    ops[2].amount = 30;

    vm.startPrank (burner);
    t.batchBurn (ops);
    t.batchBurn (ops);

    vm.startPrank (minter);
    vm.expectPartialRevert (PackVoucher.NotAllowedToBurn.selector);
    t.batchBurn (ops);

    assertEq (t.balanceOf (buyer), 20);
    assertEq (t.balanceOf (minter), 60);
  }

  function test_mintNotAllowed () public
  {
    vm.startPrank (buyer);
    vm.expectPartialRevert (PackVoucher.NotAllowedToMint.selector);
    t.mint (buyer, 10);

    assertEq (t.balanceOf (buyer), 0);
  }

  function test_limitedMint () public
  {
    vm.startPrank (tokenAdmin);
    vm.expectEmit (address (t));
    emit PackVoucher.MintLimitChanged (100);
    t.setMintLimit (100);

    vm.startPrank (minter);
    vm.expectEmit (address (t));
    emit PackVoucher.MintLimitChanged (90);
    t.mint (buyer, 10);
    t.mint (buyer, 20);

    assertEq (t.mintLimitRemaining (), 70);
    assertEq (t.balanceOf (buyer), 30);

    vm.expectPartialRevert (PackVoucher.MintLimitExceeded.selector);
    t.mint (buyer, 71);

    t.mint (buyer, 70);
    assertEq (t.mintLimitRemaining (), 0);
    assertEq (t.balanceOf (buyer), 100);

    vm.expectPartialRevert (PackVoucher.MintLimitExceeded.selector);
    t.mint (buyer, 1);
  }

  function test_batchMint () public
  {
    PackVoucher.MintOp[] memory ops = new PackVoucher.MintOp[] (3);
    ops[0].to = buyer;
    ops[0].amount = 10;
    ops[1].to = minter;
    ops[1].amount = 20;
    ops[2].to = buyer;
    ops[2].amount = 30;

    vm.startPrank (tokenAdmin);
    t.setMintLimit (100);

    vm.startPrank (minter);
    vm.expectEmit (address (t));
    emit PackVoucher.MintLimitChanged (40);
    t.batchMint (ops);

    assertEq (t.mintLimitRemaining (), 40);
    assertEq (t.balanceOf (buyer), 40);
    assertEq (t.balanceOf (minter), 20);

    vm.expectPartialRevert (PackVoucher.MintLimitExceeded.selector);
    t.batchMint (ops);

    vm.startPrank (buyer);
    vm.expectPartialRevert (PackVoucher.NotAllowedToMint.selector);
    t.batchMint (ops);

    vm.startPrank (tokenAdmin);
    t.batchMint (ops);
    assertEq (t.balanceOf (buyer), 80);
    assertEq (t.balanceOf (minter), 40);
  }

  /* ************************************************************************ */

  function test_invalidSale () public
  {
    vm.startPrank (tokenAdmin);
    t.mint (buyer, 1000);

    PackSale.PackMint memory data = ps.preview (100, 3);

    /* Sale is paused.  */
    vm.startPrank (admin);
    ps.pause ();

    vm.startPrank (buyer);
    vm.expectPartialRevert (PackVoucher.InvalidPackSaleContract.selector);
    t.redeem (ps, data, "domob");

    /* Not minter permission.  */
    vm.startPrank (admin);
    ps.unpause ();
    cm.revokeRole (cm.MINTER_ROLE (), address (ps));

    vm.startPrank (buyer);
    vm.expectPartialRevert (PackVoucher.InvalidPackSaleContract.selector);
    t.redeem (ps, data, "domob");

    /* Now it works.  */
    vm.startPrank (admin);
    cm.grantRole (cm.MINTER_ROLE (), address (ps));

    vm.startPrank (buyer);
    t.redeem (ps, data, "domob");
    assertEq (t.balanceOf (buyer), 1000 - 30);
    assertEq (cm.sharesMinted (100), 3);
  }

  function test_outdatedMintData () public
  {
    vm.startPrank (tokenAdmin);
    t.mint (buyer, 1000);

    PackSale.PackMint memory data = ps.preview (100, 3);

    vm.startPrank (admin);
    ps.configure (0, 2, 0);

    vm.startPrank (buyer);
    vm.expectPartialRevert (PackVoucher.PackMintDataInvalid.selector);
    t.redeem (ps, data, "domob");
  }

  function test_redeemExceedingBalance () public
  {
    vm.startPrank (tokenAdmin);
    t.mint (buyer, 29);

    PackSale.PackMint memory data = ps.preview (100, 3);

    vm.startPrank (buyer);
    vm.expectPartialRevert (PackVoucher.RedeemExceedsBalance.selector);
    t.redeem (ps, data, "domob");
  }

  function test_redeemSuccess () public
  {
    vm.startPrank (tokenAdmin);
    t.mint (buyer, 60);

    PackSale.PackMint memory data = ps.preview (100, 3);

    vm.startPrank (buyer);
    vm.expectEmit (address (t));
    emit PackSale.PacksBought (buyer, "domob", 100, 3, 30);
    t.redeem (ps, data, "domob");
    t.redeem (ps, data, "andy");

    assertEq (t.balanceOf (buyer), 0);
    assertEq (cm.sharesMinted (100), 6);
  }

  function test_batchRedeem () public
  {
    vm.startPrank (tokenAdmin);
    t.mint (buyer, 60);

    PackVoucher.RedeemOp[] memory ops = new PackVoucher.RedeemOp[] (2);
    ops[0].sale = ps;
    ops[0].mintData = ps.preview (100, 3);
    ops[0].receiver = "domob";
    ops[1].sale = ps;
    ops[1].mintData = ps.preview (100, 2);
    ops[1].receiver = "andy";

    /* Spot-check that conditions of redeem() are checked, too.  */
    vm.startPrank (admin);
    t.pause ();
    vm.startPrank (buyer);
    vm.expectRevert ("Pausable: paused");
    t.batchRedeem (ops);
    vm.startPrank (admin);
    t.unpause ();

    vm.startPrank (buyer);
    t.batchRedeem (ops);
    vm.expectPartialRevert (PackVoucher.RedeemExceedsBalance.selector);
    t.batchRedeem (ops);

    assertEq (t.balanceOf (buyer), 10);
    assertEq (cm.sharesMinted (100), 5);
  }

}
