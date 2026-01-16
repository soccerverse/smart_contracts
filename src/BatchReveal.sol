// SPDX-License-Identifier: MIT
// Copyright (C) 2025-2026 Soccerverse Ltd

pragma solidity ^0.8.19;

import "./Config.sol";

import "@xaya/democrit-evm/src/AccountHolder.sol";

/**
 * @dev A smart contract that owns a name and can be used to batch-send
 * reveal moves with this name for "reveal-as-a-service".  Note that this
 * is something that is entirely public and needs no special protection;
 * the authentication is against the hash the manager committed previously.
 */
contract BatchReveal is AccountHolder
{

  /**
   * @dev Data that describes the reveal for one club.
   */
  struct ClubReveal
  {

    /** @dev The club ID this is for.  */
    uint clubId;

    /**
     * @dev The full reveal move as JSON.  This must include the club ID again
     * as well as the prepared tactics.  Having this already formatted avoids
     * doing this in the smart contract and thus saves gas.
     */
    string revealMove;

  }

  /** @dev Event that is emitted when a club reveal is sent.  */
  event ClubRevealed (uint indexed clubId);

  constructor (XayaDelegation del)
    AccountHolder(del)
  {
    del.accounts ().setApprovalForAll (address (del), true);
  }

  /**
   * @dev Returns the game ID this is using, just for transparency.
   */
  function gameId () public pure returns (string memory)
  {
    return Config.GAME_ID;
  }

  /**
   * @dev Sends a batch of reveal moves with the internal account name (anyone
   * can reveal tactics, so the account name does not matter for that).
   */
  function batchReveal (ClubReveal[] memory reveals) public
  {
    require (initialised, "contract is not initialised");

    string[] memory fullPath = new string[] (4);
    fullPath[0] = "g";
    fullPath[1] = Config.GAME_ID;
    fullPath[2] = "st";
    fullPath[3] = "r";

    for (uint i = 0; i < reveals.length; ++i)
      {
        delegator.sendHierarchicalMove ("p", account, fullPath,
                                        reveals[i].revealMove);
        emit ClubRevealed (reveals[i].clubId);
      }
  }

}
