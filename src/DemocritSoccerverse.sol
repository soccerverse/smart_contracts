// SPDX-License-Identifier: MIT
// Copyright (C) 2023-2025 Soccerverse Ltd

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

import "@xaya/democrit-evm/contracts/Democrit.sol";
import "@xaya/democrit-evm/contracts/VaultManager.sol";

/**
 * @dev The Democrit main contract for Soccerverse.
 *
 * This contract adds ERC-2771 native meta transaction support to the base
 * Democrit protocol.  In addition to the normal forwarder contract,
 * also the auto-convert contract is a "trusted forwarder".  This contract
 * will make use of this when calling Democrit for accepting buy orders,
 * in which case it will set _msgSender() on the Democrit call to the user's
 * original address (instead of the auto-convert contract's address).
 *
 * The reason for this design (with a separate contract for auto-convert
 * instead of implementing this directly here) is that the code size
 * of the Democrit contract is already close to the maximum, and in this
 * way we can avoid adding a lot of more code to this contract.
 */
contract DemocritSoccerverse is Democrit, ERC2771Context, Ownable, Pausable
{

  /**
   * @dev The address of the auto-convert contract, which is allowed
   * to set a custom _msgSender() for calls.
   *
   * This is in fact "immutable" (only set once in the constructor) but
   * cannot be declared as such, because the Ownable constructor will call
   * _msgSender(), reading this variable (then all zeros), before it
   * gets initialised.
   */
  address public autoConvertAddress;

  constructor (VaultManager v, address fwd, address ac)
    Democrit(v)
    ERC2771Context(fwd)
  {
    autoConvertAddress = ac;
  }

  /* Make the contract pausable by the owner.  In a paused state, no
     market orders can be executed (i.e. orders "accepted"), while it
     is still possible to create or cancel existing orders, deposits
     and so on (and thus recover the funds locked in a vault).  This
     still effectively halts any trading, and can be used e.g. in case of
     a discovered bug or if the contract gets superseded by another one to
     prevent users from accidentally using an old contract / the old
     contract harming users who still have given it permissions.  */

  function pause () public onlyOwner
  {
    _pause ();
  }

  function unpause () public onlyOwner
  {
    _unpause ();
  }

  function acceptSellOrder (AcceptedSellOrder calldata args) public override
  {
    _requireNotPaused ();
    LimitSelling.acceptSellOrder (args);
  }

  function acceptBuyOrder (AcceptedBuyOrder calldata args) public override
  {
    _requireNotPaused ();
    LimitBuying.acceptBuyOrder (args);
  }

  /* Explicitly specify that we want to use the ERC2771 variants for
     _msgSender and _msgData.  We override isTrustedForwarder to allow
     both the "real" forwarder and the auto-convert contract.  */

  function isTrustedForwarder (address fwd)
      public view override returns (bool)
  {
    if (fwd == autoConvertAddress)
      return true;
    return ERC2771Context.isTrustedForwarder (fwd);
  }

  function _msgSender ()
      internal view override(Context, ERC2771Context) returns (address)
  {
    return ERC2771Context._msgSender ();
  }

  function _msgData ()
      internal view override(Context, ERC2771Context) returns (bytes calldata)
  {
    return ERC2771Context._msgData ();
  }

  function _contextSuffixLength ()
      internal view override(Context, ERC2771Context) returns (uint256)
  {
    return ERC2771Context._contextSuffixLength ();
  }

}
