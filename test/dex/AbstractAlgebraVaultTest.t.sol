// // SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {AlgebraVault, IAlgebraFactory, INonfungiblePositionManager} from "../../src/dex/AlgebraVault.sol";
import {AbstractDexVaultTest, IVault} from "./AbstractDexVaultTest.t.sol";
import {VaultType} from "../libraries/Swapper.sol";

abstract contract AbstractAlgebraVaultTest is AbstractDexVaultTest {
    IAlgebraFactory factory;
    INonfungiblePositionManager positionManager;

    function setUp() public virtual override(AbstractDexVaultTest) {
        super.setUp();
        vaultType = VaultType.AlgebraV1;
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = IVault(
            address(
                new TransparentUpgradeableProxy(
                    address(
                        new AlgebraVault(
                            payable(address(positionManager)),
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
                    abi.encodeCall(AlgebraVault.initialize, (admin, admin, name, symbol))
                )
            )
        );
        vm.stopPrank();
    }
}
