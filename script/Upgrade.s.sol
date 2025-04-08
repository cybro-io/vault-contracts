// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {IAavePool} from "../src/interfaces/aave/IPool.sol";
import {AaveVault, IERC20Metadata} from "../src/vaults/AaveVault.sol";
import {InitVault} from "../src/vaults/InitVault.sol";
import {CompoundVaultETH} from "../src/vaults/CompoundVaultEth.sol";
import {CompoundVault} from "../src/vaults/CompoundVaultErc20.sol";
import {JuiceVault} from "../src/vaults/JuiceVault.sol";
import {YieldStakingVault} from "../src/vaults/YieldStakingVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CEth} from "../src/interfaces/compound/IcETH.sol";
import {CErc20} from "../src/interfaces/compound/IcERC.sol";
import {IJuicePool} from "../src/interfaces/juice/IJuicePool.sol";
import {IYieldStaking} from "../src/interfaces/blastup/IYieldStacking.sol";
import {WETHMock, ERC20Mock} from "../src/mocks/WETHMock.sol";
import {IInitCore} from "../src/interfaces/init/IInitCore.sol";
import {IInitLendingPool} from "../src/interfaces/init/IInitLendingPool.sol";
import {OneClickIndex} from "../src/OneClickIndex.sol";
import {IStargatePool} from "../src/interfaces/stargate/IStargatePool.sol";
import {IStargateStaking} from "../src/interfaces/stargate/IStargateStaking.sol";
import {StargateVault} from "../src/vaults/StargateVault.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {BaseVault} from "../src/BaseVault.sol";
import {
    TransparentUpgradeableProxy,
    ProxyAdmin
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {FeeProvider, IFeeProvider} from "../src/FeeProvider.sol";
import {IChainlinkOracle} from "../src/interfaces/IChainlinkOracle.sol";
import {DeployUtils, SparkVault} from "../test/DeployUtils.sol";
import {SeasonalVault} from "../src/SeasonalVault.sol";
import {BufferVault} from "../src/vaults/BufferVault.sol";
import {GammaAlgebraVault} from "../src/vaults/GammaAlgebraVault.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {ProxyAdmin, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {BlasterSwapV2Vault} from "../src/dex/BlasterSwapV2Vault.sol";
import {BaseDexVaultV2} from "../src/forUpgrade/BaseDexVaultV2.sol";
import {AlgebraVaultV2} from "../src/forUpgrade/AlgebraVaultV2.sol";
import {AlgebraVault} from "../src/dex/AlgebraVault.sol";
import {CompoundVaultETHV2} from "../src/forUpgrade/CompoundVaultEthV2.sol";
import {CompoundVaultV2} from "../src/forUpgrade/CompoundVaultErc20V2.sol";
import {YieldStakingVaultV2} from "../src/forUpgrade/YieldStakingVaultV2.sol";
import {JuiceVaultV2} from "../src/forUpgrade/JuiceVaultV2.sol";
import {BlasterSwapV2VaultV2} from "../src/forUpgrade/BlasterSwapV2VaultV2.sol";
import {OneClickIndexV2} from "../src/forUpgrade/OneClickIndexV2.sol";
import {AaveVaultV2_InsideOneClickIndex} from "../src/forUpgrade/AaveVaultV2_OneClickBase.sol";
import {CompoundVaultV2_InsideOneClickIndex} from "../src/forUpgrade/CompoundVaultErc20V2_OneClickBase.sol";
import {InitVaultV2} from "../src/forUpgrade/InitVaultV2.sol";
import {JuiceVaultV2_InsideOneClickIndex} from "../src/forUpgrade/JuiceVaultV2_OneClick.sol";
import {CompoundVaultV2_Orbit} from "../src/forUpgrade/CompoundVaultErc20V2_Orbit.sol";

contract Upgrade is Script {
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

    function _getProxyAdmin(address vault) internal view returns (ProxyAdmin proxyAdmin, address admin) {
        proxyAdmin = ProxyAdmin(address(uint160(uint256(vm.load(address(vault), ERC1967Utils.ADMIN_SLOT)))));
        admin = proxyAdmin.owner();
    }

    function upgradeBlast() public {
        vm.createSelectFork("blast");
        // upgrade 0x3DB2bD838c2bEd431DCFA012c3419b7e94D78456
        // YieldStakingVault CYBRO WETH

        YieldStakingVaultV2 vault = YieldStakingVaultV2(0x3DB2bD838c2bEd431DCFA012c3419b7e94D78456);
        console.log("Upgrading YieldStakingVault CYBRO WETH\n  ", address(vault), "\n");
        (ProxyAdmin proxyAdmin, address admin) = _getProxyAdmin(address(vault));

        // vm.startBroadcast();
        vm.startPrank(admin);
        IFeeProvider feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        _updateFeeProviderWhitelisted(feeProvider, address(vault));
        YieldStakingVaultV2 newImpl =
            new YieldStakingVaultV2(IERC20Metadata(vault.asset()), vault.staking(), feeProvider, feeRecipient);
        console.log("\n  new impl", address(newImpl));
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(vault)), address(newImpl), new bytes(0));
        vault.initialize();
        vm.stopPrank();
        _checkBaseVaultUpgrade(BaseVault(address(vault)), admin);
        // vm.stopBroadcast();

        console.log("\n==============================================\n");

        // upgrade 0xDB5E7d5AC4E09206fED80efD7AbD9976357e1c03
        // YieldStakingVault CYBRO USDB

        vault = YieldStakingVaultV2(0xDB5E7d5AC4E09206fED80efD7AbD9976357e1c03);
        console.log("Upgrading YieldStakingVault CYBRO USDB\n  ", address(vault), "\n");
        (proxyAdmin, admin) = _getProxyAdmin(address(vault));
        // vm.startBroadcast();
        vm.startPrank(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        _updateFeeProviderWhitelisted(feeProvider, address(vault));
        newImpl = new YieldStakingVaultV2(IERC20Metadata(vault.asset()), vault.staking(), feeProvider, feeRecipient);
        console.log("\n  new impl", address(newImpl));
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(vault)), address(newImpl), new bytes(0));
        vault.initialize();
        vm.stopPrank();
        _checkBaseVaultUpgrade(BaseVault(address(vault)), admin);
        // vm.stopBroadcast();

        console.log("\n==============================================\n");

        // upgrade 0xBFb18Eda8961ee33e38678caf2BcEB2D23aEdfea
        // BlasterSwap V2 USDB/WETH

        BlasterSwapV2VaultV2 blaster_vault = BlasterSwapV2VaultV2(0xBFb18Eda8961ee33e38678caf2BcEB2D23aEdfea);
        console.log("Upgrading BlasterSwap V2 USDB/WETH\n  ", address(blaster_vault), "\n");
        (proxyAdmin, admin) = _getProxyAdmin(address(blaster_vault));
        // vm.startBroadcast();
        vm.startPrank(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        _updateFeeProviderWhitelisted(feeProvider, address(blaster_vault));
        BlasterSwapV2VaultV2 blaster_newImpl = new BlasterSwapV2VaultV2(
            payable(address(blaster_vault.router())),
            blaster_vault.token0(),
            blaster_vault.token1(),
            IERC20Metadata(blaster_vault.token0()), // USDB
            feeProvider,
            feeRecipient
        );
        console.log("\n  new impl", address(blaster_newImpl));
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(blaster_vault)), address(blaster_newImpl), new bytes(0)
        );
        blaster_vault.initialize();
        vm.stopPrank();
        _checkBaseVaultUpgrade(BaseVault(address(blaster_vault)), admin);
        // vm.stopBroadcast();

        console.log("\n==============================================\n");

        // upgrade 0x18E22f3f9a9652ee3A667d78911baC55bC2249Af
        // Juice WETH Lending

        JuiceVaultV2 juice_vault = JuiceVaultV2(0x18E22f3f9a9652ee3A667d78911baC55bC2249Af);
        console.log("Upgrading Juice WETH Lending\n  ", address(juice_vault), "\n");
        (proxyAdmin, admin) = _getProxyAdmin(address(juice_vault));
        // vm.startBroadcast();
        vm.startPrank(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        _updateFeeProviderWhitelisted(feeProvider, address(juice_vault));
        JuiceVaultV2 juice_newImpl =
            new JuiceVaultV2(IERC20Metadata(juice_vault.asset()), juice_vault.pool(), feeProvider, feeRecipient);
        console.log("\n  new impl", address(juice_newImpl));
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(juice_vault)), address(juice_newImpl), new bytes(0)
        );
        juice_vault.initialize();
        vm.stopPrank();
        _checkBaseVaultUpgrade(BaseVault(address(juice_vault)), admin);
        // vm.stopBroadcast();

        console.log("\n==============================================\n");

        // upgrade 0xD58826d2C0bAbf1A60d8b508160b52E9C19AFf07
        // Juice USDB Lending

        juice_vault = JuiceVaultV2(0xD58826d2C0bAbf1A60d8b508160b52E9C19AFf07);
        console.log("Upgrading Juice USDB Lending\n  ", address(juice_vault), "\n");
        (proxyAdmin, admin) = _getProxyAdmin(address(juice_vault));
        // vm.startBroadcast();
        vm.startPrank(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        _updateFeeProviderWhitelisted(feeProvider, address(juice_vault));
        juice_newImpl =
            new JuiceVaultV2(IERC20Metadata(juice_vault.asset()), juice_vault.pool(), feeProvider, feeRecipient);
        console.log("\n  new impl", address(juice_newImpl));
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(juice_vault)), address(juice_newImpl), new bytes(0)
        );
        juice_vault.initialize();
        vm.stopPrank();
        _checkBaseVaultUpgrade(BaseVault(address(juice_vault)), admin);
        // vm.stopBroadcast();

        console.log("\n==============================================\n");

        // upgrade 0x567103a40C408B2B8f766016C57A092A180397a1
        // Aso Finance USDB Lending (Compound)

        CompoundVaultV2 compound_vault = CompoundVaultV2(0x567103a40C408B2B8f766016C57A092A180397a1);
        console.log("Upgrading Aso Finance USDB Lending (Compound)\n  ", address(compound_vault), "\n");
        (proxyAdmin, admin) = _getProxyAdmin(address(compound_vault));
        // vm.startBroadcast();
        vm.startPrank(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        _updateFeeProviderWhitelisted(feeProvider, address(compound_vault));
        CompoundVaultV2 compound_newImpl = new CompoundVaultV2(
            IERC20Metadata(compound_vault.asset()), compound_vault.pool(), feeProvider, feeRecipient
        );
        console.log("\n  new impl", address(compound_newImpl));
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(compound_vault)), address(compound_newImpl), new bytes(0)
        );
        compound_vault.initialize();
        vm.stopPrank();
        _checkBaseVaultUpgrade(BaseVault(address(compound_vault)), admin);
        // vm.stopBroadcast();

        console.log("\n==============================================\n");

        // upgrade 0x9cc62EF691E869C05FD2eC41839889d4E74c3a3f
        // Aso Finance WETH Lending (CompoundETH)

        CompoundVaultETHV2 compoundETH_vault = CompoundVaultETHV2(payable(0x9cc62EF691E869C05FD2eC41839889d4E74c3a3f));
        console.log("Upgrading Aso Finance WETH Lending (CompoundETH)\n  ", address(compoundETH_vault), "\n");
        (proxyAdmin, admin) = _getProxyAdmin(address(compoundETH_vault));
        // vm.startBroadcast();
        vm.startPrank(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        _updateFeeProviderWhitelisted(feeProvider, address(compoundETH_vault));
        CompoundVaultETHV2 compoundETH_newImpl = new CompoundVaultETHV2(
            IERC20Metadata(compoundETH_vault.asset()), compoundETH_vault.pool(), feeProvider, feeRecipient
        );
        console.log("\n  new impl", address(compoundETH_newImpl));
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(compoundETH_vault)), address(compoundETH_newImpl), new bytes(0)
        );
        compoundETH_vault.initialize();
        vm.stopPrank();
        _checkBaseVaultUpgrade(BaseVault(address(compoundETH_vault)), admin);
        // vm.stopBroadcast();

        console.log("\n==============================================\n");

        // upgrade 0xDCCDe9C6800BeA86E2e91cF54a870BA3Ff6FAF9f
        // Aso Finance WeETH Lending (Compound)

        compound_vault = CompoundVaultV2(0xDCCDe9C6800BeA86E2e91cF54a870BA3Ff6FAF9f);
        console.log("Upgrading Aso Finance WeETH Lending (Compound)\n  ", address(compound_vault), "\n");
        (proxyAdmin, admin) = _getProxyAdmin(address(compound_vault));
        // vm.startBroadcast();
        vm.startPrank(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        _updateFeeProviderWhitelisted(feeProvider, address(compound_vault));
        compound_newImpl = new CompoundVaultV2(
            IERC20Metadata(compound_vault.asset()), compound_vault.pool(), feeProvider, feeRecipient
        );
        console.log("\n  new impl", address(compound_newImpl));
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(compound_vault)), address(compound_newImpl), new bytes(0)
        );
        compound_vault.initialize();
        vm.stopPrank();
        _checkBaseVaultUpgrade(BaseVault(address(compound_vault)), admin);
        // vm.stopBroadcast();

        console.log("\n==============================================\n");

        // upgrade 0x0667ac28015ED7146f19B2d218f81218abf32951
        // Aso Finance WBTC Lending (Compound)

        compound_vault = CompoundVaultV2(0x0667ac28015ED7146f19B2d218f81218abf32951);
        console.log("Upgrading Aso Finance WBTC Lending (Compound)\n  ", address(compound_vault), "\n");
        (proxyAdmin, admin) = _getProxyAdmin(address(compound_vault));
        // vm.startBroadcast();
        vm.startPrank(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        _updateFeeProviderWhitelisted(feeProvider, address(compound_vault));
        compound_newImpl = new CompoundVaultV2(
            IERC20Metadata(compound_vault.asset()), compound_vault.pool(), feeProvider, feeRecipient
        );
        console.log("\n  new impl", address(compound_newImpl));
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(compound_vault)), address(compound_newImpl), new bytes(0)
        );
        compound_vault.initialize();
        vm.stopPrank();
        _checkBaseVaultUpgrade(BaseVault(address(compound_vault)), admin);
        // vm.stopBroadcast();
    }

    function upgradeDEX() public {
        // upgrade 0xE9041d3483A760c7D5F8762ad407ac526fbe144f
        // BladeSwap USDB/WETH
        vm.createSelectFork("blast");

        AlgebraVaultV2 vault = AlgebraVaultV2(0xE9041d3483A760c7D5F8762ad407ac526fbe144f);
        console.log("\nUpgrading BladeSwap USDB/WETH\n  ", address(vault), "\n");
        (ProxyAdmin proxyAdmin, address admin) = _getProxyAdmin(address(vault));
        // vm.startBroadcast();
        vm.startPrank(admin);
        IFeeProvider feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        _updateFeeProviderWhitelisted(feeProvider, address(vault));
        AlgebraVaultV2 newImpl = new AlgebraVaultV2(
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
            proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(vault)), address(newImpl), new bytes(0));
            vault.initialize(positionTokenId_, tickLower_, tickUpper_, sqrtPriceLower_, sqrtPriceUpper_);
        }

        _checkDexUpgrade(vault, admin);
        vm.stopPrank();
        // vm.stopBroadcast();

        console.log("\n==============================================\n");

        // upgrade 0x370498c028564de4491B8aA2df437fb772a39EC5
        // Fenix Finance Blast/WETH
        vault = AlgebraVaultV2(0x370498c028564de4491B8aA2df437fb772a39EC5);
        console.log("Upgrading Fenix Finance Blast/WETH\n  ", address(vault), "\n");
        (proxyAdmin, admin) = _getProxyAdmin(address(vault));
        vm.startPrank(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        _updateFeeProviderWhitelisted(feeProvider, address(vault));
        newImpl = new AlgebraVaultV2(
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
            proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(vault)), address(newImpl), new bytes(0));
            vault.initialize(positionTokenId_, tickLower_, tickUpper_, sqrtPriceLower_, sqrtPriceUpper_);
        }
        _checkDexUpgrade(vault, admin);
        vm.stopPrank();

        console.log("\n==============================================\n");

        // upgrade 0x66E1BEA0a5a934B96E2d7d54Eddd6580c485521b
        // Fenix Finance WeETH/WETH
        vault = AlgebraVaultV2(0x66E1BEA0a5a934B96E2d7d54Eddd6580c485521b);
        console.log("Upgrading Fenix Finance WeETH/WETH\n  ", address(vault), "\n");
        (proxyAdmin, admin) = _getProxyAdmin(address(vault));
        vm.startPrank(admin);
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        _updateFeeProviderWhitelisted(feeProvider, address(vault));
        newImpl = new AlgebraVaultV2(
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
            proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(vault)), address(newImpl), new bytes(0));
            vault.initialize(positionTokenId_, tickLower_, tickUpper_, sqrtPriceLower_, sqrtPriceUpper_);
        }
        _checkDexUpgrade(vault, admin);
        vm.stopPrank();
    }

    function upgradeOneClick_Base() public {
        vm.createSelectFork("base");

        address[] memory accountsToMigrate = new address[](4);
        accountsToMigrate[0] = address(0x4739fEFA6949fcB90F56a9D6defb3e8d3Fd282F6);
        accountsToMigrate[1] = address(0xc541e3Cdf00d8c8E8a7CfDF5A2387FCbDc3BaF15);
        accountsToMigrate[2] = address(0xf15eb93008eD1D372F491Fde60634B46476e37aF);
        accountsToMigrate[3] = address(0xF1c53df53419b3edAa8339B3CA0c215a69dDDFED);

        // upgrade 0x0655e391e0c6e0b8cBe8C2747Ae15c67c37583B9
        // Base Index USDC

        OneClickIndexV2 vault = OneClickIndexV2(0x0655e391e0c6e0b8cBe8C2747Ae15c67c37583B9);
        console.log("\nUpgrading Base Index USDC\n  ", address(vault), "\n");
        (ProxyAdmin proxyAdmin, address admin) = _getProxyAdmin(address(vault));
        console.log("admin", admin);

        FeeProvider feeProvider = FeeProvider(0x815E9a686467Ec2CB7a7C185c565731730A5aF7e);
        (ProxyAdmin feeProviderProxyAdmin, address feeProviderAdmin) = _getProxyAdmin(address(feeProvider));
        console.log("feeProviderAdmin", feeProviderAdmin);
        console.log("feeProvider owner", feeProvider.owner());

        vm.startPrank(admin);
        IFeeProvider feeProviderImpl = new FeeProvider(feePrecision);
        console.log("\n  new impl FeeProvider", address(feeProviderImpl));
        feeProviderProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(feeProvider)), address(feeProviderImpl), new bytes(0)
        );
        vm.stopPrank();
        vm.startPrank(feeProvider.owner());
        _updateFeeProviderWhitelisted(feeProvider, address(vault));
        vm.stopPrank();

        vm.startPrank(admin);
        OneClickIndexV2 newImpl = new OneClickIndexV2(IERC20Metadata(vault.asset()), feeProvider, feeRecipient);
        console.log("\n  new impl", address(newImpl));
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(vault)), address(newImpl), new bytes(0));
        vault.initialize(accountsToMigrate);
        vm.stopPrank();
        _checkBaseVaultUpgrade(BaseVault(address(vault)), admin);
        console.log("totalLendingShares", vault.totalLendingShares());
        {
            address[] memory lendingPoolAddresses = vault.getPools();
            console.log("lendingShares1", vault.lendingShares(lendingPoolAddresses[0]));
            console.log("lendingShares2", vault.lendingShares(lendingPoolAddresses[1]));
            console.log("count", vault.getLendingPoolCount());
            console.log("maxSlippage", vault.maxSlippage());
        }

        console.log("\n==============================================\n");

        // upgrade 0x9cABCb97C0EDF8910B433188480287B8323ee0FA
        // Compound (inside oneClickIndex)

        CompoundVaultV2_InsideOneClickIndex compound_vault =
            CompoundVaultV2_InsideOneClickIndex(0x9cABCb97C0EDF8910B433188480287B8323ee0FA);
        console.log("\nUpgrading Compound (inside oneClickIndex)\n  ", address(compound_vault), "\n");
        (proxyAdmin, admin) = _getProxyAdmin(address(compound_vault));

        feeProvider = FeeProvider(0xd549D76E43c4B0Fb5282590361F9c035F20402E9);
        (feeProviderProxyAdmin, feeProviderAdmin) = _getProxyAdmin(address(feeProvider));
        console.log("feeProviderAdmin", feeProviderAdmin);
        console.log("feeProvider owner", feeProvider.owner());
        vm.startPrank(admin);
        feeProviderImpl = new FeeProvider(feePrecision);
        console.log("\n  new impl FeeProvider", address(feeProviderImpl));
        feeProviderProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(feeProvider)), address(feeProviderImpl), new bytes(0)
        );
        vm.stopPrank();
        vm.startPrank(feeProvider.owner());
        _updateFeeProviderWhitelisted(feeProvider, address(vault));
        vm.stopPrank();

        vm.startPrank(admin);
        CompoundVaultV2_InsideOneClickIndex compound_newImpl = new CompoundVaultV2_InsideOneClickIndex(
            IERC20Metadata(compound_vault.asset()), compound_vault.pool(), feeProvider, feeRecipient
        );
        console.log("\n  new impl", address(compound_newImpl));
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(compound_vault)), address(compound_newImpl), new bytes(0)
        );
        compound_vault.initialize();
        vm.stopPrank();
        _checkBaseVaultUpgrade(BaseVault(address(compound_vault)), admin);

        console.log("\n==============================================\n");

        // upgrade 0x9fe836AB706Aec38fc4e1CaB758011fC59E730Bc
        // AAVE (inside oneClickIndex)

        AaveVaultV2_InsideOneClickIndex aave_vault =
            AaveVaultV2_InsideOneClickIndex(0x9fe836AB706Aec38fc4e1CaB758011fC59E730Bc);
        console.log("\nUpgrading AAVE (inside oneClickIndex)\n  ", address(aave_vault), "\n");
        (proxyAdmin, admin) = _getProxyAdmin(address(aave_vault));

        feeProvider = FeeProvider(0xB1246DbE910376954d15ebf89abCA3007002Af38);
        (feeProviderProxyAdmin, feeProviderAdmin) = _getProxyAdmin(address(feeProvider));
        console.log("feeProviderAdmin", feeProviderAdmin);
        console.log("feeProvider owner", feeProvider.owner());
        vm.startPrank(admin);
        feeProviderImpl = new FeeProvider(feePrecision);
        console.log("\n  new impl FeeProvider", address(feeProviderImpl));
        feeProviderProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(feeProvider)), address(feeProviderImpl), new bytes(0)
        );
        vm.stopPrank();
        vm.startPrank(feeProvider.owner());
        _updateFeeProviderWhitelisted(feeProvider, address(aave_vault));
        vm.stopPrank();

        vm.startPrank(admin);
        AaveVaultV2_InsideOneClickIndex aave_newImpl = new AaveVaultV2_InsideOneClickIndex(
            IERC20Metadata(aave_vault.asset()), aave_vault.pool(), feeProvider, feeRecipient
        );
        console.log("\n  new impl", address(aave_newImpl));
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(aave_vault)), address(aave_newImpl), new bytes(0)
        );
        aave_vault.initialize();
        vm.stopPrank();
        _checkBaseVaultUpgrade(BaseVault(address(aave_vault)), admin);
    }

    function upgradeOneClick_Blast() public {
        vm.createSelectFork("blast");

        address[] memory accountsToMigrate = new address[](65);
        accountsToMigrate[0] = address(0x940efDd4460C954be5D231C25841abf36419f00c);
        accountsToMigrate[1] = address(0x051532f4856E29E37d1792E2Ca2FF36e5E8c86eD);
        accountsToMigrate[2] = address(0x19E1075D6c827B5E88B02a2DC5bD0A760A8A3311);
        accountsToMigrate[3] = address(0x2C58d611a42838d27A5b7d156B102d09FBedC587);
        accountsToMigrate[4] = address(0x194C1EDE68221f6F50976D92dbf629Ba48738e10);
        accountsToMigrate[5] = address(0x4739fEFA6949fcB90F56a9D6defb3e8d3Fd282F6);
        accountsToMigrate[6] = address(0x7a3aF90701d9bFF4EF8A9e16bf326D29C9852fB8);
        accountsToMigrate[7] = address(0x97E0a1f28c9fff064b2DF8aBbF6a5d4dB374a823);
        accountsToMigrate[8] = address(0xd49eaE572aa42F3aBC504a9e2BbB57B1018DD4d6);
        accountsToMigrate[9] = address(0x694Fdbf7d5b14b26BCDBB21FC0Ed8177F54cF060);
        accountsToMigrate[10] = address(0x4dfBfD8a68Ee3445A07bAFc449DF90272a7Fa0C5);
        accountsToMigrate[11] = address(0xD4357Cf9B5466Fe61778BAa2c463FcFBA84cCE19);
        accountsToMigrate[12] = address(0x103678B0196Ede8D8d74881563D52E5e4D6633D7);
        accountsToMigrate[13] = address(0x4893f283ad236f4a8c52cc5bf981Bb81aD36cCe9);
        accountsToMigrate[14] = address(0xd67082e6aA1fC6B1fd8620868A52f668b4A1c00F);
        accountsToMigrate[15] = address(0x6a9E8cEEB414E6Bb7E0049F6218195166FE42C47);
        accountsToMigrate[16] = address(0x70F781037a1155f3B45b2DFFaaD2eb8dBDa6098A);
        accountsToMigrate[17] = address(0xD9BeC26F2a04296e4F4E20e2A3564FB8D1d6884c);
        accountsToMigrate[18] = address(0x7A36E3AF08cF81bA16EE2E66A9aa2EA6CD88Ee27);
        accountsToMigrate[19] = address(0xD6E7E7710eC66c24fa397014372b54079b089FeF);
        accountsToMigrate[20] = address(0x24279678F637FBd8B5d08905734C8AFc5742559C);
        accountsToMigrate[21] = address(0x4F63B0fd5D0380E07616DB549F70f53ee4340f06);
        accountsToMigrate[22] = address(0x145716a68922E6bE62dEbCafacdF1967A2333aD8);
        accountsToMigrate[23] = address(0xecfE355599D683Ca4b23cEAd7612612dD01b158F);
        accountsToMigrate[24] = address(0xE0e20f863ee65A358d20EA0DA43fAe7e45599dD3);
        accountsToMigrate[25] = address(0x081C593876c4B74fa9b8A51Be22d38814369cD85);
        accountsToMigrate[26] = address(0x4dDcec0B1677dBa1dE6980e9f2529995b7EfE2b6);
        accountsToMigrate[27] = address(0x5A8BF7fdc5Be87012203233845DFe208e337529D);
        accountsToMigrate[28] = address(0xd0FD10760ABa3504A68D9482Ec808f9892096ae0);
        accountsToMigrate[29] = address(0xe6519f1b7ebAfCc44FBE1cc3b74782eE3bEE6F01);
        accountsToMigrate[30] = address(0x339D40eDb4664655f9C79fD3ab7560d9c88dFa26);
        accountsToMigrate[31] = address(0x80D88041dA9f7c2C6c2a85a2b5dD2E98e7e5Bf87);
        accountsToMigrate[32] = address(0xC72553EdB73eD80cd364666b8d0907218eC2A867);
        accountsToMigrate[33] = address(0xA6D20224839c163FD336128bAE20ce1B6977e5B7);
        accountsToMigrate[34] = address(0x0f0AcFE34c5071e80bE151e1144ab5c1eebC1b0D);
        accountsToMigrate[35] = address(0xE450278A590E3785DA2D42AE979D0F36f2Cf9E2e);
        accountsToMigrate[36] = address(0x75D59f8B22D2F4E80D660b5d24F8687E61f7044e);
        accountsToMigrate[37] = address(0x9cC7b0C48bDa7a66dD0fcaC543a5bE4AE06CF8Aa);
        accountsToMigrate[38] = address(0x942cd0f70c17CCF4D9dA75142c51e1c1C59C4410);
        accountsToMigrate[39] = address(0xEC25FC50DA74D4eE015dB4BFb4796d8d962e240B);
        accountsToMigrate[40] = address(0x65ED4289E811de166AcB852d9adC8D8608A2AE4e);
        accountsToMigrate[41] = address(0x5E35345A390E82620692e969C43769a2F063d48a);
        accountsToMigrate[42] = address(0x3225ec5e04386e35DF7093eC4Da96c4F78A11733);
        accountsToMigrate[43] = address(0xe4E280ef4b717dc9510255238bE9bF8D4018B56B);
        accountsToMigrate[44] = address(0x6a7d9B84c6f721dDD244F816C92A0aaa248e43A6);
        accountsToMigrate[45] = address(0xa9d8bd9512AEE0DBD76f2C32063571477794F953);
        accountsToMigrate[46] = address(0x991661a6B1537660e9F74F3913de824D668717D8);
        accountsToMigrate[47] = address(0xf76253AB45823D70b188f851990Cfa9146924638);
        accountsToMigrate[48] = address(0xa8a42D357564D6aea6E689bD59768A49F26DfEc9);
        accountsToMigrate[49] = address(0x56aBb99730eD09e98786b0217eEB7fd3975d870A);
        accountsToMigrate[50] = address(0x804772769001F9F617278fFfc246cbAB9a67AaAc);
        accountsToMigrate[51] = address(0xA04CF327B6bF3731B1D9e7dDa51A09f92159c459);
        accountsToMigrate[52] = address(0x29c51B472a82f970C77b051B5EaEFA1A631ceB08);
        accountsToMigrate[53] = address(0x8CF6d3Eb74dA9E339a38f193E3FB267000ee9cdf);
        accountsToMigrate[54] = address(0xF1c53df53419b3edAa8339B3CA0c215a69dDDFED);
        accountsToMigrate[55] = address(0x9cfAb6a2741FeCfaf2AB3F7e6FfdE9cb03108a4f);
        accountsToMigrate[56] = address(0xfd36D6bb501666bf1aE9Cb9c4FEB19E032993556);
        accountsToMigrate[57] = address(0x7E4088f24f636792Fe729E51a48EaEFe225A022b);
        accountsToMigrate[58] = address(0x1fF558f3b70c1FCF22d0Fba3Bc75BdC53c3057B1);
        accountsToMigrate[59] = address(0x2F07DC96539F937428BC808F463cbA3877491071);
        accountsToMigrate[60] = address(0xBBe1ba549Bc0305aDcB9ac6bf2e2022bE7A99177);
        accountsToMigrate[61] = address(0x6064248BaEB1241e5F3D86B7cb5A17feaAc5f8D0);
        accountsToMigrate[62] = address(0x62F35be2dc2dd0936D815e6ACF1432511e94C004);
        accountsToMigrate[63] = address(0x19F5959d7e369aFE2942ab2b32aEDd33664707dA);
        accountsToMigrate[64] = address(0xE7d1b40de32fC7413316e0E846b5eDD06e9bC418);

        // upgrade 0xb3E2099b135B12139C4eB774F84a5808FB25c67d
        // Blast Index USDB

        OneClickIndexV2 vault = OneClickIndexV2(0xb3E2099b135B12139C4eB774F84a5808FB25c67d);
        console.log("\nUpgrading Blast Index USDB\n  ", address(vault), "\n");
        (ProxyAdmin proxyAdmin, address admin) = _getProxyAdmin(address(vault));
        console.log("lendingShares2 BEFORE", vault.lendingShares(address(0xe394Ab698279502577A071A37022430af068Bb0c)));

        FeeProvider feeProvider = FeeProvider(0x3049f8Eee32eB335f98CF3EF69987e4Efd192647);
        (ProxyAdmin feeProviderProxyAdmin, address feeProviderAdmin) = _getProxyAdmin(address(feeProvider));
        console.log("feeProviderAdmin", feeProviderAdmin);
        console.log("feeProvider owner", feeProvider.owner());
        console.log("admin", admin);
        vm.startPrank(feeProviderAdmin);
        FeeProvider feeProviderImpl = new FeeProvider(feePrecision);
        console.log("\n  new impl FeeProvider", address(feeProviderImpl));
        feeProviderProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(feeProvider)), address(feeProviderImpl), new bytes(0)
        );
        _updateFeeProviderWhitelisted(feeProvider, address(vault));
        vm.stopPrank();

        vm.startPrank(admin);
        OneClickIndexV2 newImpl = new OneClickIndexV2(IERC20Metadata(vault.asset()), feeProvider, feeRecipient);
        console.log("\n  new impl", address(newImpl));
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(vault)), address(newImpl), new bytes(0));
        vault.initialize(accountsToMigrate);
        vm.stopPrank();
        _checkBaseVaultUpgrade(BaseVault(address(vault)), admin);
        {
            address[] memory lendingPoolAddresses = vault.getPools();
            console.log("lendingShares1", vault.lendingShares(lendingPoolAddresses[0]));
            console.log("lendingShares2", vault.lendingShares(lendingPoolAddresses[1]));
            console.log("lendingShares3", vault.lendingShares(lendingPoolAddresses[2]));
            console.log("lendingShares4", vault.lendingShares(lendingPoolAddresses[3]));
            console.log("pool4", lendingPoolAddresses[3]);
            console.log("pool3", lendingPoolAddresses[2]);
            console.log("pool2", lendingPoolAddresses[1]);
            console.log("pool1", lendingPoolAddresses[0]);
            console.log("count", vault.getLendingPoolCount());
            console.log("maxSlippage", vault.maxSlippage());
        }

        console.log("\n==============================================\n");

        // upgrade 0x346d73AcdE2a319B17CECb5bf95C49107598dF34
        // Zerolend (AAVE inside oneClickIndex)

        AaveVaultV2_InsideOneClickIndex aave_vault =
            AaveVaultV2_InsideOneClickIndex(0x346d73AcdE2a319B17CECb5bf95C49107598dF34);
        console.log("\nUpgrading Zerolend (AAVE inside oneClickIndex)\n  ", address(aave_vault), "\n");
        (proxyAdmin, admin) = _getProxyAdmin(address(aave_vault));

        feeProvider = FeeProvider(0x2E395062497dc014Be9c55E03174e89bA4Afec30);
        (feeProviderProxyAdmin, feeProviderAdmin) = _getProxyAdmin(address(feeProvider));
        console.log("feeProviderAdmin", feeProviderAdmin);
        console.log("feeProvider owner", feeProvider.owner());
        vm.startPrank(admin);
        feeProviderImpl = new FeeProvider(feePrecision);
        console.log("\n  new impl FeeProvider", address(feeProviderImpl));
        feeProviderProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(feeProvider)), address(feeProviderImpl), new bytes(0)
        );
        vm.stopPrank();
        vm.startPrank(feeProviderAdmin);
        _updateFeeProviderWhitelisted(feeProvider, address(aave_vault));
        vm.stopPrank();

        vm.startPrank(admin);
        AaveVaultV2_InsideOneClickIndex aave_newImpl = new AaveVaultV2_InsideOneClickIndex(
            IERC20Metadata(aave_vault.asset()), aave_vault.pool(), feeProvider, feeRecipient
        );
        console.log("\n  new impl", address(aave_newImpl));
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(aave_vault)), address(aave_newImpl), new bytes(0)
        );
        aave_vault.initialize();
        vm.stopPrank();
        _checkBaseVaultUpgrade(BaseVault(address(aave_vault)), admin);

        console.log("\n==============================================\n");

        // upgrade 0xe394Ab698279502577A071A37022430af068Bb0c
        // INIT (inside oneClickIndex)
        // WARNING: ZERO lending shares/totalSupply

        InitVaultV2 init_vault = InitVaultV2(0xe394Ab698279502577A071A37022430af068Bb0c);
        console.log("\nUpgrading INIT (inside oneClickIndex)\n  ", address(init_vault), "\n");
        (proxyAdmin, admin) = _getProxyAdmin(address(init_vault));

        feeProvider = FeeProvider(0x3049f8Eee32eB335f98CF3EF69987e4Efd192647);
        (feeProviderProxyAdmin, feeProviderAdmin) = _getProxyAdmin(address(feeProvider));
        console.log("feeProviderAdmin", feeProviderAdmin);
        console.log("feeProvider owner", feeProvider.owner());
        vm.startPrank(admin);
        feeProviderImpl = new FeeProvider(feePrecision);
        console.log("\n  new impl FeeProvider", address(feeProviderImpl));
        feeProviderProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(feeProvider)), address(feeProviderImpl), new bytes(0)
        );
        _updateFeeProviderWhitelisted(feeProvider, address(init_vault));
        vm.stopPrank();

        vm.startPrank(admin);
        InitVaultV2 init_newImpl =
            new InitVaultV2(IERC20Metadata(init_vault.asset()), init_vault.pool(), feeProvider, feeRecipient);
        console.log("\n  new impl", address(init_newImpl));
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(init_vault)), address(init_newImpl), new bytes(0)
        );
        init_vault.initialize();
        vm.stopPrank();
        _checkBaseVaultUpgrade(BaseVault(address(init_vault)), admin);

        console.log("\n==============================================\n");

        // upgrade 0x3fE57b59cb9f3DdE249745E6D562aA8841BC1b2D
        // Juice (inside oneClickIndex)

        JuiceVaultV2_InsideOneClickIndex juice_vault =
            JuiceVaultV2_InsideOneClickIndex(0x3fE57b59cb9f3DdE249745E6D562aA8841BC1b2D);
        console.log("\nUpgrading Juice (inside oneClickIndex)\n  ", address(juice_vault), "\n");
        (proxyAdmin, admin) = _getProxyAdmin(address(juice_vault));

        feeProvider = FeeProvider(0xC899EfA7863d755A6186a2EFa06a8Fc7e8c5BA42);
        (feeProviderProxyAdmin, feeProviderAdmin) = _getProxyAdmin(address(feeProvider));
        console.log("feeProviderAdmin", feeProviderAdmin);
        console.log("feeProvider owner", feeProvider.owner());
        vm.startPrank(admin);
        feeProviderImpl = new FeeProvider(feePrecision);
        console.log("\n  new impl FeeProvider", address(feeProviderImpl));
        feeProviderProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(feeProvider)), address(feeProviderImpl), new bytes(0)
        );
        _updateFeeProviderWhitelisted(feeProvider, address(juice_vault));
        vm.stopPrank();

        vm.startPrank(admin);
        JuiceVaultV2_InsideOneClickIndex juice_newImpl = new JuiceVaultV2_InsideOneClickIndex(
            IERC20Metadata(juice_vault.asset()), juice_vault.pool(), feeProvider, feeRecipient
        );
        console.log("\n  new impl", address(juice_newImpl));
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(juice_vault)), address(juice_newImpl), new bytes(0)
        );
        juice_vault.initialize();
        vm.stopPrank();
        _checkBaseVaultUpgrade(BaseVault(address(juice_vault)), admin);

        console.log("\n==============================================\n");

        // upgrade 0x0c0a0CcC5685974B8ab411E44e2fC70F07ce4E3d
        // Orbit (inside oneClickIndex)
        // WARNING: ZERO lending shares/totalSupply

        CompoundVaultV2_Orbit orbit_vault = CompoundVaultV2_Orbit(0x0c0a0CcC5685974B8ab411E44e2fC70F07ce4E3d);
        console.log("\nUpgrading Orbit (inside oneClickIndex)\n  ", address(orbit_vault), "\n");
        (proxyAdmin, admin) = _getProxyAdmin(address(orbit_vault));

        feeProvider = FeeProvider(0xf01e01cb6E20dc9E98380bAaAA899eed18A95d36);
        (feeProviderProxyAdmin, feeProviderAdmin) = _getProxyAdmin(address(feeProvider));
        console.log("feeProviderAdmin", feeProviderAdmin);
        console.log("feeProvider owner", feeProvider.owner());
        vm.startPrank(admin);
        feeProviderImpl = new FeeProvider(feePrecision);
        console.log("\n  new impl FeeProvider", address(feeProviderImpl));
        feeProviderProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(feeProvider)), address(feeProviderImpl), new bytes(0)
        );
        _updateFeeProviderWhitelisted(feeProvider, address(orbit_vault));
        vm.stopPrank();

        vm.startPrank(admin);
        CompoundVaultV2_Orbit orbit_newImpl = new CompoundVaultV2_Orbit(
            IERC20Metadata(orbit_vault.asset()), orbit_vault.pool(), feeProvider, feeRecipient
        );
        console.log("\n  new impl", address(orbit_newImpl));
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(orbit_vault)), address(orbit_newImpl), new bytes(0)
        );
        orbit_vault.initialize();
        vm.stopPrank();
        _checkBaseVaultUpgrade(BaseVault(address(orbit_vault)), admin);
    }

    function _checkBaseVaultUpgrade(BaseVault vault, address admin_) internal view {
        console.log("\nVERIFYING BASEVAULT UPGRADE:");
        console.log(" totalSupply", vault.totalSupply());
        console.log(" totalAssets", vault.totalAssets());
        console.log(" hasAdminRole", vault.hasRole(DEFAULT_ADMIN_ROLE, admin_));
        console.log(" hasManagerRole", vault.hasRole(MANAGER_ROLE, admin_));
    }

    function _checkDexUpgrade(BaseDexVaultV2 vault, address admin_) internal view {
        _checkBaseVaultUpgrade(BaseVault(address(vault)), admin_);
        console.log("\nVERIFYING DEX UPGRADE:");
        console.log(" tickLower", vault.tickLower());
        console.log(" tickUpper", vault.tickUpper());
        console.log(" sqrtPriceLower", vault.sqrtPriceLower());
        console.log(" sqrtPriceUpper", vault.sqrtPriceUpper());
        console.log(" positionTokenId", vault.positionTokenId());
    }
}
