// SPDX-License-Identifier: MIT
// Copyright (C) 2023-2025 Soccerverse Ltd

pragma solidity ^0.8.19;

import "./SwapProvider.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "solidity-bytes-utils/contracts/BytesLib.sol";

/**
 * @dev This implements a SwapProvider that can run a flexible path containing
 * multiple sub-paths via Uniswap v2 or Uniswap v3 DEXes (and it can combine
 * different DEXes as well, such as Uniswap and Quickswap).
 */
contract SwapperV2V3 is SwapProvider
{

  /**
   * @dev A "subpath", consisting of a single (but potentially multi-hop)
   * swap on one V2 or V3 router.
   *
   * Note that this struct is not space-optimised and contains redundant data,
   * but is built to make processing as simple and quick as possible.
   *
   * The swap data for SwapperV2V3 is an ABI-encoded list of Subpath, i.e.
   * Subpath[].  The first subpath's input token is the overall input token,
   * the last subpath's output token is the overall output token (one of which
   * is the SwapProvider's WCHI), and the subpaths next to each other share
   * a common input/output token.
   */
  struct Subpath
  {

    /** @dev The Uniswap v2 router, if this is V2.  */
    IUniswapV2Router01 v2Router;

    /** @dev The Uniswap v3 router, if this is V3.  */
    ISwapRouter v3Router;

    /** @dev The Uniswap v3 quoter, if this is V3.  */
    IQuoter v3Quoter;

    /**
     * @dev The encoded "path" for the swap, either in V2 or V3 format.
     * For V2 format, this is ABI-encoded address[].
     */
    bytes path;

  }

  /**
   * @dev All input tokens and routing contracts for this approval has been
   * given already.  We use this to give approval on a first use basis.
   */
  mapping (IERC20 => mapping (address => bool)) private tokenApproved;

  constructor (IERC20 wc)
    SwapProvider (wc)
  {}

  /**
   * @dev Returns the input and output tokens of a given Subpath.
   */
  function getSubpathTokens (Subpath memory p)
      public pure returns (address input, address output)
  {
    /* Uniswap v2 */
    if (address (p.v2Router) != address (0))
      {
        address[] memory path = abi.decode (p.path, (address[]));
        input = path[0];
        output = path[path.length - 1];
      }

    /* Uniswap v3 */
    else if (address (p.v3Router) != address (0))
      {
        input = BytesLib.toAddress (p.path, 0);
        output = BytesLib.toAddress (p.path, p.path.length - 20);
      }

    /* Something invalid */
    else
      revert ("subpath is neither V2 nor V3");
  }

  /**
   * @dev Reverses a Uniswap v3 encoded path, as is required to call
   * IQuoter.quoteExactOutput.
   */
  function reverseV3Path (bytes memory path)
      private pure returns (bytes memory res)
  {
    uint pos = path.length - 20;
    while (true)
      {
        res = abi.encodePacked (res, BytesLib.slice (path, pos, 20));
        if (pos == 0)
          break;
        pos -= 3;
        res = abi.encodePacked (res, BytesLib.slice (path, pos, 3));
        pos -= 20;
      }
  }

  function quoteExactOutput (IERC20 inputToken, uint outputAmount,
                             bytes calldata data)
      public override returns (uint)
  {
    Subpath[] memory paths = abi.decode (data, (Subpath[]));
    require (paths.length > 0, "no swap requested");

    address nextInput;
    uint inputAmount;
    uint i = paths.length - 1;
    while (true)
      {
        (address input, address output) = getSubpathTokens (paths[i]);
        if (i == paths.length - 1)
          require (output == address (wchi), "expected WCHI as output token");
        else
          require (output == nextInput, "tokens in path do not link");

        /* Uniswap v2 */
        if (address (paths[i].v2Router) != address (0))
          {
            address[] memory path = abi.decode (paths[i].path, (address[]));
            uint[] memory amounts
                = paths[i].v2Router.getAmountsIn (outputAmount, path);
            inputAmount = amounts[0];
          }

        /* Uniswap v3 */
        else if (address (paths[i].v3Quoter) != address (0))
          inputAmount = paths[i].v3Quoter.quoteExactOutput (
                            reverseV3Path (paths[i].path),
                            outputAmount);

        /* Something invalid */
        else
          revert ("subpath is neither V2 nor V3");

        nextInput = input;
        outputAmount = inputAmount;

        if (i == 0)
          break;
        --i;
      }

    require (nextInput == address (inputToken), "wrong input token for path");

    return inputAmount;
  }

  function quoteExactInput (uint inputAmount, IERC20 outputToken,
                            bytes calldata data)
      public override returns (uint)
  {
    Subpath[] memory paths = abi.decode (data, (Subpath[]));
    require (paths.length > 0, "no swap requested");

    address prevOutput;
    uint outputAmount;
    for (uint i = 0; i < paths.length; ++i)
      {
        (address input, address output) = getSubpathTokens (paths[i]);
        if (i == 0)
          require (input == address (wchi), "expected WCHI as input token");
        else
          require (input == prevOutput, "tokens in path do not link");

        /* Uniswap v2 */
        if (address (paths[i].v2Router) != address (0))
          {
            address[] memory path = abi.decode (paths[i].path, (address[]));
            uint[] memory amounts
                = paths[i].v2Router.getAmountsOut (inputAmount, path);
            outputAmount = amounts[amounts.length - 1];
          }

        /* Uniswap v3 */
        else if (address (paths[i].v3Quoter) != address (0))
          outputAmount
              = paths[i].v3Quoter.quoteExactInput (paths[i].path, inputAmount);

        /* Something invalid */
        else
          revert ("subpath is neither V2 nor V3");

        prevOutput = output;
        inputAmount = outputAmount;
      }

    require (prevOutput == address (outputToken), "wrong output token in path");

    return outputAmount;
  }

  function swapExactOutput (IERC20 inputToken, uint outputAmount,
                            bytes calldata data) public override
  {
    /* We cannot do a multi-hop swap with exact output in reverse direction
       (like quoteExactOutput) does, because then we would need to have the
       previous output tokens as input before we actually get them in a swap.

       It might be possible to do all that with a Uniswap flash loan, but
       simpler is to run a quote first and then swap with the known exact input
       instead, even though that might involve more computation (and gas).  */

    uint inputAmount = quoteExactOutput (inputToken, outputAmount, data);
    swapExactInput (inputAmount, wchi, data);
  }

  /**
   * @dev Helper function to ensure we have given approval for a given token
   * and router.
   */
  function ensureApproval (IERC20 token, address router)
      private
  {
    if (tokenApproved[token][router])
      return;

    require (token.approve (router, type (uint256).max),
             "failed to approve token");
    tokenApproved[token][router] = true;
  }

  function swapExactInput (uint inputAmount, IERC20 outputToken,
                           bytes calldata data) public override
  {
    Subpath[] memory paths = abi.decode (data, (Subpath[]));
    require (paths.length > 0, "no swap requested");

    address prevOutput;
    uint outputAmount;
    for (uint i = 0; i < paths.length; ++i)
      {
        (address input, address output) = getSubpathTokens (paths[i]);
        /* We allow other input tokens than WCHI (defined by the path)
           so that this can be used as part of swapExactOutput as well.  */
        if (i > 0)
          require (input == prevOutput, "tokens in path do not link");

        /* Uniswap v2 */
        if (address (paths[i].v2Router) != address (0))
          {
            ensureApproval (IERC20 (input), address (paths[i].v2Router));

            address[] memory path = abi.decode (paths[i].path, (address[]));
            uint[] memory amountsOut
                = paths[i].v2Router.swapExactTokensForTokens (
                      inputAmount, 0, path, address (this), block.timestamp);
            outputAmount = amountsOut[amountsOut.length - 1];
          }

        /* Uniswap v3 */
        else if (address (paths[i].v3Router) != address (0))
          {
            ensureApproval (IERC20 (input), address (paths[i].v3Router));

            ISwapRouter.ExactInputParams memory params;
            params.path = paths[i].path;
            params.recipient = address (this);
            params.deadline = block.timestamp;
            params.amountIn = inputAmount;
            params.amountOutMinimum = 0;
            outputAmount = paths[i].v3Router.exactInput (params);
          }

        /* Something invalid */
        else
          revert ("subpath is neither V2 nor V3");

        prevOutput = output;
        inputAmount = outputAmount;
      }

    require (prevOutput == address (outputToken), "wrong output token in path");
  }

}
