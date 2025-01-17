// // SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {YieldStakingVault, IERC20Metadata, IYieldStaking, IFeeProvider} from "../src/vaults/YieldStakingVault.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IShares} from "../src/interfaces/IShares.sol";
import {AbstractBaseVaultTest} from "./AbstractBaseVault.t.sol";

contract ForkYieldStakingTest is AbstractBaseVaultTest {
    IYieldStaking staking;
    IERC20Metadata weth;
    IERC20Metadata usdb;

    function setUp() public override {
        forkId = vm.createSelectFork("blast", 8149175);
        super.setUp();
        name = "Yield Staking Vault";
        symbol = "YVLT";
        weth = IERC20Metadata(address(0x4300000000000000000000000000000000000004));
        usdb = IERC20Metadata(address(0x4300000000000000000000000000000000000003));
        amount = 1e20;
        staking = IYieldStaking(payable(address(0x0E84461a00C661A18e00Cab8888d146FDe10Da8D)));
        feeProvider = IFeeProvider(address(0));
        feeRecipient = address(0);
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = YieldStakingVault(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(new YieldStakingVault(asset, staking, IFeeProvider(address(0)), address(0))),
                        admin,
                        abi.encodeCall(YieldStakingVault.initialize, (admin, name, symbol, admin))
                    )
                )
            )
        );
        vm.stopPrank();
    }

    function _increaseVaultAssets() internal override returns (bool) {
        if (asset == weth) {
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

    function test_usdb() public fork {
        asset = usdb;
        baseVaultTest(address(0x236F233dBf78341d25fB0F1bD14cb2bA4b8a777c), true);
    }

    function test_weth() public fork {
        asset = weth;
        baseVaultTest(address(0x44f33bC796f7d3df55040cd3C631628B560715C2), true);
    }
}
