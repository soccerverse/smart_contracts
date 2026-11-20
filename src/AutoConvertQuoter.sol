// SPDX-License-Identifier: MIT
// Copyright (C) 2025-2026 Soccerverse Ltd

pragma solidity ^0.8.19;

import "./AutoConvert.sol";
import "./AutoConvertLib.sol";

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
 * The quote logic itself is shared with AutoConvert through AutoConvertLib.
 *
 * In case Democrit and AutoConvert are re-deployed in production, we can
 * get rid of the AutoConvertQuoter.
 */
contract AutoConvertQuoter
{

  /** @dev AutoConvert used to get config from.  */
  AutoConvert public immutable parent;

  constructor (AutoConvert a)
  {
    parent = a;
  }

  /**
   * @dev Returns the current quote of input token required to make a
   * purchase of SMC for the given total in WCHI required.
   */
  function quoteMarketBuy (IERC20 inputToken, uint wchiRequired,
                           bytes calldata swapData)
      public returns (uint)
  {
    return AutoConvertLib.quoteMarketBuy (parent.swapper (), inputToken,
                                          wchiRequired, parent.burnFee (),
                                          parent.convertFee (), swapData);
  }

  /**
   * @dev Returns the current quote of output token received when
   * "market selling" SMC that yields a given total in WCHI.
   */
  function quoteMarketSell (IERC20 outputToken, uint wchiReceived,
                            bytes calldata swapData)
      public returns (uint)
  {
    return AutoConvertLib.quoteMarketSell (parent.swapper (), wchiReceived,
                                           parent.burnFee (),
                                           parent.convertFee (), outputToken,
                                           swapData);
  }

}
