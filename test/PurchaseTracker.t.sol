// SPDX-License-Identifier: MIT
// Copyright (C) 2024 Soccerverse Ltd

pragma solidity ^0.8.19;

import "./Utils.sol";
import "../src/PurchaseTracker.sol";

import { Test } from "forge-std/Test.sol";

contract PurchaseTrackerTest is Test
{

  address public constant admin = address (1);
  address public constant incrementer = address (2);
  address public constant approver = address (3);
  address public constant other = address (4);

  address public constant buyer1 = address (5);
  address public constant buyer2 = address (6);

  PurchaseTracker public pt;

  constructor ()
  {
    vm.label (admin, "admin");
    vm.label (incrementer, "incrementer");
    vm.label (approver, "approver");
    vm.label (buyer1, "buyer 1");
    vm.label (buyer2, "buyer 2");

    vm.startPrank (admin);
    pt = new PurchaseTracker ();
    pt.grantRole (pt.INCREMENT_TOTAL_ROLE (), incrementer);
    pt.grantRole (pt.APPROVER_ROLE (), approver);
    vm.stopPrank ();
  }

  function test_increment () public
  {
    vm.startPrank (incrementer);

    vm.expectEmit (address (pt));
    emit PurchaseTracker.TotalIncremented (buyer1, "domob", 100);
    pt.increment (buyer1, "domob", 100);

    vm.expectEmit (address (pt));
    emit PurchaseTracker.TotalIncremented (buyer2, "domob", 200);
    pt.increment (buyer2, "domob", 200);

    vm.expectEmit (address (pt));
    emit PurchaseTracker.TotalIncremented (buyer2, "andy", 300);
    pt.increment (buyer2, "andy", 300);

    vm.stopPrank ();

    assertEq (pt.getData (buyer1).total, 100);
    assertEq (pt.getData (buyer2).total, 500);
    assertEq (pt.getData ("domob").total, 300);
    assertEq (pt.getData ("andy").total, 300);

    vm.startPrank (other);
    vm.expectRevert (
        Utils.missingRoleError (other, pt.INCREMENT_TOTAL_ROLE ()));
    pt.increment (buyer1, "domob", 400);
  }

  function test_overwrite () public
  {
    vm.startPrank (incrementer);
    pt.increment (buyer1, "domob", 100);
    pt.increment (buyer2, "admin", 200);

    vm.startPrank (admin);
    vm.expectEmit (address (pt));
    emit PurchaseTracker.BuyerTotalSet (buyer1, 500);
    pt.overwrite (buyer1, 500);
    assertEq (pt.getData (buyer1).total, 500);
    assertEq (pt.getData (buyer2).total, 200);
    assertEq (pt.getData ("domob").total, 100);

    vm.expectEmit (address (pt));
    emit PurchaseTracker.AccountTotalSet ("domob", 800);
    pt.overwrite ("domob", 800);
    assertEq (pt.getData (buyer1).total, 500);
    assertEq (pt.getData ("domob").total, 800);
    assertEq (pt.getData ("admin").total, 200);

    vm.startPrank (incrementer);
    vm.expectRevert (
        Utils.missingRoleError (incrementer, pt.DEFAULT_ADMIN_ROLE ()));
    pt.overwrite (buyer1, 1);
    vm.expectRevert (
        Utils.missingRoleError (incrementer, pt.DEFAULT_ADMIN_ROLE ()));
    pt.overwrite ("domob", 1);
  }

  function test_approval () public
  {
    vm.startPrank (approver);
    pt.setApproved (buyer1, true);
    pt.setApproved (buyer2, true);

    vm.expectEmit (address (pt));
    emit PurchaseTracker.AccountApprovalSet ("domob", true);
    pt.setApproved ("domob", true);
    vm.expectEmit (address (pt));
    emit PurchaseTracker.BuyerApprovalSet (buyer2, false);
    pt.setApproved (buyer2, false);

    assertTrue (pt.getData (buyer1).approved);
    assertFalse (pt.getData (buyer2).approved);
    assertTrue (pt.getData ("domob").approved);
    assertFalse (pt.getData ("andy").approved);

    vm.startPrank (incrementer);
    vm.expectRevert (
        Utils.missingRoleError (incrementer, pt.APPROVER_ROLE ()));
    pt.setApproved (buyer2, true);
    vm.expectRevert (
        Utils.missingRoleError (incrementer, pt.APPROVER_ROLE ()));
    pt.setApproved ("andy", true);
  }

}
