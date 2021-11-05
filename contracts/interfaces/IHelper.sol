// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.8;

import "./ISuper1155.sol";

interface IHelper {
   function getByteCode() external pure returns (bytes memory);
}