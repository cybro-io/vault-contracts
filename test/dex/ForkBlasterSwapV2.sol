// // SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {BlasterSwapV2Vault, IBlasterswapV2Router02, IBlasterswapV2Factory} from "../../src/dex/BlasterSwapV2Vault.sol";
import {AbstractDexVaultTest, IVault} from "./AbstractDexVaultTest.t.sol";
import {VaultType} from "../libraries/Swapper.sol";

contract BlasterSwapV2VaultTest is AbstractDexVaultTest {
    IBlasterswapV2Factory factory;
    IBlasterswapV2Router02 router;

    function setUp() public virtual override(AbstractDexVaultTest) {
        super.setUp();
        factory = IBlasterswapV2Factory(address(0x9CC1599D4378Ea41d444642D18AA9Be44f709ffD));
        router = IBlasterswapV2Router02(payable(address(0xc972FaE6b524E8A6e0af21875675bF58a3133e60)));
        amount = 1e18;
        amountEth = 1e16;
        vaultType = VaultType.BlasterV2;
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = IVault(
            address(
                new TransparentUpgradeableProxy(
                    address(
                        new BlasterSwapV2Vault(
                            payable(address(router)),
                            address(token0),
                            address(token1),
                            asset,
                            feeProvider,
                            feeRecipient,
                            address(oracle_USDB_BLAST),
                            address(oracle_ETH_BLAST)
                        )
                    ),
                    admin,
                    abi.encodeCall(BlasterSwapV2Vault.initialize, (admin, admin, name, symbol))
                )
            )
        );
        vm.stopPrank();
    }
}
