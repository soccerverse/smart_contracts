// SPDX-License-Identifier: MIT
// Copyright (C) 2023-2025 Soccerverse Ltd

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";

import "./DemocritSoccerverse.sol";
import "./SwapProvider.sol";

/**
 * @dev A contract supporting "auto-convert" for Democrit taker orders.
 * This acts as wrapper around the base Democrit protocol, and implements
 * an automatic swap to/from WCHI for the order taker.
 *
 * This contract is Ownable.  The owner is able to configure the auto-convert
 * feature, and in particular, set the fees charged for auto-converts.  They
 * are not otherwise able to do anything that would compromise the protocol
 * or give them access to user funds on the exchange.
 */
contract AutoConvert is ERC2771Context, Ownable
{

  /** @dev WETH contract used for wrapping/unwrapping ETH with auto-convert.  */
  IWETH public immutable weth;

  /**
   * @dev Magic constant for the "token" address passed when native ETH
   * should be used instead (and wrapped/unwrapped on the fly).
   */
  address public constant ETH_TOKEN
      = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

  /**
   * @dev The DemocritSoccerverse contract this corresponds to.  This can
   * be set after deployment once by the owner, and is then fixed.
   *
   * We use this (rather than setting it up immutable in the constructor)
   * because there is a circular dependency between AutoConvert and Democrit
   * (with AutoConvert being the "second" trusted forwarder in Democrit).
   */
  DemocritSoccerverse public democrit;

  /** @dev The WCHI token used, which is retrieved from Democrit.  */
  IERC20 public wchi;

  /** @dev The swap provider used currently for auto-convert.  */
  SwapProvider public swapper;

  /** @dev The base denominator for the auto-convert fees (basis points).  */
  uint public constant BASIS_POINTS = 10000;

  /**
   * @dev Maximum permissible fee (for company and WCHI burn).  This is
   * a basic security mechanism to ensure that even the owner cannot
   * set an unreasonable fee.
   */
  uint public constant MAX_FEE = BASIS_POINTS / 20;

  /** @dev Fee charged on auto-convert in WCHI for burning.  */
  uint public burnFee;

  /**
   * @dev Address where the WCHI burn fee is sent.  This address is used
   * to collect WCHI earmarked for burning, and the actual burn will be
   * done on the underlying Xaya Core network from time to time.
   */
  address public burnReceiver;

  /** @dev Fee charged on auto-convert in the non-WCHI token.  */
  uint public convertFee;

  /**
   * @dev Address where the non-WCHI fees will be sent to.  This is
   * an address owned by the company.
   */
  address public feeReceiver;

  /** @dev Slippage tolerance for swaps executed.  */
  uint public slippageTolerance;

  /** @dev Emitted when Democrit is linked.  */
  event DemocritLinked (DemocritSoccerverse democrit, IERC20 wchi);

  /** @dev Emitted when the convert configuration is updated.  */
  event Configured (SwapProvider swapper,
                    uint burnFee, address burnReceiver,
                    uint convertFee, address feeReceiver,
                    uint slippageTolerance);

  /** @dev Emitted when a market buy with auto-convert happens.  */
  event MarketBuy (IERC20 inputToken, uint inputAmount, uint wchiAmount,
                   uint actualBurn, uint actualFee);

  /** @dev Emitted when a market sell with auto-convert happens.  */
  event MarketSell (IERC20 outputToken, uint outputAmount, uint wchiAmount,
                    uint actualBurn, uint actualFee);

  /* ************************************************************************ */

  constructor (IWETH w, address fwd)
    ERC2771Context(fwd)
  {
    weth = w;

    /* Initially, the auto-convert features are not configured.  Any
       calls to the contract requiring auto-convert will fail until
       the owner does so.  */
  }

  /**
   * @dev Returns true if swaps can be done, i.e. Democrit is linked and
   * a swap provider configured.
   */
  function isReady () public view returns (bool)
  {
    if (address (democrit) == address (0))
      return false;
    if (address (swapper) == address (0))
      return false;
    return true;
  }

  /**
   * @dev Modifier that ensures that the Democrit link and a swapper are
   * configured before a particular call is allowed.
   */
  modifier whenReady ()
  {
    require (isReady (), "the contract is not ready for swaps");
    _;
  }

  /**
   * @dev Sets up the link to the associated Democrit contract.
   */
  function linkDemocrit (DemocritSoccerverse dem) public onlyOwner
  {
    require (address (dem) != address (0), "zero address provided");
    require (address (democrit) == address (0), "Democrit is already linked");
    require (dem.autoConvertAddress () == address (this),
             "Democrit is set up with another AutoConvert");

    IERC20 wchiMemory = dem.vm ().wchi ();
    require (wchiMemory.approve (address (dem), type (uint256).max),
             "failed to approve WCHI on Democrit");

    wchi = wchiMemory;
    democrit = dem;

    emit DemocritLinked (dem, wchiMemory);
  }

  /**
   * @dev Configures the swapper and fees.  By setting the swapper to a
   * zero address, this can also be used to pause/disable conversion.
   */
  function configure (SwapProvider sw, uint bf, address burnRecv,
                      uint cf, address feeRecv, uint s) public onlyOwner
  {
    require (address (democrit) != address (0), "Democrit is not linked yet");

    if (address (sw) != address (0))
      require (sw.wchi () == wchi, "WCHI tokens mismatch");

    require (bf <= MAX_FEE, "burn fee too high");
    require (cf <= MAX_FEE, "convert fee too high");

    /* Since the convert fee is used to cover the slippage (if any),
       the slippage tolerance should be at most the fee, or else this
       won't work out.  */
    require (s <= cf, "slippage tolerance too high");

    if (bf > 0)
      require (burnRecv != address (0), "zero address provided");
    if (cf > 0)
      require (feeRecv != address (0), "zero address provided");

    swapper = sw;
    burnFee = bf;
    burnReceiver = burnRecv;
    convertFee = cf;
    feeReceiver = feeRecv;
    slippageTolerance = s;

    emit Configured (sw, bf, burnRecv, cf, feeRecv, s);
  }

  receive () external payable
  {
    /* We accept payment of native ETH, so we can unwrap WETH on the fly.  */
    require (msg.sender == address (weth), "payment is not ETH unwrapping");
  }

  /* Explicitly specify that we want to use the ERC2771 variants for
     _msgSender and _msgData.  */

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

  /* ************************************************************************ */

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
      public whenReady returns (uint)
  {
    uint totalRequired = addFee (wchiRequired, burnFee);
    uint inputRequired = swapper.quoteExactOutput (inputToken, totalRequired,
                                                   swapData);
    return addFee (inputRequired, convertFee);
  }

  /**
   * @dev Performs a market buy of SMC with auto-convert.  It takes the
   * input currency, deducts the configured fees, converts it to WCHI,
   * and then accepts the list of buy orders in Democrit.
   *
   * The user needs to first get a quote and pass in the quoted inputAmount.
   * Exactly that amount will be taken from their wallet; any changes in
   * the required amount due to slippage will be rolled into the convert fee
   * that is taken.  If the amount is not enough, the transaction will revert.
   *
   * Also the total in WCHI required for Democrit needs to be passed in.
   * This is what the swap targets; if it is not enough, then Democrit
   * will fail in accepting the sell orders.
   */
  function marketBuy (IERC20 inputToken, uint inputAmount,
                      uint wchiAmount, bytes calldata swapData,
                      Democrit.AcceptedSellOrder[] calldata orders)
      public payable whenReady
  {
    if (address (inputToken) == ETH_TOKEN)
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
        require (inputToken.transferFrom (_msgSender (), address (swapper),
                                          inputAmount),
                 "transferring the input tokens failed");
      }

    uint totalWchi = addFee (wchiAmount, burnFee);
    uint wchiFee = totalWchi - wchiAmount;
    swapper.swapExactOutput (inputToken, totalWchi, swapData);

    /* We transfer the WCHI for Democrit to the contract, and then trigger
       the buying from the contract.  The account to which SMC are sent is
       explicitly specified anyway in the orders, and the WCHI is then taken
       from the message sender (this contract).

       Note that this contract is a "trusted forwarder" for Democrit, so we have
       to pass the message sender (this address) explicitly to the call.  */

    swapper.transferToken (wchi, wchiAmount, address (this));
    (bool success, bytes memory data)
        = address (democrit).call (
      abi.encodePacked (democrit.acceptSellOrders.selector,
                        abi.encode (orders),
                        address (this))
    );
    require (success,
             string (abi.encodePacked ("failed to execute Democrit call: ",
                                       data)));

    uint actualBurn = 0;
    if (burnReceiver != address (0))
      {
        actualBurn = wchi.balanceOf (address (swapper));
        require (actualBurn >= wchiFee, "not enough WCHI fee available");
        swapper.transferToken (wchi, actualBurn, burnReceiver);
      }

    uint actualFee = 0;
    if (feeReceiver != address (0))
      {
        actualFee = inputToken.balanceOf (address (swapper));
        /* This check enforces the slippage tolerance indirectly (assuming
           that the user passed in the right quote), and thus also prevents
           sandwich attacks.  */
        uint minFee = convertFee - slippageTolerance;
        require (actualFee >= inputAmount * minFee / BASIS_POINTS,
                 "slippage too high");
        swapper.transferToken (inputToken, actualFee, feeReceiver);
      }

    emit MarketBuy (inputToken, inputAmount, wchiAmount, actualBurn, actualFee);
  }

  /* ************************************************************************ */

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
      public whenReady returns (uint)
  {
    uint wchiForSwap = removeFee (wchiReceived, burnFee);
    uint output = swapper.quoteExactInput (wchiForSwap, outputToken, swapData);

    return removeFee (output, convertFee);
  }

  /**
   * @dev Performs a market sell of SMC with auto-convert.  This fills limit
   * buy orders on Democrit on the user's behalf first.  Then it converts
   * the WCHI the user received to the desired output token using the swapper,
   * and deducts fees along the way as needed.
   *
   * The user needs to first get a quote and pass in the quoted outputAmount.
   * Exactly that amount will be returned to their wallet; any changes in
   * the resulting amount due to slippage will be rolled into the convert fee
   * that is taken.  If the amount requested cannot be recovered, the
   * transaction will revert.
   *
   * Also the total in WCHI that Democrit should yield needs to be passed in.
   * This is what the swap uses as input.
   */
  function marketSell (IERC20 outputToken, uint outputAmount,
                       uint wchiAmount, bytes calldata swapData,
                       Democrit.AcceptedBuyOrder[] calldata orders)
      public whenReady
  {
    bool nativeETH = (address (outputToken) == ETH_TOKEN);
    if (nativeETH)
      outputToken = IERC20 (address (weth));

    /* We call Democrit on behalf of the user, i.e. by passing in the user's
       address as _msgSender() to Democrit.  We can do that, since AutoConvert
       is a trusted forwarder for Democrit.

       We make sure that the amount returned in WCHI is exactly what is expected
       by the user.  */

    address seller = _msgSender ();
    {
      uint balanceBefore = wchi.balanceOf (seller);
      (bool success, bytes memory data)
          = address (democrit).call (
        abi.encodePacked (democrit.acceptBuyOrders.selector,
                          abi.encode (orders),
                          seller)
      );
      require (success,
               string (abi.encodePacked ("failed to execute Democrit call: ",
                                         data)));
      uint balanceAfter = wchi.balanceOf (seller);
      require (balanceAfter == balanceBefore + wchiAmount,
               "unexpected WCHI amount received from Democrit");
    }

    uint actualBurn = 0;
    if (burnReceiver != address (0))
      {
        actualBurn = wchiAmount * burnFee / BASIS_POINTS;
        require (wchi.transferFrom (seller, burnReceiver, actualBurn),
                 "failed to transfer WCHI to burn receiver");
      }

    uint swapInput = wchiAmount - actualBurn;
    require (wchi.transferFrom (seller, address (swapper), swapInput),
             "failed to transfer WCHI to swapper contract");
    swapper.swapExactInput (swapInput, outputToken, swapData);

    if (nativeETH)
      {
        swapper.transferToken (outputToken, outputAmount, address (this));
        weth.withdraw (outputAmount);
        (bool success, bytes memory data)
            = seller.call{value: outputAmount} ("");
        require (success,
                 string (abi.encodePacked (
                    "failed to pay unwrapped ETH to seller: ",
                    data)));
      }
    else
      swapper.transferToken (outputToken, outputAmount, seller);

    uint actualFee = 0;
    if (feeReceiver != address (0))
      {
        actualFee = outputToken.balanceOf (address (swapper));
        /* This check enforces the slippage tolerance indirectly (assuming
           that the user passed in the right quote), and thus also prevents
           sandwich attacks.  */
        uint minFee = convertFee - slippageTolerance;
        require (actualFee >= outputAmount * minFee / BASIS_POINTS,
                 "slippage too high");
        swapper.transferToken (outputToken, actualFee, feeReceiver);
      }

    emit MarketSell (outputToken, outputAmount, wchiAmount,
                     actualBurn, actualFee);
  }

  /* ************************************************************************ */

}
