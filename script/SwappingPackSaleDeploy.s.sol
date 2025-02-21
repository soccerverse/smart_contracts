
// SPDX-License-Identifier: MIT
// Copyright (C) 2024 Soccerverse Ltd

pragma solidity ^0.8.19;

import "./PackSaleConfig.sol";
import "./PolygonConfig.sol";
import "../src/SwapperUniswapV2.sol";
import "../src/SwappingPackSale.sol";

import { Script, console } from "forge-std/Script.sol";

/**
 * @dev This is the script to deploy the set of SwappingPackSale contracts
 * for all tiers, without performing the extended configuration required.
 */
contract SwappingPackSaleDeployScript is Script
{

  function run () public
  {
    uint256 privkey = vm.envUint ("PRIVKEY");
    address deployer = vm.addr (privkey);

    string[] memory tiers = PackSaleConfig.getTiers ();

    vm.startBroadcast (privkey);

    SwapProvider swapper
        = new SwapperUniswapV2 (PolygonConfig.usdc, PolygonConfig.uniswap2);

    for (uint i = 0; i < tiers.length; ++i)
      {
        SwappingPackSale ps
            = new SwappingPackSale (PolygonConfig.usdc, PackSaleConfig.cm,
                                    PackSaleConfig.pt, PackSaleConfig.ref,
                                    tiers[i], PolygonConfig.fwd,
                                    PolygonConfig.weth, swapper);
        console.logAddress (address (ps));
        ps.grantRole (ps.CONFIGURE_ROLE (), deployer);

        PackSaleConfig.cm.grantRole (
            PackSaleConfig.cm.MINTER_ROLE (), address (ps));
        PackSaleConfig.pt.grantRole (
            PackSaleConfig.pt.INCREMENT_TOTAL_ROLE (), address (ps));

        ps.pause ();
      }

    vm.stopBroadcast ();
  }

}
