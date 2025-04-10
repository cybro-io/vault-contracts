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

contract Upgrade is Script {
    struct AccountsToMigrate {
        address fund_address;
        string fund_name;
        uint256 id;
        address investor_address;
    }

    struct DeployVault {
        IERC20Metadata asset;
        address pool;
        IFeeProvider feeProvider;
        address feeRecipient;
        string name;
        string symbol;
        address admin;
        address manager;
    }

    uint32 public constant feePrecision = 10000;
    address public constant feeRecipient = address(0x66E424337c0f888DCCbCf2e0730A00A526D716f6);
    address public constant cybroWallet = address(0xE1066Cb8c18c408525Ca98C7B0ad70be8D5608CB);
    address public constant cybroManager = address(0xD06Fd4465CdEdD4D8e01ec7ebd5F835cbb22cF01);
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant STRATEGIST_ROLE = keccak256("STRATEGIST_ROLE");

    address[] public accountsToMigrate;

    function _deployFeeProvider(
        address admin,
        uint32 depositFee,
        uint32 withdrawalFee,
        uint32 performanceFee,
        uint32 managementFee
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
        console.log("FeeProvider", address(feeProvider), "feePrecision", feePrecision);
        console.log("  with fees", depositFee, withdrawalFee, performanceFee);
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

    function upgradeBlast() public {
        // upgrade 0x3DB2bD838c2bEd431DCFA012c3419b7e94D78456
        // YieldStakingVault CYBRO WETH

        // ADMIN ACCOUNT IS 0xE1066Cb8c18c408525Ca98C7B0ad70be8D5608CB
        address admin = vm.rememberKey(vm.envUint("ADMIN_PK"));
        console.log("\nREADED ADMIN ADDRESS:", admin, "\n");

        YieldStakingVault vault = YieldStakingVault(0x3DB2bD838c2bEd431DCFA012c3419b7e94D78456);
        console.log("Upgrading YieldStakingVault CYBRO WETH\n  ", address(vault), "\n");
        (ProxyAdmin proxyAdmin, address admin_) = _getProxyAdmin(address(vault));
        console.log(" ADMIN ADDRESS:", admin_, "\n");
        if (admin_ != admin) {
            revert("ADMIN ADDRESS MISMATCH");
        }

        vm.startBroadcast(admin);
        FeeProvider feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        _updateFeeProviderWhitelisted(feeProvider, address(vault));
        vm.assertTrue(feeProvider.whitelistedContracts(address(vault)));
        YieldStakingVault newImpl =
            new YieldStakingVault(IERC20Metadata(vault.asset()), vault.staking(), feeProvider, feeRecipient);
        console.log("\n  new impl", address(newImpl));
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(vault)),
            address(newImpl),
            abi.encodeWithSignature("initialize_ownableToAccessControl()")
        );
        vm.stopBroadcast();
        _checkBaseVaultUpgrade(BaseVault(address(vault)), admin);

        console.log("\n==============================================\n");

        // upgrade 0xDB5E7d5AC4E09206fED80efD7AbD9976357e1c03
        // YieldStakingVault CYBRO USDB

        vault = YieldStakingVault(0xDB5E7d5AC4E09206fED80efD7AbD9976357e1c03);
        console.log("Upgrading YieldStakingVault CYBRO USDB\n  ", address(vault), "\n");
        (proxyAdmin, admin_) = _getProxyAdmin(address(vault));
        console.log(" ADMIN ADDRESS:", admin_, "\n");

        vm.startBroadcast(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        _updateFeeProviderWhitelisted(feeProvider, address(vault));
        vm.assertTrue(feeProvider.whitelistedContracts(address(vault)));
        newImpl = new YieldStakingVault(IERC20Metadata(vault.asset()), vault.staking(), feeProvider, feeRecipient);
        console.log("\n  new impl", address(newImpl));
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(vault)),
            address(newImpl),
            abi.encodeWithSignature("initialize_ownableToAccessControl()")
        );
        vm.stopBroadcast();
        _checkBaseVaultUpgrade(BaseVault(address(vault)), admin);

        console.log("\n==============================================\n");

        // upgrade 0xBFb18Eda8961ee33e38678caf2BcEB2D23aEdfea
        // BlasterSwap  USDB/WETH

        BlasterSwapV2Vault blaster_vault = BlasterSwapV2Vault(0xBFb18Eda8961ee33e38678caf2BcEB2D23aEdfea);
        console.log("Upgrading BlasterSwap  USDB/WETH\n  ", address(blaster_vault), "\n");
        (proxyAdmin, admin_) = _getProxyAdmin(address(blaster_vault));
        console.log(" ADMIN ADDRESS:", admin_, "\n");

        vm.startBroadcast(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        _updateFeeProviderWhitelisted(feeProvider, address(blaster_vault));
        vm.assertTrue(feeProvider.whitelistedContracts(address(blaster_vault)));
        BlasterSwapV2Vault blaster_newImpl = new BlasterSwapV2Vault(
            payable(address(blaster_vault.router())),
            blaster_vault.token0(),
            blaster_vault.token1(),
            IERC20Metadata(blaster_vault.token0()), // USDB
            feeProvider,
            feeRecipient
        );
        console.log("\n  new impl", address(blaster_newImpl));
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(blaster_vault)),
            address(blaster_newImpl),
            abi.encodeWithSignature("initialize_ownableToAccessControl()")
        );
        vm.stopBroadcast();
        _checkBaseVaultUpgrade(BaseVault(address(blaster_vault)), admin);

        console.log("\n==============================================\n");

        // upgrade 0x18E22f3f9a9652ee3A667d78911baC55bC2249Af
        // Juice WETH Lending

        JuiceVault juice_vault = JuiceVault(0x18E22f3f9a9652ee3A667d78911baC55bC2249Af);
        console.log("Upgrading Juice WETH Lending\n  ", address(juice_vault), "\n");
        (proxyAdmin, admin_) = _getProxyAdmin(address(juice_vault));
        console.log(" ADMIN ADDRESS:", admin_, "\n");

        vm.startBroadcast(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        _updateFeeProviderWhitelisted(feeProvider, address(juice_vault));
        vm.assertTrue(feeProvider.whitelistedContracts(address(juice_vault)));
        JuiceVault juice_newImpl =
            new JuiceVault(IERC20Metadata(juice_vault.asset()), juice_vault.pool(), feeProvider, feeRecipient);
        console.log("\n  new impl", address(juice_newImpl));
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(juice_vault)),
            address(juice_newImpl),
            abi.encodeWithSignature("initialize_ownableToAccessControl()")
        );
        vm.stopBroadcast();
        _checkBaseVaultUpgrade(BaseVault(address(juice_vault)), admin);

        console.log("\n==============================================\n");

        // upgrade 0xD58826d2C0bAbf1A60d8b508160b52E9C19AFf07
        // Juice USDB Lending

        juice_vault = JuiceVault(0xD58826d2C0bAbf1A60d8b508160b52E9C19AFf07);
        console.log("Upgrading Juice USDB Lending\n  ", address(juice_vault), "\n");
        (proxyAdmin, admin_) = _getProxyAdmin(address(juice_vault));
        console.log(" ADMIN ADDRESS:", admin_, "\n");

        vm.startBroadcast(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        _updateFeeProviderWhitelisted(feeProvider, address(juice_vault));
        vm.assertTrue(feeProvider.whitelistedContracts(address(juice_vault)));
        juice_newImpl =
            new JuiceVault(IERC20Metadata(juice_vault.asset()), juice_vault.pool(), feeProvider, feeRecipient);
        console.log("\n  new impl", address(juice_newImpl));
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(juice_vault)),
            address(juice_newImpl),
            abi.encodeWithSignature("initialize_ownableToAccessControl()")
        );
        vm.stopBroadcast();
        _checkBaseVaultUpgrade(BaseVault(address(juice_vault)), admin);

        console.log("\n==============================================\n");

        // upgrade 0x567103a40C408B2B8f766016C57A092A180397a1
        // Aso Finance USDB Lending (Compound)

        CompoundVault compound_vault = CompoundVault(0x567103a40C408B2B8f766016C57A092A180397a1);
        console.log("Upgrading Aso Finance USDB Lending (Compound)\n  ", address(compound_vault), "\n");
        (proxyAdmin, admin_) = _getProxyAdmin(address(compound_vault));
        console.log(" ADMIN ADDRESS:", admin_, "\n");

        vm.startBroadcast(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        _updateFeeProviderWhitelisted(feeProvider, address(compound_vault));
        vm.assertTrue(feeProvider.whitelistedContracts(address(compound_vault)));
        CompoundVault compound_newImpl =
            new CompoundVault(IERC20Metadata(compound_vault.asset()), compound_vault.pool(), feeProvider, feeRecipient);
        console.log("\n  new impl", address(compound_newImpl));
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(compound_vault)),
            address(compound_newImpl),
            abi.encodeWithSignature("initialize_ownableToAccessControl()")
        );
        vm.stopBroadcast();
        _checkBaseVaultUpgrade(BaseVault(address(compound_vault)), admin);

        console.log("\n==============================================\n");

        // upgrade 0x9cc62EF691E869C05FD2eC41839889d4E74c3a3f
        // Aso Finance WETH Lending (CompoundETH)

        CompoundVaultETH compoundETH_vault = CompoundVaultETH(payable(0x9cc62EF691E869C05FD2eC41839889d4E74c3a3f));
        console.log("Upgrading Aso Finance WETH Lending (CompoundETH)\n  ", address(compoundETH_vault), "\n");
        (proxyAdmin, admin_) = _getProxyAdmin(address(compoundETH_vault));
        console.log(" ADMIN ADDRESS:", admin_, "\n");

        vm.startBroadcast(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        _updateFeeProviderWhitelisted(feeProvider, address(compoundETH_vault));
        vm.assertTrue(feeProvider.whitelistedContracts(address(compoundETH_vault)));
        CompoundVaultETH compoundETH_newImpl = new CompoundVaultETH(
            IERC20Metadata(compoundETH_vault.asset()), compoundETH_vault.pool(), feeProvider, feeRecipient
        );
        console.log("\n  new impl", address(compoundETH_newImpl));
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(compoundETH_vault)),
            address(compoundETH_newImpl),
            abi.encodeWithSignature("initialize_ownableToAccessControl()")
        );
        vm.stopBroadcast();
        _checkBaseVaultUpgrade(BaseVault(address(compoundETH_vault)), admin);

        console.log("\n==============================================\n");

        // upgrade 0xDCCDe9C6800BeA86E2e91cF54a870BA3Ff6FAF9f
        // Aso Finance WeETH Lending (Compound)

        compound_vault = CompoundVault(0xDCCDe9C6800BeA86E2e91cF54a870BA3Ff6FAF9f);
        console.log("Upgrading Aso Finance WeETH Lending (Compound)\n  ", address(compound_vault), "\n");
        (proxyAdmin, admin_) = _getProxyAdmin(address(compound_vault));
        console.log(" ADMIN ADDRESS:", admin_, "\n");

        vm.startBroadcast(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        _updateFeeProviderWhitelisted(feeProvider, address(compound_vault));
        vm.assertTrue(feeProvider.whitelistedContracts(address(compound_vault)));
        compound_newImpl =
            new CompoundVault(IERC20Metadata(compound_vault.asset()), compound_vault.pool(), feeProvider, feeRecipient);
        console.log("\n  new impl", address(compound_newImpl));
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(compound_vault)),
            address(compound_newImpl),
            abi.encodeWithSignature("initialize_ownableToAccessControl()")
        );
        vm.stopBroadcast();
        _checkBaseVaultUpgrade(BaseVault(address(compound_vault)), admin);

        console.log("\n==============================================\n");

        // upgrade 0x0667ac28015ED7146f19B2d218f81218abf32951
        // Aso Finance WBTC Lending (Compound)

        compound_vault = CompoundVault(0x0667ac28015ED7146f19B2d218f81218abf32951);
        console.log("Upgrading Aso Finance WBTC Lending (Compound)\n  ", address(compound_vault), "\n");
        (proxyAdmin, admin_) = _getProxyAdmin(address(compound_vault));
        console.log(" ADMIN ADDRESS:", admin_, "\n");

        vm.startBroadcast(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        _updateFeeProviderWhitelisted(feeProvider, address(compound_vault));
        vm.assertTrue(feeProvider.whitelistedContracts(address(compound_vault)));
        compound_newImpl =
            new CompoundVault(IERC20Metadata(compound_vault.asset()), compound_vault.pool(), feeProvider, feeRecipient);
        console.log("\n  new impl", address(compound_newImpl));
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(compound_vault)),
            address(compound_newImpl),
            abi.encodeWithSignature("initialize_ownableToAccessControl()")
        );
        vm.stopBroadcast();
        _checkBaseVaultUpgrade(BaseVault(address(compound_vault)), admin);
    }

    function upgradeDEX() public {
        // upgrade 0xE9041d3483A760c7D5F8762ad407ac526fbe144f
        // BladeSwap USDB/WETH

        // ADMIN ACCOUNT IS 0xE1066Cb8c18c408525Ca98C7B0ad70be8D5608CB
        address admin = vm.rememberKey(vm.envUint("ADMIN_PK"));
        console.log("\nREADED ADMIN ADDRESS:", admin, "\n");

        AlgebraVault vault = AlgebraVault(0xE9041d3483A760c7D5F8762ad407ac526fbe144f);
        console.log("\nUpgrading BladeSwap USDB/WETH\n  ", address(vault), "\n");
        (ProxyAdmin proxyAdmin, address admin_) = _getProxyAdmin(address(vault));
        console.log("ADMIN ADDRESS:", admin_, "\n");
        if (admin_ != admin) {
            revert("ADMIN ADDRESS MISMATCH");
        }
        vm.startBroadcast(admin);
        FeeProvider feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        _updateFeeProviderWhitelisted(feeProvider, address(vault));
        vm.assertTrue(feeProvider.whitelistedContracts(address(vault)));
        AlgebraVault newImpl = new AlgebraVault(
            payable(address(vault.positionManager())),
            vault.token0(),
            vault.token1(),
            IERC20Metadata(vault.token0()), // USDB
            feeProvider,
            feeRecipient
        );
        console.log("\n  new impl", address(newImpl));
        {
            uint256 positionTokenId_ = vault.positionTokenId();
            int24 tickLower_ = vault.tickLower();
            int24 tickUpper_ = vault.tickUpper();
            uint160 sqrtPriceLower_ = vault.sqrtPriceLower();
            uint160 sqrtPriceUpper_ = vault.sqrtPriceUpper();
            bytes memory data = abi.encodeWithSignature(
                "initialize_upgradeStorage(uint256,int24,int24,uint160,uint160)",
                positionTokenId_,
                tickLower_,
                tickUpper_,
                sqrtPriceLower_,
                sqrtPriceUpper_
            );
            proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(vault)), address(newImpl), data);
        }
        vm.stopBroadcast();
        _checkDexUpgrade(vault, admin);

        console.log("\n==============================================\n");

        // upgrade 0x370498c028564de4491B8aA2df437fb772a39EC5
        // Fenix Finance Blast/WETH
        vault = AlgebraVault(0x370498c028564de4491B8aA2df437fb772a39EC5);
        console.log("Upgrading Fenix Finance Blast/WETH\n  ", address(vault), "\n");
        (proxyAdmin, admin_) = _getProxyAdmin(address(vault));
        console.log("ADMIN ADDRESS:", admin_, "\n");

        vm.startBroadcast(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        _updateFeeProviderWhitelisted(feeProvider, address(vault));
        vm.assertTrue(feeProvider.whitelistedContracts(address(vault)));
        newImpl = new AlgebraVault(
            payable(address(vault.positionManager())),
            vault.token0(),
            vault.token1(),
            IERC20Metadata(vault.token0()), // WETH
            feeProvider,
            feeRecipient
        );
        console.log("\n  new impl", address(newImpl));
        {
            uint256 positionTokenId_ = vault.positionTokenId();
            int24 tickLower_ = vault.tickLower();
            int24 tickUpper_ = vault.tickUpper();
            uint160 sqrtPriceLower_ = vault.sqrtPriceLower();
            uint160 sqrtPriceUpper_ = vault.sqrtPriceUpper();
            bytes memory data = abi.encodeWithSignature(
                "initialize_upgradeStorage(uint256,int24,int24,uint160,uint160)",
                positionTokenId_,
                tickLower_,
                tickUpper_,
                sqrtPriceLower_,
                sqrtPriceUpper_
            );
            proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(vault)), address(newImpl), data);
        }
        vm.stopBroadcast();
        _checkDexUpgrade(vault, admin);

        console.log("\n==============================================\n");

        // upgrade 0x66E1BEA0a5a934B96E2d7d54Eddd6580c485521b
        // Fenix Finance WeETH/WETH
        vault = AlgebraVault(0x66E1BEA0a5a934B96E2d7d54Eddd6580c485521b);
        console.log("Upgrading Fenix Finance WeETH/WETH\n  ", address(vault), "\n");
        (proxyAdmin, admin_) = _getProxyAdmin(address(vault));
        console.log("ADMIN ADDRESS:", admin_, "\n");

        vm.startBroadcast(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        _updateFeeProviderWhitelisted(feeProvider, address(vault));
        vm.assertTrue(feeProvider.whitelistedContracts(address(vault)));
        newImpl = new AlgebraVault(
            payable(address(vault.positionManager())),
            vault.token0(),
            vault.token1(),
            IERC20Metadata(vault.token1()), // WETH
            feeProvider,
            feeRecipient
        );
        console.log("\n  new impl", address(newImpl));
        {
            uint256 positionTokenId_ = vault.positionTokenId();
            int24 tickLower_ = vault.tickLower();
            int24 tickUpper_ = vault.tickUpper();
            uint160 sqrtPriceLower_ = vault.sqrtPriceLower();
            uint160 sqrtPriceUpper_ = vault.sqrtPriceUpper();
            bytes memory data = abi.encodeWithSignature(
                "initialize_upgradeStorage(uint256,int24,int24,uint160,uint160)",
                positionTokenId_,
                tickLower_,
                tickUpper_,
                sqrtPriceLower_,
                sqrtPriceUpper_
            );
            proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(vault)), address(newImpl), data);
        }
        vm.stopBroadcast();
        _checkDexUpgrade(vault, admin);
    }

    function upgradeOneClick_Base() public {
        {
            string memory root = vm.projectRoot();
            string memory path = string.concat(root, "/script/current_investors.json");
            string memory json = vm.readFile(path);
            string[] memory keys = vm.parseJsonKeys(json, ".");
            bytes memory data = vm.parseJson(json, string.concat(".", keys[0]));
            AccountsToMigrate[] memory fromJson = abi.decode(data, (AccountsToMigrate[]));

            for (uint256 i = 0; i < fromJson.length; i++) {
                AccountsToMigrate memory item = fromJson[i];

                if (item.id == 45) {
                    console.log("investor_address", item.investor_address);
                    accountsToMigrate.push(item.investor_address);
                }
            }
            console.log("\naccountsToMigrate", accountsToMigrate.length);
        }

        // ADMIN ACCOUNT IS 0xE1066Cb8c18c408525Ca98C7B0ad70be8D5608CB
        address admin = vm.rememberKey(vm.envUint("ADMIN_PK"));
        // ADMIN473 ACCOUNT IS 0x4739fEFA6949fcB90F56a9D6defb3e8d3Fd282F6
        address admin473 = vm.rememberKey(vm.envUint("ADMIN473_PK"));
        console.log("\nREADED ADMIN ADDRESS:", admin, "\n");
        console.log("READED FEE PROVIDER OWNER ADDRESS:", admin473, "\n");

        // upgrade 0x0655e391e0c6e0b8cBe8C2747Ae15c67c37583B9
        // Base Index USDC

        OneClickIndex oneClick = OneClickIndex(0x0655e391e0c6e0b8cBe8C2747Ae15c67c37583B9);
        console.log("\nUpgrading Base Index USDC\n  ", address(oneClick), "\n");
        (ProxyAdmin proxyAdmin, address admin_) = _getProxyAdmin(address(oneClick));
        console.log("ADMIN ADDRESS:", admin_, "\n");
        if (admin_ != admin) {
            revert("ADMIN ADDRESS MISMATCH");
        }

        FeeProvider feeProvider = FeeProvider(0x815E9a686467Ec2CB7a7C185c565731730A5aF7e);
        (ProxyAdmin feeProviderProxyAdmin, address feeProviderAdmin) = _getProxyAdmin(address(feeProvider));
        console.log("feeProviderAdmin", feeProviderAdmin);
        console.log("feeProvider owner", feeProvider.owner());

        vm.startBroadcast(admin);
        IFeeProvider feeProviderImpl = new FeeProvider(feePrecision);
        console.log("\n  new impl FeeProvider", address(feeProviderImpl));
        feeProviderProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(feeProvider)), address(feeProviderImpl), new bytes(0)
        );
        vm.stopBroadcast();

        vm.startBroadcast(admin473);
        _updateFeeProviderWhitelisted(feeProvider, address(oneClick));
        vm.stopBroadcast();

        vm.assertTrue(feeProvider.whitelistedContracts(address(oneClick)));

        vm.startBroadcast(admin);
        OneClickIndex oneClick_newImpl = new OneClickIndex(IERC20Metadata(oneClick.asset()), feeProvider, feeRecipient);
        console.log("\n  new impl", address(oneClick_newImpl));
        {
            bytes memory data = abi.encodeWithSignature("initialize_upgradeStorage(address[])", accountsToMigrate);
            proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(oneClick)), address(oneClick_newImpl), data);
        }
        vm.stopBroadcast();
        _checkBaseVaultUpgrade(BaseVault(address(oneClick)), admin);
        console.log("totalLendingShares", oneClick.totalLendingShares());
        {
            address[] memory lendingPoolAddresses = oneClick.getPools();
            console.log("lendingShares1", oneClick.lendingShares(lendingPoolAddresses[0]));
            console.log("lendingShares2", oneClick.lendingShares(lendingPoolAddresses[1]));
            console.log("count", oneClick.getLendingPoolCount());
            console.log("maxSlippage", oneClick.maxSlippage());
            if (accountsToMigrate.length > 0) {
                console.log(
                    "\nCheck waterline\n  address:",
                    accountsToMigrate[0],
                    "\n  balance:",
                    oneClick.getWaterline(accountsToMigrate[0])
                );
            }
        }

        console.log("\n==============================================\n");

        // upgrade 0x9cABCb97C0EDF8910B433188480287B8323ee0FA
        // Compound (inside oneClickIndex)

        CompoundVault compound_vault = CompoundVault(0x9cABCb97C0EDF8910B433188480287B8323ee0FA);
        console.log("\nUpgrading Compound (inside oneClickIndex)\n  ", address(compound_vault), "\n");
        (proxyAdmin, admin_) = _getProxyAdmin(address(compound_vault));
        console.log("ADMIN ADDRESS:", admin_, "\n");

        feeProvider = FeeProvider(0xd549D76E43c4B0Fb5282590361F9c035F20402E9);
        (feeProviderProxyAdmin, feeProviderAdmin) = _getProxyAdmin(address(feeProvider));
        console.log("feeProviderAdmin", feeProviderAdmin);
        console.log("feeProvider owner", feeProvider.owner());

        vm.startBroadcast(admin);
        feeProviderImpl = new FeeProvider(feePrecision);
        console.log("\n  new impl FeeProvider", address(feeProviderImpl));
        feeProviderProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(feeProvider)), address(feeProviderImpl), new bytes(0)
        );
        vm.stopBroadcast();

        vm.startBroadcast(admin473);
        _updateFeeProviderWhitelisted(feeProvider, address(compound_vault));
        vm.stopBroadcast();

        vm.assertTrue(feeProvider.whitelistedContracts(address(compound_vault)));

        vm.startBroadcast(admin);
        CompoundVault compound_newImpl =
            new CompoundVault(IERC20Metadata(compound_vault.asset()), compound_vault.pool(), feeProvider, feeRecipient);
        console.log("\n  new impl", address(compound_newImpl));
        {
            address[] memory accountsToMigrate_ = new address[](1);
            accountsToMigrate_[0] = address(oneClick);
            proxyAdmin.upgradeAndCall(
                ITransparentUpgradeableProxy(address(compound_vault)),
                address(compound_newImpl),
                abi.encodeWithSignature("initialize_insideOneClickIndex(address[])", accountsToMigrate_)
            );
        }
        vm.stopBroadcast();
        _checkBaseVaultUpgrade(BaseVault(address(compound_vault)), admin);

        console.log("\n==============================================\n");

        // upgrade 0x9fe836AB706Aec38fc4e1CaB758011fC59E730Bc
        // AAVE (inside oneClickIndex)

        AaveVault aave_vault = AaveVault(0x9fe836AB706Aec38fc4e1CaB758011fC59E730Bc);
        console.log("\nUpgrading AAVE (inside oneClickIndex)\n  ", address(aave_vault), "\n");
        (proxyAdmin, admin_) = _getProxyAdmin(address(aave_vault));
        console.log("ADMIN ADDRESS:", admin_, "\n");

        feeProvider = FeeProvider(0xB1246DbE910376954d15ebf89abCA3007002Af38);
        (feeProviderProxyAdmin, feeProviderAdmin) = _getProxyAdmin(address(feeProvider));
        console.log("feeProviderAdmin", feeProviderAdmin);
        console.log("feeProvider owner", feeProvider.owner());

        vm.startBroadcast(admin);
        feeProviderImpl = new FeeProvider(feePrecision);
        console.log("\n  new impl FeeProvider", address(feeProviderImpl));
        feeProviderProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(feeProvider)), address(feeProviderImpl), new bytes(0)
        );
        vm.stopBroadcast();

        vm.startBroadcast(admin473);
        _updateFeeProviderWhitelisted(feeProvider, address(aave_vault));
        vm.stopBroadcast();

        vm.assertTrue(feeProvider.whitelistedContracts(address(aave_vault)));

        vm.startBroadcast(admin);
        AaveVault aave_newImpl =
            new AaveVault(IERC20Metadata(aave_vault.asset()), aave_vault.pool(), feeProvider, feeRecipient);
        console.log("\n  new impl", address(aave_newImpl));
        {
            address[] memory accountsToMigrate_ = new address[](1);
            accountsToMigrate_[0] = address(oneClick);
            proxyAdmin.upgradeAndCall(
                ITransparentUpgradeableProxy(address(aave_vault)),
                address(aave_newImpl),
                abi.encodeWithSignature("initialize_insideOneClickIndex(address[])", accountsToMigrate_)
            );
        }
        vm.stopBroadcast();
        _checkBaseVaultUpgrade(BaseVault(address(aave_vault)), admin);
    }

    function upgradeOneClick_Blast() public {
        vm.createSelectFork("blast");

        {
            string memory root = vm.projectRoot();
            string memory path = string.concat(root, "/script/current_investors.json");
            string memory json = vm.readFile(path);
            string[] memory keys = vm.parseJsonKeys(json, ".");
            bytes memory data = vm.parseJson(json, string.concat(".", keys[0]));
            AccountsToMigrate[] memory fromJson = abi.decode(data, (AccountsToMigrate[]));

            for (uint256 i = 0; i < fromJson.length; i++) {
                AccountsToMigrate memory item = fromJson[i];

                if (item.id == 36) {
                    console.log("investor_address", item.investor_address);
                    accountsToMigrate.push(item.investor_address);
                }
            }
            console.log("\naccountsToMigrate", accountsToMigrate.length);
        }

        address admin = vm.rememberKey(vm.envUint("ADMIN_PK"));
        address admin473 = vm.rememberKey(vm.envUint("ADMIN473_PK"));
        console.log("\nREADED ADMIN ADDRESS:", admin, "\n");
        console.log("READED FEE PROVIDER OWNER ADDRESS:", admin473, "\n");

        // upgrade 0xb3E2099b135B12139C4eB774F84a5808FB25c67d
        // Blast Index USDB

        OneClickIndex oneClick = OneClickIndex(0xb3E2099b135B12139C4eB774F84a5808FB25c67d);
        console.log("\nUpgrading Blast Index USDB\n  ", address(oneClick), "\n");
        (ProxyAdmin proxyAdmin, address admin_) = _getProxyAdmin(address(oneClick));
        console.log("ADMIN ADDRESS:", admin_, "\n");
        if (admin_ != admin) {
            revert("ADMIN ADDRESS MISMATCH");
        }

        FeeProvider feeProvider = FeeProvider(0x3049f8Eee32eB335f98CF3EF69987e4Efd192647);
        (ProxyAdmin feeProviderProxyAdmin, address feeProviderAdmin) = _getProxyAdmin(address(feeProvider));
        console.log("feeProviderAdmin", feeProviderAdmin);
        console.log("feeProvider owner", feeProvider.owner());
        if (feeProviderAdmin != admin473) {
            revert("ADMIN473 ADDRESS MISMATCH");
        }

        vm.startBroadcast(admin473);
        FeeProvider feeProviderImpl = new FeeProvider(feePrecision);
        console.log("\n  new impl FeeProvider", address(feeProviderImpl));
        feeProviderProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(feeProvider)), address(feeProviderImpl), new bytes(0)
        );
        _updateFeeProviderWhitelisted(feeProvider, address(oneClick));
        vm.stopBroadcast();
        vm.assertTrue(feeProvider.whitelistedContracts(address(oneClick)));

        vm.startBroadcast(admin);
        OneClickIndex oneClick_newImpl = new OneClickIndex(IERC20Metadata(oneClick.asset()), feeProvider, feeRecipient);
        console.log("\n  new impl", address(oneClick_newImpl));
        {
            bytes memory data = abi.encodeWithSignature("initialize_upgradeStorage(address[])", accountsToMigrate);
            proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(oneClick)), address(oneClick_newImpl), data);
        }
        vm.stopBroadcast();
        _checkBaseVaultUpgrade(BaseVault(address(oneClick)), admin);
        {
            address[] memory lendingPoolAddresses = oneClick.getPools();
            console.log("lendingShares1", oneClick.lendingShares(lendingPoolAddresses[0]));
            console.log("lendingShares2", oneClick.lendingShares(lendingPoolAddresses[1]));
            console.log("lendingShares3", oneClick.lendingShares(lendingPoolAddresses[2]));
            console.log("lendingShares4", oneClick.lendingShares(lendingPoolAddresses[3]));
            console.log("pool4", lendingPoolAddresses[3]);
            console.log("pool3", lendingPoolAddresses[2]);
            console.log("pool2", lendingPoolAddresses[1]);
            console.log("pool1", lendingPoolAddresses[0]);
            console.log("count", oneClick.getLendingPoolCount());
            console.log("maxSlippage", oneClick.maxSlippage());
            if (accountsToMigrate.length > 0) {
                console.log(
                    "\nCheck waterline\n  address:",
                    accountsToMigrate[0],
                    "\n  balance:",
                    oneClick.getWaterline(accountsToMigrate[10])
                );
            }
        }

        console.log("\n==============================================\n");

        // upgrade 0x346d73AcdE2a319B17CECb5bf95C49107598dF34
        // Zerolend (AAVE inside oneClickIndex)

        AaveVault aave_vault = AaveVault(0x346d73AcdE2a319B17CECb5bf95C49107598dF34);
        console.log("\nUpgrading Zerolend (AAVE inside oneClickIndex)\n  ", address(aave_vault), "\n");
        (proxyAdmin, admin_) = _getProxyAdmin(address(aave_vault));
        console.log("ADMIN ADDRESS:", admin_, "\n");

        feeProvider = FeeProvider(0x2E395062497dc014Be9c55E03174e89bA4Afec30);
        (feeProviderProxyAdmin, feeProviderAdmin) = _getProxyAdmin(address(feeProvider));
        console.log("feeProviderAdmin", feeProviderAdmin);
        console.log("feeProvider owner", feeProvider.owner());

        vm.startBroadcast(admin473);
        feeProviderImpl = new FeeProvider(feePrecision);
        console.log("\n  new impl FeeProvider", address(feeProviderImpl));
        feeProviderProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(feeProvider)), address(feeProviderImpl), new bytes(0)
        );
        _updateFeeProviderWhitelisted(feeProvider, address(aave_vault));
        vm.assertTrue(feeProvider.whitelistedContracts(address(aave_vault)));
        AaveVault aave_newImpl =
            new AaveVault(IERC20Metadata(aave_vault.asset()), aave_vault.pool(), feeProvider, feeRecipient);
        console.log("\n  new impl", address(aave_newImpl));
        {
            address[] memory accountsToMigrate_ = new address[](1);
            accountsToMigrate_[0] = address(oneClick);
            proxyAdmin.upgradeAndCall(
                ITransparentUpgradeableProxy(address(aave_vault)),
                address(aave_newImpl),
                abi.encodeWithSignature("initialize_insideOneClickIndex(address[])", accountsToMigrate_)
            );
        }
        vm.stopBroadcast();
        _checkBaseVaultUpgrade(BaseVault(address(aave_vault)), admin);

        console.log("\n==============================================\n");

        // upgrade 0xe394Ab698279502577A071A37022430af068Bb0c
        // INIT (inside oneClickIndex)
        // WARNING: ZERO lending shares/totalSupply
        {
            InitVault init_vault = InitVault(0xe394Ab698279502577A071A37022430af068Bb0c);
            console.log("\nUpgrading INIT (inside oneClickIndex)\n  ", address(init_vault), "\n");
            (proxyAdmin, admin_) = _getProxyAdmin(address(init_vault));
            console.log("ADMIN ADDRESS:", admin_, "\n");

            feeProvider = FeeProvider(0x3049f8Eee32eB335f98CF3EF69987e4Efd192647);
            (feeProviderProxyAdmin, feeProviderAdmin) = _getProxyAdmin(address(feeProvider));
            console.log("feeProviderAdmin", feeProviderAdmin);
            console.log("feeProvider owner", feeProvider.owner());

            vm.startBroadcast(admin473);
            feeProviderImpl = new FeeProvider(feePrecision);
            console.log("\n  new impl FeeProvider", address(feeProviderImpl));
            feeProviderProxyAdmin.upgradeAndCall(
                ITransparentUpgradeableProxy(address(feeProvider)), address(feeProviderImpl), new bytes(0)
            );
            _updateFeeProviderWhitelisted(feeProvider, address(init_vault));
            {
                InitVault init_newImpl =
                    new InitVault(IERC20Metadata(init_vault.asset()), init_vault.pool(), feeProvider, feeRecipient);
                console.log("\n  new impl", address(init_newImpl));

                proxyAdmin.upgradeAndCall(
                    ITransparentUpgradeableProxy(address(init_vault)),
                    address(init_newImpl),
                    abi.encodeWithSignature("initialize_insideOneClickIndex(address[])", new address[](0))
                );
            }
            vm.stopBroadcast();
            _checkBaseVaultUpgrade(BaseVault(address(init_vault)), admin);
        }
        console.log("\n==============================================\n");

        // upgrade 0x3fE57b59cb9f3DdE249745E6D562aA8841BC1b2D
        // Juice (inside oneClickIndex)
        {
            JuiceVault juice_vault = JuiceVault(0x3fE57b59cb9f3DdE249745E6D562aA8841BC1b2D);
            console.log("\nUpgrading Juice (inside oneClickIndex)\n  ", address(juice_vault), "\n");
            (proxyAdmin, admin_) = _getProxyAdmin(address(juice_vault));
            console.log("ADMIN ADDRESS:", admin_, "\n");

            feeProvider = FeeProvider(0xC899EfA7863d755A6186a2EFa06a8Fc7e8c5BA42);
            (feeProviderProxyAdmin, feeProviderAdmin) = _getProxyAdmin(address(feeProvider));
            console.log("feeProviderAdmin", feeProviderAdmin);
            console.log("feeProvider owner", feeProvider.owner());

            vm.startBroadcast(admin473);
            feeProviderImpl = new FeeProvider(feePrecision);
            console.log("\n  new impl FeeProvider", address(feeProviderImpl));
            feeProviderProxyAdmin.upgradeAndCall(
                ITransparentUpgradeableProxy(address(feeProvider)), address(feeProviderImpl), new bytes(0)
            );
            _updateFeeProviderWhitelisted(feeProvider, address(juice_vault));

            {
                JuiceVault juice_newImpl =
                    new JuiceVault(IERC20Metadata(juice_vault.asset()), juice_vault.pool(), feeProvider, feeRecipient);
                console.log("\n  new impl", address(juice_newImpl));
                address[] memory accountsToMigrate_ = new address[](1);
                accountsToMigrate_[0] = address(oneClick);
                proxyAdmin.upgradeAndCall(
                    ITransparentUpgradeableProxy(address(juice_vault)),
                    address(juice_newImpl),
                    abi.encodeWithSignature("initialize_insideOneClickIndex(address[])", accountsToMigrate_)
                );
            }
            vm.stopBroadcast();
            _checkBaseVaultUpgrade(BaseVault(address(juice_vault)), admin);
        }
        console.log("\n==============================================\n");

        // upgrade 0x0c0a0CcC5685974B8ab411E44e2fC70F07ce4E3d
        // Orbit (inside oneClickIndex)
        // WARNING: ZERO lending shares/totalSupply

        CompoundVault orbit_vault = CompoundVault(0x0c0a0CcC5685974B8ab411E44e2fC70F07ce4E3d);
        console.log("\nUpgrading Orbit (inside oneClickIndex)\n  ", address(orbit_vault), "\n");
        (proxyAdmin, admin_) = _getProxyAdmin(address(orbit_vault));
        console.log("ADMIN ADDRESS:", admin_, "\n");

        feeProvider = FeeProvider(0xf01e01cb6E20dc9E98380bAaAA899eed18A95d36);
        (feeProviderProxyAdmin, feeProviderAdmin) = _getProxyAdmin(address(feeProvider));
        console.log("feeProviderAdmin", feeProviderAdmin);
        console.log("feeProvider owner", feeProvider.owner());

        vm.startBroadcast(admin473);
        feeProviderImpl = new FeeProvider(feePrecision);
        console.log("\n  new impl FeeProvider", address(feeProviderImpl));
        feeProviderProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(feeProvider)), address(feeProviderImpl), new bytes(0)
        );
        _updateFeeProviderWhitelisted(feeProvider, address(orbit_vault));
        vm.assertTrue(feeProvider.whitelistedContracts(address(orbit_vault)));
        CompoundVault orbit_newImpl =
            new CompoundVault(IERC20Metadata(orbit_vault.asset()), orbit_vault.pool(), feeProvider, feeRecipient);
        console.log("\n  new impl", address(orbit_newImpl));
        {
            address[] memory accountsToMigrate_ = new address[](1);
            accountsToMigrate_[0] = address(0x4739fEFA6949fcB90F56a9D6defb3e8d3Fd282F6);
            proxyAdmin.upgradeAndCall(
                ITransparentUpgradeableProxy(address(orbit_vault)),
                address(orbit_newImpl),
                abi.encodeWithSignature("initialize_insideOneClickIndex(address[])", accountsToMigrate_)
            );
        }
        vm.stopBroadcast();
        _checkBaseVaultUpgrade(BaseVault(address(orbit_vault)), admin);
    }

    function _checkBaseVaultUpgrade(BaseVault vault, address admin_) internal view {
        console.log("\nVERIFYING BASEVAULT UPGRADE:");
        console.log(" totalSupply", vault.totalSupply());
        console.log(" totalAssets", vault.totalAssets());
        console.log(" hasAdminRole", vault.hasRole(DEFAULT_ADMIN_ROLE, admin_));
        console.log(" hasManagerRole", vault.hasRole(MANAGER_ROLE, admin_));
    }

    function _checkDexUpgrade(BaseDexVault vault, address admin_) internal view {
        _checkBaseVaultUpgrade(BaseVault(address(vault)), admin_);
        console.log("\nVERIFYING DEX UPGRADE:");
        console.log(" tickLower", vault.tickLower());
        console.log(" tickUpper", vault.tickUpper());
        console.log(" sqrtPriceLower", vault.sqrtPriceLower());
        console.log(" sqrtPriceUpper", vault.sqrtPriceUpper());
        console.log(" positionTokenId", vault.positionTokenId());
    }
}
