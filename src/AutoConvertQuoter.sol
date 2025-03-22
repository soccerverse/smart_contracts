// SPDX-License-Identifier: MIT
// Copyright (C) 2025 Soccerverse Ltd

pragma solidity ^0.8.19;

import "./AutoConvert.sol";

/**
 * @dev This is a helper contract that re-implements the quote* functions
 * from AutoConvert, using the configuration from another AutoConvert contract.
 *
 * When adding support for Uniswap V3, we had to change the quote* functions
 * to be not "view".  This breaks the existing (deployed) AutoConvert.  With
 * this separate contract to run the "modified" code for quoting, we can keep
 * the original contract deployed and won't need to migrate the orderbook
 * to a new one.
 *
 * In case Democrit and AutoConvert are re-deployed in production, we can
 * get rid of the AutoConvertQuoter.
 */
contract AutoConvertQuoter
{

  /** @dev AutoConvert used to get config from.  */
  AutoConvert public immutable parent;

  /** @dev The base denominator for the auto-convert fees (basis points).  */
  uint public constant BASIS_POINTS = 10000;

  constructor (AutoConvert a)
  {
    parent = a;
  }

  /**
   * @dev Helper function that adds a fee in basis points to a given amount.
   */
  function addFee (uint amount, uint bps) private pure returns (uint)
  {
    return amount * (BASIS_POINTS + bps) / BASIS_POINTS;
  }

  /**
   * @dev Returns the current quote of input token required to make a
   * purchase of SMC for the given total in WCHI required.
   */
  function quoteMarketBuy (IERC20 inputToken, uint wchiRequired,
                           bytes calldata swapData)
      public returns (uint)
  {
    uint totalRequired = addFee (wchiRequired, parent.burnFee ());
    uint inputRequired = parent.swapper ().quoteExactOutput (
                            inputToken, totalRequired, swapData);
    return addFee (inputRequired, parent.convertFee ());
  }

  /**
   * @dev Helper function that removes a fee in basis points from a given
   * total amount.
   */
  function removeFee (uint amount, uint bps) private pure returns (uint)
  {
    return amount * (BASIS_POINTS - bps) / BASIS_POINTS;
  }

  /**
   * @dev Returns the current quote of output token received when
   * "market selling" SMC that yields a given total in WCHI.
   */
  function quoteMarketSell (IERC20 outputToken, uint wchiReceived,
                            bytes calldata swapData)
      public returns (uint)
  {
    uint wchiForSwap = removeFee (wchiReceived, parent.burnFee ());
    uint output = parent.swapper ().quoteExactInput (
                    wchiForSwap, outputToken, swapData);

    return removeFee (output, parent.convertFee ());
  }

}
