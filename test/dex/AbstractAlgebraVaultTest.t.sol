// // SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {AlgebraVault, IAlgebraFactory, INonfungiblePositionManager} from "../../src/AlgebraVault.sol";
import {AbstractDexVaultTest, IDexVault} from "./AbstractDexVaultTest.t.sol";

abstract contract AbstractAlgebraVaultTest is AbstractDexVaultTest {
    IAlgebraFactory factory;
    INonfungiblePositionManager positionManager;

    function setUp() public virtual override {
        super.setUp();
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = IDexVault(
            address(
                new TransparentUpgradeableProxy(
                    address(new AlgebraVault(payable(address(positionManager)), address(token0), address(token1))),
                    admin,
                    abi.encodeCall(AlgebraVault.initialize, (admin, "nameVault", "symbolVault"))
                )
            )
        );
        vm.stopPrank();
    }
}
