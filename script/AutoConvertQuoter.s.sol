// SPDX-License-Identifier: MIT
// Copyright (C) 2025 Soccerverse Ltd

pragma solidity ^0.8.19;

import "../src/AutoConvertQuoter.sol";

import { Script } from "forge-std/Script.sol";

/**
 * @dev This is the script to deploy the AutoConvertQuoter.
 */
contract AutoConvertQuoterScript is Script
{

  /** @dev The production AutoConvert deployment.  */
  AutoConvert public constant autoconv
      = AutoConvert (payable (0xA3098c68Fd99233B57Bd065AAc545Cca5f1ac296));

  function run () public
  {
    uint256 privkey = vm.envUint ("PRIVKEY");

    vm.startBroadcast (privkey);
    new AutoConvertQuoter (autoconv);
    vm.stopBroadcast ();
  }

}
