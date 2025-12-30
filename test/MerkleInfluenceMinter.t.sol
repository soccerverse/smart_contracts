// SPDX-License-Identifier: MIT
// Copyright (C) 2025 Soccerverse Ltd

pragma solidity ^0.8.19;

import "./MinterTest.sol";
import "../src/MerkleInfluenceMinter.sol";

/**
 * @dev Test data we use.  This is based on the test Merkle tree constructed
 * in tools/merkle-mint/test-data.py.
 */
library TestData
{

  /** @dev The test data root hash.  */
  bytes32 internal constant ROOT_HASH
      = hex"f2bec6653850ea2a572be65a9c4d8bf246c2cf76023de304c5a0382ada4dbee8";

  /**
   * @dev Returns the mint data for the valid test mint with the given index
   * included in the test Merkle tree.
   */
  function getMint (uint index)
      public pure returns (MerkleInfluenceMinter.MintData memory)
  {
    if (index == 0)
      return MerkleInfluenceMinter.MintData (42, 5, "domob");
    if (index == 1)
      return MerkleInfluenceMinter.MintData (42, 10, "andy");
    if (index == 2)
      return MerkleInfluenceMinter.MintData (100, 1, "domob");
    revert ("invalid index for test data");
  }

  /**
   * @dev Returns the Merkle proof for the test mint with given index.
   */
  function getProof (uint index)
      public pure returns (bytes32[] memory)
  {
    bytes32[] memory res = new bytes32[] (2);

    if (index == 0)
      {
        res[0] = hex"008ca0446e917b72b677fc0b8956495ce878734d7ecf9a88495037a8bb9c9623";
        res[1] = hex"d6aed8215fc2c17ec01cc2b3a1ad0f8a4a090da5b28cf9465583f49b0ebbd9cc";
        return res;
      }

    if (index == 1)
      {
        res[0] = hex"8c20ebd3c3ecb59d55d0082391015d29e6bc3c60ed0d7d413c5eee1897cb5acc";
        res[1] = hex"d6aed8215fc2c17ec01cc2b3a1ad0f8a4a090da5b28cf9465583f49b0ebbd9cc";
        return res;
      }

    if (index == 2)
      {
        res[0] = hex"0000000000000000000000000000000000000000000000000000000000000000";
        res[1] = hex"6059e337eec553c11b327b4b69405d614eb6d962a0c887cac12eedf5553a9f6f";
        return res;
      }

    revert ("invalid index for test data");
  }

}

contract MerkleInfluenceMinterTest is MinterTest
{

  /** @dev The deployed MerkleInfluenceMinter contract.  */
  MerkleInfluenceMinter public immutable minter;

  constructor ()
  {
    minter = new MerkleInfluenceMinter (cm, TestData.ROOT_HASH);

    vm.startPrank (admin);
    cm.grantRole (cm.MINTER_ROLE (), address (minter));
    vm.stopPrank ();
  }

  function test_mintHash () public view
  {
    /* The first proof entries of the first two mints are the leaf hashes
       of the respective other element.  */
    assertEq (minter.mintHash (TestData.getMint (0)),
              TestData.getProof (1)[0]);
    assertEq (minter.mintHash (TestData.getMint (1)),
              TestData.getProof (0)[0]);
  }

  function test_executeSuccess () public
  {
    MerkleInfluenceMinter.MintData memory m = TestData.getMint (1);
    bytes32[] memory proof = TestData.getProof (1);

    address sender = vm.addr (100);

    vm.expectEmit (address (minter));
    emit MerkleInfluenceMinter.MintDone (m.clubId, m.num, m.receiver, sender);
    vm.prank (sender);
    minter.execute (m, proof);

    assertEq (minter.mintsDone (), 1);
    assertEq (cm.sharesMinted (m.clubId), m.num);
    assertTrue (minter.alreadyMinted (minter.mintHash (m)));
    assertFalse (minter.alreadyMinted (minter.mintHash (TestData.getMint (2))));
  }

  function test_executeAlreadyMinted () public
  {
    MerkleInfluenceMinter.MintData memory m = TestData.getMint (0);
    bytes32[] memory proof = TestData.getProof (0);

    minter.execute (m, proof);

    vm.expectPartialRevert (MerkleInfluenceMinter.MintAlreadyDone.selector);
    minter.execute (m, proof);

    assertEq (minter.mintsDone (), 1);
    assertEq (cm.sharesMinted (m.clubId), m.num);
  }

  function test_executeInvalidProof () public
  {
    MerkleInfluenceMinter.MintData memory m = TestData.getMint (0);
    bytes32[] memory proof0 = TestData.getProof (0);
    bytes32[] memory proof1 = TestData.getProof (1);

    vm.expectPartialRevert (MerkleInfluenceMinter.MerkleInvalid.selector);
    minter.execute (m, proof1);

    m.receiver = "mallory";
    vm.expectPartialRevert (MerkleInfluenceMinter.MerkleInvalid.selector);
    minter.execute (m, proof0);

    assertEq (minter.mintsDone (), 0);
    assertEq (cm.sharesMinted (m.clubId), 0);
  }

  function test_batchOperations () public
  {
    MerkleInfluenceMinter.MintData[] memory data
        = new MerkleInfluenceMinter.MintData[] (3);
    MerkleInfluenceMinter.MintWithProof[] memory withProof
        = new MerkleInfluenceMinter.MintWithProof[] (2);

    for (uint i = 0; i < 3; ++i)
      {
        data[i] = TestData.getMint (i);
        if (i < withProof.length)
          {
            withProof[i].mint = data[i];
            withProof[i].proof = TestData.getProof (i);
          }
      }

    minter.executeBatch (withProof);
    assertEq (minter.mintsDone (), 2);
    assertEq (cm.sharesMinted (data[0].clubId), data[0].num + data[1].num);

    bool[] memory alreadyDone = minter.checkDoneBatch (data);
    assertEq (alreadyDone.length, data.length);
    assertTrue (alreadyDone[0]);
    assertTrue (alreadyDone[1]);
    assertFalse (alreadyDone[2]);
  }

}
