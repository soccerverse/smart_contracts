// SPDX-License-Identifier: MIT
// Copyright (C) 2023 Soccerverse Ltd

pragma solidity ^0.8.19;

import "../src/SwapProvider.sol";

/**
 * @dev This is an implementation of the ISwapProvider interface, for use
 * in testing.  The swap will just be done at a user-specified rate (with
 * the extra data), based on tokens a specific supply address holds.
 */
contract TestSwapProvider is SwapProvider
{

  /**
   * @dev The "supply" address from which tokens used in swaps are taken
   * (and input tokens sent to).  It must have approved this contract
   * as necessary.
   */
  address public immutable supply;

  constructor (IERC20 wc, address s)
    SwapProvider (wc)
  {
    supply = s;
  }

  /**
   * @dev Encodes the desired rate at which a swap should be performed
   * (one "other token" is worth X WCHI).  The returned value is the "data"
   * that can be passed to the other functions.
   */
  function rate (uint value) public pure returns (bytes memory)
  {
    return abi.encode (value);
  }

  function quoteExactOutput (IERC20, uint outputAmount, bytes calldata data)
      public pure override returns (uint)
  {
    return outputAmount / abi.decode (data, (uint));
  }

  function quoteExactInput (uint inputAmount, IERC20, bytes calldata data)
      public pure override returns (uint)
  {
    return inputAmount / abi.decode (data, (uint));
  }

  function swapExactOutput (IERC20 inputToken, uint outputAmount,
                            bytes calldata data) public override
  {
    uint inputAmount = outputAmount / abi.decode (data, (uint));
    require (inputToken.transfer (supply, inputAmount),
             "sending input token failed");
    require (wchi.transferFrom (supply, address (this), outputAmount),
             "sending output token failed");
  }

  function swapExactInput (uint inputAmount, IERC20 outputToken,
                           bytes calldata data) public override
  {
    uint outputAmount = inputAmount / abi.decode (data, (uint));
    require (wchi.transfer (supply, inputAmount),
             "sending input token failed");
    require (outputToken.transferFrom (supply, address (this), outputAmount),
             "sending output token failed");
  }

}
