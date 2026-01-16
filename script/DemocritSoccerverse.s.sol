
// SPDX-License-Identifier: MIT
// Copyright (C) 2024-2026 Soccerverse Ltd

pragma solidity ^0.8.19;

import "./PolygonConfig.sol";
import "../src/AutoConvert.sol";
import "../src/DemocritSoccerverse.sol";
import "../src/SoccerverseConfig.sol";
import "../src/SwapperUniswapV2.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@xaya/democrit-evm/src/VaultManager.sol";
import "@xaya/eth-account-registry/src/IXayaAccounts.sol";
import "@xaya/eth-delegator-contract/src/XayaDelegation.sol";

import { Script, console } from "forge-std/Script.sol";

/**
 * @dev This is the script to deploy all contracts making up Democrit
 * for Soccerverse (including AutoConvert).
 */
contract DemocritSoccerverseScript is Script
{

  address public constant burnReceiver
      = 0x2659deaa71B51124bA6e6493b795486b3027Dbc9;
  address public constant feeReceiver
      = 0x75254A2aD4dE46eC7373Ef30Bdd92e66835B47C5;

  function run () public
  {
    uint256 privkey = vm.envUint ("PRIVKEY");
    address deployer = vm.addr (privkey);

    XayaDelegation del = PolygonConfig.del;
    IXayaAccounts acc = del.accounts ();
    IERC20 wchi = acc.wchiToken ();

    vm.startBroadcast (privkey);

    SwapProvider swapper = new SwapperUniswapV2 (wchi, PolygonConfig.uniswap2);
    AutoConvert autoconv
        = new AutoConvert (PolygonConfig.weth, PolygonConfig.fwd);

    SoccerverseConfig cfg = new SoccerverseConfig ();
    VaultManager vman = new VaultManager (del, cfg);
    DemocritSoccerverse dem
        = new DemocritSoccerverse (vman, PolygonConfig.fwd, address (autoconv));

    string memory name = string (abi.encodePacked (
        "Democrit ",
        Strings.toHexString (address (dem))
    ));
    console.log (name);

    uint tokenId = acc.tokenIdForName ("p", name);
    acc.register ("p", name);
    acc.safeTransferFrom (deployer, address (vman), tokenId);

    vman.transferOwnership (address (dem));
    autoconv.linkDemocrit (dem);
    autoconv.configure (swapper, 100, burnReceiver, 100, feeReceiver, 50);

    dem.pause ();

    vm.stopBroadcast ();
  }

}
