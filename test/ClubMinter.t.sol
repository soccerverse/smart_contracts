// SPDX-License-Identifier: MIT
// Copyright (C) 2024 Soccerverse Ltd

pragma solidity ^0.8.19;

import "./MinterTest.sol";
import "./Utils.sol";
import "../src/Config.sol";

import "@openzeppelin/contracts/utils/Strings.sol";

contract ClubMinterTest is MinterTest
{

  address public constant minter = address (1);
  address public constant notMinter = address (2);

  address public constant alice = address (3);
  address public constant bob = address (4);
  address public constant charly = address (5);

  uint public immutable cap;

  constructor ()
  {
    vm.label (minter, "minter");
    vm.label (notMinter, "notMinter");
    vm.label (alice, "alice");
    vm.label (bob, "bob");
    vm.label (charly, "charly");

    cap = cm.shareSupply ();
    vm.startPrank (admin);
    cm.grantRole (cm.MINTER_ROLE (), minter);
    vm.stopPrank ();
  }

  function test_shareMinting () public
  {
    string[] memory path = new string[] (3);
    path[0] = "cmd";
    path[1] = "mint";
    path[2] = "shares";

    vm.startPrank (minter);

    expectMove ("g", Config.GAME_ID, 0, path,
                '{"s":{"club":10},"r":"domob","n":100}');
    cm.mintShares (10, 100, "domob");

    expectMove ("g", Config.GAME_ID, 0, path, string (abi.encodePacked (
        '{"s":{"club":42},"r":"a\\\"b","n":',
        Strings.toString (cap / 10),
        '}'
    )));
    cm.mintShares (42, cap / 10, 'a"b');

    expectMove ("g", Config.GAME_ID, 0, path, '{"s":{"club":10},"r":"","n":1}');
    cm.mintShares (10, 1, "");

    expectMove ("g", Config.GAME_ID, 0, path, string (abi.encodePacked (
        '{"s":{"club":42},"r":"andy","n":',
        Strings.toString (9 * cap / 10),
        '}'
    )));
    cm.mintShares (42, 9 * cap / 10, "andy");

    assertEq (cm.sharesMinted (10), 101);
    assertEq (cm.sharesMinted (42), cap);
    assertEq (cm.sharesMinted (100), 0);

    assertEq (cm.sharesAvailable (10), cap - 101);
    assertEq (cm.sharesAvailable (42), 0);
    assertEq (cm.sharesAvailable (100), cap);
  }

  function test_clubSmcMinting () public
  {
    string[] memory path = new string[] (3);
    path[0] = "cmd";
    path[1] = "mint";
    path[2] = "clubsmc";

    vm.startPrank (minter);
    expectMove ("g", Config.GAME_ID, 0, path, '{"c":10,"n":100}');
    cm.mintClubSmc (10, 100);
    expectMove ("g", Config.GAME_ID, 0, path, '{"c":20,"n":200}');
    cm.mintClubSmc (20, 200);
  }

  function test_mintingPermission () public
  {
    vm.startPrank (notMinter);
    vm.expectRevert (Utils.missingRoleError (notMinter, cm.MINTER_ROLE ()));
    cm.mintShares (10, 100, "domob");
    vm.expectRevert (Utils.missingRoleError (notMinter, cm.MINTER_ROLE ()));
    cm.mintClubSmc (10, 100);
  }

  function test_supplyCap () public
  {
    vm.startPrank (minter);
    cm.mintShares (10, cap - 1, "domob");
    vm.expectRevert ("mint cap exceeded");
    cm.mintShares (10, 2, "domob");
    cm.mintShares (10, 1, "domob");
    cm.mintShares (42, 10, "domob");
  }

  function test_mintZeroShares () public
  {
    vm.startPrank (minter);
    cm.mintShares (10, 0, "domob");
    assertEq (cm.sharesMinted (10), 0);
  }

  function test_mintZeroSmc () public
  {
    vm.startPrank (minter);
    cm.mintClubSmc (10, 0);
  }

  function test_batchMint () public
  {
    ClubMinter.MintForClub[] memory mints = new ClubMinter.MintForClub[] (3);
    mints[0] = ClubMinter.MintForClub (10, 5, "domob", 0);
    mints[1] = ClubMinter.MintForClub (20, 0, "", 123);
    mints[2] = ClubMinter.MintForClub (30, 2, "andy", 456);

    vm.startPrank (notMinter);
    vm.expectRevert (Utils.missingRoleError (notMinter, cm.MINTER_ROLE ()));
    cm.batchMint (mints);

    string[] memory pathShares = new string[] (3);
    pathShares[0] = "cmd";
    pathShares[1] = "mint";
    pathShares[2] = "shares";

    string[] memory pathSmc = new string[] (3);
    pathSmc[0] = "cmd";
    pathSmc[1] = "mint";
    pathSmc[2] = "clubsmc";

    vm.startPrank (minter);
    expectMove ("g", Config.GAME_ID, 0, pathShares,
                '{"s":{"club":10},"r":"domob","n":5}');
    expectMove ("g", Config.GAME_ID, 1, pathSmc, '{"c":20,"n":123}');
    expectMove ("g", Config.GAME_ID, 2, pathShares,
                '{"s":{"club":30},"r":"andy","n":2}');
    expectMove ("g", Config.GAME_ID, 3, pathSmc, '{"c":30,"n":456}');
    cm.batchMint (mints);
  }

}
