// SPDX-License-Identifier: MIT
// Copyright (C) 2024 Soccerverse Ltd

pragma solidity ^0.8.19;

import "./TestSanctionsList.sol";
import "./SaleTest.sol";

contract SwappingPackSaleTest is SaleTest
{

  address public constant buyer = address (101);
  string public constant receiver = "receiver";

  uint public constant balance = 1000;
  uint public immutable allShares;
  bytes public rate;

  constructor ()
  {
    vm.label (buyer, "buyer");

    /* The buyer is also sending native ETH in tests.  */
    vm.deal (buyer, 1e18);

    allShares = cm.shareSupply ();

    /* 1 WCHI or ETH is worth 10 USDC for buying packs.  */
    rate = swapper.rate (10);

    vm.startPrank (supply);
    usdc.transfer (buyer, balance);
    wchi.transfer (buyer, balance);

    vm.startPrank (buyer);
    usdc.approve (address (ps), type (uint256).max);
    wchi.approve (address (ps), type (uint256).max);

    vm.startPrank (admin);
    cm.grantRole (cm.MINTER_ROLE (), admin);
    ps.setPayee (payee);
    /* One pack costs 100 USDC.  */
    ps.configure (0, 1, 0);
    setPricing (allShares, 100);
    ps.addClub (10);

    vm.stopPrank ();
  }

  /* ************************************************************************ */

  function test_invalidEthPayment () public
  {
    (bool ok, ) = address (ps).call {value: 42} ("");
    assertFalse (ok);
  }

  function test_quoteMint () public view
  {
    PackSale.PackMint memory data = ps.preview (10, 2);
    assertEq (ps.quoteMint (data, usdc, rate), 200);
    assertEq (ps.quoteMint (data, IERC20 (address (weth)), rate), 20);
    data = ps.preview (10, 4);
    assertEq (ps.quoteMint (data, wchi, rate), 40);
  }

  function test_previewAndQuote () public view
  {
    (PackSale.PackMint memory data, uint cost)
        = ps.previewAndQuote (10, 2, usdc, rate);

    assertEq (cost, 200);
    assertEq (data.cost, cost);
    assertEq (ps.quoteMint (data, usdc, rate), cost);
  }

  /* ************************************************************************ */

  function test_failsWhenPaused () public
  {
    vm.prank (admin);
    ps.pause ();

    PackSale.PackMint memory data = ps.preview (10, 2);
    vm.startPrank (buyer);
    vm.expectRevert ("Pausable: paused");
    ps.mintWithSwap (data, receiver, usdc, 200, rate);
    vm.expectRevert ("Pausable: paused");
    ps.mintWithSwap (data, receiver, wchi, 20, rate);
  }

  function test_failsWhenPreviewIsOutdated () public
  {
    PackSale.PackMint memory data = ps.preview (10, 2);

    vm.startPrank (admin);
    setPricing (allShares, 200);

    vm.startPrank (buyer);
    vm.expectRevert ("provided PackMint data is no longer valid");
    ps.mintWithSwap (data, receiver, usdc, 200, rate);
    vm.expectRevert ("provided PackMint data is no longer valid");
    ps.mintWithSwap (data, receiver, wchi, 20, rate);
  }

  function test_mintingInPaymentToken () public
  {
    PackSale.PackMint memory data = ps.preview (10, 2);
    vm.startPrank (buyer);

    vm.expectRevert ("wrong inputAmount supplied for non-swapping mint");
    ps.mintWithSwap (data, receiver, usdc, 100, rate);

    vm.expectRevert ("payment only allowed for native ETH input");
    ps.mintWithSwap{value: 10} (data, receiver, usdc, 200, rate);

    ps.mintWithSwap (data, receiver, usdc, 200, rate);

    assertEq (cm.sharesMinted (10), 2);

    assertEq (usdc.balanceOf (buyer), balance - 200);
    assertEq (usdc.balanceOf (payee), 200);

    assertEq (wchi.balanceOf (buyer), balance);
    assertEq (wchi.balanceOf (payee), 0);
  }

  function test_mintingWithERC20 () public
  {
    PackSale.PackMint memory data = ps.preview (10, 2);
    vm.startPrank (buyer);

    vm.expectRevert ("payment only allowed for native ETH input");
    ps.mintWithSwap{value: 10} (data, receiver, wchi, 19, rate);

    /* This is an input amount that is not sufficient after swapping.  */
    vm.expectRevert ("ERC20: transfer amount exceeds balance");
    ps.mintWithSwap (data, receiver, wchi, 19, rate);

    /* Mint without excess first.  */
    ps.mintWithSwap (data, receiver, wchi, 20, rate);
    /* Mint with excess that will be returned.  */
    data = ps.preview (10, 3);
    ps.mintWithSwap (data, receiver, wchi, 35, rate);

    assertEq (cm.sharesMinted (10), 5);

    assertEq (usdc.balanceOf (buyer), balance);
    assertEq (usdc.balanceOf (payee), 500);

    assertEq (wchi.balanceOf (buyer), balance - 50);
    assertEq (wchi.balanceOf (payee), 0);
  }

  function test_mintingWithNativeETH () public
  {
    IERC20 eth = IERC20 (ps.ETH_TOKEN ());
    PackSale.PackMint memory data = ps.preview (10, 2);
    vm.startPrank (buyer);

    vm.expectRevert ("payment does not match input amount");
    ps.mintWithSwap (data, receiver, eth, 20, rate);
    vm.expectRevert ("payment does not match input amount");
    ps.mintWithSwap{value: 25} (data, receiver, eth, 20, rate);

    /* Input amount is not sufficient after swapping.  */
    vm.expectRevert ();
    ps.mintWithSwap{value: 19} (data, receiver, eth, 19, rate);

    uint balanceBefore = buyer.balance;

    /* Mint once without excess and once with.  */
    ps.mintWithSwap{value: 20} (data, receiver, eth, 20, rate);
    data = ps.preview (10, 3);
    ps.mintWithSwap{value: 35} (data, receiver, eth, 35, rate);

    assertEq (cm.sharesMinted (10), 5);

    assertEq (usdc.balanceOf (buyer), balance);
    assertEq (usdc.balanceOf (payee), 500);

    assertEq (buyer.balance, balanceBefore - 50);
  }

  /* ************************************************************************ */

}
