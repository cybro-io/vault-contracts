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

contract AaveVaultAvalancheTest is AbstractBaseVaultTest {
    function setUp() public override {
        forkId = vm.createSelectFork("avalanche", lastCachedBlockid_AVALANCHE);
        super.setUp();
        amount = 1e20;
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = _deployAave(
            VaultSetup(
                asset, address(aave_pool_AVALANCHE), address(feeProvider), feeRecipient, name, symbol, admin, admin
            )
        );
        vm.stopPrank();
    }

    function _increaseVaultAssets() internal pure override returns (bool) {
        return false;
    }

    function test_frax() public {
        asset = frax_AVALANCHE;
        baseVaultTest(true);
    }

    function test_weth() public {
        asset = weth_AVALANCHE;
        amount = 1e18;
        baseVaultTest(true);
    }
}

contract AaveVaultMetisTest is AbstractBaseVaultTest {
    function setUp() public override {
        forkId = vm.createSelectFork("metis", lastCachedBlockid_METIS);
        super.setUp();
        amount = 1e20;
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = _deployAave(
            VaultSetup(asset, address(aave_pool_METIS), address(feeProvider), feeRecipient, name, symbol, admin, admin)
        );
        vm.stopPrank();
    }

    function _increaseVaultAssets() internal pure override returns (bool) {
        return false;
    }

    function test_dai() public {
        asset = dai_METIS;
        baseVaultTest(true);
    }
}

contract AaveVaultSonicTest is AbstractBaseVaultTest {
    function setUp() public override {
        forkId = vm.createSelectFork("sonic", lastCachedBlockid_SONIC);
        super.setUp();
        amount = 1e18;
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = _deployAave(
            VaultSetup(asset, address(aave_pool_SONIC), address(feeProvider), feeRecipient, name, symbol, admin, admin)
        );
        vm.stopPrank();
    }

    function _increaseVaultAssets() internal pure override returns (bool) {
        return false;
    }

    function test_weth() public {
        asset = weth_SONIC;
        baseVaultTest(true);
    }
}

contract AaveVaultBscTest is AbstractBaseVaultTest {
    function setUp() public override {
        forkId = vm.createSelectFork("bsc", lastCachedBlockid_BSC);
        super.setUp();
        amount = 1e7;
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = _deployAave(
            VaultSetup(
                asset, address(aave_avalonPool_BSC), address(feeProvider), feeRecipient, name, symbol, admin, admin
            )
        );
        vm.stopPrank();
    }

    function _increaseVaultAssets() internal pure override returns (bool) {
        return false;
    }

    function test_btcb() public {
        asset = btcb_BSC;
        baseVaultTest(true);
    }
}

contract AaveVaultCoreTest is AbstractBaseVaultTest {
    function setUp() public override {
        forkId = vm.createSelectFork("core", lastCachedBlockid_CORE);
        super.setUp();
        amount = 1e9;
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = _deployAave(
            VaultSetup({
                asset: asset,
                pool: address(aave_colendPool_CORE),
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
        asset = usdt_CORE;
        baseVaultTest(true);
    }

    function test_usdc() public {
        asset = usdc_CORE;
        baseVaultTest(true);
    }

    function test_wbtc() public {
        asset = wbtc_CORE;
        amount = 1e7;
        baseVaultTest(true);
    }
}
