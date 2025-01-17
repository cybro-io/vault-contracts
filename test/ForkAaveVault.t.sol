// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {IAavePool} from "../src/interfaces/aave/IPool.sol";
import {AaveVault, IERC20Metadata, IFeeProvider} from "../src/vaults/AaveVault.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
    TransparentUpgradeableProxy,
    ProxyAdmin
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {BaseVault} from "../src/BaseVault.sol";
import {AbstractBaseVaultTest, IVault} from "./AbstractBaseVault.t.sol";

contract AaveVaultTest is AbstractBaseVaultTest {
    IAavePool aavePool;

    function setUp() public override {
        forkId = vm.createSelectFork("blast", 8149175);
        amount = 1e20;
        super.setUp();
        aavePool = IAavePool(address(0xd2499b3c8611E36ca89A70Fda2A72C49eE19eAa8));
        feeProvider = IFeeProvider(address(0));
        feeRecipient = address(0);
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = IVault(
            address(
                new TransparentUpgradeableProxy(
                    address(new AaveVault(asset, aavePool, IFeeProvider(address(0)), address(0))),
                    admin,
                    abi.encodeCall(AaveVault.initialize, (admin, "nameVault", "symbolVault", admin))
                )
            )
        );
        vm.stopPrank();
    }

    function _increaseVaultAssets() internal pure override returns (bool) {
        return false;
    }

    function test_usdb() public {
        asset = IERC20Metadata(address(0x4300000000000000000000000000000000000003));
        baseVaultTest(address(0x3Ba925fdeAe6B46d0BB4d424D829982Cb2F7309e), true);
    }

    function test_weth_deposit() public {
        asset = IERC20Metadata(address(0x4300000000000000000000000000000000000004));
        baseVaultTest(address(0x44f33bC796f7d3df55040cd3C631628B560715C2), true);
    }

    function test_otherTokens_deposit() public {
        asset = IERC20Metadata(address(0x66714DB8F3397c767d0A602458B5b4E3C0FE7dd1));
        deal(address(asset), user, amount);
        deal(address(asset), user2, amount);
        deal(address(asset), admin, amount);
        baseVaultTest(address(0), false);
    }
}
