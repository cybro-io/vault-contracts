// // SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {BaseDexUniformVault} from "../../src/dex/BaseDexUniformVault.sol";
import {AbstractBaseVaultTest} from "../AbstractBaseVault.t.sol";
import {Swapper, VaultType} from "../libraries/Swapper.sol";
import {DexPriceCheck} from "../../src/libraries/DexPriceCheck.sol";
import {AlgebraVault} from "../../src/dex/AlgebraVault.sol";
import {BlasterSwapV3Vault} from "../../src/dex/BlasterSwapV3Vault.sol";
import {BlasterSwapV2Vault} from "../../src/dex/BlasterSwapV2Vault.sol";

abstract contract AbstractDexVaultTest is AbstractBaseVaultTest {
    uint256 amountEth;

    IERC20Metadata token0;
    IERC20Metadata token1;

    bool zeroOrOne;
    Swapper swapper;
    VaultType vaultType;

    function setUp() public virtual override(AbstractBaseVaultTest) {
        forkId = vm.createSelectFork("blast", lastCachedBlockid_BLAST);
        super.setUp();
        amount = 3e21;
        amountEth = 5e18;
        token0 = usdb_BLAST;
        token1 = weth_BLAST;
        vm.label(address(token0), "USDB");
        vm.label(address(token1), "WETH");
        swapper = new Swapper();
    }

    function _increaseVaultAssets() internal pure virtual override returns (bool) {
        return false;
    }

    function _additionalChecksAfterDeposit(address, uint256, uint256) internal view override {
        (uint256 checkAmount0, uint256 checkAmount1) = BaseDexUniformVault(address(vault)).getPositionAmounts();
        vm.assertGt(checkAmount0, 0);
        vm.assertGt(checkAmount1, 0);
    }

    function _checkMovePrice() internal {
        uint256 currentPrice = BaseDexUniformVault(address(vault)).getCurrentSqrtPrice();
        swapper.movePoolPrice(
            vaultType == VaultType.BlasterV2
                ? address(BlasterSwapV2Vault(address(vault)).lpToken())
                : address(BlasterSwapV3Vault(address(vault)).pool()),
            address(token0),
            address(token1),
            uint160(currentPrice * 105 / 100),
            vaultType
        );
        uint256 currentPriceAfterChange = BaseDexUniformVault(address(vault)).getCurrentSqrtPrice();
        vm.assertGt(currentPriceAfterChange, currentPrice);
        vm.startPrank(user4);
        vm.expectRevert(DexPriceCheck.PriceManipulation.selector);
        vault.deposit(amount, user4, 0);
        vm.stopPrank();
    }

    function test_vault() public fork {
        asset = token0;
        baseVaultTest(true);
        _checkMovePrice();
    }

    function test_vault2() public fork {
        asset = token1;
        amount = amountEth;
        baseVaultTest(true);
        _checkMovePrice();
    }
}
