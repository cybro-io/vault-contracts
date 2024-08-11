// // SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {AlgebraVault, IAlgebraFactory, IAlgebraPool, INonfungiblePositionManager} from "../src/AlgebraVault.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

/// @notice Contracts for BladeSwap
// Algebra Factory 0xA87DbF5082Af26c9A6Ab2B854E378f704638CCa5
// Algebra NonfungiblePositionManager 0x7553b306773EFa59E6f9676aFE049D2D2AbdfDd6
// Algebra Pool Deployer 0xfFeEcb1fe0EAaEFeE69d122F6B7a0368637cb593
// BLAST token address 0xb1a5700fa2358173fe465e6ea4ff52e36e88e2ad
// USDB/WETH pool 0xdA5AaEb22eD5b8aa76347eC57424CA0d109eFB2A

contract ForkBladeSwapVaultTest is Test {
    AlgebraVault vault;
    IAlgebraFactory factory = IAlgebraFactory(address(0xA87DbF5082Af26c9A6Ab2B854E378f704638CCa5));
    INonfungiblePositionManager positionManager =
        INonfungiblePositionManager(payable(address(0x7553b306773EFa59E6f9676aFE049D2D2AbdfDd6)));
    uint256 amount;
    uint256 forkId;
    address user;
    address user2;

    address internal admin;
    uint256 internal adminPrivateKey;

    /// @notice USDB
    IERC20Metadata token0 = IERC20Metadata(address(0x4300000000000000000000000000000000000003));
    /// @notice WETH
    IERC20Metadata token1 = IERC20Metadata(address(0x4300000000000000000000000000000000000004));

    function setUp() public {
        adminPrivateKey = 0xba132ce;
        admin = vm.addr(adminPrivateKey);
        forkId = vm.createSelectFork("blast");
        user = address(100);
        user2 = address(101);
        amount = 1e20;
    }

    modifier fork() {
        vm.selectFork(forkId);
        _;
    }

    function _initializeNewVault() internal {
        vm.startPrank(admin);
        vault = AlgebraVault(
            address(
                new TransparentUpgradeableProxy(
                    address(new AlgebraVault(address(positionManager), address(token0), address(token1))),
                    admin,
                    abi.encodeCall(AlgebraVault.initialize, (admin, "nameVault", "symbolVault"))
                )
            )
        );
        vm.stopPrank();
    }

    function _deposit(address _user, bool inToken0) internal returns (uint256 shares) {
        vm.startPrank(_user);
        if (inToken0) {
            token0.approve(address(vault), amount);
        } else {
            token1.approve(address(vault), amount);
        }
        shares = vault.deposit(inToken0, amount, _user);
        vm.stopPrank();
    }

    function _redeem(address _owner, address _receiver, bool _inToken0, uint256 _shares)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        vm.startPrank(_receiver);
        (amount0, amount1) = vault.redeem(_inToken0, _shares, _receiver, _owner);
        vm.stopPrank();
    }

    function test_BladeSwap() public fork {
        _initializeNewVault();
        vm.prank(address(0x3Ba925fdeAe6B46d0BB4d424D829982Cb2F7309e));
        token0.transfer(user, amount);
        uint256 sharesUser = _deposit(user, true);
        console.log("shares user", sharesUser);

        vm.prank(address(0x44f33bC796f7d3df55040cd3C631628B560715C2));
        token1.transfer(user2, amount);
        uint256 sharesUser2 = _deposit(user2, false);
        console.log("shares user2", sharesUser2);

        (uint256 amount0, uint256 amount1) = _redeem(user, user, false, sharesUser);
        vm.expectRevert();
        (amount0, amount1) = _redeem(user2, user, true, sharesUser2);
        vm.prank(user2);
        IERC20Metadata(address(vault)).approve(user, sharesUser2);
        (amount0, amount1) = _redeem(user2, user, true, sharesUser2);
    }
}
