// SPDX-License-Identifier: MIT
// Copyright (C) 2026 Soccerverse Ltd

pragma solidity ^0.8.19;

import "./PackSaleConfig.sol";
import "../src/MerkleInfluenceMinter.sol";

import { Script } from "forge-std/Script.sol";

/**
 * @dev This is the script to deploy and initialise a MerkleInfluenceMinter
 * smart contract
 */
contract MerkleInfluenceMinterScript is Script
{

  /** @dev The Merkle tree root hash to use for the deployment.  */
  bytes32 public constant ROOT_HASH
      = hex"9bf36fdda71d71298766398dd9705d0d8fdb2fdcf881c863baec123433861e5d";

  function run () public
  {
    uint256 privkey = vm.envUint ("PRIVKEY");

    vm.startBroadcast (privkey);
    new MerkleInfluenceMinter (PackSaleConfig.cm, ROOT_HASH);
    vm.stopBroadcast ();
  }

}
