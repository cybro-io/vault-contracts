// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {IFeeProvider} from "../src/FeeProvider.sol";
import {AbstractBaseVaultTest, IVault} from "./AbstractBaseVault.t.sol";
import {JonesCamelotVault} from "../src/vaults/JonesCamelotVault.sol";
import {VaultType} from "./libraries/Swapper.sol";

contract JonesCamelotVaultTest is AbstractBaseVaultTest {
    address pool;

    function setUp() public override {
        forkId = vm.createSelectFork("arbitrum", lastCachedBlockid_ARBITRUM);
        super.setUp();
        specialWarpTime = 1000;
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = IVault(
            _deployJonesCamelot(
                VaultSetup({
                    asset: asset,
                    feeRecipient: feeRecipient,
                    feeProvider: address(feeProvider),
                    pool: pool,
                    admin: admin,
                    manager: admin,
                    name: name,
                    symbol: symbol
                })
            )
        );
        vm.stopPrank();
    }

    function _increaseVaultAssets() internal pure override returns (bool) {
        return false;
    }

    function test_wethWeeth() public {
        asset = weth_ARBITRUM;
        pool = address(compounder_jones_ARBITRUM);
        amount = 1e18;
        baseVaultTest(true);
        _checkMovePrice(
            JonesCamelotVault(address(vault)).token0(),
            JonesCamelotVault(address(vault)).token1(),
            VaultType.AlgebraV1_9
        );
    }
}
