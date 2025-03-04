// SPDX-License-Identifier: MIT
// Copyright (C) 2024-2025 Soccerverse Ltd

pragma solidity ^0.8.19;

import "./XayaTest.sol";

import "../src/ClubMinter.sol";

/**
 * @dev A test contract that sets up all that is required for testing
 * the ClubMinter.
 */
abstract contract MinterTest is XayaTest
{

  /** @dev Address that is owner for the minter.  */
  address public constant admin = address (2);

  /** @dev Address that owns the g/ name for Soccerverse.  */
  address public constant gname = address (3);

  ClubMinter public immutable cm;

  constructor ()
  {
    vm.label (admin, "admin");
    vm.label (gname, "gname");

    vm.prank (admin);
    cm = new ClubMinter (del, ClubMinter (address (0)));

    vm.startPrank (supply);
    wchi.transfer (gname, 100e8);

    vm.startPrank (gname);
    wchi.approve (address (acc), type (uint256).max);
    acc.setApprovalForAll (address (del), true);
    acc.register ("g", cm.gameId ());
    vm.stopPrank ();

    setUpClubMinter (cm);
  }

  /**
   * @dev Sets up the required config for a ClubMinter contract (such as giving
   * it WCHI tokens and granting it delegate permission on the admin name).
   */
  function setUpClubMinter (ClubMinter c) internal
  {
    vm.startPrank (supply);
    wchi.transfer (address (c), 1e8);

    vm.startPrank (gname);
    string[] memory path = new string[] (2);
    path[0] = "cmd";
    path[1] = "mint";
    del.grant ("g", c.gameId (), path, address (c),
               type (uint256).max, false);

    vm.stopPrank ();
  }

}
