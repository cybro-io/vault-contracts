// // SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {JuiceVault, IERC20Metadata, IFeeProvider} from "../src/vaults/JuiceVault.sol";
import {IJuicePool} from "../src/interfaces/juice/IJuicePool.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {AbstractBaseVaultTest} from "./AbstractBaseVault.t.sol";

// 0x4A1d9220e11a47d8Ab22Ccd82DA616740CF0920a Juice usdb lending pool
// 0x44f33bC796f7d3df55040cd3C631628B560715C2 Juice weth lending pool

contract JuiceVaultTest is AbstractBaseVaultTest {
    address usdbPool;
    address wethPool;
    address currentPool;

    function setUp() public override {
        forkId = vm.createSelectFork("blast", lastCachedBlockid_BLAST);
        super.setUp();
        usdbPool = address(juice_usdbPool_BLAST);
        wethPool = address(juice_wethPool_BLAST);
        amount = 1e20;
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault =
            _deployJuice(VaultSetup(asset, currentPool, address(feeProvider), feeRecipient, name, symbol, admin, admin));
        vm.stopPrank();
    }

    function _increaseVaultAssets() internal pure override returns (bool) {
        return false;
    }

    function test_usdb() public fork {
        asset = usdb_BLAST;
        currentPool = usdbPool;
        baseVaultTest(true);
    }

    function test_weth_deposit() public fork {
        asset = weth_BLAST;
        currentPool = wethPool;
        baseVaultTest(true);
    }
}
