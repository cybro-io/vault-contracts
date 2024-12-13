// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {IVault} from "./IVault.sol";

interface IDexVault is IVault {
    function getPositionAmounts() external view returns (uint256 amount0, uint256 amount1);
    function getCurrentSqrtPrice() external view returns (uint160);
}
