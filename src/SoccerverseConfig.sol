// SPDX-License-Identifier: MIT
// Copyright (C) 2023-2024 Soccerverse Ltd

pragma solidity ^0.8.19;

import "@xaya/democrit-evm/contracts/IDemocritConfig.sol";
import "@xaya/democrit-evm/contracts/JsonUtils.sol";

import "@openzeppelin/contracts/utils/Strings.sol";

import "./Config.sol";

/**
 * @dev The Democrit config for Soccerverse.  The tradable asset is just
 * the SMC coin.
 */
contract SoccerverseConfig is IDemocritConfig
{

  string public constant gameId = Config.GAME_ID;

  uint64 public constant feeDenominator = 10**18;
  uint64 public constant maxRelPoolFee = 10**17;

  bytes32 private constant HASH_SMC = keccak256 ("smc");

  function isTradableAsset (string memory asset)
      public pure returns (bool)
  {
    bytes32 hash = keccak256 (abi.encodePacked (asset));
    return hash == HASH_SMC;
  }

  function createVaultMove (string memory, uint vaultId,
                            string memory founder,
                            string memory, uint amount)
      public pure returns (string memory)
  {
    return string (abi.encodePacked (
        "{\"tv\":{\"c\":{",
        "\"id\":", Strings.toString (vaultId), ",",
        "\"f\":", JsonUtils.escapeString (founder), ",",
        "\"a\":", Strings.toString (amount),
        "}}}"
    ));
  }

  function checkpointMove (string memory, uint num, bytes32 hash)
      public pure returns (string memory)
  {
    return string (abi.encodePacked (
        "{\"tv\":{\"cp\":{",
        "\"n\":", Strings.toString (num), ",",
        "\"h\":\"", Strings.toHexString (uint256 (hash)), "\"",
        "}}}"
    ));
  }

  function sendFromVaultMove (string memory, uint vaultId,
                              string memory recipient,
                              string memory, uint amount)
      public pure returns (string memory)
  {
    return string (abi.encodePacked (
        "{\"tv\":{\"s\":{",
        "\"id\":", Strings.toString (vaultId), ",",
        "\"r\":", JsonUtils.escapeString (recipient), ",",
        "\"a\":", Strings.toString (amount),
        "}}}"
    ));
  }

  function fundVaultMove (string memory controller, uint vaultId,
                          string memory, string memory, uint)
      public pure returns (string[] memory path, string memory mv)
  {
    mv = string (abi.encodePacked (
        "{",
        "\"id\":", Strings.toString (vaultId), ",",
        "\"c\":", JsonUtils.escapeString (controller),
        "}"
    ));

    path = new string[] (2);
    path[0] = "tv";
    path[1] = "f";
  }

}
