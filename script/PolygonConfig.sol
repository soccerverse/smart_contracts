
// SPDX-License-Identifier: MIT
// Copyright (C) 2024 Soccerverse Ltd

pragma solidity ^0.8.19;

import "../src/ISanctionsList.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";
import "@xaya/eth-account-registry/contracts/XayaAccounts.sol";
import "@xaya/eth-delegator-contract/contracts/XayaDelegation.sol";

/**
 * @dev Helper library defining constants such as token addresses
 * used for deployments on the Polygon network.
 */
library PolygonConfig
{

  /** @dev Xaya delegation contract.  */
  XayaDelegation public constant del
      = XayaDelegation (0xEB4c2EF7874628B646B8A59e4A309B94e14C2a6B);

  /** @dev ERC-2771 forwarder contract to use for meta transactions.  */
  address public constant fwd = 0xf0511f123164602042ab2bCF02111fA5D3Fe97CD;

  /** @dev Uniswap v2 router for swapping.  */
  IUniswapV2Router01 public constant uniswap2
      = IUniswapV2Router01 (0xedf6066a2b290C185783862C7F4776A2C8077AD1);

  /** @dev Chainalysis sanctions oracle.  */
  ISanctionsList public constant sanctions
      = ISanctionsList (0x40C57923924B5c5c5455c48D93317139ADDaC8fb);

  /**
   * @dev "WETH" token contract used.  (Note that since we are on Polygon,
   * this is WMATIC, and not "actual" PoS WETH!)
   */
  IWETH public constant weth
      = IWETH (0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);

  /** @dev USDC token contract used.  */
  IERC20Metadata public constant usdc
      = IERC20Metadata (0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359);

  /**
   * @dev Returns the WCHI token address.
   */
  function wchi () public view returns (IERC20Metadata)
  {
    /* IXayaAccounts declares the wchiToken() function not as view, but it
       is in XayaAccounts.  */
    XayaAccounts acc = XayaAccounts (address (del.accounts ()));
    return IERC20Metadata (address (acc.wchiToken ()));
  }

}
