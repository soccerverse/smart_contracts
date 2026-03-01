// SPDX-License-Identifier: MIT
// Copyright (C) 2025 Soccerverse Ltd

pragma solidity ^0.8.19;

import "./ClubMinter.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @dev This contract holds a set of desired mints of club influence, which
 * should be performed via the ClubMinter.  The set is defined by a Merkle
 * root hash at contract deployment.
 *
 * Once deployed, exactly the mints from this set can be executed without
 * further authorisation required from this contract, until all is minted.
 *
 * This provides a way to run batch mints in a safe way, where minting
 * permission is once granted to the deployed contract in a small transaction
 * verifying just the root hash (essentially), and then the full list of
 * mints, including in multiple transactions and batches, can be done
 * safely against the pre-authorised set of mints by a wallet that has
 * no special permissions.  This way we can avoid giving minting permission
 * (even if temporary) to a single hot wallet used to run a minting script,
 * and instead keep it all secured by the team multisig that needs to just
 * perform one action to grant the MerkleInfluenceMinter with the right
 * root hash minting permission.
 *
 * This contract is Ownable, and gives the owner permission to renounce
 * the MINTER_ROLE the contract has (so that this can be done without requiring
 * to go through a multisig or high-security transaction again with the key
 * admin account for ClubMinter).  The owner has no other permissions.
 */
contract MerkleInfluenceMinter is Ownable
{

  /**
   * @dev Data about one desired mint.  This forms the data on the
   * Merkle tree.
   *
   * Due to the way in which we track duplicates (by hash of this struct),
   * it is not possible to have two mints with exactly same data in the tree;
   * but this is not necessary, any mints should be aggregated (num summed up)
   * by clubId and receiver anyway.
   */
  struct MintData
  {

    /** @dev The club ID for which to mint shares.  */
    uint clubId;

    /** @dev Number of shares to mint for this club.  */
    uint num;

    /** @dev Recipient account name.  */
    string receiver;

  }

  /**
   * @dev Data about one mint with its Merkle proof.
   */
  struct MintWithProof
  {

    /** @dev The mint data itself.  */
    MintData mint;

    /** @dev The Merkle proof for it.  */
    bytes32[] proof;

  }

  /** @dev The ClubMinter used to run the mints.  */
  ClubMinter public immutable minter;

  /** @dev The Merkle root hash.  */
  bytes32 public immutable rootHash;

  /** @dev All mints that have been done already.  */
  mapping (bytes32 => bool) public alreadyMinted;

  /**
   * @dev Counts how many mints have been done already.  With knowledge of
   * the full Merkle tree, this can be used to quickly check if all is done.
   */
  uint public mintsDone;

  /** @dev Emitted when a single mint has been done.  */
  event MintDone (uint clubId, uint num, string receiver, address minter);

  /** @dev Error raised when a mint has already been done and is re-tried.  */
  error MintAlreadyDone (uint clubId, uint num, string receiver);

  /**
   * @dev Error raised when a given mint is not in the Merkle tree or the
   * proof is wrong.
   */
  error MerkleInvalid (uint clubId, uint num, string receiver);

  constructor (ClubMinter m, bytes32 r)
  {
    minter = m;
    rootHash = r;
  }

  /**
   * @dev Returns the hash of a MintData structure that we use to identify
   * it on the Merkle tree and also to track mints already done.
   */
  function mintHash (MintData calldata data)
      public pure returns (bytes32)
  {
    /* The string has variable length in the ABI encoding, but the other
       data fields have not, so it is safe to hash them all together with the
       string at the end.

       We use a domain separator to ensure that the data can never match
       an internal node in the Merkle tree (which hashes together two
       uint256's).  */
    return keccak256 (abi.encodePacked (
        bytes1 (0x00),
        data.clubId, data.num, data.receiver
    ));
  }

  /**
   * @dev Batch checks a list of mints whether or not they have already
   * been done.  This is useful for the tools managing the minting transactions
   * to call read-only (not on-chain directly).
   */
  function checkDoneBatch (MintData[] calldata data)
      public view returns (bool[] memory res)
  {
    res = new bool[] (data.length);
    for (uint i = 0; i < data.length; ++i)
      res[i] = alreadyMinted[mintHash (data[i])];
  }

  /**
   * @dev Checks and executes (if valid) a given mint.  Everyone is allowed
   * to do this, as the contract enforces that only the pre-authorised mints
   * can be executed (and they can be executed only once).
   */
  function execute (MintData calldata data, bytes32[] calldata proof)
      public
  {
    bytes32 hash = mintHash (data);
    if (alreadyMinted[hash])
      revert MintAlreadyDone (data.clubId, data.num, data.receiver);

    if (!MerkleProof.verifyCalldata (proof, rootHash, hash))
      revert MerkleInvalid (data.clubId, data.num, data.receiver);

    alreadyMinted[hash] = true;
    minter.mintShares (data.clubId, data.num, data.receiver);
    ++mintsDone;
    emit MintDone (data.clubId, data.num, data.receiver, msg.sender);
  }

  /**
   * @dev Executes a batch of mints.
   */
  function executeBatch (MintWithProof[] calldata batch)
      public
  {
    for (uint i = 0; i < batch.length; ++i)
      execute (batch[i].mint, batch[i].proof);
  }

  /**
   * @dev Renounces the MINTER_ROLE the contract has on the ClubMinter.
   */
  function renounceMinterRole () public onlyOwner
  {
    minter.renounceRole (minter.MINTER_ROLE (), address (this));
  }

}
