// SPDX-License-Identifier: MIT
// Copyright (C) 2026 Soccerverse Ltd

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

import "./PackVoucher.sol";

/**
 * @dev This contract implements custom minting logic / permissions for
 * SVV.  It is separate from the core SVV contract (PackVoucher), so that we
 * can replace it if needed without touching the existing token contract.  This
 * contract has TOKEN_ADMIN_ROLE on the PackVoucher, and thus unlimited minting
 * allowance.  It applies its own budgeting for minting per address.
 */
contract SVVMinter is AccessControlEnumerable
{

  /** @dev The PackVoucher / SVV contract used.  */
  PackVoucher public immutable svv;

  /** @dev Per-address remaining minting allowance.  */
  mapping (address => uint) public addressMintLimit;

  /** @dev Event emitted when the mint limit is changed.  */
  event MintLimitChanged (address minter, uint oldLimit, uint newLimit);

  /**
   * @dev Error raised when an address tries to mint more tokens
   * than the current remaining limit.
   */
  error MintLimitExceeded (address minter, uint attempt, uint limit);

  constructor (PackVoucher v)
  {
    _grantRole (DEFAULT_ADMIN_ROLE, msg.sender);
    svv = v;
  }

  /**
   * @dev Checks if this contract actually has unlimited minting permission
   * on its associated PackVoucher contract.
   */
  function hasMintingPermission () public view returns (bool)
  {
    return svv.hasRole (svv.TOKEN_ADMIN_ROLE (), address (this));
  }

  /**
   * @dev Modifies the minting limit for a given address, as the admin.
   */
  function setLimit (address minter, uint newLimit)
      public onlyRole (DEFAULT_ADMIN_ROLE)
  {
    uint oldLimit = addressMintLimit[minter];
    if (newLimit != oldLimit)
      {
        addressMintLimit[minter] = newLimit;
        emit MintLimitChanged (minter, oldLimit, newLimit);
      }
  }

  /**
   * @dev Batch-mints vouchers to a set of addresses.
   */
  function batchMint (PackVoucher.MintOp[] memory ops) public
  {
    uint total = 0;
    for (uint i = 0; i < ops.length; ++i)
      total += ops[i].amount;

    /* Avoid an edge case where someone without minting limit (i.e. an
       arbitrary address) could send 0 SVV mints, spamming events.  */
    if (total == 0)
      return;

    address minter = msg.sender;
    uint remaining = addressMintLimit[minter];
    if (total > remaining)
      revert MintLimitExceeded (minter, total, remaining);

    if (total > 0)
      {
        uint newRemaining = remaining - total;
        addressMintLimit[minter] = newRemaining;
        emit MintLimitChanged (minter, remaining, newRemaining);
      }

    svv.batchMint (ops);
  }

  /**
   * @dev Mints new tokens to the given receiver.
   */
  function mint (address to, uint amount) public
  {
    PackVoucher.MintOp[] memory ops = new PackVoucher.MintOp[] (1);
    ops[0].to = to;
    ops[0].amount = amount;

    batchMint (ops);
  }

}
