// SPDX-License-Identifier: MIT
// Copyright (C) 2025 Soccerverse Ltd

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "./ClubMinter.sol";
import "./PackSale.sol";

/**
 * @dev This contract implements an ERC20 token that represents "vouchers"
 * for buying club packs.  The token can be minted by the Soccerverse team,
 * such as for give-aways.  It can be used to mint club packs "equivalent"
 * to USDC.
 *
 * Minting is done by this contract directly.  It uses the "real" PackSale
 * contracts to preview what a particular pack costs and contains, and then it
 * mints the pack contents directly with the ClubMinter and "pays for" it by
 * burning the voucher tokens.
 */
contract PackVoucher is ERC20, AccessControlEnumerable, Pausable
{

  /** @dev Addresses with this role can freely mint and burn voucher tokens.  */
  bytes32 public constant TOKEN_ADMIN_ROLE = keccak256 ("TOKEN_ADMIN_ROLE");

  /**
   * @dev Addresses with this role can mint a limited amount of voucher tokens.
   * This is what will be used mainly for giving out vouchers, by addresses
   * that are "less secure" (than the team multisig).  The multisig is used
   * to "top up" the limit from time to time.
   */
  bytes32 public constant LIMITED_MINTER_ROLE
      = keccak256 ("LIMITED_MINTER_ROLE");

  /**
   * @dev Addresses with this role can burn tokens but not mint them.  */
   bytes32 public constant BURNER_ROLE = keccak256 ("BURNER_ROLE");

  /** @dev The ClubMinter used.  */
  ClubMinter public immutable minter;

  /** @dev The payment token this is "equivalent to" (such as USDC).  */
  IERC20Metadata public immutable eqvToken;

  /**
   * @dev Amount of voucher tokens that the LIMITED_MINTER_ROLE can still mint
   * until the TOKEN_ADMIN_ROLE needs to step in to increase the limit again.
   */
  uint public mintLimitRemaining;

  /* ************************************************************************ */

  constructor (string memory name, string memory symbol,
               ClubMinter m, IERC20Metadata t)
    ERC20(name, symbol)
  {
    _grantRole (DEFAULT_ADMIN_ROLE, msg.sender);
    minter = m;
    eqvToken = t;
  }

  function pause () public onlyRole (DEFAULT_ADMIN_ROLE)
  {
    _pause ();
  }

  function unpause () public onlyRole (DEFAULT_ADMIN_ROLE)
  {
    _unpause ();
  }

  /**
   * @dev The decimals used for this token are based on the decimals of the
   * payment token this is supposed to be "equivalent" to.
   */
  function decimals ()
      public view virtual override returns (uint8)
  {
    return eqvToken.decimals ();
  }

  /** @dev Error raised when a transfer is attempted.  */
  error TransferIsNotPossible (address from, address to, uint256 amount);

  /**
   * @dev The token is not transferrable, to avoid trading or selling of
   * vouchers (rather than redeeming them for packs).  The TOKEN_ADMIN_ROLE
   * can, if needed, burn and re-mint tokens.
   */
  function _beforeTokenTransfer (address from, address to, uint256 amount)
      internal virtual override
  {
    super._beforeTokenTransfer (from, to, amount);

    /* Mints and burns are fine, but normal transfers are disallowed.  */
    if (from != address (0) && to != address (0))
      revert TransferIsNotPossible (from, to, amount);
  }

  /* ************************************************************************ */

  /** @dev Event emitted when the mint limit is changed.  */
  event MintLimitChanged (uint newLimit);

  /** @dev Error raised when permissions are not sufficient to burn tokens.  */
  error NotAllowedToBurn (address operator, address owner);

  /** @dev Error raised when an address is in general not allowed to mint.  */
  error NotAllowedToMint (address operator);

  /**
   * @dev Error raised when a LIMITED_MINTER_ROLE tries to mint more tokens
   * than the current remaining limit.
   */
  error MintLimitExceeded (address operator, uint attempt, uint limit);

  /**
   * @dev Sets the limit of tokens that LIMITED_MINTER_ROLE can mint.  This can
   * be used by a TOKEN_ADMIN_ROLE to "top up" the limit, from which the
   * LIMITED_MINTER_ROLE can then draw for a while.
   */
  function setMintLimit (uint newLimit)
      public onlyRole (TOKEN_ADMIN_ROLE)
  {
    mintLimitRemaining = newLimit;
    emit MintLimitChanged (newLimit);
  }

  /**
   * @dev Data about a burn operation.
   */
  struct BurnOp
  {

    /** @dev The address to burn tokens from.  */
    address from;

    /** @dev The amount to burn.  */
    uint amount;

  }

  /**
   * @dev Executes a batch of burn operations.
   */
  function batchBurn (BurnOp[] memory ops) public
  {
    bool isBurner = (hasRole (TOKEN_ADMIN_ROLE, msg.sender)
                      || hasRole (BURNER_ROLE, msg.sender));

    for (uint i = 0; i < ops.length; ++i)
      {
        if (!isBurner && msg.sender != ops[i].from)
          revert NotAllowedToBurn (msg.sender, ops[i].from);

        _burn (ops[i].from, ops[i].amount);
      }
  }

  /**
   * @dev Burn some tokens owned by the given address.
   */
  function burnFrom (address from, uint amount) public
  {
    BurnOp[] memory ops = new BurnOp[] (1);
    ops[0].from = from;
    ops[0].amount = amount;

    batchBurn (ops);
  }

  /**
   * @dev Data about a mint operation.
   */
  struct MintOp
  {

    /** @dev The address receiving the vouchers.  */
    address to;

    /** @dev Amount to credit to this address.  */
    uint amount;

  }

  /**
   * @dev Batch-mints vouchers to a set of addresses.
   */
  function batchMint (MintOp[] memory ops) public
  {
    uint total = 0;
    for (uint i = 0; i < ops.length; ++i)
      total += ops[i].amount;

    if (!hasRole (TOKEN_ADMIN_ROLE, msg.sender))
      {
        if (!hasRole (LIMITED_MINTER_ROLE, msg.sender))
          revert NotAllowedToMint (msg.sender);

        uint limit = mintLimitRemaining;
        if (total > limit)
          revert MintLimitExceeded (msg.sender, total, limit);

        limit -= total;
        mintLimitRemaining = limit;
        emit MintLimitChanged (limit);
      }

    for (uint i = 0; i < ops.length; ++i)
      _mint (ops[i].to, ops[i].amount);
  }

  /**
   * @dev Mints new tokens to the given receiver.  This can be done by the
   * TOKEN_ADMIN_ROLE unlimited, and the LIMITED_MINTER_ROLE up to the
   * remaining limit.
   */
  function mint (address to, uint amount) public
  {
    MintOp[] memory ops = new MintOp[] (1);
    ops[0].to = to;
    ops[0].amount = amount;

    batchMint (ops);
  }

  /* ************************************************************************ */

  /** @dev Error raised if an invalid PackSale contract is used for minting.  */
  error InvalidPackSaleContract (PackSale sale);

  /** @dev Error raised if mint is called with wrong mintData.  */
  error PackMintDataInvalid (PackSale sale, PackSale.PackMint mintData);

  /** @dev Error raised if mint exceeds voucher balance.  */
  error RedeemExceedsBalance (uint cost, uint balance);

  /**
   * @dev Checks that the given PackSale contract is "active" and it is fine
   * to use it as reference for available packs.  A contract is active if it
   * is not paused and has MINTER_ROLE with the ClubMinter, i.e. it could be
   * used directly to mint packs as well.  Contracts that have e.g. been
   * superseded by new deployments will typically be paused and not have the
   * MINTER_ROLE, and won't be able to be used as reference here.
   */
  function checkSaleIsActive (PackSale sale) private view
  {
    if (sale.paused ())
      revert InvalidPackSaleContract (sale);

    if (!minter.hasRole (minter.MINTER_ROLE (), address (sale)))
      revert InvalidPackSaleContract (sale);

    /* Otherwise it is fine.  */
  }

  /**
   * @dev Data about a redeem operation.
   */
  struct RedeemOp
  {

    /** @dev The PackSale contract this is buying a pack from.  */
    PackSale sale;

    /** @dev The full "preview" data for the purchase.  */
    PackSale.PackMint mintData;

    /** @dev The recipient account name.  */
    string receiver;

  }

  /**
   * @dev Runs a batch redeem operation.
   */
  function batchRedeem (RedeemOp[] memory ops)
      public whenNotPaused
  {
    uint totalCost = 0;
    for (uint i = 0; i < ops.length; ++i)
      {
        checkSaleIsActive (ops[i].sale);

        if (!ops[i].sale.isPackMintCurrent (ops[i].mintData))
          revert PackMintDataInvalid (ops[i].sale, ops[i].mintData);

        totalCost += ops[i].mintData.cost;
      }

    /* _burn reverts if the balance is not sufficient, but this explicit
       check ensures we produce a more useful error.  */
    address buyer = msg.sender;
    uint balance = balanceOf (buyer);
    if (totalCost > balance)
      revert RedeemExceedsBalance (totalCost, balance);

    _burn (buyer, totalCost);

    for (uint i = 0; i < ops.length; ++i)
      {
        for (uint j = 0; j < ops[i].mintData.shares.length; ++j)
          minter.mintShares (ops[i].mintData.shares[j].clubId,
                             ops[i].mintData.shares[j].numShares,
                             ops[i].receiver);

        emit PackSale.PacksBought (buyer, ops[i].receiver,
                                   ops[i].mintData.primaryClubId,
                                   ops[i].mintData.numPacks,
                                   ops[i].mintData.cost);
      }
  }

  /**
   * @dev Mints club packs equivalent to one of the packs from the official
   * shop (the passed-in PackSale contract) with the voucher tokens.
   */
  function redeem (PackSale sale, PackSale.PackMint calldata mintData,
                   string calldata receiver)
      public
  {
    RedeemOp[] memory ops = new RedeemOp[] (1);
    ops[0].sale = sale;
    ops[0].mintData = mintData;
    ops[0].receiver = receiver;

    batchRedeem (ops);
  }

}
