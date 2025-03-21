// SPDX-License-Identifier: MIT
// Copyright (C) 2023-2025 Soccerverse Ltd

pragma solidity ^0.8.19;

import "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";

import "./PackSale.sol";
import "./PurchaseTracker.sol";
import "./ReferralTracker.sol";
import "./SwapProvider.sol";

/**
 * @dev An extension to the basic PackSale contract, which supports minting
 * with auto-convert (swapping any input token to the payment token on-the-fly
 * using a UniswapV2 router such as Quickswap).
 */
contract SwappingPackSale is PackSale
{

  /** @dev WETH contract used for wrapping/unwrapping ETH with auto-convert.  */
  IWETH public immutable weth;

  /**
   * @dev Magic constant for the "token" address passed when native ETH
   * should be used instead (and wrapped/unwrapped on the fly).
   */
  address public constant ETH_TOKEN
      = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

  /** @dev The provider used for swapping into USDC.  */
  SwapProvider public immutable swapper;

  /* ************************************************************************ */

  constructor (IERC20Metadata t, ClubMinter m,
               PurchaseTracker pt, ReferralTracker rt,
               string memory nm, address fwd,
               IWETH w, SwapProvider s)
    PackSale (t, m, pt, rt, nm, fwd)
  {
    weth = w;
    swapper = s;
    require (t == s.wchi (), "SwapProvider does not output the right token");
  }

  receive () external payable
  {
    /* We accept payment of native ETH, so we can unwrap WETH on the fly.  */
    require (msg.sender == address (weth), "payment is not ETH unwrapping");
  }

  /* ************************************************************************ */

  /**
   * @dev Returns the current (exact) input amount required of a certain
   * token to buy a given mint (which is already previewed).  This number
   * should be increased by some slippage tolerance by the frontend before
   * calling into the actual mint function.
   *
   * The swapData argument is the swap-specific extra data (e.g. path)
   * used by the SwapProvider.
   */
  function quoteMint (PackMint memory mintData, IERC20 inputToken,
                      bytes calldata swapData)
      public returns (uint)
  {
    if (inputToken == token)
      return mintData.cost;

    return swapper.quoteExactOutput (inputToken, mintData.cost, swapData);
  }

  /**
   * @dev Previews and quotes the input amount required of a certain token
   * to buy the given number of packs.
   */
  function previewAndQuote (uint clubId, uint numPacks,
                            IERC20 inputToken, bytes calldata swapData)
      public returns (PackMint memory mintData, uint cost)
  {
    mintData = preview (clubId, numPacks);
    cost = quoteMint (mintData, inputToken, swapData);
  }

  /**
   * @dev Mints share packs, paying for them in the given token (or native
   * ETH if inputToken is set as ETH_TOKEN).  The inputAmount of that token
   * is used as swap input, which must be enough to yield the required cost
   * in the payment token, and should be chosen based on quoteMint plus
   * some slippage tolerance.  The excess amount is returned.
   *
   * The swapData argument is the swap-specific extra data such as path
   * information for the SwapProvider used.
   */
  function mintWithSwap (PackMint calldata mintData, string calldata receiver,
                         IERC20 inputToken, uint inputAmount,
                         bytes calldata swapData)
      public payable whenNotPaused
  {
    require (payee != address (0), "no payee configured");

    uint totalRequired = mintData.cost;

    if (inputToken == token)
      {
        /* The input token is already the one used for payment.  In this case,
           verify that the inputAmount is the expected one (just in case)
           and call the non-swapping mint.  */
        require (msg.value == 0, "payment only allowed for native ETH input");
        require (inputAmount == totalRequired,
                 "wrong inputAmount supplied for non-swapping mint");
        mint (mintData, receiver);
        return;
      }

    address buyer = _msgSender ();

    bool nativeETH = (address (inputToken) == ETH_TOKEN);
    if (nativeETH)
      {
        require (msg.value == inputAmount,
                 "payment does not match input amount");
        inputToken = IERC20 (address (weth));
        weth.deposit{value: inputAmount} ();
        require (weth.transfer (address (swapper), inputAmount),
                 "failed to transfer WETH to swapper");
      }
    else
      {
        require (msg.value == 0, "payment only allowed for native ETH input");
        require (inputToken.transferFrom (buyer, address (swapper),
                                          inputAmount),
                 "transferring the input tokens failed");
      }

    swapper.swapExactOutput (inputToken, totalRequired, swapData);
    swapper.transferToken (token, totalRequired, payee);
    mintInternal (mintData, receiver, buyer);

    /* What remains of the input token is returned to the original buyer.  */
    uint excess = inputToken.balanceOf (address (swapper));
    if (excess > 0)
      {
        if (nativeETH)
          {
            swapper.transferToken (inputToken, excess, address (this));
            weth.withdraw (excess);
            (bool success, bytes memory res)
                = buyer.call{value: excess} ("");
            require (success,
                     string (abi.encodePacked (
                        "failed to pay unwrapped ETH back to buyer: ",
                        res)));
          }
        else
          swapper.transferToken (inputToken, excess, buyer);
      }
  }

  /* ************************************************************************ */

}
