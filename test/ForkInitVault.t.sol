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
    InitVault usdbVault;
    InitVault wethVault;
    InitVault blastVault;
    IInitLendingPool currentPool;

    function setUp() public override {
        forkId = vm.createSelectFork("blast", 9330000);
        super.setUp();
        usdbPool = IInitLendingPool(address(0xc5EaC92633aF47c0023Afa0116500ab86FAB430F));
        wethPool = IInitLendingPool(address(0xD20989EB39348994AA99F686bb4554090d0C09F3));
        blastPool = IInitLendingPool(address(0xdafB6929442303e904A2f673A0E7EB8753Bab571));
        amount = 1e20;
        feeProvider = IFeeProvider(address(0));
        feeRecipient = address(0);
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = InitVault(
            address(
                new TransparentUpgradeableProxy(
                    address(new InitVault(asset, currentPool, IFeeProvider(address(0)), address(0))),
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
        asset = IERC20Metadata(address(0x4300000000000000000000000000000000000003));
        currentPool = usdbPool;
        baseVaultTest(address(0x3Ba925fdeAe6B46d0BB4d424D829982Cb2F7309e), true);
    }

    function test_blast() public fork {
        asset = IERC20Metadata(address(0xb1a5700fA2358173Fe465e6eA4Ff52E36e88E2ad));
        currentPool = blastPool;
        baseVaultTest(address(0xCB4A7EeE965CB1A0f28931a125Ef360d058892DE), true);
    }

    function test_weth() public fork {
        asset = IERC20Metadata(address(0x4300000000000000000000000000000000000004));
        currentPool = wethPool;
        baseVaultTest(address(0x66714DB8F3397c767d0A602458B5b4E3C0FE7dd1), true);
    }
}
