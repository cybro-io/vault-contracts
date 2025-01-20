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
    IJuicePool usdbPool;
    IJuicePool wethPool;
    IJuicePool currentPool;

    function setUp() public override {
        forkId = vm.createSelectFork("blast", lastCachedBlockid_BLAST);
        super.setUp();
        usdbPool = IJuicePool(address(0x4A1d9220e11a47d8Ab22Ccd82DA616740CF0920a));
        wethPool = IJuicePool(address(0x44f33bC796f7d3df55040cd3C631628B560715C2));
        amount = 1e20;
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = JuiceVault(
            address(
                new TransparentUpgradeableProxy(
                    address(new JuiceVault(asset, currentPool, IFeeProvider(feeProvider), feeRecipient)),
                    admin,
                    abi.encodeCall(JuiceVault.initialize, (admin, "nameVault", "symbolVault", admin))
                )
            )
        );
        vm.stopPrank();
    }

    function _increaseVaultAssets() internal pure override returns (bool) {
        return false;
    }

    function test_usdb() public fork {
        asset = usdbBlast;
        currentPool = usdbPool;
        baseVaultTest(true);
    }

    function test_weth_deposit() public fork {
        asset = wethBlast;
        currentPool = wethPool;
        baseVaultTest(true);
    }
}
