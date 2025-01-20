// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {InitVault, IERC20Metadata, IFeeProvider} from "../src/vaults/InitVault.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IInitLendingPool} from "../src/interfaces/init/IInitLendingPool.sol";
import {AbstractBaseVaultTest} from "./AbstractBaseVault.t.sol";

contract InitVaultTest is AbstractBaseVaultTest {
    IInitLendingPool usdbPool;
    IInitLendingPool wethPool;
    IInitLendingPool blastPool;
    IInitLendingPool currentPool;

    function setUp() public override {
        forkId = vm.createSelectFork("blast", lastCachedBlockid_BLAST);
        super.setUp();
        usdbPool = IInitLendingPool(address(0xc5EaC92633aF47c0023Afa0116500ab86FAB430F));
        wethPool = IInitLendingPool(address(0xD20989EB39348994AA99F686bb4554090d0C09F3));
        blastPool = IInitLendingPool(address(0xdafB6929442303e904A2f673A0E7EB8753Bab571));
        amount = 1e20;
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = InitVault(
            address(
                new TransparentUpgradeableProxy(
                    address(new InitVault(asset, currentPool, IFeeProvider(feeProvider), feeRecipient)),
                    admin,
                    abi.encodeCall(InitVault.initialize, (admin, "nameVault", "symbolVault", admin))
                )
            )
        );
        vm.stopPrank();
    }

    function _increaseVaultAssets() internal override returns (bool) {
        vm.warp(block.timestamp + 100);
        currentPool.accrueInterest();
        return true;
    }

    function test_usdb() public fork {
        asset = usdbBlast;
        currentPool = usdbPool;
        baseVaultTest(true);
    }

    function test_blast() public fork {
        asset = blastBlast;
        currentPool = blastPool;
        baseVaultTest(true);
    }

    function test_weth() public fork {
        asset = wethBlast;
        currentPool = wethPool;
        baseVaultTest(true);
    }
}
