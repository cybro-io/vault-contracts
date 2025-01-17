// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {IAavePool} from "../src/interfaces/aave/IPool.sol";
import {AaveVault, IERC20Metadata} from "../src/vaults/AaveVault.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {JuiceVault} from "../src/vaults/JuiceVault.sol";
import {IJuicePool} from "../src/interfaces/juice/IJuicePool.sol";
import {OneClickIndex} from "../src/OneClickIndex.sol";
import {FeeProvider, IFeeProvider} from "../src/FeeProvider.sol";
import {BufferVaultMock} from "../src/mocks/BufferVaultMock.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";

contract OneClickIndexTest is Test {
    IAavePool aavePool;
    IJuicePool usdbJuicePool;
    JuiceVault juiceVault;
    AaveVault aaveVault;
    BufferVaultMock bufferVault;
    IERC20Metadata usdb = IERC20Metadata(address(0x4300000000000000000000000000000000000003));
    uint256 amount;
    uint256 amount2;
    uint256 forkId;
    address user;
    address user2;

    OneClickIndex lending;
    uint256 lendingShare;
    uint256 lendingShare2;
    uint8 precision;

    address feeRecipient;
    IFeeProvider feeProvider;

    address internal admin;
    uint256 internal adminPrivateKey;

    uint32 depositFee;
    uint32 withdrawalFee;
    uint32 performanceFee;
    uint32 administrationFee;
    uint32 feePrecision;

    function setUp() public {
        adminPrivateKey = 0xba132ce;
        admin = vm.addr(adminPrivateKey);
        forkId = vm.createSelectFork("blast", 8149175);
        aavePool = IAavePool(address(0xd2499b3c8611E36ca89A70Fda2A72C49eE19eAa8));
        usdbJuicePool = IJuicePool(address(0x4A1d9220e11a47d8Ab22Ccd82DA616740CF0920a));
        amount = 1e20;
        amount2 = 2e21;
        precision = 20;
        lendingShare = 25 * 10 ** (precision - 2);
        lendingShare2 = 50 * 10 ** (precision - 2);
        user = address(100);
        user2 = address(101);
        feeRecipient = address(102);
        depositFee = 100;
        withdrawalFee = 200;
        performanceFee = 300;
        administrationFee = 100;
        feePrecision = 1e5;
        vm.startPrank(admin);
        feeProvider = FeeProvider(
            address(
                new TransparentUpgradeableProxy(
                    address(new FeeProvider(feePrecision)),
                    admin,
                    abi.encodeCall(
                        FeeProvider.initialize, (admin, depositFee, withdrawalFee, performanceFee, administrationFee)
                    )
                )
            )
        );
        lending = OneClickIndex(
            address(
                new TransparentUpgradeableProxy(
                    address(new OneClickIndex(usdb, feeProvider, feeRecipient)),
                    admin,
                    abi.encodeCall(OneClickIndex.initialize, (admin, "nameVault", "symbolVault", admin, admin))
                )
            )
        );
        vm.stopPrank();
    }

    modifier fork() {
        vm.selectFork(forkId);
        _;
    }

    function _initializeUSDBVaults() internal {
        aaveVault = AaveVault(
            address(
                new TransparentUpgradeableProxy(
                    address(new AaveVault(usdb, aavePool, IFeeProvider(address(0)), address(0))),
                    admin,
                    abi.encodeCall(AaveVault.initialize, (admin, "nameVault", "symbolVault", admin))
                )
            )
        );

        juiceVault = JuiceVault(
            address(
                new TransparentUpgradeableProxy(
                    address(new JuiceVault(usdb, usdbJuicePool, IFeeProvider(address(0)), address(0))),
                    admin,
                    abi.encodeCall(JuiceVault.initialize, (admin, "nameVault", "symbolVault", admin))
                )
            )
        );
        vm.startPrank(admin);
        address[] memory vaults = new address[](2);
        vaults[0] = address(aaveVault);
        vaults[1] = address(juiceVault);
        uint256[] memory lendingShares = new uint256[](2);
        lendingShares[0] = lendingShare;
        lendingShares[1] = lendingShare2;
        lending.addLendingPools(vaults);
        lending.setLendingShares(vaults, lendingShares);
        vm.stopPrank();
    }

    function _ininitializeBufferVault() internal {
        vm.startPrank(admin);
        bufferVault = BufferVaultMock(
            address(
                new TransparentUpgradeableProxy(
                    address(new BufferVaultMock(usdb, IFeeProvider(address(0)), address(0))),
                    admin,
                    abi.encodeCall(BufferVaultMock.initialize_mock, (admin, "nameVault", "symbolVault", admin))
                )
            )
        );
        address[] memory vaults = new address[](1);
        vaults[0] = address(bufferVault);
        uint256[] memory lendingShares = new uint256[](1);
        lendingShares[0] = lendingShare;
        lending.addLendingPools(vaults);
        lending.setLendingShares(vaults, lendingShares);
        vm.stopPrank();
    }

    function test_getters() public {
        _initializeUSDBVaults();
        uint256 amountWithDepositFee = amount * (feePrecision - depositFee) / feePrecision;
        uint256 amount2WithDepositFee = amount2 * (feePrecision - depositFee) / feePrecision;
        vm.assertEq(lending.getLendingPoolCount(), 2);
        vm.assertEq(lending.totalLendingShares(), lendingShare + lendingShare2);

        vm.startPrank(address(0x236F233dBf78341d25fB0F1bD14cb2bA4b8a777c));
        usdb.transfer(user, amount);
        usdb.transfer(user2, amount2);
        vm.stopPrank();

        vm.startPrank(user);
        usdb.approve(address(lending), amount);
        uint256 userShares = lending.deposit(amount, user, 0);
        console.log("user shares", userShares);
        vm.stopPrank();

        // test pause

        vm.prank(admin);
        lending.pause();

        vm.startPrank(user2);
        usdb.approve(address(lending), amount2);
        vm.expectRevert();
        lending.deposit(amount2, user2, 0);
        vm.stopPrank();

        vm.prank(admin);
        lending.unpause();

        vm.startPrank(user2);
        uint256 user2Shares = lending.deposit(amount2, user2, 0);
        console.log("user2 shares", user2Shares);
        vm.stopPrank();

        vm.assertApproxEqAbs(lending.totalAssets(), amountWithDepositFee + amount2WithDepositFee, 1e10);
        vm.assertEq(lending.getDepositFee(user), depositFee);
        vm.assertEq(lending.getWithdrawalFee(user), withdrawalFee);
        vm.assertEq(lending.getPerformanceFee(user), performanceFee);
        vm.assertEq(lending.feePrecision(), feePrecision);
        vm.assertApproxEqAbs(
            lending.getBalanceOfPool(address(aaveVault)),
            (amountWithDepositFee + amount2WithDepositFee) * lendingShare / (lendingShare + lendingShare2),
            1e5
        );
        vm.assertApproxEqAbs(
            lending.getBalanceOfPool(address(juiceVault)),
            (amountWithDepositFee + amount2WithDepositFee) * lendingShare2 / (lendingShare + lendingShare2),
            1e5
        );
        vm.assertApproxEqAbs(lending.getBalanceInUnderlying(user), amountWithDepositFee, 1e5);
        vm.assertEq(lending.getSharePriceOfPool(address(aaveVault)), aaveVault.sharePrice());
        vm.assertEq(lending.getSharePriceOfPool(address(juiceVault)), juiceVault.sharePrice());
        vm.assertApproxEqAbs(lending.getWaterline(user), amountWithDepositFee, 1e5);
        vm.assertApproxEqAbs(lending.getWaterline(user2), amount2WithDepositFee, 1e5);
        vm.assertApproxEqAbs(lending.quoteWithdrawalFee(user), amountWithDepositFee * withdrawalFee / feePrecision, 1e5);
    }

    function test() public {
        _initializeUSDBVaults();
        uint256 amountWithDepositFee = amount * (feePrecision - depositFee) / feePrecision;
        uint256 amountWithWithdrawalFee = (amountWithDepositFee / 2) * (feePrecision - withdrawalFee) / feePrecision;
        uint256 amount2WithDepositFee = amount2 * (feePrecision - depositFee) / feePrecision;
        uint256 amount2WithWithdrawalFee = (amount2WithDepositFee / 2) * (feePrecision - withdrawalFee) / feePrecision;

        vm.startPrank(address(0x236F233dBf78341d25fB0F1bD14cb2bA4b8a777c));
        usdb.transfer(user, amount);
        usdb.transfer(user2, amount2);
        vm.stopPrank();

        vm.startPrank(user);
        usdb.approve(address(lending), amount);
        uint256 userShares = lending.deposit(amount, user, 0);
        console.log("user shares", userShares);
        vm.stopPrank();

        vm.startPrank(user2);
        usdb.approve(address(lending), amount2);
        uint256 user2Shares = lending.deposit(amount2, user2, 0);
        console.log("user2 shares", user2Shares);
        vm.stopPrank();

        // update lending share
        vm.startPrank(admin);
        address[] memory vaults = new address[](1);
        vaults[0] = address(aaveVault);
        uint256[] memory lendingShares = new uint256[](1);
        lendingShares[0] = lendingShare2;
        lending.setLendingShares(vaults, lendingShares);
        lending.rebalance(address(juiceVault), address(aaveVault), juiceVault.balanceOf(address(lending)) / 4 - 1000);
        vm.assertApproxEqAbs(
            juiceVault.balanceOf(address(lending)),
            aaveVault.balanceOf(address(lending)),
            amountWithDepositFee * 2 / 1e10
        );

        vaults[0] = address(aaveVault);
        lendingShares[0] = lendingShare;
        lending.setLendingShares(vaults, lendingShares);
        lending.rebalanceAuto();
        vm.assertApproxEqAbs(
            juiceVault.balanceOf(address(lending)),
            aaveVault.balanceOf(address(lending)) * 2,
            amountWithDepositFee * 2 / 1e10
        );
        vm.stopPrank();
        // redeem
        vm.startPrank(user);
        lending.redeem(userShares / 2, user, user, 0);
        vm.assertApproxEqAbs(usdb.balanceOf(user), amountWithWithdrawalFee, amountWithWithdrawalFee / 1e5);
        vm.stopPrank();
        vm.startPrank(user2);
        lending.redeem(user2Shares / 2, user2, user2, 0);
        vm.assertApproxEqAbs(usdb.balanceOf(user2), amount2WithWithdrawalFee, amount2WithWithdrawalFee / 1e5);
        vm.stopPrank();
        vm.assertGt(usdb.balanceOf(feeRecipient), 0);
    }

    function test_buffer() public {
        _initializeUSDBVaults();
        _ininitializeBufferVault();

        vm.startPrank(address(0x236F233dBf78341d25fB0F1bD14cb2bA4b8a777c));
        usdb.transfer(user, amount);
        usdb.transfer(user2, amount2);
        usdb.transfer(admin, amount2);
        vm.stopPrank();

        vm.startPrank(user);
        usdb.approve(address(lending), amount);
        uint256 userShares = lending.deposit(amount, user, 0);
        console.log("user shares", userShares);
        vm.stopPrank();

        vm.startPrank(user2);
        usdb.approve(address(lending), amount2);
        uint256 user2Shares = lending.deposit(amount2, user2, 0);
        console.log("user2 shares", user2Shares);
        vm.stopPrank();

        uint256 balanceBefore = lending.getBalanceOfPool(address(bufferVault));
        uint256 userBalanceBefore = lending.getBalanceInUnderlying(user);

        vm.startPrank(admin);
        bufferVault.reduceAssets(lending.getBalanceOfPool(address(bufferVault)) / 2);
        vm.stopPrank();

        vm.assertGt(balanceBefore, lending.getBalanceOfPool(address(bufferVault)));
        vm.assertEq(lending.getProfit(user), 0);
        vm.assertGt(userBalanceBefore, lending.getBalanceInUnderlying(user));

        vm.startPrank(admin);
        usdb.transfer(address(bufferVault), usdb.balanceOf(admin));
        uint256 depositedBalanceBefore = lending.getWaterline(user);
        uint256 depositedBalance2Before = lending.getWaterline(user2);
        address[] memory users = new address[](2);
        users[0] = user;
        users[1] = user2;
        lending.collectPerformanceFee(users);
        vm.assertGt(lending.getWaterline(user), depositedBalanceBefore);
        vm.assertGt(lending.getWaterline(user2), depositedBalance2Before);
        vm.stopPrank();
    }
}
