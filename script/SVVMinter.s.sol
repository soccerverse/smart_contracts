// SPDX-License-Identifier: MIT
// Copyright (C) 2026 Soccerverse Ltd

pragma solidity ^0.8.19;

import "./PolygonConfig.sol";
import "../src/SVVMinter.sol";

import { Script } from "forge-std/Script.sol";

/**
 * @dev This is the script to deploy the SVVMinter smart contract.
 */
contract SVVMinterScript is Script
{

  function run () public
  {
    uint256 privkey = vm.envUint ("PRIVKEY");
    vm.startBroadcast (privkey);

    new SVVMinter (PolygonConfig.svv);

    vm.stopBroadcast ();
  }

}
