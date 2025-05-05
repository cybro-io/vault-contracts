// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {AaveVault, IERC20Metadata} from "../src/vaults/AaveVault.sol";
import {InitVault} from "../src/vaults/InitVault.sol";
import {CompoundVaultETH} from "../src/vaults/CompoundVaultEth.sol";
import {CompoundVault} from "../src/vaults/CompoundVaultErc20.sol";
import {JuiceVault} from "../src/vaults/JuiceVault.sol";
import {YieldStakingVault} from "../src/vaults/YieldStakingVault.sol";
import {OneClickIndex} from "../src/OneClickIndex.sol";
import {BaseVault} from "../src/BaseVault.sol";
import {
    TransparentUpgradeableProxy,
    ProxyAdmin,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {FeeProvider, IFeeProvider} from "../src/FeeProvider.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {AlgebraVault} from "../src/dex/AlgebraVault.sol";
import {BaseDexVault} from "../src/dex/BaseDexVault.sol";
import {BaseDexUniformVault} from "../src/dex/BaseDexUniformVault.sol";
import {BlasterSwapV2Vault} from "../src/dex/BlasterSwapV2Vault.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {DeployUtils} from "../test/DeployUtils.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Upgrade is Script, StdCheats, DeployUtils {
    struct AccountsToMigrate {
        address fund_address;
        string fund_name;
        uint256 id;
        address investor_address;
    }

    struct UpgradeParams {
        address vault;
        address newImpl;
        bool recalculateWaterline;
    }

    uint32 public constant feePrecision = 10000;
    address public constant feeRecipient = address(0x66E424337c0f888DCCbCf2e0730A00A526D716f6);
    address public constant cybroWallet = address(0xE1066Cb8c18c408525Ca98C7B0ad70be8D5608CB);
    address public constant cybroManager = address(0xD06Fd4465CdEdD4D8e01ec7ebd5F835cbb22cF01);
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant STRATEGIST_ROLE = keccak256("STRATEGIST_ROLE");

    AccountsToMigrate[] public parsedAccountsToMigrate;
    IERC20Metadata public asset_;
    uint256 public snapshotId;
    mapping(address vault => address[]) public realAccountsToMigrate;
    mapping(address vault => mapping(address account => uint256 waterline)) public waterlines;

    function _testCanRedeem(IVault vault, address user_) internal {
        uint256 sharesOfUserBefore = vault.balanceOf(user_);
        uint256 balanceInAssets = sharesOfUserBefore * _getSharePrice(address(vault)) / 10 ** vault.decimals();
        vm.startPrank(user_);
        try vault.redeem(sharesOfUserBefore, user_, user_, 0) returns (uint256 assets) {
            vm.assertApproxEqAbs(assets, balanceInAssets, balanceInAssets / 3);
        } catch (bytes memory reason) {
            if (reason.length == 0) {
                bytes memory data =
                    abi.encodeWithSignature("redeem(uint256,address,address)", sharesOfUserBefore, user_, user_);
                (bool success, bytes memory returnData) = address(vault).call(data);
                if (!success) {
                    data = abi.encodeWithSignature("redeem(uint256,address)", sharesOfUserBefore, user_);
                    (success, returnData) = address(vault).call(data);
                    if (!success) {
                        data = abi.encodeWithSignature(
                            "redeem(bool,uint256,address,address,uint256)",
                            _isToken0(address(vault)),
                            sharesOfUserBefore,
                            user_,
                            user_,
                            0
                        );
                        (success, returnData) = address(vault).call(data);
                        if (!success) {
                            revert("ERROR redeeming");
                        }
                    }
                }
                vm.assertApproxEqAbs(abi.decode(returnData, (uint256)), balanceInAssets, balanceInAssets / 3);
            } else {
                assembly {
                    revert(add(reason, 32), mload(reason))
                }
            }
        }
        vm.stopPrank();
        vm.assertEq(vault.balanceOf(user_), 0);
        vm.revertToState(snapshotId);
    }

    function _isToken0(address vault) internal view returns (bool isToken0) {
        vm.assertTrue(
            address(asset_) == BaseDexVault(vault).token0() || address(asset_) == BaseDexVault(vault).token1()
        );
        isToken0 = address(asset_) == BaseDexVault(vault).token0();
    }

    function _checkItem(
        address vault,
        bool recalculateWaterline,
        address investor_address,
        uint256 sharePrice,
        uint256 decimals
    ) internal {
        uint256 balance = IERC20Metadata(vault).balanceOf(investor_address);
        if (balance > 0) {
            console.log("investor_address", investor_address, "balanceOf", balance);
            if (!recalculateWaterline) {
                balance = balance * sharePrice / 10 ** decimals;
            } else {
                (bool success, bytes memory returnData) =
                    address(vault).call(abi.encodeWithSignature("getDepositedBalance(address)", investor_address));
                if (success) {
                    balance = abi.decode(returnData, (uint256));
                } else {
                    revert("ERROR getting deposited balance");
                }
            }
            realAccountsToMigrate[vault].push(investor_address);
            waterlines[vault][investor_address] = balance;
            snapshotId = vm.snapshotState();
            _testCanRedeem(IVault(vault), investor_address);
        }
    }

    function _parse() internal {
        if (parsedAccountsToMigrate.length == 0) {
            string memory root = vm.projectRoot();
            string memory path = string.concat(root, "/script/current_investors.json");
            string memory json = vm.readFile(path);
            string[] memory keys = vm.parseJsonKeys(json, ".");
            bytes memory data = vm.parseJson(json, string.concat(".", keys[0]));
            AccountsToMigrate[] memory temp_ = abi.decode(data, (AccountsToMigrate[]));
            for (uint256 i = 0; i < temp_.length; i++) {
                parsedAccountsToMigrate.push(temp_[i]);
            }
        }
    }

    function _getSharePrice(address vault) internal returns (uint256 sharePrice) {
        (bool success, bytes memory returnData) = address(vault).call(abi.encodeWithSignature("sharePrice()"));
        if (success) {
            sharePrice = abi.decode(returnData, (uint256));
        } else {
            (uint256 amount0, uint256 amount1) = BaseDexVault(vault).getPositionAmounts();
            uint256 sqrtPrice = BaseDexUniformVault(vault).getCurrentSqrtPrice();
            sharePrice = (
                _isToken0(vault)
                    ? Math.mulDiv(amount1, 2 ** 192, sqrtPrice * sqrtPrice) + amount0
                    : Math.mulDiv(amount0, sqrtPrice * sqrtPrice, 2 ** 192) + amount1
            ) * (10 ** IERC20Metadata(vault).decimals()) / IVault(vault).totalSupply();
        }
    }

    function _updateWaterlinesForVault(address vault, bool recalculateWaterline, address[] memory accountsToMigrate_)
        internal
        returns (address)
    {
        _parse();
        uint256 sharePrice = _getSharePrice(vault);
        uint256 decimals = IERC20Metadata(vault).decimals();
        console.log("Updating waterlines for vault:", vault, "\n");
        if (accountsToMigrate_.length == 0) {
            for (uint256 i = 0; i < parsedAccountsToMigrate.length; i++) {
                AccountsToMigrate memory item = parsedAccountsToMigrate[i];
                if (item.fund_address == vault) {
                    _checkItem(vault, recalculateWaterline, item.investor_address, sharePrice, decimals);
                }
            }
        } else {
            for (uint256 i = 0; i < accountsToMigrate_.length; i++) {
                _checkItem(vault, recalculateWaterline, accountsToMigrate_[i], sharePrice, decimals);
            }
        }
        console.log("\naccountsToMigrate", realAccountsToMigrate[vault].length, "\n");
        return vault;
    }

    function _deployFeeProvider(
        address admin,
        uint32 depositFee,
        uint32 withdrawalFee,
        uint32 performanceFee,
        uint32 managementFee,
        address vault
    ) internal returns (IFeeProvider feeProvider) {
        feeProvider = IFeeProvider(
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
        vm.assertEq(feeProvider.getFeePrecision(), feePrecision);
        vm.assertEq(feeProvider.getDepositFee(admin), depositFee);
        vm.assertEq(feeProvider.getWithdrawalFee(admin), withdrawalFee);
        vm.assertEq(feeProvider.getPerformanceFee(admin), performanceFee);
        _updateFeeProviderWhitelisted(feeProvider, address(vault));
        vm.assertTrue(feeProvider.whitelistedContracts(address(vault)));
        console.log("FeeProvider", address(feeProvider), "feePrecision", feePrecision);
        console.log("  with fees:");
        console.log("    depositFee", depositFee);
        console.log("    withdrawalFee", withdrawalFee);
        console.log("    performanceFee", performanceFee);
        console.log("    managementFee", managementFee);
        return feeProvider;
    }

    function _updateFeeProviderWhitelisted(IFeeProvider feeProvider_, address whitelisted) internal {
        address[] memory whitelistedContracts = new address[](1);
        whitelistedContracts[0] = whitelisted;
        bool[] memory isWhitelisted = new bool[](1);
        isWhitelisted[0] = true;
        feeProvider_.setWhitelistedContracts(whitelistedContracts, isWhitelisted);
    }

    function _getProxyAdmin(address vault) internal view returns (ProxyAdmin proxyAdmin, address admin_) {
        proxyAdmin = ProxyAdmin(address(uint160(uint256(vm.load(address(vault), ERC1967Utils.ADMIN_SLOT)))));
        admin_ = proxyAdmin.owner();
    }

    function _getAdmin(address vault) internal view returns (address admin_) {
        (, admin_) = _getProxyAdmin(vault);
    }

    function _beforeUpgrade(UpgradeParams memory params)
        internal
        view
        returns (ProxyAdmin, uint256, uint256, address, address)
    {
        console.log("\n New implementation", params.newImpl, "\n");
        (ProxyAdmin proxyAdmin, address admin_) = _getProxyAdmin(params.vault);
        uint256 totalSupplyBefore = IERC20Metadata(params.vault).totalSupply();
        uint256 tvlBefore;
        try IVault(params.vault).totalAssets() returns (uint256 t) {
            tvlBefore = t;
        } catch {
            tvlBefore = type(uint256).max;
        }
        address owner_;
        try Ownable(params.vault).owner() returns (address owner__) {
            owner_ = owner__;
        } catch {
            owner_ = address(0);
        }
        return (proxyAdmin, tvlBefore, totalSupplyBefore, admin_, owner_);
    }

    function _afterUpgrade(UpgradeParams memory params, uint256 totalSupplyBefore, address owner_) internal {
        if (owner_ != address(0)) {
            vm.assertTrue(BaseVault(params.vault).hasRole(DEFAULT_ADMIN_ROLE, owner_));
            vm.assertTrue(BaseVault(params.vault).hasRole(MANAGER_ROLE, owner_));
        }
        _checkMigratedAccounts(params.vault);
        _testVaultWorks(BaseVault(params.vault), 10 ** IERC20Metadata(params.vault).decimals());
        vm.assertEq(IERC20Metadata(params.vault).totalSupply(), totalSupplyBefore);
        console.log("\nTESTS PASSED");
        console.log("\n==============================================\n");
    }

    function _beforeUpgrade_FixUnderlyingTVL(address vault)
        internal
        view
        returns (ProxyAdmin, uint256, uint256, address)
    {
        (ProxyAdmin proxyAdmin, address admin_) = _getProxyAdmin(vault);
        return (proxyAdmin, IVault(vault).totalAssets(), IERC20Metadata(vault).totalSupply(), admin_);
    }

    function _afterUpgrade_FixUnderlyingTVL(address vault, uint256 totalAssetsBefore, uint256 totalSupplyBefore)
        internal
    {
        vm.assertEq(IERC20Metadata(vault).totalSupply(), totalSupplyBefore);
        vm.assertEq(IVault(vault).totalAssets(), totalAssetsBefore);
        uint256 underlyingTVL = IVault(vault).underlyingTVL();
        uint256 decimals = 10 ** IERC20Metadata(vault).decimals();
        vm.assertLt(underlyingTVL, 1e10 * decimals);
        console.log("Underlying TVL", underlyingTVL, "div decimals", underlyingTVL / decimals);
        _testVaultWorks(BaseVault(vault), decimals);
        console.log("\nTESTS PASSED");
        console.log("\n==============================================\n");
    }

    function _upgradeDEX_FixUnderlyingTVL(address vault, address newImpl) internal {
        console.log("\n New implementation", address(newImpl), "\n");
        (ProxyAdmin proxyAdmin, uint256 totalAssetsBefore, uint256 totalSupplyBefore, address admin_) =
            _beforeUpgrade_FixUnderlyingTVL(address(vault));
        vm.startBroadcast(admin_);
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(vault)), address(newImpl), bytes(""));
        vm.stopBroadcast();
        _afterUpgrade_FixUnderlyingTVL(address(vault), totalAssetsBefore, totalSupplyBefore);
    }

    function _checkMigratedAccounts(address vault) internal {
        if (realAccountsToMigrate[vault].length == 0) {
            return;
        } else {
            for (uint256 i = 0; i < realAccountsToMigrate[vault].length; i++) {
                address account = realAccountsToMigrate[vault][i];
                vm.assertEq(IVault(vault).getWaterline(account), waterlines[vault][account]);
                snapshotId = vm.snapshotState();
                _testCanRedeem(IVault(vault), account);
            }
        }
    }

    function _upgradeVault(UpgradeParams memory params) internal {
        (ProxyAdmin proxyAdmin, uint256 tvlBefore, uint256 totalSupplyBefore, address admin_, address owner_) =
            _beforeUpgrade(params);
        vm.startBroadcast(admin_);
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(params.vault),
            address(params.newImpl),
            abi.encodeCall(
                AaveVault.initialize_upgrade, (realAccountsToMigrate[params.vault], params.recalculateWaterline)
            )
        );
        vm.stopBroadcast();
        if (tvlBefore != type(uint256).max) {
            vm.assertEq(IVault(params.vault).totalAssets(), tvlBefore);
        }
        _afterUpgrade(params, totalSupplyBefore, owner_);
    }

    function _upgradeDexVault(UpgradeParams memory params) internal {
        (ProxyAdmin proxyAdmin,, uint256 totalSupplyBefore, address admin_, address owner_) = _beforeUpgrade(params);
        vm.startBroadcast(admin_);
        bytes memory data = abi.encodeCall(
            AlgebraVault.initialize_upgradeStorage,
            (
                BaseDexVault(params.vault).positionTokenId(),
                BaseDexVault(params.vault).tickLower(),
                BaseDexVault(params.vault).tickUpper(),
                BaseDexVault(params.vault).sqrtPriceLower(),
                BaseDexVault(params.vault).sqrtPriceUpper(),
                realAccountsToMigrate[params.vault]
            )
        );
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(params.vault), params.newImpl, data);
        vm.stopBroadcast();
        _afterUpgrade(params, totalSupplyBefore, owner_);
    }

    function _upgradeFeeProvider(IFeeProvider feeProvider_, address vault_) internal {
        (ProxyAdmin feeProviderProxyAdmin, address feeProviderAdmin) = _getProxyAdmin(address(feeProvider_));
        address owner_ = FeeProvider(address(feeProvider_)).owner();
        vm.startBroadcast(feeProviderAdmin);
        address feeProviderImpl = address(new FeeProvider(feePrecision));
        console.log("\n  new impl FeeProvider", feeProviderImpl);
        feeProviderProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(feeProvider_)), feeProviderImpl, new bytes(0)
        );
        vm.stopBroadcast();

        vm.startBroadcast(owner_);
        _updateFeeProviderWhitelisted(feeProvider_, vault_);
        vm.stopBroadcast();
        vm.assertTrue(feeProvider_.whitelistedContracts(vault_));
    }

    function upgradeBlast() public {
        // ADMIN ACCOUNT IS 0xE1066Cb8c18c408525Ca98C7B0ad70be8D5608CB

        // upgrade 0x3DB2bD838c2bEd431DCFA012c3419b7e94D78456
        // YieldStakingVault CYBRO WETH

        YieldStakingVault yieldStaking_weth_vault = YieldStakingVault(
            _updateWaterlinesForVault(0x3DB2bD838c2bEd431DCFA012c3419b7e94D78456, false, new address[](0))
        );
        console.log("Upgrading YieldStakingVault CYBRO WETH\n  ", address(yieldStaking_weth_vault), "\n");

        address admin = _getAdmin(address(yieldStaking_weth_vault));
        vm.startBroadcast(admin);
        IFeeProvider feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0, address(yieldStaking_weth_vault));
        YieldStakingVault newImpl = new YieldStakingVault(
            IERC20Metadata(yieldStaking_weth_vault.asset()),
            yieldStaking_weth_vault.staking(),
            feeProvider,
            feeRecipient
        );
        vm.stopBroadcast();
        _upgradeVault(
            UpgradeParams({
                vault: address(yieldStaking_weth_vault),
                newImpl: address(newImpl),
                recalculateWaterline: false
            })
        );

        // upgrade 0xDB5E7d5AC4E09206fED80efD7AbD9976357e1c03
        // YieldStakingVault CYBRO USDB

        YieldStakingVault yieldStaking_usdb_vault = YieldStakingVault(
            _updateWaterlinesForVault(0xDB5E7d5AC4E09206fED80efD7AbD9976357e1c03, false, new address[](0))
        );
        console.log("Upgrading YieldStakingVault CYBRO USDB\n  ", address(yieldStaking_usdb_vault), "\n");

        admin = _getAdmin(address(yieldStaking_usdb_vault));
        vm.startBroadcast(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0, address(yieldStaking_usdb_vault));
        newImpl = new YieldStakingVault(
            IERC20Metadata(yieldStaking_usdb_vault.asset()),
            yieldStaking_usdb_vault.staking(),
            feeProvider,
            feeRecipient
        );
        vm.stopBroadcast();
        _upgradeVault(
            UpgradeParams({
                vault: address(yieldStaking_usdb_vault),
                newImpl: address(newImpl),
                recalculateWaterline: false
            })
        );

        // upgrade 0xBFb18Eda8961ee33e38678caf2BcEB2D23aEdfea
        // BlasterSwap  USDB/WETH

        BlasterSwapV2Vault blaster_vault = BlasterSwapV2Vault(0xBFb18Eda8961ee33e38678caf2BcEB2D23aEdfea);
        console.log("Upgrading BlasterSwap  USDB/WETH\n  ", address(blaster_vault), "\n");

        asset_ = IERC20Metadata(blaster_vault.token0()); // USDB
        _updateWaterlinesForVault(address(blaster_vault), false, new address[](0));
        admin = _getAdmin(address(blaster_vault));
        vm.startBroadcast(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0, address(blaster_vault));
        BlasterSwapV2Vault blaster_newImpl = new BlasterSwapV2Vault(
            payable(address(blaster_vault.router())),
            blaster_vault.token0(),
            blaster_vault.token1(),
            asset_,
            feeProvider,
            feeRecipient,
            address(_getOracleForToken(blaster_vault.token0())),
            address(_getOracleForToken(blaster_vault.token1()))
        );
        vm.stopBroadcast();
        _upgradeVault(
            UpgradeParams({
                vault: address(blaster_vault),
                newImpl: address(blaster_newImpl),
                recalculateWaterline: false
            })
        );

        // upgrade 0x18E22f3f9a9652ee3A667d78911baC55bC2249Af
        // Juice WETH Lending

        JuiceVault juice_weth_vault =
            JuiceVault(_updateWaterlinesForVault(0x18E22f3f9a9652ee3A667d78911baC55bC2249Af, false, new address[](0)));
        console.log("Upgrading Juice WETH Lending\n  ", address(juice_weth_vault), "\n");

        admin = _getAdmin(address(juice_weth_vault));
        vm.startBroadcast(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0, address(juice_weth_vault));
        JuiceVault juice_newImpl =
            new JuiceVault(IERC20Metadata(juice_weth_vault.asset()), juice_weth_vault.pool(), feeProvider, feeRecipient);
        vm.stopBroadcast();
        _upgradeVault(
            UpgradeParams({
                vault: address(juice_weth_vault),
                newImpl: address(juice_newImpl),
                recalculateWaterline: false
            })
        );

        // upgrade 0xD58826d2C0bAbf1A60d8b508160b52E9C19AFf07
        // Juice USDB Lending
        JuiceVault juice_usdb_vault =
            JuiceVault(_updateWaterlinesForVault(0xD58826d2C0bAbf1A60d8b508160b52E9C19AFf07, false, new address[](0)));
        console.log("Upgrading Juice USDB Lending\n  ", address(juice_usdb_vault), "\n");

        admin = _getAdmin(address(juice_usdb_vault));
        vm.startBroadcast(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0, address(juice_usdb_vault));
        juice_newImpl =
            new JuiceVault(IERC20Metadata(juice_usdb_vault.asset()), juice_usdb_vault.pool(), feeProvider, feeRecipient);
        vm.stopBroadcast();
        _upgradeVault(
            UpgradeParams({
                vault: address(juice_usdb_vault),
                newImpl: address(juice_newImpl),
                recalculateWaterline: false
            })
        );

        // upgrade 0x567103a40C408B2B8f766016C57A092A180397a1
        // Aso Finance USDB Lending (Compound)
        CompoundVault compound_usdb_vault = CompoundVault(
            _updateWaterlinesForVault(0x567103a40C408B2B8f766016C57A092A180397a1, false, new address[](0))
        );
        console.log("Upgrading Aso Finance USDB Lending (Compound)\n  ", address(compound_usdb_vault), "\n");

        admin = _getAdmin(address(compound_usdb_vault));
        vm.startBroadcast(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0, address(compound_usdb_vault));
        CompoundVault compound_newImpl = new CompoundVault(
            IERC20Metadata(compound_usdb_vault.asset()), compound_usdb_vault.pool(), feeProvider, feeRecipient
        );
        vm.stopBroadcast();
        _upgradeVault(
            UpgradeParams({
                vault: address(compound_usdb_vault),
                newImpl: address(compound_newImpl),
                recalculateWaterline: false
            })
        );

        // upgrade 0x9cc62EF691E869C05FD2eC41839889d4E74c3a3f
        // Aso Finance WETH Lending (CompoundETH)
        {
            CompoundVaultETH compound_eth_vault = CompoundVaultETH(
                payable(_updateWaterlinesForVault(0x9cc62EF691E869C05FD2eC41839889d4E74c3a3f, false, new address[](0)))
            );
            console.log("Upgrading Aso Finance WETH Lending (CompoundETH)\n  ", address(compound_eth_vault), "\n");

            admin = _getAdmin(address(compound_eth_vault));
            vm.startBroadcast(admin);
            feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0, address(compound_eth_vault));
            CompoundVaultETH compoundETH_newImpl = new CompoundVaultETH(
                IERC20Metadata(compound_eth_vault.asset()), compound_eth_vault.pool(), feeProvider, feeRecipient
            );
            vm.stopBroadcast();
            _upgradeVault(
                UpgradeParams({
                    vault: address(compound_eth_vault),
                    newImpl: address(compoundETH_newImpl),
                    recalculateWaterline: false
                })
            );
        }

        // upgrade 0xDCCDe9C6800BeA86E2e91cF54a870BA3Ff6FAF9f
        // Aso Finance WeETH Lending (Compound)
        {
            CompoundVault compound_weeth_vault = CompoundVault(
                _updateWaterlinesForVault(0xDCCDe9C6800BeA86E2e91cF54a870BA3Ff6FAF9f, false, new address[](0))
            );
            console.log("Upgrading Aso Finance WeETH Lending (Compound)\n  ", address(compound_weeth_vault), "\n");

            admin = _getAdmin(address(compound_weeth_vault));
            vm.startBroadcast(admin);
            feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0, address(compound_weeth_vault));
            compound_newImpl = new CompoundVault(
                IERC20Metadata(compound_weeth_vault.asset()), compound_weeth_vault.pool(), feeProvider, feeRecipient
            );
            vm.stopBroadcast();
            _upgradeVault(
                UpgradeParams({
                    vault: address(compound_weeth_vault),
                    newImpl: address(compound_newImpl),
                    recalculateWaterline: false
                })
            );
        }
        // upgrade 0x0667ac28015ED7146f19B2d218f81218abf32951
        // Aso Finance WBTC Lending (Compound)

        CompoundVault compound_wbtc_vault = CompoundVault(
            _updateWaterlinesForVault(0x0667ac28015ED7146f19B2d218f81218abf32951, false, new address[](0))
        );
        console.log("Upgrading Aso Finance WBTC Lending (Compound)\n  ", address(compound_wbtc_vault), "\n");

        admin = _getAdmin(address(compound_wbtc_vault));
        vm.startBroadcast(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0, address(compound_wbtc_vault));
        compound_newImpl = new CompoundVault(
            IERC20Metadata(compound_wbtc_vault.asset()), compound_wbtc_vault.pool(), feeProvider, feeRecipient
        );
        vm.stopBroadcast();
        _upgradeVault(
            UpgradeParams({
                vault: address(compound_wbtc_vault),
                newImpl: address(compound_newImpl),
                recalculateWaterline: false
            })
        );
    }

    function upgradeDEX() public {
        // ADMIN ACCOUNT IS 0xE1066Cb8c18c408525Ca98C7B0ad70be8D5608CB

        // upgrade 0xE9041d3483A760c7D5F8762ad407ac526fbe144f
        // BladeSwap USDB/WETH

        AlgebraVault vault = AlgebraVault(0xE9041d3483A760c7D5F8762ad407ac526fbe144f);
        console.log("\nUpgrading BladeSwap USDB/WETH\n  ", address(vault), "\n");

        address admin = _getAdmin(address(vault));
        asset_ = IERC20Metadata(vault.token0()); // USDB
        _updateWaterlinesForVault(address(vault), false, new address[](0));
        vm.startBroadcast(admin);
        IFeeProvider feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0, address(vault));
        AlgebraVault newImpl = new AlgebraVault(
            payable(address(vault.positionManager())),
            vault.token0(),
            vault.token1(),
            asset_,
            feeProvider,
            feeRecipient,
            address(_getOracleForToken(vault.token0())),
            address(_getOracleForToken(vault.token1()))
        );
        vm.stopBroadcast();
        _upgradeDexVault(UpgradeParams({vault: address(vault), newImpl: address(newImpl), recalculateWaterline: false}));

        // upgrade 0x370498c028564de4491B8aA2df437fb772a39EC5
        // Fenix Finance Blast/WETH

        vault = AlgebraVault(0x370498c028564de4491B8aA2df437fb772a39EC5);
        console.log("Upgrading Fenix Finance Blast/WETH\n  ", address(vault), "\n");

        admin = _getAdmin(address(vault));
        asset_ = IERC20Metadata(vault.token0()); // WETH
        _updateWaterlinesForVault(address(vault), false, new address[](0));
        vm.startBroadcast(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0, address(vault));
        newImpl = new AlgebraVault(
            payable(address(vault.positionManager())),
            vault.token0(),
            vault.token1(),
            asset_,
            feeProvider,
            feeRecipient,
            address(_getOracleForToken(vault.token0())),
            address(_getOracleForToken(vault.token1()))
        );
        vm.stopBroadcast();
        _upgradeDexVault(UpgradeParams({vault: address(vault), newImpl: address(newImpl), recalculateWaterline: false}));

        // upgrade 0x66E1BEA0a5a934B96E2d7d54Eddd6580c485521b
        // Fenix Finance WeETH/WETH

        vault = AlgebraVault(0x66E1BEA0a5a934B96E2d7d54Eddd6580c485521b);
        console.log("Upgrading Fenix Finance WeETH/WETH\n  ", address(vault), "\n");

        admin = _getAdmin(address(vault));
        asset_ = IERC20Metadata(vault.token1()); // WETH
        _updateWaterlinesForVault(address(vault), false, new address[](0));
        vm.startBroadcast(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0, address(vault));
        newImpl = new AlgebraVault(
            payable(address(vault.positionManager())),
            vault.token0(),
            vault.token1(),
            asset_, // WETH
            feeProvider,
            feeRecipient,
            address(0),
            address(0)
        );
        vm.stopBroadcast();
        _upgradeDexVault(UpgradeParams({vault: address(vault), newImpl: address(newImpl), recalculateWaterline: false}));
    }

    function upgradeDex_FixUnderlyingTVL() public {
        // upgrade 0xE9041d3483A760c7D5F8762ad407ac526fbe144f
        // BladeSwap USDB/WETH

        AlgebraVault vault = AlgebraVault(0xE9041d3483A760c7D5F8762ad407ac526fbe144f);
        console.log("\nUpgrading BladeSwap USDB/WETH\n  ", address(vault), "\n");

        address admin = _getAdmin(address(vault));
        asset_ = IERC20Metadata(vault.token0()); // USDB
        vm.startBroadcast(admin);
        IFeeProvider feeProvider = vault.feeProvider();
        AlgebraVault newImpl = new AlgebraVault(
            payable(address(vault.positionManager())),
            vault.token0(),
            vault.token1(),
            asset_,
            feeProvider,
            feeRecipient,
            address(_getOracleForToken(vault.token0())),
            address(_getOracleForToken(vault.token1()))
        );
        vm.stopBroadcast();
        _upgradeDEX_FixUnderlyingTVL(address(vault), address(newImpl));

        // upgrade 0x370498c028564de4491B8aA2df437fb772a39EC5
        // Fenix Finance Blast/WETH

        vault = AlgebraVault(0x370498c028564de4491B8aA2df437fb772a39EC5);
        console.log("Upgrading Fenix Finance Blast/WETH\n  ", address(vault), "\n");

        admin = _getAdmin(address(vault));
        asset_ = IERC20Metadata(vault.token0()); // WETH
        vm.startBroadcast(admin);
        feeProvider = vault.feeProvider();
        newImpl = new AlgebraVault(
            payable(address(vault.positionManager())),
            vault.token0(),
            vault.token1(),
            asset_,
            feeProvider,
            feeRecipient,
            address(_getOracleForToken(vault.token0())),
            address(_getOracleForToken(vault.token1()))
        );
        vm.stopBroadcast();
        _upgradeDEX_FixUnderlyingTVL(address(vault), address(newImpl));

        // upgrade 0x66E1BEA0a5a934B96E2d7d54Eddd6580c485521b
        // Fenix Finance WeETH/WETH

        vault = AlgebraVault(0x66E1BEA0a5a934B96E2d7d54Eddd6580c485521b);
        console.log("Upgrading Fenix Finance WeETH/WETH\n  ", address(vault), "\n");

        admin = _getAdmin(address(vault));
        asset_ = IERC20Metadata(vault.token1()); // WETH
        vm.startBroadcast(admin);
        feeProvider = vault.feeProvider();
        newImpl = new AlgebraVault(
            payable(address(vault.positionManager())),
            vault.token0(),
            vault.token1(),
            asset_, // WETH
            feeProvider,
            feeRecipient,
            address(0),
            address(0)
        );
        vm.stopBroadcast();
        _upgradeDEX_FixUnderlyingTVL(address(vault), address(newImpl));
    }

    function upgradeOneClick_Base() public {
        // ADMIN ACCOUNT IS 0xEFCFA8a86970fD14Ea9AB593716C2544cedC4Ff7
        // ADMIN473 ACCOUNT IS 0x4739fEFA6949fcB90F56a9D6defb3e8d3Fd282F6

        OneClickIndex oneClick =
            OneClickIndex(_updateWaterlinesForVault(0x0655e391e0c6e0b8cBe8C2747Ae15c67c37583B9, true, new address[](0)));
        address[] memory accountsToMigrate_ = new address[](1);
        accountsToMigrate_[0] = address(oneClick);

        // upgrade 0x9cABCb97C0EDF8910B433188480287B8323ee0FA
        // Compound (inside oneClickIndex)

        CompoundVault compound_vault = CompoundVault(
            _updateWaterlinesForVault(0x9cABCb97C0EDF8910B433188480287B8323ee0FA, true, accountsToMigrate_)
        );
        console.log("\nUpgrading Compound (inside oneClickIndex)\n  ", address(compound_vault), "\n");

        IFeeProvider feeProvider = compound_vault.feeProvider();
        _upgradeFeeProvider(feeProvider, address(compound_vault));

        vm.startBroadcast(_getAdmin(address(compound_vault)));
        CompoundVault compound_newImpl =
            new CompoundVault(IERC20Metadata(compound_vault.asset()), compound_vault.pool(), feeProvider, feeRecipient);
        vm.stopBroadcast();
        _upgradeVault(
            UpgradeParams({
                vault: address(compound_vault),
                newImpl: address(compound_newImpl),
                recalculateWaterline: true
            })
        );

        // upgrade 0x9fe836AB706Aec38fc4e1CaB758011fC59E730Bc
        // AAVE (inside oneClickIndex)

        AaveVault aave_vault =
            AaveVault(_updateWaterlinesForVault(0x9fe836AB706Aec38fc4e1CaB758011fC59E730Bc, true, accountsToMigrate_));
        console.log("\nUpgrading AAVE (inside oneClickIndex)\n  ", address(aave_vault), "\n");

        feeProvider = aave_vault.feeProvider();
        _upgradeFeeProvider(feeProvider, address(aave_vault));

        vm.startBroadcast(_getAdmin(address(aave_vault)));
        AaveVault aave_newImpl =
            new AaveVault(IERC20Metadata(aave_vault.asset()), aave_vault.pool(), feeProvider, feeRecipient);
        vm.stopBroadcast();
        _upgradeVault(
            UpgradeParams({vault: address(aave_vault), newImpl: address(aave_newImpl), recalculateWaterline: true})
        );

        // upgrade 0x0655e391e0c6e0b8cBe8C2747Ae15c67c37583B9
        // Base Index USDC

        console.log("\nUpgrading Base Index USDC\n  ", address(oneClick), "\n");
        feeProvider = oneClick.feeProvider();
        _upgradeFeeProvider(feeProvider, address(oneClick));

        vm.startBroadcast(_getAdmin(address(oneClick)));
        OneClickIndex oneClick_newImpl = new OneClickIndex(IERC20Metadata(oneClick.asset()), feeProvider, feeRecipient);
        vm.stopBroadcast();
        _upgradeVault(
            UpgradeParams({vault: address(oneClick), newImpl: address(oneClick_newImpl), recalculateWaterline: true})
        );
    }

    function upgradeOneClick_Blast() public {
        // ADMIN ACCOUNT IS 0xE1066Cb8c18c408525Ca98C7B0ad70be8D5608CB
        // ADMIN473 ACCOUNT IS 0x4739fEFA6949fcB90F56a9D6defb3e8d3Fd282F6

        OneClickIndex oneClick =
            OneClickIndex(_updateWaterlinesForVault(0xb3E2099b135B12139C4eB774F84a5808FB25c67d, true, new address[](0)));
        address[] memory accountsToMigrate_ = new address[](1);
        accountsToMigrate_[0] = address(oneClick);

        // upgrade 0x346d73AcdE2a319B17CECb5bf95C49107598dF34
        // Zerolend (AAVE inside oneClickIndex)

        AaveVault aave_vault =
            AaveVault(_updateWaterlinesForVault(0x346d73AcdE2a319B17CECb5bf95C49107598dF34, true, accountsToMigrate_));
        console.log("\nUpgrading Zerolend (AAVE inside oneClickIndex)\n  ", address(aave_vault), "\n");

        IFeeProvider feeProvider = aave_vault.feeProvider();
        _upgradeFeeProvider(feeProvider, address(aave_vault));

        vm.startBroadcast(_getAdmin(address(aave_vault)));
        AaveVault aave_newImpl =
            new AaveVault(IERC20Metadata(aave_vault.asset()), aave_vault.pool(), feeProvider, feeRecipient);
        vm.stopBroadcast();
        _upgradeVault(
            UpgradeParams({vault: address(aave_vault), newImpl: address(aave_newImpl), recalculateWaterline: true})
        );

        // upgrade 0xe394Ab698279502577A071A37022430af068Bb0c
        // INIT (inside oneClickIndex)
        // WARNING: ZERO lending shares/totalSupply

        InitVault init_vault =
            InitVault(_updateWaterlinesForVault(0xe394Ab698279502577A071A37022430af068Bb0c, false, new address[](0)));
        console.log("\nUpgrading INIT (inside oneClickIndex)\n  ", address(init_vault), "\n");

        feeProvider = init_vault.feeProvider();
        _upgradeFeeProvider(feeProvider, address(init_vault));

        vm.startBroadcast(_getAdmin(address(init_vault)));
        InitVault init_newImpl =
            new InitVault(IERC20Metadata(init_vault.asset()), init_vault.pool(), feeProvider, feeRecipient);
        vm.stopBroadcast();
        _upgradeVault(
            UpgradeParams({vault: address(init_vault), newImpl: address(init_newImpl), recalculateWaterline: false})
        );

        // upgrade 0x3fE57b59cb9f3DdE249745E6D562aA8841BC1b2D
        // Juice (inside oneClickIndex)
        {
            JuiceVault juice_vault = JuiceVault(
                _updateWaterlinesForVault(0x3fE57b59cb9f3DdE249745E6D562aA8841BC1b2D, true, accountsToMigrate_)
            );
            console.log("\nUpgrading Juice (inside oneClickIndex)\n  ", address(juice_vault), "\n");

            feeProvider = juice_vault.feeProvider();
            _upgradeFeeProvider(feeProvider, address(juice_vault));

            vm.startBroadcast(_getAdmin(address(juice_vault)));
            JuiceVault juice_newImpl =
                new JuiceVault(IERC20Metadata(juice_vault.asset()), juice_vault.pool(), feeProvider, feeRecipient);
            vm.stopBroadcast();
            _upgradeVault(
                UpgradeParams({vault: address(juice_vault), newImpl: address(juice_newImpl), recalculateWaterline: true})
            );
        }

        // upgrade 0x0c0a0CcC5685974B8ab411E44e2fC70F07ce4E3d
        // Orbit (inside oneClickIndex)
        // WARNING: ZERO balanceOf oneClick

        accountsToMigrate_[0] = address(0x4739fEFA6949fcB90F56a9D6defb3e8d3Fd282F6);
        CompoundVault orbit_vault = CompoundVault(
            _updateWaterlinesForVault(0x0c0a0CcC5685974B8ab411E44e2fC70F07ce4E3d, true, accountsToMigrate_)
        );
        console.log("\nUpgrading Orbit (inside oneClickIndex)\n  ", address(orbit_vault), "\n");

        feeProvider = orbit_vault.feeProvider();
        _upgradeFeeProvider(feeProvider, address(orbit_vault));

        vm.startBroadcast(_getAdmin(address(orbit_vault)));
        CompoundVault orbit_newImpl =
            new CompoundVault(IERC20Metadata(orbit_vault.asset()), orbit_vault.pool(), feeProvider, feeRecipient);
        vm.stopBroadcast();
        _upgradeVault(
            UpgradeParams({vault: address(orbit_vault), newImpl: address(orbit_newImpl), recalculateWaterline: true})
        );

        // upgrade 0xb3E2099b135B12139C4eB774F84a5808FB25c67d
        // Blast Index USDB

        console.log("\nUpgrading Blast Index USDB\n  ", address(oneClick), "\n");
        feeProvider = oneClick.feeProvider();
        _upgradeFeeProvider(feeProvider, address(oneClick));

        vm.startBroadcast(_getAdmin(address(oneClick)));
        OneClickIndex oneClick_newImpl = new OneClickIndex(IERC20Metadata(oneClick.asset()), feeProvider, feeRecipient);
        vm.stopBroadcast();
        _upgradeVault(
            UpgradeParams({vault: address(oneClick), newImpl: address(oneClick_newImpl), recalculateWaterline: true})
        );
    }

    function _testVaultWorks(BaseVault vault, uint256 amount) internal {
        IERC20Metadata token = IERC20Metadata(vault.asset());
        address user = address(100);
        if (vault.asset() == address(usdb_BLAST)) {
            vm.startPrank(assetProvider_USDB_BLAST);
            token.transfer(user, amount);
            vm.stopPrank();
        } else if (vault.asset() == address(weth_BLAST)) {
            vm.startPrank(assetProvider_WETH_BLAST);
            token.transfer(user, amount);
            vm.stopPrank();
        } else {
            deal(vault.asset(), user, amount);
        }

        vm.startPrank(user);
        token.approve(address(vault), amount);
        uint256 shares = vault.deposit(amount, user, 0);
        uint256 assets = vault.redeem(shares, user, user, 0);
        vm.stopPrank();
        console.log("balance of user before", amount);
        console.log("Shares after deposit", shares, "Redeemed assets", assets);
    }
}
