// // SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {
    BlasterSwapV3Vault, IUniswapV3Factory, INonfungiblePositionManager
} from "../../src/dex/BlasterSwapV3Vault.sol";
import {AbstractDexVaultTest, IVault} from "./AbstractDexVaultTest.t.sol";

contract BlasterSwapV3VaultTest is AbstractDexVaultTest {
    IUniswapV3Factory factory;
    INonfungiblePositionManager positionManager;
    uint24 fee;

    function setUp() public virtual override(AbstractDexVaultTest) {
        super.setUp();
        fee = 500;
        factory = IUniswapV3Factory(address(0x1A8027625C830aAC43aD82a3f7cD6D5fdCE89d78));
        positionManager = INonfungiblePositionManager(payable(address(0x1e60C4113C86231Ef4b5B0b1cbf689F1b30e7966)));
        amountEth = 1e17;
        amount = 5e20;
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
                            feeRecipient,
                            address(_getMockOracleForToken(address(token0))),
                            address(_getMockOracleForToken(address(token1)))
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
