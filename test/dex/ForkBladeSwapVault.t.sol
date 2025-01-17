// // SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {IAlgebraFactory, INonfungiblePositionManager} from "../../src/dex/AlgebraVault.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {AbstractAlgebraVaultTest} from "./AbstractAlgebraVaultTest.t.sol";

/// @notice Contracts for BladeSwap
// Algebra Factory 0xA87DbF5082Af26c9A6Ab2B854E378f704638CCa5
// Algebra NonfungiblePositionManager 0x7553b306773EFa59E6f9676aFE049D2D2AbdfDd6
// Algebra Pool Deployer 0xfFeEcb1fe0EAaEFeE69d122F6B7a0368637cb593
// BLAST token address 0xb1a5700fa2358173fe465e6ea4ff52e36e88e2ad
// USDB/WETH pool 0xdA5AaEb22eD5b8aa76347eC57424CA0d109eFB2A

contract ForkBladeSwapVaultTest is AbstractAlgebraVaultTest {
    function setUp() public virtual override(AbstractAlgebraVaultTest) {
        super.setUp();
        token0 = IERC20Metadata(address(0x4300000000000000000000000000000000000003));
        token1 = IERC20Metadata(address(0x4300000000000000000000000000000000000004));
        factory = IAlgebraFactory(address(0xA87DbF5082Af26c9A6Ab2B854E378f704638CCa5));
        positionManager = INonfungiblePositionManager(payable(address(0x7553b306773EFa59E6f9676aFE049D2D2AbdfDd6)));
        transferFromToken0 = address(0x3Ba925fdeAe6B46d0BB4d424D829982Cb2F7309e);
        transferFromToken1 = address(0x44f33bC796f7d3df55040cd3C631628B560715C2);
        vm.label(address(token0), "USDB");
        vm.label(address(token1), "WETH");
    }
}
