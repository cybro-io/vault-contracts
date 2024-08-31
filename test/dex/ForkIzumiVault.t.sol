// // SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IzumiVault, IiZiSwapFactory, ILiquidityManager} from "../../src/IzumiVault.sol";
import {AbstractDexVaultTest, IDexVault} from "./AbstractDexVaultTest.t.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

contract IzumiVaultTest is AbstractDexVaultTest {
    IiZiSwapFactory factory;
    ILiquidityManager positionManager;
    uint24 fee;

    function setUp() public virtual override {
        super.setUp();
        fee = 3000;
        token0 = IERC20Metadata(address(0x4300000000000000000000000000000000000003));
        token1 = IERC20Metadata(address(0x4300000000000000000000000000000000000004));
        factory = IiZiSwapFactory(address(0x5162f29E9626CF7186ec40ab97D92230B428ff2d));
        positionManager = ILiquidityManager(payable(address(0x5e7902aDf0Ea0ff827683Cc1d431F740CAD0731b)));
        transferFromToken0 = address(0x3Ba925fdeAe6B46d0BB4d424D829982Cb2F7309e);
        transferFromToken1 = address(0x44f33bC796f7d3df55040cd3C631628B560715C2);
        vm.label(address(token0), "USDB");
        vm.label(address(token1), "WETH");
        amount = 1e16;
        amountEth = 1e15;
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = IDexVault(
            address(
                new TransparentUpgradeableProxy(
                    address(new IzumiVault(payable(address(positionManager)), address(token0), address(token1), fee)),
                    admin,
                    abi.encodeCall(IzumiVault.initialize, (admin, "nameVault", "symbolVault"))
                )
            )
        );
        vm.stopPrank();
    }
}
