// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {CErc20} from "../src/interfaces/compound/IcERC.sol";
import {CEth} from "../src/interfaces/compound/IcETH.sol";
import {CompoundVault, IERC20Metadata} from "../src/vaults/CompoundVaultErc20.sol";
import {CompoundVaultETH} from "../src/vaults/CompoundVaultEth.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IFeeProvider} from "../src/FeeProvider.sol";
import {AbstractBaseVaultTest, IVault} from "./AbstractBaseVault.t.sol";

// 0x8C415331761063E5D6b1c8E700f996b13603Fc2E Orbit WBTC decimals 8
// 0x0872b71EFC37CB8DdE22B2118De3d800427fdba0 oEther V2 decimals 18
// 0x9aECEdCD6A82d26F2f86D331B17a1C1676442A87 Orbit USDB decimals 18

contract CompoundVaultTest is AbstractBaseVaultTest {
    CErc20 usdbPool;
    CErc20 wbtcPool;
    CEth ethPool;
    uint256 wbtcAmount;
    uint256 ethAmount;

    function setUp() public override {
        forkId = vm.createSelectFork("blast", lastCachedBlockid_BLAST);
        super.setUp();
        usdbPool = compound_usdbPool_BLAST;
        wbtcPool = compound_wbtcPool_BLAST;
        ethPool = compound_ethPool_BLAST;
        amount = 1e19;
        wbtcAmount = 1 * 1e6;
        ethAmount = 1e18;
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        if (asset == weth_BLAST) {
            vault = CompoundVaultETH(
                payable(
                    address(
                        new TransparentUpgradeableProxy(
                            address(new CompoundVaultETH(weth_BLAST, ethPool, IFeeProvider(feeProvider), feeRecipient)),
                            admin,
                            abi.encodeCall(CompoundVaultETH.initialize, (admin, name, symbol, admin))
                        )
                    )
                )
            );
        } else {
            vault = CompoundVault(
                address(
                    new TransparentUpgradeableProxy(
                        address(
                            new CompoundVault(
                                asset,
                                asset == usdb_BLAST ? usdbPool : wbtcPool,
                                IFeeProvider(feeProvider),
                                feeRecipient
                            )
                        ),
                        admin,
                        abi.encodeCall(CompoundVault.initialize, (admin, name, symbol, admin))
                    )
                )
            );
        }
        vm.stopPrank();
    }

    function _increaseVaultAssets() internal pure override returns (bool) {
        return false;
    }

    function test_usdb() public {
        asset = usdb_BLAST;
        baseVaultTest(true);
    }

    function test_wbtc() public {
        asset = wbtc_BLAST;
        amount = wbtcAmount;
        baseVaultTest(true);
    }

    function test_eth() public {
        asset = weth_BLAST;
        amount = ethAmount;
        baseVaultTest(true);
    }
}

contract CompoundVaultBaseChainTest is AbstractBaseVaultTest {
    function setUp() public override {
        forkId = vm.createSelectFork("base", lastCachedBlockid_BASE);
        super.setUp();
        amount = 1e10;
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = CompoundVault(
            address(
                new TransparentUpgradeableProxy(
                    address(
                        new CompoundVault(asset, compound_moonwellUSDC_BASE, IFeeProvider(feeProvider), feeRecipient)
                    ),
                    admin,
                    abi.encodeCall(CompoundVault.initialize, (admin, name, symbol, admin))
                )
            )
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

contract CompoundVaultArbitrumTest is AbstractBaseVaultTest {
    function setUp() public override {
        forkId = vm.createSelectFork("arbitrum", lastCachedBlockid_ARBITRUM);
        super.setUp();
        amount = 1e10;
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = CompoundVault(
            address(
                new TransparentUpgradeableProxy(
                    address(
                        new CompoundVault(
                            asset, compound_lodestarUSDC_ARBITRUM, IFeeProvider(feeProvider), feeRecipient
                        )
                    ),
                    admin,
                    abi.encodeCall(CompoundVault.initialize, (admin, name, symbol, admin))
                )
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
}

contract CompoundVaultOptimismTest is AbstractBaseVaultTest {
    CErc20 pool_;

    function setUp() public override {
        forkId = vm.createSelectFork("optimism", lastCachedBlockid_OPTIMISM);
        super.setUp();
        amount = 1e9;
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = _deployCompound(
            VaultSetup({
                asset: asset,
                pool: address(pool_),
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
        asset = usdc_OPTIMISM;
        pool_ = compound_moonwellUSDC_OPTIMISM;
        baseVaultTest(true);
    }

    function test_wsteth() public {
        asset = wsteth_OPTIMISM;
        pool_ = compound_moonwellWSTETH_OPTIMISM;
        amount = 1e18;
        baseVaultTest(true);
    }

    function test_usdt() public {
        asset = usdt_OPTIMISM;
        pool_ = compound_moonwellUSDT_OPTIMISM;
        baseVaultTest(true);
    }
}

contract CompoundVaultUnichainTest is AbstractBaseVaultTest {
    function setUp() public override {
        forkId = vm.createSelectFork("unichain", lastCachedBlockid_UNICHAIN);
        super.setUp();
        amount = 1e9;
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = _deployCompound(
            VaultSetup({
                asset: asset,
                pool: address(compound_venusUSDC_UNICHAIN),
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
        asset = usdc_UNICHAIN;
        baseVaultTest(true);
    }
}
