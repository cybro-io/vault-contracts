// // SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {
    BlasterSwapV3Vault, IUniswapV3Factory, INonfungiblePositionManager
} from "../../src/dex/BlasterSwapV3Vault.sol";
import {AbstractDexVaultTest, IVault} from "./AbstractDexVaultTest.t.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

contract BlasterSwapV3VaultTest is AbstractDexVaultTest {
    IUniswapV3Factory factory;
    INonfungiblePositionManager positionManager;
    uint24 fee;

    function setUp() public virtual override(AbstractDexVaultTest) {
        super.setUp();
        fee = 500;
        token0 = IERC20Metadata(address(0x4300000000000000000000000000000000000003));
        token1 = IERC20Metadata(address(0x4300000000000000000000000000000000000004));
        factory = IUniswapV3Factory(address(0x1A8027625C830aAC43aD82a3f7cD6D5fdCE89d78));
        positionManager = INonfungiblePositionManager(payable(address(0x1e60C4113C86231Ef4b5B0b1cbf689F1b30e7966)));
        transferFromToken0 = address(0x3Ba925fdeAe6B46d0BB4d424D829982Cb2F7309e);
        transferFromToken1 = address(0x44f33bC796f7d3df55040cd3C631628B560715C2);
        vm.label(address(token0), "USDB");
        vm.label(address(token1), "WETH");
        amountEth = 1e18;
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = IVault(
            address(
                new TransparentUpgradeableProxy(
                    address(
                        new BlasterSwapV3Vault(
                            payable(address(positionManager)),
                            address(token0),
                            address(token1),
                            fee,
                            asset,
                            feeProvider,
                            feeRecipient
                        )
                    ),
                    admin,
                    abi.encodeCall(BlasterSwapV3Vault.initialize, (admin, admin, name, symbol))
                )
            )
        );
        vm.stopPrank();
    }
}
