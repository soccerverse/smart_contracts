// SPDX-License-Identifier: MIT
// Copyright (C) 2024 Soccerverse Ltd

pragma solidity ^0.8.19;

import "../src/BoolSet.sol";

import { Test } from "forge-std/Test.sol";

using BoolSet for BoolSet.Type;

contract BoolSetTest is Test
{

  /// forge-config: default.allow_internal_expect_revert = true
  function test_indexOutOfBounds () public
  {
    BoolSet.Type memory bs = BoolSet.create (0);
    vm.expectRevert ("index out of bounds");
    bs.setTrue (0);
    vm.expectRevert ("index out of bounds");
    bs.get (0);

    bs = BoolSet.create (10);
    vm.expectRevert ("index out of bounds");
    bs.setTrue (10);
    vm.expectRevert ("index out of bounds");
    bs.get (10);

    bs = BoolSet.create (1);
    vm.expectRevert ("index out of bounds");
    bs.setTrue (10);
    vm.expectRevert ("index out of bounds");
    bs.get (10);
  }

  function test_singleBits () public pure
  {
    uint len = 300;

    for (uint i = 0; i < len; ++i)
      {
        BoolSet.Type memory bs = BoolSet.create (len);
        bs.setTrue (i);

        for (uint j = 0; j < len; ++j)
          assertEq (bs.get (j), i == j);
      }
  }

  function test_variousLengths () public pure
  {
    uint max = 300;

    BoolSet.Type memory bs = BoolSet.create (1);
    bs.setTrue (0);
    assertTrue (bs.get (0));

    bs = BoolSet.create (2);
    bs.setTrue (1);
    assertFalse (bs.get (0));
    assertTrue (bs.get (1));

    for (uint i = 3; i < max; ++i)
      {
        bs = BoolSet.create (i);
        bs.setTrue (0);
        bs.setTrue (i - 1);

        for (uint j = 0; j < i; ++j)
          assertEq (bs.get (j), j == 0 || j == i - 1);
      }
  }

  function test_multipleBits () public pure
  {
    BoolSet.Type memory bs = BoolSet.create (10);

    bs.setTrue (1);
    bs.setTrue (5);
    bs.setTrue (3);
    bs.setTrue (1);

    assertFalse (bs.get (0));
    assertTrue (bs.get (1));
    assertFalse (bs.get (2));
    assertTrue (bs.get (3));
    assertFalse (bs.get (4));
    assertTrue (bs.get (5));
  }

}
