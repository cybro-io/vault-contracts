// // SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {IDexVault} from "../../src/interfaces/IDexVault.sol";
import {IFeeProvider} from "../../src/interfaces/IFeeProvider.sol";
import {FeeProvider} from "../../src/FeeProvider.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

abstract contract AbstractDexVaultTest is Test {
    IDexVault vault;
    uint256 amount;
    uint256 amountEth;
    uint256 forkId;
    address user;
    address user2;

    address admin;
    uint256 adminPrivateKey;

    IERC20Metadata token0;
    IERC20Metadata token1;

    address transferFromToken0;
    address transferFromToken1;

    uint8 precision;
    address feeRecipient;
    IFeeProvider feeProvider;

    uint32 depositFee;
    uint32 withdrawalFee;
    uint32 performanceFee;
    uint32 feePrecision;

    bool zeroOrOne;

    function setUp() public virtual {
        adminPrivateKey = 0xba132ce;
        admin = vm.addr(adminPrivateKey);
        forkId = vm.createSelectFork("blast", 8245770);
        user = address(100);
        user2 = address(101);
        amount = 3e21;
        amountEth = 5e18;
        feeRecipient = address(102);
        depositFee = 100;
        withdrawalFee = 200;
        performanceFee = 300;
        feePrecision = 1e5;
        vm.startPrank(admin);
        feeProvider = FeeProvider(
            address(
                new TransparentUpgradeableProxy(
                    address(new FeeProvider(feePrecision)),
                    admin,
                    abi.encodeCall(FeeProvider.initialize, (admin, depositFee, withdrawalFee, performanceFee))
                )
            )
        );
        vm.stopPrank();
    }

    modifier fork() {
        vm.selectFork(forkId);
        _;
    }

    function _initializeNewVault(bool _zeroOrOne) internal virtual;

    function _deposit(address _user, bool inToken0, uint256 _amount) internal virtual returns (uint256 shares) {
        vm.startPrank(_user);
        if (inToken0) {
            token0.approve(address(vault), _amount);
        } else {
            token1.approve(address(vault), _amount);
        }
        shares = vault.deposit(_amount, _user, 0);
        vm.stopPrank();
    }

    function _redeem(address _owner, address _receiver, uint256 _shares) internal virtual returns (uint256 assets) {
        vm.startPrank(_receiver);
        assets = vault.redeem(_shares, _receiver, _owner, 0);
        vm.stopPrank();
    }

    function test_vault() public fork {
        _initializeNewVault(true);
        vm.startPrank(address(transferFromToken0));
        token0.transfer(user, amount);
        token0.transfer(user2, amount);
        vm.stopPrank();
        uint256 sharesUser = _deposit(user, true, amount);
        console.log("shares user", sharesUser);

        uint256 sharesUser2 = _deposit(user2, true, amount);
        console.log("shares user2", sharesUser2);

        uint256 assets = _redeem(user, user, sharesUser);
        vm.assertApproxEqAbs(token0.balanceOf(user), amount, amount / 70);

        vm.expectRevert();
        _redeem(user2, user, sharesUser2);

        vm.prank(user2);
        IERC20Metadata(address(vault)).approve(user, sharesUser2);
        assets = _redeem(user2, user, sharesUser2);
        vm.assertApproxEqAbs(token0.balanceOf(user), 2 * amount, amount / 70);
    }

    function test_vault2() public fork {
        _initializeNewVault(false);
        vm.startPrank(address(transferFromToken1));
        token1.transfer(user, amountEth);
        token1.transfer(user2, amountEth);
        vm.stopPrank();
        uint256 sharesUser = _deposit(user, false, amountEth);
        console.log("shares user", sharesUser);

        uint256 sharesUser2 = _deposit(user2, false, amountEth);
        console.log("shares user2", sharesUser2);

        uint256 assets = _redeem(user, user, sharesUser);
        vm.assertApproxEqAbs(token1.balanceOf(user), amountEth, amountEth / 80);

        vm.expectRevert();
        _redeem(user2, user, sharesUser2);

        vm.prank(user2);
        IERC20Metadata(address(vault)).approve(user, sharesUser2);
        assets = _redeem(user2, user, sharesUser2);
        vm.startPrank(user);
        token1.transfer(user2, token1.balanceOf(user));
        vm.assertApproxEqAbs(token1.balanceOf(user2), 2 * amountEth, amountEth / 80);
        vm.stopPrank();
    }
}
