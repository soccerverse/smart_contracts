// SPDX-License-Identifier: MIT
// Copyright (C) 2025 Soccerverse Ltd

pragma solidity ^0.8.19;

import "./PolygonConfig.sol";
import "../src/BatchReveal.sol";

import "@openzeppelin/contracts/utils/Strings.sol";
import "@xaya/eth-account-registry/contracts/IXayaAccounts.sol";

import { Script } from "forge-std/Script.sol";

/**
 * @dev This is the script to deploy and initialise the BatchReveal contract.
 */
contract BatchRevealScript is Script
{

  function run () public
  {
    uint256 privkey = vm.envUint ("PRIVKEY");
    address sender = vm.addr (privkey);

    IXayaAccounts acc = PolygonConfig.del.accounts ();
    IERC20Metadata wchi = PolygonConfig.wchi ();

    vm.startBroadcast (privkey);
    BatchReveal batch = new BatchReveal (PolygonConfig.del);
    vm.stopBroadcast ();

    /* Generate an account name from the contract address, and expect it
       to be available (if it is not, just retry perhaps, or modify this
       script).  */
    string memory nm = string (abi.encodePacked (
      "BatchReveal ",
      Strings.toHexString (address (batch))
    ));
    uint tokenId = acc.tokenIdForName ("p", nm);
    uint fee = acc.policy ().checkRegistration ("p", nm);

    if (wchi.allowance (sender, address (acc)) < fee)
      {
        vm.startBroadcast (privkey);
        wchi.approve (address (acc), fee);
        vm.stopBroadcast ();
      }

    vm.startBroadcast (privkey);
    acc.register ("p", nm);
    acc.safeTransferFrom (sender, address (batch), tokenId);
    vm.stopBroadcast ();

    require (batch.initialised ());
  }

}
