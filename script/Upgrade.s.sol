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
        address admin;
        bool moveOrSetCurrentBalance;
        bool ownableToAccessControl;
        address[] accountsToMigrate;
        bool testVaultWorks;
    }

    struct DexUpgradeParams {
        uint256 positionTokenId;
        int24 tickLower;
        int24 tickUpper;
        uint160 sqrtPriceLower;
        uint160 sqrtPriceUpper;
    }

    uint32 public constant feePrecision = 10000;
    address public constant feeRecipient = address(0x66E424337c0f888DCCbCf2e0730A00A526D716f6);
    address public constant cybroWallet = address(0xE1066Cb8c18c408525Ca98C7B0ad70be8D5608CB);
    address public constant cybroManager = address(0xD06Fd4465CdEdD4D8e01ec7ebd5F835cbb22cF01);
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant STRATEGIST_ROLE = keccak256("STRATEGIST_ROLE");

    address[] public fromJson_accountsToMigrate;
    AccountsToMigrate[] public parsedAccountsToMigrate;

    function _updateAccountsToMigrate(address vault) internal {
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
        delete fromJson_accountsToMigrate;

        for (uint256 i = 0; i < parsedAccountsToMigrate.length; i++) {
            AccountsToMigrate memory item = parsedAccountsToMigrate[i];

            if (item.fund_address == vault) {
                console.log(
                    "investor_address",
                    item.investor_address,
                    "balanceOf",
                    IERC20Metadata(vault).balanceOf(item.investor_address)
                );
                fromJson_accountsToMigrate.push(item.investor_address);
            }
        }
        console.log("\naccountsToMigrate", fromJson_accountsToMigrate.length);
    }

    function _deployFeeProvider(
        address admin,
        uint32 depositFee,
        uint32 withdrawalFee,
        uint32 performanceFee,
        uint32 managementFee,
        address vault
    ) internal returns (FeeProvider feeProvider) {
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
        vm.assertEq(feeProvider.getFeePrecision(), feePrecision);
        vm.assertEq(feeProvider.getDepositFee(admin), depositFee);
        vm.assertEq(feeProvider.getWithdrawalFee(admin), withdrawalFee);
        vm.assertEq(feeProvider.getPerformanceFee(admin), performanceFee);
        _updateFeeProviderWhitelisted(feeProvider, address(vault));
        vm.assertTrue(feeProvider.whitelistedContracts(address(vault)));
        console.log("FeeProvider", address(feeProvider), "feePrecision", feePrecision);
        console.log("  with fees", depositFee, withdrawalFee, performanceFee);
        return feeProvider;
    }

    function _updateFeeProviderWhitelisted(FeeProvider feeProvider_, address whitelisted) internal {
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

    function _beforeUpgrade(UpgradeParams memory params) internal returns (ProxyAdmin, uint256, uint256) {
        console.log("\n New implementation", params.newImpl, "\n");
        _updateAccountsToMigrate(params.vault);
        (ProxyAdmin proxyAdmin, address admin_) = _getProxyAdmin(params.vault);
        console.log(" ADMIN ADDRESS:", admin_, "\n");
        if (admin_ != params.admin) {
            revert("ADMIN ADDRESS MISMATCH");
        }
        uint256 totalSupplyBefore = IERC20Metadata(params.vault).totalSupply();
        uint256 tvlBefore;
        try IVault(params.vault).totalAssets() returns (uint256 t) {
            tvlBefore = t;
        } catch {
            tvlBefore = type(uint256).max;
        }
        return (proxyAdmin, tvlBefore, totalSupplyBefore);
    }

    function _afterUpgrade(UpgradeParams memory params, uint256 totalSupplyBefore) internal view {
        vm.assertEq(IERC20Metadata(params.vault).totalSupply(), totalSupplyBefore);
        console.log("\n==============================================\n");
    }

    function _upgradeVault(UpgradeParams memory params) internal {
        (ProxyAdmin proxyAdmin, uint256 tvlBefore, uint256 totalSupplyBefore) = _beforeUpgrade(params);
        vm.startBroadcast(params.admin);
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(params.vault),
            address(params.newImpl),
            abi.encodeCall(
                AaveVault.initialize_upgrade,
                (
                    params.accountsToMigrate.length == 0 ? fromJson_accountsToMigrate : params.accountsToMigrate,
                    params.ownableToAccessControl,
                    params.moveOrSetCurrentBalance
                )
            )
        );
        vm.stopBroadcast();
        if (tvlBefore != type(uint256).max) {
            vm.assertEq(IVault(params.vault).totalAssets(), tvlBefore);
        }
        if (params.testVaultWorks) {
            _testVaultWorks(BaseVault(params.vault), 10 ** IERC20Metadata(params.vault).decimals());
        }
        _afterUpgrade(params, totalSupplyBefore);
    }

    function _upgradeDexVault(UpgradeParams memory params, DexUpgradeParams memory dexParams) internal {
        (ProxyAdmin proxyAdmin,, uint256 totalSupplyBefore) = _beforeUpgrade(params);
        vm.startBroadcast(params.admin);
        bytes memory data = abi.encodeCall(
            AlgebraVault.initialize_upgradeStorage,
            (
                dexParams.positionTokenId,
                dexParams.tickLower,
                dexParams.tickUpper,
                dexParams.sqrtPriceLower,
                dexParams.sqrtPriceUpper,
                fromJson_accountsToMigrate
            )
        );
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(params.vault), params.newImpl, data);
        vm.stopBroadcast();
        if (params.testVaultWorks) {
            _testVaultWorks(BaseVault(params.vault), 10 ** IERC20Metadata(params.vault).decimals());
        }
        _afterUpgrade(params, totalSupplyBefore);
    }

    function _upgradeFeeProvider(FeeProvider feeProvider_, address admin_, address owner_, address vault_) internal {
        (ProxyAdmin feeProviderProxyAdmin, address feeProviderAdmin) = _getProxyAdmin(address(feeProvider_));
        console.log("feeProviderAdmin", feeProviderAdmin);
        console.log("feeProvider owner", feeProvider_.owner());
        vm.startBroadcast(admin_);
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
        // upgrade 0x3DB2bD838c2bEd431DCFA012c3419b7e94D78456
        // YieldStakingVault CYBRO WETH

        // ADMIN ACCOUNT IS 0xE1066Cb8c18c408525Ca98C7B0ad70be8D5608CB
        address admin = vm.rememberKey(vm.envUint("ADMIN_PK"));
        console.log("\nREADED ADMIN ADDRESS:", admin, "\n");

        YieldStakingVault vault = YieldStakingVault(0x3DB2bD838c2bEd431DCFA012c3419b7e94D78456);
        console.log("Upgrading YieldStakingVault CYBRO WETH\n  ", address(vault), "\n");

        vm.startBroadcast(admin);
        FeeProvider feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0, address(vault));
        YieldStakingVault newImpl =
            new YieldStakingVault(IERC20Metadata(vault.asset()), vault.staking(), feeProvider, feeRecipient);
        vm.stopBroadcast();
        _upgradeVault(
            UpgradeParams({
                vault: address(vault),
                newImpl: address(newImpl),
                admin: admin,
                moveOrSetCurrentBalance: false,
                ownableToAccessControl: true,
                accountsToMigrate: new address[](0),
                testVaultWorks: true
            })
        );

        // upgrade 0xDB5E7d5AC4E09206fED80efD7AbD9976357e1c03
        // YieldStakingVault CYBRO USDB

        vault = YieldStakingVault(0xDB5E7d5AC4E09206fED80efD7AbD9976357e1c03);
        console.log("Upgrading YieldStakingVault CYBRO USDB\n  ", address(vault), "\n");

        vm.startBroadcast(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0, address(vault));
        newImpl = new YieldStakingVault(IERC20Metadata(vault.asset()), vault.staking(), feeProvider, feeRecipient);
        vm.stopBroadcast();
        _upgradeVault(
            UpgradeParams({
                vault: address(vault),
                newImpl: address(newImpl),
                admin: admin,
                moveOrSetCurrentBalance: false,
                ownableToAccessControl: true,
                accountsToMigrate: new address[](0),
                testVaultWorks: true
            })
        );

        // upgrade 0xBFb18Eda8961ee33e38678caf2BcEB2D23aEdfea
        // BlasterSwap  USDB/WETH

        BlasterSwapV2Vault blaster_vault = BlasterSwapV2Vault(0xBFb18Eda8961ee33e38678caf2BcEB2D23aEdfea);
        console.log("Upgrading BlasterSwap  USDB/WETH\n  ", address(blaster_vault), "\n");

        vm.startBroadcast(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0, address(blaster_vault));
        BlasterSwapV2Vault blaster_newImpl = new BlasterSwapV2Vault(
            payable(address(blaster_vault.router())),
            blaster_vault.token0(),
            blaster_vault.token1(),
            IERC20Metadata(blaster_vault.token0()), // USDB
            feeProvider,
            feeRecipient
        );
        vm.stopBroadcast();
        _upgradeVault(
            UpgradeParams({
                vault: address(blaster_vault),
                newImpl: address(blaster_newImpl),
                admin: admin,
                moveOrSetCurrentBalance: false,
                ownableToAccessControl: true,
                accountsToMigrate: new address[](0),
                testVaultWorks: true
            })
        );

        // upgrade 0x18E22f3f9a9652ee3A667d78911baC55bC2249Af
        // Juice WETH Lending

        JuiceVault juice_vault = JuiceVault(0x18E22f3f9a9652ee3A667d78911baC55bC2249Af);
        console.log("Upgrading Juice WETH Lending\n  ", address(juice_vault), "\n");

        vm.startBroadcast(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0, address(juice_vault));
        JuiceVault juice_newImpl =
            new JuiceVault(IERC20Metadata(juice_vault.asset()), juice_vault.pool(), feeProvider, feeRecipient);
        vm.stopBroadcast();
        _upgradeVault(
            UpgradeParams({
                vault: address(juice_vault),
                newImpl: address(juice_newImpl),
                admin: admin,
                moveOrSetCurrentBalance: false,
                ownableToAccessControl: true,
                accountsToMigrate: new address[](0),
                testVaultWorks: true
            })
        );

        // upgrade 0xD58826d2C0bAbf1A60d8b508160b52E9C19AFf07
        // Juice USDB Lending

        juice_vault = JuiceVault(0xD58826d2C0bAbf1A60d8b508160b52E9C19AFf07);
        console.log("Upgrading Juice USDB Lending\n  ", address(juice_vault), "\n");

        vm.startBroadcast(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0, address(juice_vault));
        juice_newImpl =
            new JuiceVault(IERC20Metadata(juice_vault.asset()), juice_vault.pool(), feeProvider, feeRecipient);
        vm.stopBroadcast();
        _upgradeVault(
            UpgradeParams({
                vault: address(juice_vault),
                newImpl: address(juice_newImpl),
                admin: admin,
                moveOrSetCurrentBalance: false,
                ownableToAccessControl: true,
                accountsToMigrate: new address[](0),
                testVaultWorks: true
            })
        );

        // upgrade 0x567103a40C408B2B8f766016C57A092A180397a1
        // Aso Finance USDB Lending (Compound)

        CompoundVault compound_vault = CompoundVault(0x567103a40C408B2B8f766016C57A092A180397a1);
        console.log("Upgrading Aso Finance USDB Lending (Compound)\n  ", address(compound_vault), "\n");

        vm.startBroadcast(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0, address(compound_vault));
        CompoundVault compound_newImpl =
            new CompoundVault(IERC20Metadata(compound_vault.asset()), compound_vault.pool(), feeProvider, feeRecipient);
        vm.stopBroadcast();
        _upgradeVault(
            UpgradeParams({
                vault: address(compound_vault),
                newImpl: address(compound_newImpl),
                admin: admin,
                moveOrSetCurrentBalance: false,
                ownableToAccessControl: true,
                accountsToMigrate: new address[](0),
                testVaultWorks: true
            })
        );

        // upgrade 0x9cc62EF691E869C05FD2eC41839889d4E74c3a3f
        // Aso Finance WETH Lending (CompoundETH)

        CompoundVaultETH compoundETH_vault = CompoundVaultETH(payable(0x9cc62EF691E869C05FD2eC41839889d4E74c3a3f));
        console.log("Upgrading Aso Finance WETH Lending (CompoundETH)\n  ", address(compoundETH_vault), "\n");

        vm.startBroadcast(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0, address(compoundETH_vault));
        CompoundVaultETH compoundETH_newImpl = new CompoundVaultETH(
            IERC20Metadata(compoundETH_vault.asset()), compoundETH_vault.pool(), feeProvider, feeRecipient
        );
        vm.stopBroadcast();
        _upgradeVault(
            UpgradeParams({
                vault: address(compoundETH_vault),
                newImpl: address(compoundETH_newImpl),
                admin: admin,
                moveOrSetCurrentBalance: false,
                ownableToAccessControl: true,
                accountsToMigrate: new address[](0),
                testVaultWorks: true
            })
        );

        // upgrade 0xDCCDe9C6800BeA86E2e91cF54a870BA3Ff6FAF9f
        // Aso Finance WeETH Lending (Compound)

        compound_vault = CompoundVault(0xDCCDe9C6800BeA86E2e91cF54a870BA3Ff6FAF9f);
        console.log("Upgrading Aso Finance WeETH Lending (Compound)\n  ", address(compound_vault), "\n");

        vm.startBroadcast(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0, address(compound_vault));
        compound_newImpl =
            new CompoundVault(IERC20Metadata(compound_vault.asset()), compound_vault.pool(), feeProvider, feeRecipient);
        vm.stopBroadcast();
        _upgradeVault(
            UpgradeParams({
                vault: address(compound_vault),
                newImpl: address(compound_newImpl),
                admin: admin,
                moveOrSetCurrentBalance: false,
                ownableToAccessControl: true,
                accountsToMigrate: new address[](0),
                testVaultWorks: true
            })
        );

        // upgrade 0x0667ac28015ED7146f19B2d218f81218abf32951
        // Aso Finance WBTC Lending (Compound)

        compound_vault = CompoundVault(0x0667ac28015ED7146f19B2d218f81218abf32951);
        console.log("Upgrading Aso Finance WBTC Lending (Compound)\n  ", address(compound_vault), "\n");

        vm.startBroadcast(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0, address(compound_vault));
        compound_newImpl =
            new CompoundVault(IERC20Metadata(compound_vault.asset()), compound_vault.pool(), feeProvider, feeRecipient);
        vm.stopBroadcast();
        _upgradeVault(
            UpgradeParams({
                vault: address(compound_vault),
                newImpl: address(compound_newImpl),
                admin: admin,
                moveOrSetCurrentBalance: false,
                ownableToAccessControl: true,
                accountsToMigrate: new address[](0),
                testVaultWorks: true
            })
        );
    }

    function upgradeDEX() public {
        // ADMIN ACCOUNT IS 0xE1066Cb8c18c408525Ca98C7B0ad70be8D5608CB
        address admin = vm.rememberKey(vm.envUint("ADMIN_PK"));
        console.log("\nREADED ADMIN ADDRESS:", admin, "\n");

        // upgrade 0xE9041d3483A760c7D5F8762ad407ac526fbe144f
        // BladeSwap USDB/WETH

        AlgebraVault vault = AlgebraVault(0xE9041d3483A760c7D5F8762ad407ac526fbe144f);
        console.log("\nUpgrading BladeSwap USDB/WETH\n  ", address(vault), "\n");

        vm.startBroadcast(admin);
        FeeProvider feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0, address(vault));
        AlgebraVault newImpl = new AlgebraVault(
            payable(address(vault.positionManager())),
            vault.token0(),
            vault.token1(),
            IERC20Metadata(vault.token0()), // USDB
            feeProvider,
            feeRecipient
        );
        vm.stopBroadcast();
        _upgradeDexVault(
            UpgradeParams({
                vault: address(vault),
                newImpl: address(newImpl),
                admin: admin,
                moveOrSetCurrentBalance: false,
                ownableToAccessControl: true,
                accountsToMigrate: new address[](0),
                testVaultWorks: true
            }),
            DexUpgradeParams({
                positionTokenId: vault.positionTokenId(),
                tickLower: vault.tickLower(),
                tickUpper: vault.tickUpper(),
                sqrtPriceLower: vault.sqrtPriceLower(),
                sqrtPriceUpper: vault.sqrtPriceUpper()
            })
        );

        // upgrade 0x370498c028564de4491B8aA2df437fb772a39EC5
        // Fenix Finance Blast/WETH

        vault = AlgebraVault(0x370498c028564de4491B8aA2df437fb772a39EC5);
        console.log("Upgrading Fenix Finance Blast/WETH\n  ", address(vault), "\n");

        vm.startBroadcast(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0, address(vault));
        newImpl = new AlgebraVault(
            payable(address(vault.positionManager())),
            vault.token0(),
            vault.token1(),
            IERC20Metadata(vault.token0()), // WETH
            feeProvider,
            feeRecipient
        );
        vm.stopBroadcast();
        _upgradeDexVault(
            UpgradeParams({
                vault: address(vault),
                newImpl: address(newImpl),
                admin: admin,
                moveOrSetCurrentBalance: false,
                ownableToAccessControl: true,
                accountsToMigrate: new address[](0),
                testVaultWorks: true
            }),
            DexUpgradeParams({
                positionTokenId: vault.positionTokenId(),
                tickLower: vault.tickLower(),
                tickUpper: vault.tickUpper(),
                sqrtPriceLower: vault.sqrtPriceLower(),
                sqrtPriceUpper: vault.sqrtPriceUpper()
            })
        );

        // upgrade 0x66E1BEA0a5a934B96E2d7d54Eddd6580c485521b
        // Fenix Finance WeETH/WETH

        vault = AlgebraVault(0x66E1BEA0a5a934B96E2d7d54Eddd6580c485521b);
        console.log("Upgrading Fenix Finance WeETH/WETH\n  ", address(vault), "\n");

        vm.startBroadcast(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0, address(vault));
        newImpl = new AlgebraVault(
            payable(address(vault.positionManager())),
            vault.token0(),
            vault.token1(),
            IERC20Metadata(vault.token1()), // WETH
            feeProvider,
            feeRecipient
        );
        vm.stopBroadcast();
        _upgradeDexVault(
            UpgradeParams({
                vault: address(vault),
                newImpl: address(newImpl),
                admin: admin,
                moveOrSetCurrentBalance: false,
                ownableToAccessControl: true,
                accountsToMigrate: new address[](0),
                testVaultWorks: true
            }),
            DexUpgradeParams({
                positionTokenId: vault.positionTokenId(),
                tickLower: vault.tickLower(),
                tickUpper: vault.tickUpper(),
                sqrtPriceLower: vault.sqrtPriceLower(),
                sqrtPriceUpper: vault.sqrtPriceUpper()
            })
        );
    }

    function upgradeOneClick_Base() public {
        // ADMIN ACCOUNT IS 0xEFCFA8a86970fD14Ea9AB593716C2544cedC4Ff7
        address admin = vm.rememberKey(vm.envUint("ADMINEFC_PK"));
        // ADMIN473 ACCOUNT IS 0x4739fEFA6949fcB90F56a9D6defb3e8d3Fd282F6
        address admin473 = vm.rememberKey(vm.envUint("ADMIN473_PK"));
        console.log("\nREADED ADMIN ADDRESS:", admin, "\n");
        console.log("READED FEE PROVIDER OWNER ADDRESS:", admin473, "\n");

        // upgrade 0x0655e391e0c6e0b8cBe8C2747Ae15c67c37583B9
        // Base Index USDC

        OneClickIndex oneClick = OneClickIndex(0x0655e391e0c6e0b8cBe8C2747Ae15c67c37583B9);
        console.log("\nUpgrading Base Index USDC\n  ", address(oneClick), "\n");

        FeeProvider feeProvider = FeeProvider(0x815E9a686467Ec2CB7a7C185c565731730A5aF7e);
        _upgradeFeeProvider(feeProvider, admin, admin473, address(oneClick));

        vm.startBroadcast(admin);
        OneClickIndex oneClick_newImpl = new OneClickIndex(IERC20Metadata(oneClick.asset()), feeProvider, feeRecipient);
        vm.stopBroadcast();
        _upgradeVault(
            UpgradeParams({
                vault: address(oneClick),
                newImpl: address(oneClick_newImpl),
                admin: admin,
                moveOrSetCurrentBalance: false,
                ownableToAccessControl: false,
                accountsToMigrate: new address[](0),
                testVaultWorks: false
            })
        );

        // upgrade 0x9cABCb97C0EDF8910B433188480287B8323ee0FA
        // Compound (inside oneClickIndex)

        CompoundVault compound_vault = CompoundVault(0x9cABCb97C0EDF8910B433188480287B8323ee0FA);
        console.log("\nUpgrading Compound (inside oneClickIndex)\n  ", address(compound_vault), "\n");

        feeProvider = FeeProvider(0xd549D76E43c4B0Fb5282590361F9c035F20402E9);
        _upgradeFeeProvider(feeProvider, admin, admin473, address(compound_vault));

        address[] memory accountsToMigrate_ = new address[](1);
        accountsToMigrate_[0] = address(oneClick);

        vm.startBroadcast(admin);
        CompoundVault compound_newImpl =
            new CompoundVault(IERC20Metadata(compound_vault.asset()), compound_vault.pool(), feeProvider, feeRecipient);
        vm.stopBroadcast();
        _upgradeVault(
            UpgradeParams({
                vault: address(compound_vault),
                newImpl: address(compound_newImpl),
                admin: admin,
                moveOrSetCurrentBalance: true,
                ownableToAccessControl: false,
                accountsToMigrate: accountsToMigrate_,
                testVaultWorks: true
            })
        );

        // upgrade 0x9fe836AB706Aec38fc4e1CaB758011fC59E730Bc
        // AAVE (inside oneClickIndex)

        AaveVault aave_vault = AaveVault(0x9fe836AB706Aec38fc4e1CaB758011fC59E730Bc);
        console.log("\nUpgrading AAVE (inside oneClickIndex)\n  ", address(aave_vault), "\n");

        feeProvider = FeeProvider(0xB1246DbE910376954d15ebf89abCA3007002Af38);
        _upgradeFeeProvider(feeProvider, admin, admin473, address(aave_vault));

        vm.startBroadcast(admin);
        AaveVault aave_newImpl =
            new AaveVault(IERC20Metadata(aave_vault.asset()), aave_vault.pool(), feeProvider, feeRecipient);
        vm.stopBroadcast();
        _upgradeVault(
            UpgradeParams({
                vault: address(aave_vault),
                newImpl: address(aave_newImpl),
                admin: admin,
                moveOrSetCurrentBalance: true,
                ownableToAccessControl: false,
                accountsToMigrate: accountsToMigrate_,
                testVaultWorks: true
            })
        );
        console.log("Test OneClick");
        _testVaultWorks(BaseVault(address(oneClick)), 10 ** IERC20Metadata(address(oneClick)).decimals());
    }

    function upgradeOneClick_Blast() public {
        // ADMIN ACCOUNT IS 0xE1066Cb8c18c408525Ca98C7B0ad70be8D5608CB
        address admin = vm.rememberKey(vm.envUint("ADMIN_PK"));
        // ADMIN473 ACCOUNT IS 0x4739fEFA6949fcB90F56a9D6defb3e8d3Fd282F6
        address admin473 = vm.rememberKey(vm.envUint("ADMIN473_PK"));
        console.log("\nREADED ADMIN ADDRESS:", admin, "\n");
        console.log("READED FEE PROVIDER OWNER ADDRESS:", admin473, "\n");

        // upgrade 0xb3E2099b135B12139C4eB774F84a5808FB25c67d
        // Blast Index USDB

        OneClickIndex oneClick = OneClickIndex(0xb3E2099b135B12139C4eB774F84a5808FB25c67d);
        console.log("\nUpgrading Blast Index USDB\n  ", address(oneClick), "\n");

        FeeProvider feeProvider = FeeProvider(0x3049f8Eee32eB335f98CF3EF69987e4Efd192647);
        _upgradeFeeProvider(feeProvider, admin473, admin473, address(oneClick));

        vm.startBroadcast(admin);
        OneClickIndex oneClick_newImpl = new OneClickIndex(IERC20Metadata(oneClick.asset()), feeProvider, feeRecipient);
        vm.stopBroadcast();
        _upgradeVault(
            UpgradeParams({
                vault: address(oneClick),
                newImpl: address(oneClick_newImpl),
                admin: admin,
                moveOrSetCurrentBalance: false,
                ownableToAccessControl: false,
                accountsToMigrate: new address[](0),
                testVaultWorks: false
            })
        );

        address[] memory accountsToMigrate_ = new address[](1);
        accountsToMigrate_[0] = address(oneClick);

        // upgrade 0x346d73AcdE2a319B17CECb5bf95C49107598dF34
        // Zerolend (AAVE inside oneClickIndex)

        AaveVault aave_vault = AaveVault(0x346d73AcdE2a319B17CECb5bf95C49107598dF34);
        console.log("\nUpgrading Zerolend (AAVE inside oneClickIndex)\n  ", address(aave_vault), "\n");

        feeProvider = FeeProvider(0x2E395062497dc014Be9c55E03174e89bA4Afec30);
        _upgradeFeeProvider(feeProvider, admin473, admin473, address(aave_vault));

        vm.startBroadcast(admin473);
        AaveVault aave_newImpl =
            new AaveVault(IERC20Metadata(aave_vault.asset()), aave_vault.pool(), feeProvider, feeRecipient);
        vm.stopBroadcast();
        _upgradeVault(
            UpgradeParams({
                vault: address(aave_vault),
                newImpl: address(aave_newImpl),
                admin: admin473,
                moveOrSetCurrentBalance: true,
                ownableToAccessControl: false,
                accountsToMigrate: accountsToMigrate_,
                testVaultWorks: true
            })
        );

        // upgrade 0xe394Ab698279502577A071A37022430af068Bb0c
        // INIT (inside oneClickIndex)
        // WARNING: ZERO lending shares/totalSupply
        {
            InitVault init_vault = InitVault(0xe394Ab698279502577A071A37022430af068Bb0c);
            console.log("\nUpgrading INIT (inside oneClickIndex)\n  ", address(init_vault), "\n");

            feeProvider = FeeProvider(0x3049f8Eee32eB335f98CF3EF69987e4Efd192647);
            _upgradeFeeProvider(feeProvider, admin473, admin473, address(init_vault));

            vm.startBroadcast(admin473);
            InitVault init_newImpl =
                new InitVault(IERC20Metadata(init_vault.asset()), init_vault.pool(), feeProvider, feeRecipient);
            vm.stopBroadcast();
            _upgradeVault(
                UpgradeParams({
                    vault: address(init_vault),
                    newImpl: address(init_newImpl),
                    admin: admin473,
                    moveOrSetCurrentBalance: false,
                    ownableToAccessControl: false,
                    accountsToMigrate: new address[](0),
                    testVaultWorks: true
                })
            );
        }

        // upgrade 0x3fE57b59cb9f3DdE249745E6D562aA8841BC1b2D
        // Juice (inside oneClickIndex)
        {
            JuiceVault juice_vault = JuiceVault(0x3fE57b59cb9f3DdE249745E6D562aA8841BC1b2D);
            console.log("\nUpgrading Juice (inside oneClickIndex)\n  ", address(juice_vault), "\n");

            feeProvider = FeeProvider(0xC899EfA7863d755A6186a2EFa06a8Fc7e8c5BA42);
            _upgradeFeeProvider(feeProvider, admin473, admin473, address(juice_vault));

            vm.startBroadcast(admin473);
            JuiceVault juice_newImpl =
                new JuiceVault(IERC20Metadata(juice_vault.asset()), juice_vault.pool(), feeProvider, feeRecipient);
            vm.stopBroadcast();
            _upgradeVault(
                UpgradeParams({
                    vault: address(juice_vault),
                    newImpl: address(juice_newImpl),
                    admin: admin473,
                    moveOrSetCurrentBalance: true,
                    ownableToAccessControl: false,
                    accountsToMigrate: accountsToMigrate_,
                    testVaultWorks: true
                })
            );
        }

        // upgrade 0x0c0a0CcC5685974B8ab411E44e2fC70F07ce4E3d
        // Orbit (inside oneClickIndex)
        // WARNING: ZERO lending shares/totalSupply

        CompoundVault orbit_vault = CompoundVault(0x0c0a0CcC5685974B8ab411E44e2fC70F07ce4E3d);
        console.log("\nUpgrading Orbit (inside oneClickIndex)\n  ", address(orbit_vault), "\n");

        feeProvider = FeeProvider(0xf01e01cb6E20dc9E98380bAaAA899eed18A95d36);
        _upgradeFeeProvider(feeProvider, admin473, admin473, address(orbit_vault));

        vm.startBroadcast(admin473);
        CompoundVault orbit_newImpl =
            new CompoundVault(IERC20Metadata(orbit_vault.asset()), orbit_vault.pool(), feeProvider, feeRecipient);
        vm.stopBroadcast();
        accountsToMigrate_[0] = address(0x4739fEFA6949fcB90F56a9D6defb3e8d3Fd282F6);
        _upgradeVault(
            UpgradeParams({
                vault: address(orbit_vault),
                newImpl: address(orbit_newImpl),
                admin: admin473,
                moveOrSetCurrentBalance: true,
                ownableToAccessControl: false,
                accountsToMigrate: accountsToMigrate_,
                testVaultWorks: true
            })
        );
        console.log("Test OneClick");
        _testVaultWorks(BaseVault(address(oneClick)), 10 ** IERC20Metadata(address(oneClick)).decimals());
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
