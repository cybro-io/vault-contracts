// // SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console, console2} from "forge-std/Test.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IFeeProvider} from "../../src/interfaces/IFeeProvider.sol";
import {FeeProvider} from "../../src/FeeProvider.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {BaseVault} from "../../src/BaseVault.sol";
import {BaseDexUniformVault} from "../../src/dex/BaseDexUniformVault.sol";

abstract contract AbstractDexVaultTest is Test {
    IVault vault;
    uint256 amount;
    uint256 amountEth;
    uint256 forkId;
    address user;
    address user2;
    address userForFeeTests;

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
        userForFeeTests = address(1011);
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
        address vaultAddress = vm.computeCreateAddress(admin, vm.getNonce(admin) + 1);
        address[] memory whitelistedContracts = new address[](1);
        whitelistedContracts[0] = vaultAddress;
        bool[] memory isWhitelisted = new bool[](1);
        isWhitelisted[0] = true;
        feeProvider.setWhitelistedContracts(whitelistedContracts, isWhitelisted);
        vm.stopPrank();
    }

    modifier fork() {
        vm.selectFork(forkId);
        _;
    }

    function _initializeNewVault(IERC20Metadata _asset) internal virtual;

    function _deposit(address _user, bool inToken0, uint256 _amount) internal virtual returns (uint256 shares) {
        vm.startPrank(_user);
        if (inToken0) {
            token0.approve(address(vault), _amount);
        } else {
            token1.approve(address(vault), _amount);
        }
        vm.expectEmit(true, true, false, false, address(vault));
        emit BaseVault.Deposit(_user, _user, 0, 0, 0, 0, 0);
        shares = vault.deposit(_amount, _user, 0);
        vm.stopPrank();

        vm.startPrank(admin);
        feeProvider.setFees(depositFee * 2, withdrawalFee * 2, performanceFee * 2);
        vm.assertEq(vault.getDepositFee(_user), depositFee);
        vm.assertEq(vault.getWithdrawalFee(_user), withdrawalFee);
        vm.assertEq(vault.getPerformanceFee(_user), performanceFee);
        vm.assertEq(vault.getDepositFee(userForFeeTests), depositFee * 2);
        vm.assertEq(vault.getWithdrawalFee(userForFeeTests), withdrawalFee * 2);
        vm.assertEq(vault.getPerformanceFee(userForFeeTests), performanceFee * 2);
        feeProvider.setFees(depositFee, withdrawalFee, performanceFee);
        vm.stopPrank();

        (uint256 checkAmount0, uint256 checkAmount1) = BaseDexUniformVault(address(vault)).getPositionAmounts();
        vm.assertGt(checkAmount0, 0);
        vm.assertGt(checkAmount1, 0);
    }

    function _redeem(address _owner, address _receiver, uint256 _shares) internal virtual returns (uint256 assets) {
        vm.startPrank(_receiver);
        uint256 withdrawalFee_ = vault.quoteWithdrawalFee(_owner);
        vm.assertGt(withdrawalFee_, 0);
        vm.expectEmit(true, true, true, false, address(vault));
        emit BaseVault.Withdraw(_receiver, _receiver, _owner, _shares, 0, 0, 0, 0);
        assets = vault.redeem(_shares, _receiver, _owner, 0);
        vm.stopPrank();
    }

    function test_vault() public fork {
        _initializeNewVault(token0);
        vm.assertGt(vault.underlyingTVL(), 10 ** token0.decimals());
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

        vm.startPrank(user);
        vm.expectRevert();
        vault.redeem(sharesUser2, user, user2, 0);
        vm.stopPrank();

        vm.prank(user2);
        IERC20Metadata(address(vault)).approve(user, sharesUser2);
        assets = _redeem(user2, user, sharesUser2);
        vm.assertApproxEqAbs(token0.balanceOf(user), 2 * amount, amount / 70);
    }

    function test_vault2() public fork {
        _initializeNewVault(token1);
        vm.assertGt(vault.underlyingTVL(), 10 ** token1.decimals());
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

        vm.startPrank(user);
        vm.expectRevert();
        vault.redeem(sharesUser2, user, user2, 0);
        vm.stopPrank();

        vm.prank(user2);
        IERC20Metadata(address(vault)).approve(user, sharesUser2);
        assets = _redeem(user2, user, sharesUser2);
        vm.startPrank(user);
        token1.transfer(user2, token1.balanceOf(user));
        vm.assertApproxEqAbs(token1.balanceOf(user2), 2 * amountEth, amountEth / 80);
        vm.stopPrank();
    }
}
