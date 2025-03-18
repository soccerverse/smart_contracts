// SPDX-License-Identifier: MIT
// Copyright (C) 2023-2025 Soccerverse Ltd

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @dev This is the interface of a provider for swapping between tokens,
 * as used by Democrit's auto-convert feature.  It can be implemented based
 * on an on-chain DEX such as Uniswap v2 or v3.
 *
 * All methods accept an implementation-specific "data" argument, which
 * can contain other data required, such as swap paths.
 *
 * Token swaps are done from / to the contract's balance.  Democrit will
 * directly move tokens from the user's wallet to this contract, and the
 * contract has a method to withdraw tokens from its own balance onwards
 * after the swap, which Democrit will use.
 */
abstract contract SwapProvider
{

  /** @dev The WCHI token used.  */
  IERC20 public immutable wchi;

  constructor (IERC20 wc)
  {
    wchi = wc;
  }

  /**
   * @dev Transfers tokens owned by this contract.  This is a method
   * that Democrit will use to distribute the swap output.  It can be
   * called by anyone, as this contract is not expected to hold tokens
   * "long term".  Any balances it receives will be distributed by
   * Democrit right away in the same transaction.
   */
  function transferToken (IERC20 token, uint amount, address receiver) public
  {
    require (token.transfer (receiver, amount), "token transfer failed");
  }

  /**
   * @dev Returns the expected amount of input token required to get
   * the provided output amount in WCHI.
   *
   * This function is not marked as view because Uniswap v3 quoting is not
   * view either.  It is not making relevant state changes, though, and should
   * only be used in off-chain calls.
   */
  function quoteExactOutput (IERC20 inputToken, uint outputAmount,
                             bytes calldata data)
      public virtual returns (uint);

  /**
   * @dev Returns the expected amount of output token if the provided
   * input amount of WCHI is swapped.
   */
  function quoteExactInput (uint inputAmount, IERC20 outputToken,
                            bytes calldata data)
      public virtual returns (uint);

  /**
   * @dev Performs a swap of input tokens to exact output WCHI tokens.
   */
  function swapExactOutput (IERC20 inputToken, uint outputAmount,
                            bytes calldata data) public virtual;

  /**
   * @dev Performs a swap of an exact input of WCHI to the desired output.
   */
  function swapExactInput (uint inputAmount, IERC20 outputToken,
                           bytes calldata data) public virtual;

}
