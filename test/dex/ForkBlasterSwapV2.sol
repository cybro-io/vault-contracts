// // SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {BlasterSwapV2Vault, IBlasterswapV2Router02, IBlasterswapV2Factory} from "../../src/BlasterSwapV2Vault.sol";
import {AbstractDexVaultTest, IDexVault} from "./AbstractDexVaultTest.t.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

contract BlasterSwapV2VaultTest is AbstractDexVaultTest {
    IBlasterswapV2Factory factory;
    IBlasterswapV2Router02 router;

    function setUp() public virtual override {
        super.setUp();
        token0 = IERC20Metadata(address(0x4300000000000000000000000000000000000003));
        token1 = IERC20Metadata(address(0x4300000000000000000000000000000000000004));
        factory = IBlasterswapV2Factory(address(0x9CC1599D4378Ea41d444642D18AA9Be44f709ffD));
        router = IBlasterswapV2Router02(payable(address(0xc972FaE6b524E8A6e0af21875675bF58a3133e60)));
        transferFromToken0 = address(0x3Ba925fdeAe6B46d0BB4d424D829982Cb2F7309e);
        transferFromToken1 = address(0x44f33bC796f7d3df55040cd3C631628B560715C2);
        vm.label(address(token0), "USDB");
        vm.label(address(token1), "WETH");
        amountEth = 1e18;
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = IDexVault(
            address(
                new TransparentUpgradeableProxy(
                    address(new BlasterSwapV2Vault(payable(address(router)), address(token0), address(token1))),
                    admin,
                    abi.encodeCall(BlasterSwapV2Vault.initialize, (admin, "nameVault", "symbolVault"))
                )
            )
        );
        vm.stopPrank();
    }

    function _deposit(address _user, bool inToken0, uint256 _amount)
        internal
        virtual
        override
        returns (uint256 shares)
    {
        vm.startPrank(_user);
        if (inToken0) {
            token0.approve(address(vault), _amount);
        } else {
            token1.approve(address(vault), _amount);
        }
        uint160 currentPrice = vault.getCurrentPrice();
        shares = vault.deposit(inToken0, _amount, _user, currentPrice * 99 / 100, currentPrice * 101 / 100);
        vm.stopPrank();
    }
}
