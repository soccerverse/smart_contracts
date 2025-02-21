// SPDX-License-Identifier: MIT
// Copyright (C) 2024 Soccerverse Ltd

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

/**
 * @dev On-chain tracking of referrals for Soccerverse.
 *
 * This contract tracks referrals between Xaya account names for Soccerverse.
 * By having this information on-chain, we can use it from other contracts
 * to implement referral rewards if we want.
 *
 * A whitelist of addresses is allowed to set referrers, for names that have
 * no referrers set yet.  The admin is allowed to modify this list of addresses,
 * and also to overwrite / clear referers if that may be needed to fix issues.
 */
contract ReferralTracker is AccessControlEnumerable
{

  /** @dev Addresses with this role can set (but not overwrite) referrers.  */
  bytes32 public constant SET_REFERRER_ROLE = keccak256 ("SET_REFERRER_ROLE");

  /**
   * @dev Data about one referral.
   */
  struct RefData
  {

    /** @dev The referrer name.  */
    string referrer;

    /** @dev The timestamp when the user was referred.  */
    uint timestamp;

  }

  /** @dev The referral data of given account names.  */
  mapping (string => RefData) public refDataOf;

  /** @dev Emitted when a referrer is set or updated.  */
  event ReferrerUpdated (string name, string referrer, uint timestamp);

  constructor ()
  {
    _grantRole (DEFAULT_ADMIN_ROLE, msg.sender);
  }

  /**
   * @dev Checks if there is a referrer for the given name.
   */
  function hasReferrer (string calldata name) public view returns (bool)
  {
    return refDataOf[name].timestamp > 0;
  }

  /**
   * @dev Returns the referrer and whether or not there is one in a single call.
   */
  function maybeGetReferrer (string calldata name)
      public view returns (RefData memory data, bool exists)
  {
    data = refDataOf[name];
    exists = data.timestamp > 0;
  }

  /**
   * @dev Sets the referrer for the given name, if it does not already exist.
   * If it exists already, then nothing is done.
   */
  function trySetReferrer (string calldata name, string calldata referrer)
      public onlyRole (SET_REFERRER_ROLE) returns (bool)
  {
    require (bytes (referrer).length > 0, "cannot set empty referrer");

    RefData storage ptr = refDataOf[name];

    if (ptr.timestamp > 0)
      return false;

    ptr.timestamp = block.timestamp;
    ptr.referrer = referrer;

    emit ReferrerUpdated (name, referrer, block.timestamp);

    return true;
  }

  /**
   * @dev Sets or overwrites the referrer of the given name.  If the referrer
   * is the empty string, then it will be removed, i.e. the name will be
   * seen as not having been referred (yet).
   */
  function overwriteReferrer (string calldata name,
                              string calldata referrer, uint ts)
      public onlyRole (DEFAULT_ADMIN_ROLE)
  {
    if (bytes (referrer).length == 0)
      delete refDataOf[name];
    else
      {
        RefData storage ptr = refDataOf[name];
        ptr.referrer = referrer;
        ptr.timestamp = ts;
      }

    emit ReferrerUpdated (name, referrer, ts);
  }

}
