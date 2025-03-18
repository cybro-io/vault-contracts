// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {BaseVault} from "../src/BaseVault.sol";
import {FeeProvider, IFeeProvider} from "../src/FeeProvider.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {ERC20Mock} from "../src/mocks/ERC20Mock.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {DeployUtils} from "./DeployUtils.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract AbstractBaseVaultTest is Test, DeployUtils {
    using MessageHashUtils for bytes32;
    using ECDSA for bytes32;
    using SafeERC20 for IERC20Metadata;

    uint256 forkId;
    IVault vault;
    IERC20Metadata asset;
    ERC20Mock testToken;
    uint256 testTokenAmount;
    address user;
    address user2;
    address user3;
    address user4;
    address user5;

    address feeRecipient;
    IFeeProvider feeProvider;

    address internal admin;
    uint256 internal adminPrivateKey;

    uint32 depositFee;
    uint32 withdrawalFee;
    uint32 performanceFee;
    uint32 managementFee;
    uint32 feePrecision;

    address vaultAddress;

    uint256 amount;
    string name;
    string symbol;

    address assetProvider;

    address[] signers;
    uint8[] discountTiers;
    uint32[] discounts;
    uint256[] minAmounts;
    uint256 specialWarpTime;

    function setUp() public virtual {
        adminPrivateKey = baseAdminPrivateKey;
        admin = vm.addr(baseAdminPrivateKey);
        user = address(100);
        user2 = address(101);
        user3 = address(1020202);
        user4 = address(1030303);
        user5 = address(1001001);
        feeRecipient = address(102);
        vm.label(admin, "Admin");
        vm.label(user, "User");
        vm.label(user2, "User2");
        vm.label(user3, "User3");
        vm.label(user5, "User5");
        vm.label(feeRecipient, "FeeRecipient");
        depositFee = 100;
        withdrawalFee = 200;
        performanceFee = 300;
        managementFee = 1000;
        feePrecision = 1e5;
        name = "nameVault";
        symbol = "symbolVault";
        vm.startPrank(admin);
        testToken = new ERC20Mock("Test Token", "TEST", 18);
        testTokenAmount = 5e18;
        specialWarpTime = 120 days;

        discountTiers.push(0);
        discounts.push(0);
        minAmounts.push(0);
        discountTiers.push(1);
        discounts.push(1000);
        minAmounts.push(1e18);
        discountTiers.push(2);
        discounts.push(2000);
        minAmounts.push(1e19);

        feeProvider = FeeProvider(
            address(
                new TransparentUpgradeableProxy(
                    address(new FeeProvider(feePrecision)),
                    admin,
                    abi.encodeCall(
                        FeeProvider.initialize, (admin, depositFee, withdrawalFee, performanceFee, managementFee)
                    )
                )
            )
        );
        vm.label(address(feeProvider), "FeeProvider");
        vaultAddress = vm.computeCreateAddress(admin, vm.getNonce(admin) + 1);
        address[] memory whitelistedContracts = new address[](1);
        whitelistedContracts[0] = vaultAddress;
        bool[] memory isWhitelisted = new bool[](1);
        isWhitelisted[0] = true;
        feeProvider.setWhitelistedContracts(whitelistedContracts, isWhitelisted);
        signers.push(admin);
        feeProvider.setSigners(signers, isWhitelisted);
        feeProvider.setTiers(discountTiers, discounts, minAmounts);
        vm.stopPrank();
    }

    modifier fork() {
        vm.selectFork(forkId);
        _;
    }

    function _initializeNewVault() internal virtual;

    function _increaseVaultAssets() internal virtual returns (bool);

    function _getAssetProvider(IERC20Metadata asset_) internal view returns (address assetProvider_) {
        if (block.chainid == 81457) {
            if (asset_ == usdb_BLAST) {
                assetProvider_ = assetProvider_USDB_BLAST;
            } else if (asset_ == weth_BLAST) {
                assetProvider_ = assetProvider_WETH_BLAST;
            } else if (asset_ == blast_BLAST) {
                assetProvider_ = assetProvider_BLAST_BLAST;
            } else {
                assetProvider_ = assetProvider_WBTC_BLAST;
            }
        } else if (block.chainid == 42161) {
            if (asset_ == usdt_ARBITRUM) {
                assetProvider_ = assetProvider_USDT_ARBITRUM;
            } else if (asset_ == usdc_ARBITRUM) {
                assetProvider_ = assetProvider_USDC_ARBITRUM;
            } else if (asset_ == weth_ARBITRUM) {
                assetProvider_ = assetProvider_WETH_ARBITRUM;
            } else if (asset_ == wbtc_ARBITRUM) {
                assetProvider_ = assetProvider_WBTC_ARBITRUM;
            } else if (asset_ == dai_ARBITRUM) {
                assetProvider_ = assetProvider_DAI_ARBITRUM;
            } else if (asset_ == weeth_ARBITRUM) {
                assetProvider_ = assetProvider_WEETH_ARBITRUM;
            }
        } else if (block.chainid == 8453) {
            if (asset_ == usdc_BASE) {
                assetProvider_ = assetProvider_USDC_BASE;
            } else if (asset_ == weth_BASE) {
                assetProvider_ = assetProvider_WETH_BASE;
            } else if (asset_ == cbwbtc_BASE) {
                assetProvider_ = assetProvider_CBWBTC_BASE;
            }
        } else if (block.chainid == 1) {
            if (asset_ == usdt_ETHEREUM) {
                assetProvider_ = assetProvider_USDT_ETHEREUM;
            } else if (asset_ == weth_ETHEREUM) {
                assetProvider_ = assetProvider_WETH_ETHEREUM;
            }
        }
    }

    function _setAssetProvider() internal {
        assetProvider = _getAssetProvider(asset);
    }

    function _provideAndApproveSpecific(bool needToProvide, IERC20Metadata asset_, uint256 amount_) internal {
        if (needToProvide) {
            address assetProvider_ = _getAssetProvider(asset_);
            vm.startPrank(assetProvider_);
            asset_.transfer(user, amount_);
            asset_.transfer(user2, amount_);
            asset_.transfer(user3, amount_);
            asset_.transfer(user4, amount_);
            asset_.transfer(admin, amount_);
            vm.stopPrank();
        }
        vm.startPrank(user);
        asset_.forceApprove(vaultAddress, amount_);
        vm.stopPrank();
        vm.startPrank(user2);
        asset_.forceApprove(vaultAddress, amount_);
        vm.stopPrank();
        vm.startPrank(user3);
        asset_.forceApprove(vaultAddress, amount_);
        vm.stopPrank();
        vm.startPrank(user4);
        asset_.forceApprove(vaultAddress, amount_);
        vm.stopPrank();
        vm.startPrank(admin);
        asset_.forceApprove(vaultAddress, amount_);
        vm.stopPrank();
    }

    function _provideAndApprove(bool needToProvide) internal {
        vm.label(address(vault), "Vault");
        _setAssetProvider();
        _provideAndApproveSpecific(needToProvide, asset, amount);
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
            vm.assertEq(vault.getManagementFee(), managementFee);
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

    function _additionalChecksAfterDeposit(address _user, uint256 amount_, uint256 shares) internal virtual {}

    function _getSignature(address _user, uint256 _stakedAmount, uint256 _deadline)
        internal
        returns (bytes memory signature)
    {
        vm.startPrank(admin);
        bytes32 digest = keccak256(abi.encodePacked(_user, _stakedAmount, _deadline)).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(adminPrivateKey, digest);
        signature = abi.encodePacked(r, s, v);
        vm.stopPrank();
    }

    function _deposit(address _user, uint256 amount_) internal returns (uint256 shares) {
        uint256 amountWithFee = amount_;
        uint256 deadline = block.timestamp + 1e10;
        bytes memory signature;
        if (feeProvider != IFeeProvider(address(0))) {
            uint32 depositFee_ = vault.getDepositFee(_user);
            vm.expectRevert();
            feeProvider.setStakedAmount(_user, 100, 0, new bytes(0));
            signature = _getSignature(_user, minAmounts[0], deadline);
            feeProvider.setStakedAmount(_user, minAmounts[0], deadline, signature);
            (uint256 stakedAmount_, uint256 deadline_) = feeProvider.stakedAmountInfo(_user);
            vm.assertEq(stakedAmount_, minAmounts[0]);
            vm.assertEq(deadline_, deadline);
            vm.assertEq(depositFee_, feeProvider.getDepositFee(_user));

            signature = _getSignature(_user, minAmounts[1], deadline);
            feeProvider.setStakedAmount(_user, minAmounts[1], deadline, signature);
            (stakedAmount_, deadline_) = feeProvider.stakedAmountInfo(_user);
            vm.assertEq(stakedAmount_, minAmounts[1]);
            if (depositFee_ > 0) {
                vm.assertGt(depositFee_, feeProvider.getDepositFee(_user));
                depositFee_ = vault.getDepositFee(_user);
            }
            if (vm.randomUint() % 2 == 0) {
                signature = _getSignature(_user, 0, deadline);
                feeProvider.setStakedAmount(_user, 0, deadline, signature);
            } else if (depositFee_ > 0) {
                depositFee_ = vault.getDepositFee(_user);
            }
            amountWithFee = amountWithFee * (feePrecision - depositFee_) / feePrecision;
        }
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 tvlBefore = vault.totalAssets();

        signature = _getSignature(_user, minAmounts[1], deadline);
        vm.startPrank(_user);
        if (feeProvider != IFeeProvider(address(0)) ? feeProvider.getDiscount(_user) > 0 : false) {
            shares = vault.updateFeeDiscountDeposit(amount_, _user, 0, minAmounts[1], deadline, signature);
        } else {
            shares = vault.deposit(amount_, _user, 0);
        }
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
        if (tvlBefore == 0) {
            vm.assertApproxEqAbs(vault.totalAssets(), amountWithFee, amountWithFee / 10);
        }

        if (feeProvider != IFeeProvider(address(0))) {
            signature = _getSignature(_user, 0, deadline);
            vm.startPrank(admin);
            feeProvider.setStakedAmount(_user, 0, deadline, signature);
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
        _additionalChecksAfterDeposit(_user, amount_, shares);
        vm.warp(block.timestamp + 10000);
    }

    function _redeem(address _caller, address _owner, address _receiver, uint256 _shares)
        internal
        returns (uint256 assets)
    {
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 tvlBefore = vault.totalAssets();
        uint256 balanceOfUserBefore = vault.balanceOf(_owner);
        uint256 balanceOfReceiverBefore = asset.balanceOf(_receiver);
        uint256 amountWithoutFees = _shares * vault.sharePrice() / (10 ** vault.decimals());

        vm.startPrank(_caller);
        assets = vault.redeem(_shares, _receiver, _owner, 0);
        vm.stopPrank();

        vm.assertEq(totalSupplyBefore - vault.totalSupply(), _shares);
        vm.assertEq(balanceOfUserBefore - vault.balanceOf(_owner), _shares);
        vm.assertApproxEqAbs(tvlBefore - vault.totalAssets(), amountWithoutFees, amountWithoutFees / 100);
        vm.assertApproxEqAbs(asset.balanceOf(_receiver) - balanceOfReceiverBefore, assets, assets / 100);
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

    function _checkEmergencyWithdraw(address _user) internal virtual {
        address[] memory accounts = new address[](2);
        accounts[0] = _user;
        accounts[1] = user5;
        uint256 balanceOfUserBefore = asset.balanceOf(_user);

        vm.startPrank(user5);
        vm.expectRevert();
        vault.emergencyWithdraw(accounts);
        vm.stopPrank();

        vm.startPrank(admin);
        vault.emergencyWithdraw(accounts);
        vm.assertEq(vault.balanceOf(_user), 0);
        vm.assertEq(vault.balanceOf(user5), 0);
        vm.assertGt(asset.balanceOf(_user), balanceOfUserBefore);
        vm.stopPrank();
    }

    function _checkValidateTokenToRecover() internal virtual returns (address tokenToValidate, bool isValidated) {
        return (address(0), false);
    }

    function _checkWithdrawFunds() internal {
        vm.deal(address(vault), 1e18);
        vm.startPrank(user);
        vm.expectRevert();
        vault.withdrawFunds(address(0));
        vm.stopPrank();

        vm.startPrank(admin);
        (address tokenToValidate, bool isValidated) = _checkValidateTokenToRecover();
        if (isValidated) {
            vm.expectRevert();
            vault.withdrawFunds(tokenToValidate);
        }
        vault.withdrawFunds(address(0));
        vm.assertEq(address(vault).balance, 0);

        testToken.mint(address(vault), testTokenAmount);
        vm.assertEq(testToken.balanceOf(address(vault)), testTokenAmount);
        vault.withdrawFunds(address(testToken));
        vm.assertEq(testToken.balanceOf(address(vault)), 0);
        vm.assertEq(testToken.balanceOf(address(admin)), testTokenAmount);
        vm.stopPrank();
    }

    function _middleInteractions() internal virtual {}

    function baseVaultTest(bool needToProvide) public fork {
        _initializeNewVault();
        _provideAndApprove(needToProvide);
        _checkGetters();
        _checkPause();

        uint256 shares1 = _deposit(user, amount);
        console.log("shares user", shares1);
        console.log("totalAssets", vault.totalAssets());
        uint256 shares2 = _deposit(user2, amount);
        console.log("shares user2", shares2);
        console.log("totalAssets", vault.totalAssets());

        _middleInteractions();

        uint256 sharePriceBefore = vault.sharePrice();
        if (_increaseVaultAssets()) vm.assertGt(vault.sharePrice(), sharePriceBefore);

        uint256 assets1 = _redeem(user, user, user, shares1);
        console.log("assets1", assets1);

        _redeemExpectRevert(user2, user, shares2);

        uint256 assets2 = _approveAndRedeem(user2, user, user2, shares2);
        console.log("assets2", assets2);

        _deposit(admin, amount);
        _increaseVaultAssets();

        if (feeProvider != IFeeProvider(address(0))) {
            vm.startPrank(admin);
            uint256 depositedBalanceBefore = vault.getWaterline(admin);
            address[] memory users = new address[](2);
            users[0] = admin;
            vault.collectPerformanceFee(users);
            assert(vault.getWaterline(admin) >= depositedBalanceBefore);
            vm.warp(block.timestamp + specialWarpTime);
            uint256 totalSupplyBefore = vault.totalSupply();
            vault.collectManagementFee();
            vm.assertGt(vault.totalSupply(), totalSupplyBefore);
            totalSupplyBefore = vault.totalSupply();
            vault.collectManagementFee();
            vm.assertEq(vault.totalSupply(), totalSupplyBefore);
            vm.stopPrank();
        }
        _checkEmergencyWithdraw(admin);
        _checkWithdrawFunds();
    }
}
