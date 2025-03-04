
// SPDX-License-Identifier: MIT
// Copyright (C) 2024-2025 Soccerverse Ltd

pragma solidity ^0.8.19;

import "./PolygonConfig.sol";
import "../src/ClubMinter.sol";

import { Script } from "forge-std/Script.sol";

/**
 * @dev This is the script to deploy the ClubMinter smart contract.
 */
contract ClubMinterScript is Script
{

  function run () public
  {
    uint256 privkey = vm.envUint ("PRIVKEY");
    vm.startBroadcast (privkey);

    new ClubMinter (PolygonConfig.del, ClubMinter (address (0)));

    vm.stopBroadcast ();
  }

}
