// SPDX-License-Identifier: MIT
// Copyright (C) 2024-2026 Soccerverse Ltd

pragma solidity ^0.8.19;

import "./XayaTest.sol";

import "../src/AutoConvert.sol";
import "../src/DemocritSoccerverse.sol";
import "../src/SoccerverseConfig.sol";

import "@xaya/democrit-evm/src/LimitBuying.sol";
import "@xaya/democrit-evm/src/VaultManager.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @dev A test contract that sets up all that is required for testing
 * with a Democrit environment (including AutoConvert).
 */
abstract contract DemocritTest is XayaTest
{

  /**
   * @dev Address that is owner for the AutoConvert contract and can thus
   * configure fees (for instance).
   */
  address public constant admin = address (2);

  AutoConvert public immutable autoconv;
  DemocritSoccerverse public immutable dem;
  VaultManager public immutable vman;

  constructor ()
  {
    vm.label (admin, "admin");

    address ctrlName = address (ripemd160 ("ctrl name"));
    registerName ("p", "ctrl", ctrlName);

    vm.startPrank (admin);
    SoccerverseConfig cfg = new SoccerverseConfig ();
    vman = new VaultManager (del, cfg);
    autoconv = new AutoConvert (IWETH (address (weth)), address (0));
    dem = new DemocritSoccerverse (vman, address (0), address (autoconv));
    vman.transferOwnership (address (dem));
    autoconv.linkDemocrit (dem);

    vm.startPrank (ctrlName);
    uint tokenId = acc.tokenIdForName ("p", "ctrl");
    acc.safeTransferFrom (ctrlName, address (vman), tokenId);
    assertTrue (vman.initialised ());

    vm.startPrank (supply);
    wchi.transfer (address (vman), 1e8);

    vm.stopPrank ();
  }

  /**
   * @dev Registers a name with the given address, handling required set up
   * before that (such as transferring some WCHI and approving in the
   * accounts and delegation contracts).
   */
  function registerName (string memory ns, string memory name, address addr)
      internal
  {
    vm.startPrank (supply);
    wchi.transfer (addr, 1e8);

    vm.startPrank (addr);
    wchi.approve (address (acc), type (uint256).max);
    acc.register (ns, name);
    acc.setApprovalForAll (address (del), true);

    vm.stopPrank ();
  }

  /**
   * @dev Creates a checkpoint in the contract and returns its hash.
   */
  function createCheckpoint ()
      internal returns (bytes32 res)
  {
    /* Make sure that we simulate a normal progression of blocks.  */
    vm.roll (block.number + 1);

    res = blockhash (block.number - 1);
    vman.maybeCreateCheckpoint ();

    vm.roll (block.number + 1);
  }

  /**
   * @dev Signs the pool data with the given address.  This returns the
   * signature and VaultCheck struct filled in already.
   */
  function signVaultCheck (string memory operator, uint256 privKey,
                           uint vaultId, bytes32 checkpoint)
      internal view
      returns (LimitBuying.VaultCheck memory vault, bytes memory sgn)
  {
    bytes memory body = abi.encode (
        keccak256 ("VaultCheck(uint256 vaultId,bytes32 checkpoint,uint256 nonce)"),
        vaultId,
        checkpoint,
        dem.signatureNonce (operator)
    );
    bytes32 digest = ECDSA.toTypedDataHash (dem.domainSeparator (),
                                            keccak256 (body));

    (uint8 v, bytes32 r, bytes32 s) = vm.sign (privKey, digest);
    sgn = abi.encodePacked (r, s, v);
    vault = LimitBuying.VaultCheck (vaultId, checkpoint);
  }

}
