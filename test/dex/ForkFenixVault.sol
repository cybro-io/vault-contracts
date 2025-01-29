// // SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {AlgebraVault, IAlgebraFactory, INonfungiblePositionManager} from "../../src/dex/AlgebraVault.sol";
import {AbstractAlgebraVaultTest} from "./AbstractAlgebraVaultTest.t.sol";

/// @notice Contracts for Fenix
// Algebra Factory 0x7a44CD060afC1B6F4c80A2B9b37f4473E74E25Df
// Algebra NonfungiblePositionManager 0x8881b3Fb762d1D50e6172f621F107E24299AA1Cd

contract ForkFenixVaultTest is AbstractAlgebraVaultTest {
    function setUp() public virtual override(AbstractAlgebraVaultTest) {
        super.setUp();
        factory = IAlgebraFactory(address(0x7a44CD060afC1B6F4c80A2B9b37f4473E74E25Df));
        positionManager = INonfungiblePositionManager(payable(address(0x8881b3Fb762d1D50e6172f621F107E24299AA1Cd)));
    }
}
