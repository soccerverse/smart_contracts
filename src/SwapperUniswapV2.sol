// SPDX-License-Identifier: MIT
// Copyright (C) 2023 Soccerverse Ltd

pragma solidity ^0.8.19;

import "./SwapProvider.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";

/**
 * @dev This implements the SwapProvider based on a Uniswap v2 DEX.  The swap
 * data encodes the fixed routing path.
 */
contract SwapperUniswapV2 is SwapProvider
{

  /**
   * @dev The address of the Uniswap router we use.  We use Router01 here
   * since we only need the interface, and the calls we use are included
   * in that already.  The implementation will be set upon deployment, and
   * can point to the latest router.
   */
  IUniswapV2Router01 public immutable router;

  /**
   * @dev All input tokens (other than WCHI), for which the router has
   * already been given approval.  We use this to give approval on first use
   * for each token (and not on later uses).
   */
  mapping (address => bool) private tokenApproved;

  constructor (IERC20 wc, IUniswapV2Router01 r)
    SwapProvider (wc)
  {
    router = r;
    wc.approve (address (r), type (uint256).max);
  }

  /**
   * @dev Encodes a given swap path into a "data" argument that can be passed
   * to the other functions.  Note that the path contains only the intermediate
   * tokens, not the input or output (and may be empty if a direct pair
   * exists).  This is in contrast to the "path" argument for Uniswap.
   */
  function encodePath (address[] calldata path)
      public pure returns (bytes memory)
  {
    return abi.encode (path);
  }

  /**
   * @dev Helper method that takes an encoded path with intermediate pairs
   * as well as input and output tokens and fills in the full path argument
   * as used by Uniswap.
   */
  function getFullPath (IERC20 inputToken, IERC20 outputToken,
                        bytes calldata data)
      private pure returns (address[] memory res)
  {
    address[] memory intermediate = abi.decode (data, (address[]));
    res = new address[] (intermediate.length + 2);
    res[0] = address (inputToken);
    for (uint i = 0; i < intermediate.length; ++i)
      res[i + 1] = intermediate[i];
    res[intermediate.length + 1] = address (outputToken);
  }

  function quoteExactOutput (IERC20 inputToken, uint outputAmount,
                             bytes calldata data)
      public view override returns (uint)
  {
    address[] memory path = getFullPath (inputToken, wchi, data);
    uint[] memory amounts = router.getAmountsIn (outputAmount, path);
    return amounts[0];
  }

  function quoteExactInput (uint inputAmount, IERC20 outputToken,
                            bytes calldata data)
      public view override returns (uint)
  {
    address[] memory path = getFullPath (wchi, outputToken, data);
    uint[] memory amounts = router.getAmountsOut (inputAmount, path);
    return amounts[amounts.length - 1];
  }

  function swapExactOutput (IERC20 inputToken, uint outputAmount,
                            bytes calldata data) public override
  {
    address[] memory path = getFullPath (inputToken, wchi, data);

    if (!tokenApproved[address (inputToken)])
      {
        inputToken.approve (address (router), type (uint256).max);
        tokenApproved[address (inputToken)] = true;
      }

    /* Note that the AutoConvert contract itself enforces a maximum slippage,
       so we can call into Uniswap without any limit.  */
    router.swapTokensForExactTokens (outputAmount, type (uint256).max, path,
                                     address (this), block.timestamp);
  }

  function swapExactInput (uint inputAmount, IERC20 outputToken,
                           bytes calldata data) public override
  {
    /* Note that the AutoConvert contract itself enforces a maximum slippage,
       so we can call into Uniswap without any limit.  */
    address[] memory path = getFullPath (wchi, outputToken, data);
    router.swapExactTokensForTokens (inputAmount, 0, path,
                                     address (this), block.timestamp);
  }

}
