// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {AcrossVault} from "../src/vaults/AcrossVault.sol";
import {AbstractBaseVaultTest} from "./AbstractBaseVault.t.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AcrossVaultTest is AbstractBaseVaultTest {
    using SafeERC20 for IERC20Metadata;

    function setUp() public override {
        forkId = vm.createSelectFork("ethereum", lastCachedBlockid_ETHEREUM);
        super.setUp();
        amount = 1e18;
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = _deployAcross(
            VaultSetup(
                asset, address(across_hubPool_ETHEREUM), address(feeProvider), feeRecipient, name, symbol, admin, admin
            )
        );
        vm.stopPrank();
    }

    function _increaseVaultAssets() internal override returns (bool) {
        vm.warp(block.timestamp + 1000);
        vm.startPrank(admin);
        uint256 reinvestedAssets = AcrossVault(address(vault)).claimReinvest(0);
        console.log("reinvestedAssets", reinvestedAssets);
        vm.assertEq(IERC20Metadata(AcrossVault(address(vault)).acx()).balanceOf(address(vault)), 0);
        vm.stopPrank();
        return true;
    }

    function test_weth() public {
        asset = weth_ETHEREUM;
        baseVaultTest(true);
    }

    function test_usdt() public {
        asset = usdt_ETHEREUM;
        amount = 1e9;
        vm.startPrank(assetProvider_USDT_ETHEREUM);
        asset.safeTransfer(user, amount);
        asset.safeTransfer(user2, amount);
        asset.safeTransfer(admin, amount);
        vm.stopPrank();
        baseVaultTest(false);
    }
}
