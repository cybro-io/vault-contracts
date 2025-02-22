// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {AbstractBaseVaultTest, IVault} from "./AbstractBaseVault.t.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract SparkVaultTest is AbstractBaseVaultTest {
    function setUp() public override {
        forkId = vm.createSelectFork("base", lastCachedBlockid_BASE);
        super.setUp();
        amount = 1e10;
        vm.label(address(susds_BASE), "SUSDS");
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = _deploySparkVault(
            VaultSetup(asset, address(psm3Pool_BASE), address(feeProvider), feeRecipient, name, symbol, admin, admin)
        );
        vm.stopPrank();
    }

    function _increaseVaultAssets() internal pure override returns (bool) {
        return false;
    }

    function test_usdb() public {
        asset = usdc_BASE;
        baseVaultTest(true);
    }
}
