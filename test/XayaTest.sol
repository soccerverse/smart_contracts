// SPDX-License-Identifier: MIT
// Copyright (C) 2024-2025 Soccerverse Ltd

pragma solidity ^0.8.19;

import "./TestToken.sol";

import "WETH9/WETH9.sol";

import "@xaya/eth-account-registry/contracts/IXayaPolicy.sol";
import "@xaya/eth-account-registry/contracts/XayaAccounts.sol";
import "@xaya/eth-account-registry/test/TestPolicy.sol";
import "@xaya/eth-delegator-contract/contracts/XayaDelegation.sol";

import { Test } from "forge-std/Test.sol";

/**
 * @dev A test contract that sets up a basic Xaya environment (with WCHI
 * token, accounts contract and move delegation).
 */
abstract contract XayaTest is Test
{

  /** @dev Address that owns the WCHI supply.  */
  address public constant supply = address (1);

  WETH9 public immutable weth;
  ERC20 public immutable wchi;
  IXayaPolicy public immutable policy;
  XayaAccounts public immutable acc;
  XayaDelegation public immutable del;

  constructor ()
  {
    vm.label (supply, "supply");

    weth = new WETH9 ();
    wchi = new TestToken (supply, 80e6 * 1e8);
    policy = new TestPolicy ();
    acc = new XayaAccounts (wchi, policy);
    del = new XayaDelegation (acc, address (0));
  }

  /**
   * @dev Helper function that expects that the next transaction will
   * send a Xaya move of the given name.  If multiple moves are
   * expected in a single future call, the nonceDelta can be used
   * to make sure each of them uses the correct nonce.
   */
  function expectMove (string memory ns, string memory name, uint nonceDelta,
                       string memory mv, address mover)
      internal
  {
    uint tokenId = acc.tokenIdForName (ns, name);
    uint nonce = acc.nextNonce (tokenId) + nonceDelta;

    vm.expectEmit (address (acc));
    emit IXayaAccounts.Move (ns, name, mv, tokenId, nonce, mover,
                             0, address (0));
  }

  /**
   * @dev Helper function that expects the next transaction to send a Xaya
   * move with a given value at a certain JSON hierarchy.
   */
  function expectMove (string memory ns, string memory name, uint nonceDelta,
                       string[] memory path, string memory mv)
      internal
  {
    string memory fullMv = "";
    for (uint i = 0; i < path.length; ++i)
      fullMv = string (abi.encodePacked (fullMv, "{\"", path[i], "\":"));
    fullMv = string (abi.encodePacked (fullMv, mv));
    for (uint i = 0; i < path.length; ++i)
      fullMv = string (abi.encodePacked (fullMv, "}"));

    expectMove (ns, name, nonceDelta, fullMv, address (del));
  }

}
