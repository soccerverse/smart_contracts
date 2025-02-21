// SPDX-License-Identifier: MIT
// Copyright (C) 2024 Soccerverse Ltd

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

/**
 * @dev On-chain tracking of total pack purchases.
 *
 * This contract tracks how much (in terms of USD value) each address
 * and Xaya user account has spent, in total, buying packs from us.
 * With this data, we can then do on-chain checking to ensure KYC / AML
 * rules are followed.
 *
 * This contract is separate (as opposed to being part of the larger
 * sales contract or checking logic for purchases) so that we can ensure
 * that the data remains if we need to update other bits of the logic
 * to new contracts.
 *
 * It also keeps a whitelist of buyer addresses and accounts that
 * have gone through KYC, so that this data is also "permanent"
 * and will survive a contract redeployment of the sale itself.
 *
 * A whitelist of other contracts (such as the sales contracts) can
 * increment the total, which is the normal way of operation.  The
 * admin account is able to explicitly overwrite any total, too,
 * in case we need to fix up an issue of some sort manually.
 */
contract PurchaseTracker is AccessControlEnumerable
{

  /** @dev Addresses with this role can increment the total.  */
  bytes32 public constant INCREMENT_TOTAL_ROLE
      = keccak256 ("INCREMENT_TOTAL_ROLE");

  /** @dev Addresses with this role can whitelist KYC.  */
  bytes32 public constant APPROVER_ROLE = keccak256 ("APPROVER_ROLE");

  /**
   * @dev Data stored about a buyer address or account name.
   */
  struct Data
  {

    /** @dev The total purchase (in token, i.e. USDC, base units).  */
    uint total;

    /** @dev Whether or not the entity has been KYC approved.  */
    bool approved;

  }

  /** @dev Data for each buyer address.  */
  mapping (address => Data) public buyers;

  /** @dev Data for each recipient account name.  */
  mapping (string => Data) public accounts;

  /** @dev Emitted when a buy is recorded, i.e. totals are incremented.  */
  event TotalIncremented (address indexed buyer, string account, uint purchase);

  /** @dev Emitted when the total for an address is overwritten.  */
  event BuyerTotalSet (address indexed buyer, uint total);

  /** @dev Emitted when the total for an account is overwritten.  */
  event AccountTotalSet (string account, uint total);

  /** @dev Emitted when the approval status for an address changes.  */
  event BuyerApprovalSet (address indexed buyer, bool approved);

  /** @dev Emitted when the approval status for a recipient name changes.  */
  event AccountApprovalSet (string account, bool approved);

  constructor ()
  {
    _grantRole (DEFAULT_ADMIN_ROLE, msg.sender);
  }

  /**
   * @dev Returns the data struct for a given buyer address.
   */
  function getData (address buyer)
      public view returns (Data memory)
  {
    return buyers[buyer];
  }

  /**
   * @dev Returns the data struct for a given recipient address.
   */
  function getData (string calldata account)
      public view returns (Data memory)
  {
    return accounts[account];
  }

  /**
   * @dev Increments the total for a purchase (which is always tied to both
   * an address and an account).
   */
  function increment (address buyer, string calldata account, uint purchase)
      public onlyRole (INCREMENT_TOTAL_ROLE)
  {
    buyers[buyer].total += purchase;
    accounts[account].total += purchase;

    emit TotalIncremented (buyer, account, purchase);
  }

  /**
   * @dev Overwrites the total for a buyer address.
   */
  function overwrite (address buyer, uint total)
      public onlyRole (DEFAULT_ADMIN_ROLE)
  {
    buyers[buyer].total = total;
    emit BuyerTotalSet (buyer, total);
  }

  /**
   * @dev Overwrites the total for an account.
   */
  function overwrite (string calldata account, uint total)
      public onlyRole (DEFAULT_ADMIN_ROLE)
  {
    accounts[account].total = total;
    emit AccountTotalSet (account, total);
  }

  /**
   * @dev Sets the approval status of a buyer address.
   */
  function setApproved (address buyer, bool approved)
      public onlyRole (APPROVER_ROLE)
  {
    buyers[buyer].approved = approved;
    emit BuyerApprovalSet (buyer, approved);
  }

  /**
   * @dev Sets the approval status of a recipient account.
   */
  function setApproved (string calldata account, bool approved)
      public onlyRole (APPROVER_ROLE)
  {
    accounts[account].approved = approved;
    emit AccountApprovalSet (account, approved);
  }

}
