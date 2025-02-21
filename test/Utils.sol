// SPDX-License-Identifier: MIT
// Copyright (C) 2024 Soccerverse Ltd

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @dev Basic helper utilities for tests.
 */
library Utils
{

  /**
   * @dev Builds the correct error message that AccessControl's onlyRole
   * will revert with.
   */
  function missingRoleError (address addr, bytes32 role)
      internal pure returns (bytes memory)
  {
    return abi.encodePacked (
        "AccessControl: account ",
        Strings.toHexString (addr),
        " is missing role ",
        Strings.toHexString (uint256 (role), 32)
    );
  }

}
