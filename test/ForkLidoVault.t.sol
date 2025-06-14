// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {IFeeProvider} from "../src/FeeProvider.sol";
import {AbstractBaseVaultTest, IVault} from "./AbstractBaseVault.t.sol";
import {LidoVault} from "../src/vaults/LidoVault.sol";
import {VaultType} from "./libraries/Swapper.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

abstract contract LidoVaultTest is AbstractBaseVaultTest {
    IUniswapV3Pool currentPool;
    IERC20Metadata wstETH__;

    function setUp() public virtual override {
        super.setUp();
        amount = 1e18;
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = _deployLido(
            VaultSetup(asset, address(currentPool), address(feeProvider), feeRecipient, name, symbol, admin, admin)
        );
        vm.stopPrank();
    }

    function _increaseVaultAssets() internal override returns (bool) {
        dealTokens(wstETH__, address(vault), 1e18);
        return true;
    }

    function test() public {
        baseVaultTest(true);
    }
}

contract LidoVaultTestArbitrum is LidoVaultTest {
    function setUp() public override {
        forkId = vm.createSelectFork("arbitrum", lastCachedBlockid_ARBITRUM);
        super.setUp();
        currentPool = pool_WETH_wstETH_ARBITRUM;
        asset = weth_ARBITRUM;
        wstETH__ = wstETH_ARBITRUM;
    }
}

contract LidoVaultTestBase is LidoVaultTest {
    function setUp() public override {
        forkId = vm.createSelectFork("base", lastCachedBlockid_BASE);
        super.setUp();
        currentPool = pool_WETH_wstETH_BASE;
        asset = weth_BASE;
        wstETH__ = wstETH_BASE;
    }
}
