// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {AbstractBaseVaultTest, IVault} from "./AbstractBaseVault.t.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract AaveVaultTest is AbstractBaseVaultTest {
    function setUp() public override {
        forkId = vm.createSelectFork("blast", lastCachedBlockid_BLAST);
        super.setUp();
        amount = 1e20;
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = _deployAave(
            VaultSetup(
                asset, address(aave_zerolendPool_BLAST), address(feeProvider), feeRecipient, name, symbol, admin, admin
            )
        );
        vm.stopPrank();
    }

    function _increaseVaultAssets() internal pure override returns (bool) {
        return false;
    }

    function test_usdb() public {
        asset = usdb_BLAST;
        baseVaultTest(true);
    }

    function test_weth_deposit() public {
        asset = weth_BLAST;
        baseVaultTest(true);
    }
}

contract AaveVaultBaseChainTest is AbstractBaseVaultTest {
    function setUp() public override {
        forkId = vm.createSelectFork("base", lastCachedBlockid_BASE);
        super.setUp();
        amount = 1e10;
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = _deployAave(
            VaultSetup(asset, address(aave_pool_BASE), address(feeProvider), feeRecipient, name, symbol, admin, admin)
        );
        vm.stopPrank();
    }

    function _increaseVaultAssets() internal pure override returns (bool) {
        return false;
    }

    function test_usdc() public {
        asset = usdc_BASE;
        baseVaultTest(true);
    }
}

contract AaveVaultArbitrumTest is AbstractBaseVaultTest {
    function setUp() public override {
        forkId = vm.createSelectFork("arbitrum", lastCachedBlockid_ARBITRUM);
        super.setUp();
        amount = 1e10;
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = _deployAave(
            VaultSetup(
                asset, address(aave_pool_ARBITRUM), address(feeProvider), feeRecipient, name, symbol, admin, admin
            )
        );
        vm.stopPrank();
    }

    function _increaseVaultAssets() internal pure override returns (bool) {
        return false;
    }

    function test_usdc() public {
        asset = usdc_ARBITRUM;
        baseVaultTest(true);
    }

    function test_usdt() public {
        asset = usdt_ARBITRUM;
        baseVaultTest(true);
    }
}
