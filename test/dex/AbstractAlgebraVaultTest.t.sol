// // SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {AlgebraVault, IAlgebraFactory, INonfungiblePositionManager} from "../../src/AlgebraVault.sol";
import {AbstractDexVaultTest} from "./AbstractDexVaultTest.t.sol";

abstract contract AbstractAlgebraVaultTest is AbstractDexVaultTest {
    AlgebraVault vault;
    IAlgebraFactory factory;
    INonfungiblePositionManager positionManager;

    function setUp() public virtual override {
        super.setUp();
    }

    function _vault() internal view override returns (address) {
        return address(vault);
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = AlgebraVault(
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

    function _deposit(address _user, bool inToken0) internal override returns (uint256 shares) {
        vm.startPrank(_user);
        if (inToken0) {
            token0.approve(address(vault), amount);
        } else {
            token1.approve(address(vault), amount);
        }
        uint160 sqrtPriceX96 = vault.getCurrentSqrtPrice();
        shares = vault.deposit(inToken0, amount, _user, sqrtPriceX96 * 99 / 100, sqrtPriceX96 * 101 / 100);
        vm.stopPrank();
    }

    function _redeem(address _owner, address _receiver, bool _inToken0, uint256 _shares)
        internal
        override
        returns (uint256 assets)
    {
        vm.startPrank(_receiver);
        assets = vault.redeem(_inToken0, _shares, _receiver, _owner, 0);
        vm.stopPrank();
    }
}
