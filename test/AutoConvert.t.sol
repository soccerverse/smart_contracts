// SPDX-License-Identifier: MIT
// Copyright (C) 2024-2026 Soccerverse Ltd

pragma solidity ^0.8.19;

import "./DemocritTest.sol";
import "./TestSwapProvider.sol";
import "./TestToken.sol";

import "@xaya/democrit-evm/src/LimitSelling.sol";

contract AutoConvertTest is DemocritTest
{

  address public constant buyer = address (101);
  address public constant seller = address (102);
  address public constant pool = address (103);
  address public constant fee = address (104);

  uint256 public constant poolSignerKey = 4242;
  address public immutable poolSigner;

  ERC20 public immutable usdc;
  ERC20 public immutable ethToken;

  TestSwapProvider public immutable swapper;

  LimitSelling.AcceptedSellOrder[] public marketBuy;
  LimitBuying.AcceptedBuyOrder[] public marketSell;

  bytes public rate1000;

  constructor ()
  {
    poolSigner = vm.addr (poolSignerKey);
    vm.label (buyer, "buyer");
    vm.label (seller, "seller");
    vm.label (pool, "pool");
    vm.label (poolSigner, "pool signer");
    vm.label (fee, "fee receiver");

    usdc = new TestToken (supply, 1e9 * 1e6);
    ethToken = ERC20 (autoconv.ETH_TOKEN ());
    swapper = new TestSwapProvider (wchi, supply);
    rate1000 = swapper.rate (1000);

    createFounder ("p", "buyer", buyer);
    createFounder ("p", "seller", seller);
    createFounder ("p", "pool", pool);
    vm.prank (pool);
    acc.setApprovalForAll (poolSigner, true);

    vm.deal (buyer, 1e6);
    setTokenBalance (wchi, buyer, 1e6);
    setTokenBalance (wchi, seller, 0);
    setTokenBalance (wchi, fee, 0);

    setTokenBalance (usdc, buyer, 1e6);
    setTokenBalance (usdc, seller, 0);
    setTokenBalance (usdc, fee, 0);

    vm.startPrank (supply);
    vm.deal (supply, 1e9);
    weth.deposit{value: 1e6} ();
    weth.approve (address (swapper), type (uint256).max);
    wchi.approve (address (swapper), type (uint256).max);
    usdc.approve (address (swapper), type (uint256).max);

    vm.startPrank (buyer);
    wchi.approve (address (dem), type (uint256).max);
    wchi.approve (address (autoconv), type (uint256).max);
    vm.stopPrank ();

    vm.prank (seller);
    wchi.approve (address (autoconv), type (uint256).max);
    vm.prank (buyer);
    usdc.approve (address (autoconv), type (uint256).max);

    uint sellOrder = dem.nextOrderId ();
    vm.prank (seller);
    dem.createSellOrder ("seller", "smc", 1000, 1e6);
    bytes32 cpHash = createCheckpoint ();
    marketBuy.push (LimitSelling.AcceptedSellOrder (sellOrder, 1000, "buyer",
                                                    cpHash));

    uint poolId = vman.getNextVaultId ();
    vm.prank (pool);
    dem.createPool ("pool", "", "smc", 1000, 0);
    uint depositId = vman.getNextVaultId ();
    vm.prank (seller);
    dem.createSellDeposit ("seller", "smc", 1000);
    cpHash = createCheckpoint ();
    uint buyOrder = dem.nextOrderId ();
    vm.prank (buyer);
    dem.createBuyOrder ("buyer", "smc", 1000, 1e6, poolId, cpHash);
    (LimitBuying.VaultCheck memory vault, bytes memory sgn)
        = signVaultCheck ("pool", poolSignerKey, depositId, cpHash);
    marketSell.push (LimitBuying.AcceptedBuyOrder (buyOrder, 1000, vault, sgn));
  }

  /**
   * @dev Registers a name with the given address, and sets up everything for it
   * to act as a vault founder (i.e. sets up delegation to the VaultManager).
   */
  function createFounder (string memory ns, string memory name, address addr)
      internal
  {
    registerName (ns, name, addr);

    string[] memory path = new string[] (1);
    path[0] = "g";

    vm.prank (addr);
    del.grant (ns, name, path, address (vman), type (uint256).max, false);
  }

  /**
   * @dev Sets the token balance of the given account by transferring to/from
   * supply.
   */
  function setTokenBalance (ERC20 token, address addr, uint bal)
      internal
  {
    uint cur = token.balanceOf (addr);
    if (cur > 0)
      {
        vm.prank (addr);
        token.transfer (supply, cur);
      }

    vm.prank (supply);
    token.transfer (addr, bal);

    assertEq (token.balanceOf (addr), bal);
  }

  /**
   * @dev Configures the AutoConvert contract with the given fee rates for
   * burn and convert.
   */
  function setFees (uint burn, uint convert)
      internal
  {
    vm.prank (admin);
    autoconv.configure (swapper, burn, fee, convert, fee, 0);
  }

  /* ************************************************************************ */

  function test_linkDemocritConditions () public
  {
    vm.prank (buyer);
    AutoConvert ac = new AutoConvert (IWETH (address (weth)), address (0));

    vm.prank (buyer);
    vm.expectRevert ("zero address provided");
    ac.linkDemocrit (DemocritSoccerverse (address (0)));

    vm.prank (seller);
    vm.expectRevert ("Ownable: caller is not the owner");
    ac.linkDemocrit (dem);

    vm.prank (buyer);
    vm.expectRevert ("Democrit is set up with another AutoConvert");
    ac.linkDemocrit (dem);

    vm.prank (admin);
    vm.expectRevert ("Democrit is already linked");
    autoconv.linkDemocrit (dem);
  }

  function test_configureChecksFees () public
  {
    vm.startPrank (admin);

    vm.expectRevert ("burn fee too high");
    autoconv.configure (swapper, 501, fee, 0, fee, 0);

    vm.expectRevert ("convert fee too high");
    autoconv.configure (swapper, 0, fee, 501, fee, 0);

    vm.expectRevert ("slippage tolerance too high");
    autoconv.configure (swapper, 0, fee, 100, fee, 101);
  }

  function test_configureChecksAddresses () public
  {
    vm.startPrank (admin);

    vm.expectRevert ("zero address provided");
    autoconv.configure (swapper, 1, address (0), 0, fee, 0);

    vm.expectRevert ("zero address provided");
    autoconv.configure (swapper, 0, fee, 1, address (0), 0);
  }

  function test_configureOnlyOwner () public
  {
    vm.prank (buyer);
    vm.expectRevert ("Ownable: caller is not the owner");
    autoconv.configure (swapper, 0, fee, 0, fee, 0);
  }

  function test_configureSuccess () public
  {
    vm.startPrank (admin);

    autoconv.configure (swapper, 500, fee, 0, address (0), 0);
    assertTrue (autoconv.isReady ());
    assertEq (address (autoconv.swapper ()), address (swapper));
    assertEq (autoconv.burnFee (), 500);
    assertEq (autoconv.burnReceiver (), fee);
    assertEq (autoconv.convertFee (), 0);
    assertEq (autoconv.feeReceiver (), address (0));
    assertEq (autoconv.slippageTolerance (), 0);

    autoconv.configure (SwapProvider (address (0)),
                        0, address (0), 500, fee, 10);
    assertFalse (autoconv.isReady ());
    assertEq (address (autoconv.swapper ()), address (0));
    assertEq (autoconv.burnFee (), 0);
    assertEq (autoconv.burnReceiver (), address (0));
    assertEq (autoconv.convertFee (), 500);
    assertEq (autoconv.feeReceiver (), fee);
    assertEq (autoconv.slippageTolerance (), 10);
  }

  function test_invalidEthPayment () public
  {
    (bool ok, ) = address (autoconv).call {value: 42} ("");
    assertFalse (ok);
  }

  function test_pausingAndUnpausing () public
  {
    setFees (0, 0);

    assertFalse (dem.paused ());
    vm.prank (buyer);
    vm.expectRevert ("Ownable: caller is not the owner");
    dem.pause ();
    assertFalse (dem.paused ());
    vm.prank (admin);
    dem.pause ();
    assertTrue (dem.paused ());

    /* When paused, no market orders should be possible to do, neither via
       AutoConvert nor Democrit directly.  Since the error happens in Democrit
       directly and is rethrown in AutoConvert from a low-level call, we
       can't easily get the exact revert reason, and thus just expect
       any revert.  */
    vm.startPrank (buyer);
    vm.expectRevert ();
    autoconv.marketBuy (usdc, 1000, 1e6, rate1000, marketBuy);
    vm.expectRevert ();
    dem.acceptSellOrders (marketBuy);

    vm.startPrank (seller);
    vm.expectRevert ();
    autoconv.marketSell (usdc, 1000, 1e6, rate1000, marketSell);
    vm.expectRevert ();
    dem.acceptBuyOrders (marketSell);
    vm.stopPrank ();

    vm.prank (buyer);
    vm.expectRevert ("Ownable: caller is not the owner");
    dem.unpause ();
    assertTrue (dem.paused ());
    vm.prank (admin);
    dem.unpause ();
    assertFalse (dem.paused ());
  }

  /* ************************************************************************ */

  function test_quoteMarketBuy () public
  {
    vm.expectRevert ("the contract is not ready for swaps");
    autoconv.quoteMarketBuy (usdc, 1e6, rate1000);

    setFees (0, 0);
    assertEq (autoconv.quoteMarketBuy (usdc, 1e6, rate1000), 1000);

    setFees (100, 0);
    assertEq (autoconv.quoteMarketBuy (usdc, 1e6, rate1000), 1010);

    setFees (0, 200);
    assertEq (autoconv.quoteMarketBuy (usdc, 1e6, rate1000), 1020);

    setFees (100, 200);
    assertEq (autoconv.quoteMarketBuy (usdc, 1e6, rate1000), 1030);
  }

  function test_marketBuyFailsWhenNotReady () public
  {
    vm.prank (buyer);
    vm.expectRevert ("the contract is not ready for swaps");
    autoconv.marketBuy (usdc, 1000, 1e6, rate1000, marketBuy);
  }

  function test_marketBuyFailsInputTransfer () public
  {
    setFees (0, 0);
    vm.startPrank (buyer);
    usdc.approve (address (autoconv), 0);
    vm.expectRevert ("ERC20: insufficient allowance");
    autoconv.marketBuy (usdc, 1000, 1e6, rate1000, marketBuy);
  }

  function test_marketBuyFailsInsufficientOutput () public
  {
    setFees (0, 0);
    vm.prank (buyer);
    vm.expectRevert ();
    autoconv.marketBuy (usdc, 900, 900e3, rate1000, marketBuy);
  }

  function test_marketBuyFailsSlippageTooHigh () public
  {

    /* This also sets slippage tolerance to zero.  In this situation, the
       resulting amount of WCHI is not enough at all to cover even
       the Democrit trade alone.  */
    setFees (0, 0);
    bytes memory rate = swapper.rate (999);
    vm.prank (buyer);
    vm.expectRevert ("ERC20: transfer amount exceeds balance");
    autoconv.marketBuy (usdc, 1000, 1e6, rate, marketBuy);

    /* In this test, the total amount is sufficient, but the remaining fee
       is not the expected minimum, since slippage is lower than the convert
       fee but higher than the slippage tolerance.  */
    vm.prank (admin);
    autoconv.configure (swapper, 0, fee, 500, fee, 100);
    rate = swapper.rate (980);
    vm.prank (buyer);
    vm.expectRevert ("slippage too high");
    autoconv.marketBuy (usdc, 1050, 1e6, rate, marketBuy);
  }

  function test_marketBuyWithoutFeesOrSlippage () public
  {
    setFees (0, 0);
    vm.prank (buyer);
    autoconv.marketBuy (usdc, 1000, 1e6, rate1000, marketBuy);

    assertEq (wchi.balanceOf (seller), 1e6);
    assertEq (usdc.balanceOf (buyer), 999e3);

    assertEq (wchi.balanceOf (fee), 0);
    assertEq (usdc.balanceOf (fee), 0);
  }

  function test_marketBuyGoodSlippage () public
  {
    setFees (0, 0);
    bytes memory rate = swapper.rate (1010);
    vm.prank (buyer);
    autoconv.marketBuy (usdc, 1000, 1e6, rate, marketBuy);

    assertEq (wchi.balanceOf (seller), 1e6);
    assertEq (usdc.balanceOf (buyer), 999e3);

    assertEq (wchi.balanceOf (fee), 0);
    assertEq (usdc.balanceOf (fee), 10);
  }

  function test_marketBuySippageAndFees () public
  {
    vm.prank (admin);
    autoconv.configure (swapper, 200, fee, 500, fee, 200);

    uint quote = autoconv.quoteMarketBuy (usdc, 1e6, rate1000);
    bytes memory rate = swapper.rate (990);
    vm.prank (buyer);
    autoconv.marketBuy (usdc, quote, 1e6, rate, marketBuy);

    assertEq (wchi.balanceOf (seller), 1e6);
    assertEq (usdc.balanceOf (buyer), 1e6 - quote);

    assertEq (wchi.balanceOf (fee), 20e3);
    assertEq (usdc.balanceOf (fee), 41);
  }

  function test_marketBuyInvalidEthPayments () public
  {
    setFees (0, 0);
    vm.startPrank (buyer);

    vm.expectRevert ("payment only allowed for native ETH input");
    autoconv.marketBuy{value: 10} (usdc, 1000, 1e6, rate1000, marketBuy);

    vm.expectRevert ("payment does not match input amount");
    autoconv.marketBuy{value: 42} (ethToken, 1000, 1e6, rate1000, marketBuy);
  }

  function test_marketBuyEthPayment () public
  {
    setFees (0, 100);
    vm.prank (buyer);
    autoconv.marketBuy{value: 1010} (ethToken, 1010, 1e6, rate1000, marketBuy);

    assertEq (wchi.balanceOf (seller), 1e6);
    assertEq (usdc.balanceOf (buyer), 1e6);

    assertEq (wchi.balanceOf (fee), 0);
    assertEq (usdc.balanceOf (fee), 0);
    assertEq (weth.balanceOf (fee), 10);
  }

  /* ************************************************************************ */

  function test_quoteMarketSell () public
  {
    vm.expectRevert ("the contract is not ready for swaps");
    autoconv.quoteMarketSell (usdc, 1e6, rate1000);

    setFees (0, 0);
    assertEq (autoconv.quoteMarketSell (usdc, 1e6, rate1000), 1000);

    setFees (100, 0);
    assertEq (autoconv.quoteMarketSell (usdc, 1e6, rate1000), 990);

    setFees (0, 200);
    assertEq (autoconv.quoteMarketSell (usdc, 1e6, rate1000), 980);

    setFees (100, 200);
    assertEq (autoconv.quoteMarketSell (usdc, 1e6, rate1000), 970);
  }

  function test_marketSellFailsWhenNotReady () public
  {
    vm.prank (seller);
    vm.expectRevert ("the contract is not ready for swaps");
    autoconv.marketSell (usdc, 1000, 1e6, rate1000, marketSell);
  }

  function test_marketSellFailsWithDemocrit () public
  {
    setFees (0, 0);
    setTokenBalance (wchi, buyer, 0);
    vm.prank (seller);
    vm.expectRevert ();
    autoconv.marketSell (usdc, 1000, 1e6, rate1000, marketSell);
  }

  function test_marketSellFailsWithWchiAmountMismatch () public
  {
    setFees (0, 0);
    vm.startPrank (seller);

    vm.expectRevert ("unexpected WCHI amount received from Democrit");
    autoconv.marketSell (usdc, 1000, 1e6 + 1, rate1000, marketSell);

    vm.expectRevert ("unexpected WCHI amount received from Democrit");
    autoconv.marketSell (usdc, 1000, 1e6 - 1, rate1000, marketSell);
  }

  function test_marketSellFailsWithSellerNotApprovedWchi () public
  {
    setFees (0, 0);
    vm.startPrank (seller);
    wchi.approve (address (autoconv), 0);
    vm.expectRevert ("ERC20: insufficient allowance");
    autoconv.marketSell (usdc, 1000, 1e6, rate1000, marketSell);
  }

  function test_marketSellFailsSlippageTooHigh () public
  {
    /* No fees, but the amount of tokens received is insufficient for the
       expected amount of the seller.  */
    setFees (0, 0);
    bytes memory rate = swapper.rate (1001);
    vm.prank (seller);
    vm.expectRevert ("ERC20: transfer amount exceeds balance");
    autoconv.marketSell (usdc, 1000, 1e6, rate, marketSell);

    /* In this test, the amount received would be sufficient for the user's
       requested output, but the remaining amount for fees is too low.  */
    vm.prank (admin);
    autoconv.configure (swapper, 0, fee, 500, fee, 100);
    rate = swapper.rate (1020);
    vm.prank (seller);
    vm.expectRevert ("slippage too high");
    autoconv.marketSell (usdc, 950, 1e6, rate, marketSell);
  }

  function test_marketSellWithoutFeesOrSlippage () public
  {
    /* The existing amount of WCHI of the seller should be left alone.  */
    setTokenBalance (wchi, seller, 42);

    setFees (0, 0);
    vm.prank (seller);
    autoconv.marketSell (usdc, 1000, 1e6, rate1000, marketSell);

    assertEq (wchi.balanceOf (seller), 42);
    assertEq (usdc.balanceOf (seller), 1000);
    assertEq (wchi.balanceOf (buyer), 0);

    assertEq (wchi.balanceOf (fee), 0);
    assertEq (usdc.balanceOf (fee), 0);
  }

  function test_marketSellGoodSlippage () public
  {
    /* The existing amount of WCHI of the seller should be left alone.  */
    setTokenBalance (wchi, seller, 42);

    setFees (0, 0);
    bytes memory rate = swapper.rate (990);
    vm.prank (seller);
    autoconv.marketSell (usdc, 1000, 1e6, rate, marketSell);

    assertEq (wchi.balanceOf (seller), 42);
    assertEq (usdc.balanceOf (seller), 1000);
    assertEq (wchi.balanceOf (buyer), 0);

    assertEq (wchi.balanceOf (fee), 0);
    assertEq (usdc.balanceOf (fee), 10);
  }

  function test_marketSellSlippageAndFees () public
  {
    /* The existing amount of WCHI of the seller should be left alone.  */
    setTokenBalance (wchi, seller, 42);

    vm.prank (admin);
    autoconv.configure (swapper, 200, fee, 500, fee, 200);
    uint quote = autoconv.quoteMarketSell (usdc, 1e6, rate1000);
    bytes memory rate = swapper.rate (1010);
    vm.prank (seller);
    autoconv.marketSell (usdc, quote, 1e6, rate, marketSell);

    assertEq (wchi.balanceOf (seller), 42);
    assertEq (usdc.balanceOf (seller), quote);
    assertEq (wchi.balanceOf (buyer), 0);

    assertEq (wchi.balanceOf (fee), 20e3);
    assertEq (usdc.balanceOf (fee), 39);
  }

  function test_marketSellUnwrapsEth () public
  {
    uint before = seller.balance;

    setFees (0, 100);
    vm.prank (seller);
    autoconv.marketSell (ethToken, 990, 1e6, rate1000, marketSell);

    assertEq (wchi.balanceOf (seller), 0);
    assertEq (usdc.balanceOf (buyer), 1e6);

    assertEq (wchi.balanceOf (fee), 0);
    assertEq (usdc.balanceOf (fee), 0);
    assertEq (weth.balanceOf (fee), 10);

    assertEq (seller.balance, before + 990);
  }

  /* ************************************************************************ */

}
