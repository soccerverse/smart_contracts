// SPDX-License-Identifier: MIT
// Copyright (C) 2025 Soccerverse Ltd

pragma solidity ^0.8.19;

import "./PolygonConfig.sol";
import "../src/SwapperV2V3.sol";

import { Script } from "forge-std/Script.sol";

/**
 * @dev This is the script to deploy the SwapperV2V3 smart contract
 * alone by itself (such as to update the AutoConvert swapper).
 */
contract SwapperV2V3Script is Script
{

  function run () public
  {
    uint256 privkey = vm.envUint ("PRIVKEY");

    IERC20Metadata wchi = PolygonConfig.wchi ();

    vm.startBroadcast (privkey);
    new SwapperV2V3 (wchi);
    vm.stopBroadcast ();
  }

}
