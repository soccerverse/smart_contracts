
// SPDX-License-Identifier: MIT
// Copyright (C) 2024 Soccerverse Ltd

pragma solidity ^0.8.19;

import "../src/PurchaseTracker.sol";

import { Script } from "forge-std/Script.sol";

/**
 * @dev This is the script to deploy the PurchaseTracker smart contract.
 */
contract PurchaseTrackerScript is Script
{

  function run () public
  {
    uint256 privkey = vm.envUint ("PRIVKEY");
    vm.startBroadcast (privkey);

    new PurchaseTracker ();

    vm.stopBroadcast ();
  }

}
