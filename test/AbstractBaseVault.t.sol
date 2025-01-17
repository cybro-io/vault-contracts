// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {
    TransparentUpgradeableProxy,
    ProxyAdmin
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {BaseVault} from "../src/BaseVault.sol";
import {FeeProvider, IFeeProvider} from "../src/FeeProvider.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IVault} from "../src/interfaces/IVault.sol";

abstract contract AbstractBaseVaultTest is Test {
    uint256 forkId;
    IVault vault;
    IERC20Metadata asset;
    address user;
    address user2;
    address user5;

    address feeRecipient;
    IFeeProvider feeProvider;

    address internal admin;
    uint256 internal adminPrivateKey;

    uint32 depositFee;
    uint32 withdrawalFee;
    uint32 performanceFee;
    uint32 administrationFee;
    uint32 feePrecision;

    address vaultAddress;

    uint256 amount;
    string name;
    string symbol;

    function setUp() public virtual {
        adminPrivateKey = 0xba132ce;
        admin = vm.addr(adminPrivateKey);
        user = address(100);
        user2 = address(101);
        user5 = address(1001001);
        feeRecipient = address(102);
        depositFee = 100;
        withdrawalFee = 200;
        performanceFee = 300;
        administrationFee = 100;
        feePrecision = 1e5;
        name = "nameVault";
        symbol = "symbolVault";
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
        vaultAddress = vm.computeCreateAddress(admin, vm.getNonce(admin) + 1);
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

    function _initializeNewVault() internal virtual;

    function _increaseVaultAssets() internal virtual returns (bool);

    function _provideAndApprove(address assetProvider, bool needToProvide) internal {
        if (needToProvide) {
            vm.startPrank(assetProvider);
            asset.transfer(user, amount);
            asset.transfer(user2, amount);
            asset.transfer(admin, amount);
            vm.stopPrank();
        }
        vm.startPrank(user);
        asset.approve(vaultAddress, amount);
        vm.stopPrank();
        vm.startPrank(user2);
        asset.approve(vaultAddress, amount);
        vm.stopPrank();
        vm.startPrank(admin);
        asset.approve(vaultAddress, amount);
        vm.stopPrank();
    }

    function _checkGetters() internal view {
        vm.assertEq(address(vault.asset()), address(asset));
        vm.assertEq(address(vault.feeProvider()), address(feeProvider));
        vm.assertEq(vault.feeRecipient(), feeRecipient);
        vm.assertEq(vault.name(), name);
        vm.assertEq(vault.symbol(), symbol);
        vm.assertGt(vault.underlyingTVL(), 0);
        if (feeProvider != IFeeProvider(address(0))) {
            vm.assertEq(vault.getDepositFee(user), depositFee);
            vm.assertEq(vault.getWithdrawalFee(user), withdrawalFee);
            vm.assertEq(vault.getPerformanceFee(user), performanceFee);
            vm.assertEq(vault.getAdministrationFee(), administrationFee);
            vm.assertEq(vault.feePrecision(), feePrecision);
        }
    }

    function _checkPause() internal {
        vm.prank(admin);
        vault.pause();
        vm.startPrank(user);
        vm.expectRevert();
        vault.deposit(amount, user, 0);
        vm.stopPrank();
        vm.prank(admin);
        vault.unpause();
    }

    function _deposit(address _user, uint256 amount_) internal returns (uint256 shares) {
        uint256 amountWithFee = amount_;
        if (feeProvider != IFeeProvider(address(0))) {
            uint32 depositFee_ = vault.getDepositFee(_user);
            amountWithFee = amountWithFee * (feePrecision - depositFee_) / feePrecision;
        }
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 tvlBefore = vault.totalAssets();

        vm.startPrank(_user);
        shares = vault.deposit(amount_, _user, 0);
        vm.stopPrank();

        (bool success, bytes memory returnData) =
            address(vault).call(abi.encodeWithSelector(bytes4(keccak256("assetWethPool()"))));
        if (success) {
            address check = abi.decode(returnData, (address));
            if (check == address(0)) {
                amountWithFee = uint64(amountWithFee / 10 ** 12) * 10 ** 12;
            }
        }

        vm.assertApproxEqAbs(vault.getWaterline(_user), amountWithFee, amount / 100);
        vm.assertApproxEqAbs(vault.getBalanceInUnderlying(_user), amountWithFee, amount / 100);
        vm.assertApproxEqAbs(vault.getProfit(_user), 0, amount / 100);
        vm.assertEq(vault.totalSupply() - totalSupplyBefore, shares);
        vm.assertEq(vault.balanceOf(_user), shares);
        vm.assertApproxEqAbs(shares * vault.sharePrice() / (10 ** vault.decimals()), amountWithFee, amount / 100);
        vm.assertApproxEqAbs(vault.totalAssets() - tvlBefore, amountWithFee, amount / 100);

        if (feeProvider != IFeeProvider(address(0))) {
            vm.startPrank(admin);
            feeProvider.setFees(depositFee * 2, withdrawalFee * 2, performanceFee * 2);
            vm.assertEq(vault.getDepositFee(_user), depositFee);
            vm.assertEq(vault.getWithdrawalFee(_user), withdrawalFee);
            vm.assertEq(vault.getPerformanceFee(_user), performanceFee);
            vm.assertEq(vault.getDepositFee(user5), depositFee * 2);
            vm.assertEq(vault.getWithdrawalFee(user5), withdrawalFee * 2);
            vm.assertEq(vault.getPerformanceFee(user5), performanceFee * 2);
            feeProvider.setFees(depositFee, withdrawalFee, performanceFee);
            vm.stopPrank();
        }
    }

    function _redeem(address _caller, address _owner, address _receiver, uint256 _shares)
        internal
        returns (uint256 assets)
    {
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 tvlBefore = vault.totalAssets();
        uint256 balanceOfUserBefore = vault.balanceOf(_owner);
        uint256 balanceOfReceiverBefore = asset.balanceOf(_receiver);
        uint256 amountWithFees = _shares * vault.sharePrice() / (10 ** vault.decimals());
        if (feeProvider != IFeeProvider(address(0))) {
            uint32 withdrawalFee_ = vault.getWithdrawalFee(_owner);
            uint32 performanceFee_ = vault.getPerformanceFee(_owner);
            amountWithFees = (amountWithFees * (feePrecision - performanceFee_) / feePrecision)
                * (feePrecision - withdrawalFee_) / feePrecision;
        }

        vm.startPrank(_caller);
        assets = vault.redeem(_shares, _receiver, _owner, 0);
        vm.stopPrank();

        vm.assertEq(totalSupplyBefore - vault.totalSupply(), _shares);
        vm.assertEq(balanceOfUserBefore - vault.balanceOf(_owner), _shares);
        vm.assertApproxEqAbs(tvlBefore - vault.totalAssets(), assets, assets / 100);
        vm.assertApproxEqAbs(asset.balanceOf(_receiver) - balanceOfReceiverBefore, amountWithFees, amountWithFees / 100);
    }

    function _redeemExpectRevert(address _owner, address _receiver, uint256 _shares) internal {
        vm.startPrank(_receiver);
        vm.expectRevert();
        vault.redeem(_shares, _receiver, _owner, 0);
        vm.stopPrank();
    }

    function _approveAndRedeem(address _owner, address _userWithAllowance, address _receiver, uint256 _shares)
        internal
        returns (uint256 assets)
    {
        vm.prank(_owner);
        vault.approve(_userWithAllowance, _shares);
        assets = _redeem(_userWithAllowance, _owner, _receiver, _shares);
    }

    function baseVaultTest(address assetProvider, bool needToProvide) public fork {
        _provideAndApprove(assetProvider, needToProvide);
        _initializeNewVault();
        _checkGetters();
        _checkPause();

        uint256 shares1 = _deposit(user, amount);
        console.log("shares user", shares1);
        uint256 shares2 = _deposit(user2, amount);
        console.log("shares user2", shares2);

        uint256 sharePriceBefore = vault.sharePrice();
        if (_increaseVaultAssets()) vm.assertGt(vault.sharePrice(), sharePriceBefore);

        uint256 assets1 = _redeem(user, user, user, shares1);
        console.log("assets1", assets1);

        // check collect perfomance fee
        // vm.startPrank(admin);
        // uint256 depositedBalanceBefore = usdtVault.getWaterline(user);
        // address[] memory users = new address[](2);
        // users[0] = user;
        // usdtVault.collectPerformanceFee(users);
        // assert(usdtVault.getWaterline(user) >= depositedBalanceBefore);
        // vm.stopPrank();

        _redeemExpectRevert(user2, user, shares2);

        uint256 assets2 = _approveAndRedeem(user2, user, user2, shares2);
        console.log("assets2", assets2);

        if (feeProvider != IFeeProvider(address(0))) {
            _deposit(admin, amount);
            _increaseVaultAssets();
            vm.startPrank(admin);
            uint256 depositedBalanceBefore = vault.getWaterline(admin);
            address[] memory users = new address[](2);
            users[0] = admin;
            vault.collectPerformanceFee(users);
            assert(vault.getWaterline(admin) >= depositedBalanceBefore);
            uint256 totalSupplyBefore = vault.totalSupply();
            vault.collectAdministrationFee();
            vm.assertGt(vault.totalSupply(), totalSupplyBefore);
            vm.stopPrank();
        }
    }
}
