// SPDX-License-Identifier: MIT
// Copyright (C) 2025 Soccerverse Ltd

pragma solidity ^0.8.19;

import "./XayaTest.sol";
import "../src/Config.sol";
import "../src/BatchReveal.sol";

contract BatchRevealTest is XayaTest
{

  /** @dev Address where the BatchReveal contract is deployed.  */
  BatchReveal public immutable batch;

  constructor ()
  {
    batch = new BatchReveal (del);

    vm.prank (supply);
    wchi.transfer (address (batch), 1e8);
  }

  /**
   * @dev Initialises the contract with an account name.
   */
  function initialise (string memory nm) internal
  {
    uint tokenId = acc.tokenIdForName ("p", nm);
    vm.startPrank (supply);
    wchi.approve (address (acc), type (uint256).max);
    acc.register ("p", nm);
    acc.safeTransferFrom (supply, address (batch), tokenId);
    vm.stopPrank ();
  }

  function test_batchReveal () public
  {
    initialise ("acc");

    string[] memory fullPath = new string[] (4);
    fullPath[0] = "g";
    fullPath[1] = Config.GAME_ID;
    fullPath[2] = "st";
    fullPath[3] = "r";

    BatchReveal.ClubReveal[] memory rev = new BatchReveal.ClubReveal[] (3);
    rev[0] = BatchReveal.ClubReveal (42, "{\"foo\":5}");
    rev[1] = BatchReveal.ClubReveal (5, "{\"bar\":false}");
    rev[2] = BatchReveal.ClubReveal (100, "{\"baz\":[]}");

    expectMove ("p", "acc", 0, fullPath, "{\"foo\":5}");
    vm.expectEmit (address (batch));
    emit BatchReveal.ClubRevealed (42);
    expectMove ("p", "acc", 1, fullPath, "{\"bar\":false}");
    vm.expectEmit (address (batch));
    emit BatchReveal.ClubRevealed (5);
    expectMove ("p", "acc", 2, fullPath, "{\"baz\":[]}");
    vm.expectEmit (address (batch));
    emit BatchReveal.ClubRevealed (100);

    batch.batchReveal (rev);
  }

  function test_batchRevealNotInitialised () public
  {
    BatchReveal.ClubReveal[] memory rev = new BatchReveal.ClubReveal[] (1);
    rev[0] = BatchReveal.ClubReveal (42, "{\"foo\":5}");

    vm.expectRevert ("contract is not initialised");
    batch.batchReveal (rev);
  }

}
