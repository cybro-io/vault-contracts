// // SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {YieldStakingVault, IERC20Metadata, IYieldStaking, IFeeProvider} from "../src/vaults/YieldStakingVault.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IShares} from "../src/interfaces/IShares.sol";
import {AbstractBaseVaultTest} from "./AbstractBaseVault.t.sol";

contract ForkYieldStakingTest is AbstractBaseVaultTest {
    IYieldStaking staking;

    function setUp() public override {
        forkId = vm.createSelectFork("blast", lastCachedBlockid_BLAST);
        super.setUp();
        name = "Yield Staking Vault";
        symbol = "YVLT";
        amount = 1e20;
        staking = IYieldStaking(payable(address(0x0E84461a00C661A18e00Cab8888d146FDe10Da8D)));
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = _deployYieldStaking(
            VaultSetup(asset, address(staking), address(feeProvider), feeRecipient, name, symbol, admin, admin)
        );
        vm.stopPrank();
    }

    function _increaseVaultAssets() internal override returns (bool) {
        if (asset == weth_BLAST) {
            vm.deal(address(asset), address(asset).balance * 101 / 100);

            vm.prank(address(0x4300000000000000000000000000000000000000));
            IShares(address(asset)).addValue(0);
        } else {
            vm.startPrank(address(0xB341285d5683C74935ad14c446E137c8c8829549));
            IShares(address(asset)).addValue(IShares(address(asset)).count() * 3);
            vm.stopPrank();
        }
        return true;
    }

    function test_usdb() public {
        asset = usdb_BLAST;
        baseVaultTest(true);
    }

    function test_weth() public {
        asset = weth_BLAST;
        baseVaultTest(true);
    }
}
