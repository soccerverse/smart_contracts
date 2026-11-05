// SPDX-License-Identifier: MIT
// Copyright (C) 2026 Soccerverse Ltd

pragma solidity ^0.8.19;

import "./SaleTest.sol";
import "./Utils.sol";
import "../src/SVVMinter.sol";

contract SVVMinterTest is SaleTest
{

  address public constant minter = address (101);
  address public constant secondMinter = address (102);
  address public constant alice = address (103);
  address public constant bob = address (104);

  PackVoucher public immutable t;
  SVVMinter public immutable m;

  constructor ()
  {
    vm.label (minter, "minter");
    vm.label (secondMinter, "second minter");
    vm.label (alice, "alice");
    vm.label (bob, "bob");

    vm.startPrank (admin);

    t = new PackVoucher ("Voucher", "SVV", cm, usdc);
    m = new SVVMinter (t);
    t.grantRole (t.TOKEN_ADMIN_ROLE (), address (m));

    vm.stopPrank ();
  }

  /* ************************************************************************ */

  function test_mintingPermission () public
  {
    assertTrue (m.hasMintingPermission ());

    vm.startPrank (admin);
    t.revokeRole (t.TOKEN_ADMIN_ROLE (), address (m));
    assertFalse (m.hasMintingPermission ());

    t.grantRole (t.TOKEN_ADMIN_ROLE (), address (m));
    assertTrue (m.hasMintingPermission ());
  }

  function test_setLimit () public
  {
    vm.startPrank (minter);
    vm.expectRevert (Utils.missingRoleError (minter, m.DEFAULT_ADMIN_ROLE ()));
    m.setLimit (minter, 100);

    vm.startPrank (admin);

    vm.expectEmit (address (m));
    emit SVVMinter.MintLimitChanged (minter, 0, 100);
    m.setLimit (minter, 100);
    assertEq (m.addressMintLimit (minter), 100);

    vm.expectEmit (address (m));
    emit SVVMinter.MintLimitChanged (minter, 100, 40);
    m.setLimit (minter, 40);
    assertEq (m.addressMintLimit (minter), 40);
  }

  function test_setLimitUnchanged () public
  {
    vm.startPrank (admin);
    m.setLimit (minter, 100);

    vm.recordLogs ();
    m.setLimit (minter, 100);

    assertEq (vm.getRecordedLogs ().length, 0);
    assertEq (m.addressMintLimit (minter), 100);
  }

  /* ************************************************************************ */

  function test_mint () public
  {
    vm.startPrank (admin);
    m.setLimit (minter, 100);

    vm.startPrank (minter);
    vm.expectEmit (address (m));
    emit SVVMinter.MintLimitChanged (minter, 100, 90);
    m.mint (alice, 10);

    assertEq (t.balanceOf (alice), 10);
    assertEq (m.addressMintLimit (minter), 90);
  }

  function test_mintLimitExceeded () public
  {
    vm.prank (minter);
    vm.expectPartialRevert (SVVMinter.MintLimitExceeded.selector);
    m.mint (alice, 1);

    vm.startPrank (admin);
    m.setLimit (minter, 100);

    vm.startPrank (minter);
    vm.expectPartialRevert (SVVMinter.MintLimitExceeded.selector);
    m.mint (alice, 101);

    assertEq (t.balanceOf (alice), 0);
    assertEq (m.addressMintLimit (minter), 100);
  }

  function test_batchMint () public
  {
    PackVoucher.MintOp[] memory ops = new PackVoucher.MintOp[] (3);
    ops[0].to = alice;
    ops[0].amount = 10;
    ops[1].to = bob;
    ops[1].amount = 20;
    ops[2].to = alice;
    ops[2].amount = 5;

    vm.startPrank (admin);
    m.setLimit (minter, 100);

    vm.startPrank (minter);
    vm.expectEmit (address (m));
    emit SVVMinter.MintLimitChanged (minter, 100, 65);
    m.batchMint (ops);

    assertEq (t.balanceOf (alice), 15);
    assertEq (t.balanceOf (bob), 20);
    assertEq (m.addressMintLimit (minter), 65);

    PackVoucher.MintOp[] memory tooMany = new PackVoucher.MintOp[] (1);
    tooMany[0].to = bob;
    tooMany[0].amount = 66;

    vm.expectPartialRevert (SVVMinter.MintLimitExceeded.selector);
    m.batchMint (tooMany);

    assertEq (t.balanceOf (bob), 20);
    assertEq (m.addressMintLimit (minter), 65);
  }

  function test_zeroMint () public
  {
    vm.startPrank (admin);
    m.setLimit (minter, 100);

    /* No logs should be emitted for zero mints, not even Transfer
       from the SVV contract itself.  */
    vm.recordLogs ();

    vm.startPrank (minter);
    m.mint (alice, 0);

    vm.startPrank (secondMinter);
    m.mint (alice, 0);

    assertEq (vm.getRecordedLogs ().length, 0);
    assertEq (t.balanceOf (alice), 0);
    assertEq (m.addressMintLimit (minter), 100);
  }

  function test_perAddressLimits () public
  {
    vm.startPrank (admin);
    m.setLimit (minter, 10);
    m.setLimit (secondMinter, 20);

    vm.startPrank (minter);
    vm.expectPartialRevert (SVVMinter.MintLimitExceeded.selector);
    m.mint (alice, 11);
    m.mint (alice, 10);

    vm.startPrank (secondMinter);
    m.mint (bob, 20);

    vm.startPrank (minter);
    vm.expectPartialRevert (SVVMinter.MintLimitExceeded.selector);
    m.mint (alice, 1);

    assertEq (t.balanceOf (alice), 10);
    assertEq (t.balanceOf (bob), 20);
    assertEq (m.addressMintLimit (minter), 0);
    assertEq (m.addressMintLimit (secondMinter), 0);
  }

}
