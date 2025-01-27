// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {InitVault, IERC20Metadata, IFeeProvider} from "../src/vaults/InitVault.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IInitLendingPool} from "../src/interfaces/init/IInitLendingPool.sol";
import {AbstractBaseVaultTest} from "./AbstractBaseVault.t.sol";

contract InitVaultTest is AbstractBaseVaultTest {
    address usdbPool;
    address wethPool;
    address blastPool;
    address currentPool;

    function setUp() public override {
        forkId = vm.createSelectFork("blast", lastCachedBlockid_BLAST);
        super.setUp();
        usdbPool = address(0xc5EaC92633aF47c0023Afa0116500ab86FAB430F);
        wethPool = address(0xD20989EB39348994AA99F686bb4554090d0C09F3);
        blastPool = address(0xdafB6929442303e904A2f673A0E7EB8753Bab571);
        amount = 1e20;
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault =
            _deployInit(VaultSetup(asset, currentPool, address(feeProvider), feeRecipient, name, symbol, admin, admin));
        vm.stopPrank();
    }

    function _increaseVaultAssets() internal override returns (bool) {
        vm.warp(block.timestamp + 10000);
        IInitLendingPool(currentPool).accrueInterest();
        return true;
    }

    function test_usdb() public fork {
        asset = usdb_BLAST;
        currentPool = usdbPool;
        baseVaultTest(true);
    }

    function test_blast() public fork {
        asset = blast_BLAST;
        currentPool = blastPool;
        baseVaultTest(true);
    }

    function test_weth() public fork {
        asset = weth_BLAST;
        currentPool = wethPool;
        baseVaultTest(true);
    }
}
