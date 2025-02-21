// SPDX-License-Identifier: MIT
// Copyright (C) 2024 Soccerverse Ltd

pragma solidity ^0.8.19;

import "./Utils.sol";
import "../src/ReferralTracker.sol";

import { Test } from "forge-std/Test.sol";

contract ReferralTrackerTest is Test
{

  address public constant admin = address (ripemd160 ("admin"));
  address public constant setter = address (ripemd160 ("whitelisted"));
  address public constant other = address (ripemd160 ("other"));

  ReferralTracker public rt;

  constructor ()
  {
    vm.startPrank (admin);
    rt = new ReferralTracker ();
    rt.grantRole (rt.SET_REFERRER_ROLE (), setter);
    vm.stopPrank ();
  }

  function test_trySetReferrer () public
  {
    assertFalse (rt.hasReferrer ("andy"));
    assertFalse (rt.hasReferrer ("domob"));

    vm.startPrank (setter);
    rt.trySetReferrer ("andy", "ref");
    uint t1 = block.timestamp;
    skip (10);
    rt.trySetReferrer ("domob", "ref");
    uint t2 = block.timestamp;
    rt.trySetReferrer ("andy", "ref2");
    vm.stopPrank ();

    assertTrue (rt.hasReferrer ("andy"));
    assertTrue (rt.hasReferrer ("domob"));
    (string memory ref, uint ts) = rt.refDataOf ("andy");
    assertEq (ref, "ref");
    assertEq (ts, t1);
    (ref, ts) = rt.refDataOf ("domob");
    assertEq (ref, "ref");
    assertEq (ts, t2);

    vm.startPrank (other);
    vm.expectRevert (Utils.missingRoleError (other, rt.SET_REFERRER_ROLE ()));
    rt.trySetReferrer ("foo", "ref");
    assertFalse (rt.hasReferrer ("foo"));
  }

  function test_overwriteReferrer () public
  {
    vm.startPrank (admin);

    rt.overwriteReferrer ("domob", "ref", 100);
    assertTrue (rt.hasReferrer ("domob"));
    (string memory ref, uint ts) = rt.refDataOf ("domob");
    assertEq (ref, "ref");
    assertEq (ts, 100);

    rt.overwriteReferrer ("domob", "ref2", 200);
    assertTrue (rt.hasReferrer ("domob"));
    (ref, ts) = rt.refDataOf ("domob");
    assertEq (ref, "ref2");
    assertEq (ts, 200);

    rt.overwriteReferrer ("domob", "", 300);
    assertFalse (rt.hasReferrer ("domob"));

    vm.stopPrank ();

    vm.startPrank (setter);
    vm.expectRevert (Utils.missingRoleError (setter, rt.DEFAULT_ADMIN_ROLE ()));
    rt.overwriteReferrer ("foo", "ref", 400);
    assertFalse (rt.hasReferrer ("foo"));
  }

  function test_maybeGetReferrer () public
  {
    vm.prank (setter);
    rt.trySetReferrer ("domob", "ref");
    uint ts = block.timestamp;

    (ReferralTracker.RefData memory rd, bool exists)
        = rt.maybeGetReferrer ("domob");
    assertTrue (exists);
    assertEq (rd.referrer, "ref");
    assertEq (rd.timestamp, ts);

    (rd, exists) = rt.maybeGetReferrer ("andy");
    assertFalse (exists);
  }

}
