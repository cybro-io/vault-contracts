// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {CompoundLayerbankVault} from "../src/vaults/CompoundLayerbankVault.sol";
import {IFeeProvider} from "../src/FeeProvider.sol";
import {AbstractBaseVaultTest, IVault} from "./AbstractBaseVault.t.sol";

contract CompoundLayerbankVaultScrollTest is AbstractBaseVaultTest {
    function setUp() public override {
        forkId = vm.createSelectFork("scroll", lastCachedBlockid_SCROLL);
        super.setUp();
        amount = 1e18;
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = _deployCompoundLayerbank(
            VaultSetup({
                asset: asset,
                pool: address(compound_layerbankWSTETH_SCROLL),
                feeProvider: address(feeProvider),
                feeRecipient: feeRecipient,
                name: name,
                symbol: symbol,
                admin: admin,
                manager: admin
            })
        );
        vm.stopPrank();
    }

    function _increaseVaultAssets() internal pure override returns (bool) {
        return false;
    }

    function test_wsteth() public {
        asset = wsteth_SCROLL;
        baseVaultTest(true);
    }
}

contract CompoundLayerbankVaultModeTest is AbstractBaseVaultTest {
    function setUp() public override {
        forkId = vm.createSelectFork("mode", lastCachedBlockid_MODE);
        super.setUp();
        amount = 1e9;
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = _deployCompoundLayerbank(
            VaultSetup({
                asset: asset,
                pool: address(compound_layerbankUSDC_MODE),
                feeProvider: address(feeProvider),
                feeRecipient: feeRecipient,
                name: name,
                symbol: symbol,
                admin: admin,
                manager: admin
            })
        );
        vm.stopPrank();
    }

    function _increaseVaultAssets() internal pure override returns (bool) {
        return false;
    }

    function test_usdc() public {
        asset = usdc_MODE;
        baseVaultTest(true);
    }
}

contract CompoundLayerbankVaultB2Test is AbstractBaseVaultTest {
    function setUp() public override {
        forkId = vm.createSelectFork("b2", lastCachedBlockid_B2);
        super.setUp();
        amount = 1e8;
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = _deployCompoundLayerbank(
            VaultSetup({
                asset: asset,
                pool: address(compound_layerbankUSDT_B2),
                feeProvider: address(feeProvider),
                feeRecipient: feeRecipient,
                name: name,
                symbol: symbol,
                admin: admin,
                manager: admin
            })
        );
        vm.stopPrank();
    }

    function _increaseVaultAssets() internal pure override returns (bool) {
        return false;
    }

    function test_usdt() public {
        asset = usdt_B2;
        baseVaultTest(true);
    }
}
