// SPDX-License-Identifier: MIT
// Copyright (C) 2025 Soccerverse Ltd

pragma solidity ^0.8.19;

import "./PackSaleConfig.sol";
import "./PolygonConfig.sol";
import "../src/PackVoucher.sol";

import { Script } from "forge-std/Script.sol";

/**
 * @dev This is the script to deploy the PackVoucher smart contract.
 */
contract PackVoucherScript is Script
{

  function run () public
  {
    uint256 privkey = vm.envUint ("PRIVKEY");
    vm.startBroadcast (privkey);

    new PackVoucher ("Soccerverse Vouchers", "SVV",
                     PackSaleConfig.cm, PolygonConfig.usdc);

    vm.stopBroadcast ();
  }

}
