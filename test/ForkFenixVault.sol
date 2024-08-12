// // SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {AlgebraVault, IAlgebraFactory, IAlgebraPool, INonfungiblePositionManager} from "../src/AlgebraVault.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

/// @notice Contracts for BladeSwap
// Algebra Factory 0x7a44CD060afC1B6F4c80A2B9b37f4473E74E25Df
// Algebra NonfungiblePositionManager 0x8881b3Fb762d1D50e6172f621F107E24299AA1Cd

contract ForkFenixVaultTest is Test {
    AlgebraVault vault;
    IAlgebraFactory factory = IAlgebraFactory(address(0x7a44CD060afC1B6F4c80A2B9b37f4473E74E25Df));
    INonfungiblePositionManager positionManager =
        INonfungiblePositionManager(payable(address(0x8881b3Fb762d1D50e6172f621F107E24299AA1Cd)));
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
                    address(new AlgebraVault(payable(address(positionManager)), address(token0), address(token1))),
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

    function test_FenixFinance() public fork {
        _initializeNewVault();
        vm.prank(address(0x3Ba925fdeAe6B46d0BB4d424D829982Cb2F7309e));
        token0.transfer(user, amount);
        uint256 sharesUser = _deposit(user, true);
        console.log("shares user", sharesUser);

        vm.prank(address(0x44f33bC796f7d3df55040cd3C631628B560715C2));
        token1.transfer(user2, amount);
        uint256 sharesUser2 = _deposit(user2, false);
        console.log("shares user 2", sharesUser2);

        (uint256 amount0, uint256 amount1) = _redeem(user, user, true, sharesUser);
        vm.assertEq(amount1, 0);
        vm.assertApproxEqAbs(token0.balanceOf(user), amount, 1e19);

        vm.expectRevert();
        _redeem(user2, user, true, sharesUser2);

        vm.prank(user2);
        IERC20Metadata(address(vault)).approve(user, sharesUser2);
        (amount0, amount1) = _redeem(user2, user, false, sharesUser2);
        vm.assertEq(amount0, 0);
        vm.startPrank(user);
        token1.transfer(user2, token1.balanceOf(user));
        vm.assertApproxEqAbs(token1.balanceOf(user2), amount, 1e19);
        vm.stopPrank();
    }
}
