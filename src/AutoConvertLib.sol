// SPDX-License-Identifier: MIT
// Copyright (C) 2026 Soccerverse Ltd

pragma solidity ^0.8.19;

import "./SwapProvider.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @dev Shared logic for the auto-convert quote functions.
 */
library AutoConvertLib
{

  /** @dev The base denominator for the auto-convert fees (basis points).  */
  uint internal constant BASIS_POINTS = 10000;

  /**
   * @dev Helper function that adds a fee in basis points to a given amount.
   */
  function addFee (uint amount, uint bps) internal pure returns (uint)
  {
    return amount * (BASIS_POINTS + bps) / BASIS_POINTS;
  }

  /**
   * @dev Converts a net amount into the fee-inclusive amount, such that
   * the fee is the given basis points of the returned total.
   */
  function convertFeeInclusive (uint net, uint bps)
      internal pure returns (uint)
  {
    if (bps == 0)
      return net;

    uint denom = BASIS_POINTS - bps;
    return (net * BASIS_POINTS + denom - 1) / denom;
  }

  /**
   * @dev Converts a gross amount into the net amount, such that the fee
   * is the given basis points of the returned net amount.
   */
  function convertFeeExclusive (uint gross, uint bps)
      internal pure returns (uint)
  {
    if (bps == 0)
      return gross;

    return gross * BASIS_POINTS / (BASIS_POINTS + bps);
  }

  /**
   * @dev Returns the current quote of input token required to make a
   * purchase of SMC for the given total in WCHI required.
   */
  function quoteMarketBuy (SwapProvider swapper, IERC20 inputToken,
                           uint wchiRequired, uint burnFee, uint convertFee,
                           bytes memory swapData)
      internal returns (uint)
  {
    uint totalRequired = addFee (wchiRequired, burnFee);
    uint inputRequired = swapper.quoteExactOutput (inputToken, totalRequired,
                                                   swapData);
    return convertFeeInclusive (inputRequired, convertFee);
  }

  /**
   * @dev Returns the current quote of output token received when
   * "market selling" SMC that yields a given total in WCHI.
   */
  function quoteMarketSell (SwapProvider swapper, uint wchiReceived,
                            uint burnFee, uint convertFee,
                            IERC20 outputToken, bytes memory swapData)
      internal returns (uint)
  {
    uint burn = wchiReceived * burnFee / BASIS_POINTS;
    uint wchiForSwap = wchiReceived - burn;
    uint output = swapper.quoteExactInput (wchiForSwap, outputToken, swapData);
    return convertFeeExclusive (output, convertFee);
  }

}
