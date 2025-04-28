// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {AcrossVault} from "../src/vaults/AcrossVault.sol";
import {AbstractBaseVaultTest} from "./AbstractBaseVault.t.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

contract AcrossVaultTest is AbstractBaseVaultTest {
    using SafeERC20 for IERC20Metadata;

    bool transferred;

    function setUp() public override {
        forkId = vm.createSelectFork("ethereum", lastCachedBlockid_ETHEREUM);
        super.setUp();
        amount = 1e18;
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault =
            _deployAcross(VaultSetup(asset, address(0), address(feeProvider), feeRecipient, name, symbol, admin, admin));
        AcrossVault across = AcrossVault(address(vault));
        console.log("sqrt acxPrice", across.getACXPrice());
        {
            uint256 sqrtPrice_ = across.getACXPrice();
            console.log("acxPrice", (uint256(sqrtPrice_) * uint256(sqrtPrice_)) >> 96);
        }
        (uint160 sqrtPrice,,,,,,) = IUniswapV3Pool(across.acxWethPool()).slot0();
        console.log("pool price", (uint256(sqrtPrice) * uint256(sqrtPrice)) >> 96);
        vm.stopPrank();
    }

    function _increaseVaultAssets() internal override returns (bool) {
        vm.warp(block.timestamp + 1000);
        if (!transferred) {
            vm.startPrank(user4);
            asset.safeTransfer(address(vault), amount);
            vm.stopPrank();
            transferred = true;
        }
        vm.startPrank(admin);
        AcrossVault(address(vault)).reinvest();
        console.log("reinvestedAssets", AcrossVault(address(vault)).reinvested());
        vm.assertEq(IERC20Metadata(AcrossVault(address(vault)).acx()).balanceOf(address(vault)), 0);
        vm.stopPrank();
        return true;
    }

    function test_weth() public {
        asset = weth_ETHEREUM;
        baseVaultTest(true);
        vm.startPrank(admin);
        AcrossVault(address(vault)).claimReinvest(address(admin));
        vm.stopPrank();
    }

    function test_usdt() public {
        asset = usdt_ETHEREUM;
        amount = 1e9;
        baseVaultTest(true);
        _testAfterBase();
    }

    function test_usdc() public {
        asset = usdc_ETHEREUM;
        amount = 1e9;
        baseVaultTest(true);
        _testAfterBase();
    }

    function test_wbtc() public {
        asset = wbtc_ETHEREUM;
        amount = 1e7;
        baseVaultTest(true);
        _testAfterBase();
    }

    function _testAfterBase() internal {
        vm.startPrank(admin);
        uint256 balanceBefore = asset.balanceOf(address(vault));
        console.log("balanceBefore", balanceBefore);
        console.log("reinvestedAssets", AcrossVault(address(vault)).reinvested());
        console.log("rewards", AcrossVault(address(vault)).getRewards());
        AcrossVault(address(vault)).claimReinvest(address(admin));
        vm.stopPrank();
    }
}
