// // SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {AlgebraVault, IAlgebraFactory, INonfungiblePositionManager} from "../../src/AlgebraVault.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {AbstractAlgebraVaultTest} from "./AbstractAlgebraVaultTest.t.sol";

/// @notice Contracts for BladeSwap
// Algebra Factory 0x7a44CD060afC1B6F4c80A2B9b37f4473E74E25Df
// Algebra NonfungiblePositionManager 0x8881b3Fb762d1D50e6172f621F107E24299AA1Cd

contract ForkFenixVaultTest is AbstractAlgebraVaultTest {
    function setUp() public virtual override {
        super.setUp();
        token0 = IERC20Metadata(address(0x4300000000000000000000000000000000000003));
        token1 = IERC20Metadata(address(0x4300000000000000000000000000000000000004));
        factory = IAlgebraFactory(address(0x7a44CD060afC1B6F4c80A2B9b37f4473E74E25Df));
        positionManager = INonfungiblePositionManager(payable(address(0x8881b3Fb762d1D50e6172f621F107E24299AA1Cd)));
        transferFromToken0 = address(0x3Ba925fdeAe6B46d0BB4d424D829982Cb2F7309e);
        transferFromToken1 = address(0x44f33bC796f7d3df55040cd3C631628B560715C2);
        vm.label(address(token0), "USDB");
        vm.label(address(token1), "WETH");
    }
}
