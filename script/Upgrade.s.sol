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

    // function tryUpgrade() public {
    //     vm.createSelectFork("blast");
    //     {
    //         IVault aso = IVault(0x0667ac28015ED7146f19B2d218f81218abf32951);
    //         console.log("asset", IERC20Metadata(aso.asset()).symbol());
    //         console.log("decimals", IERC20Metadata(aso.asset()).decimals());
    //         console.log("totalAssets", aso.totalAssets());
    //     }
    //     YieldStakingVault vault = YieldStakingVault(0x3DB2bD838c2bEd431DCFA012c3419b7e94D78456);
    //     address staking_ = address(vault.staking());
    //     {
    //         address investor = address(0x00658B1C845CE3FcAfe1390DdEa9f5907e12803F);
    //         console.log("balanceOf investor", vault.balanceOf(investor));
    //         console.log("totalSupply", vault.totalSupply());
    //         console.log("totalAssets", vault.totalAssets());
    //     }
    //     ProxyAdmin proxyAdmin = ProxyAdmin(address(uint160(uint256(vm.load(address(vault), ERC1967Utils.ADMIN_SLOT)))));
    //     address admin = proxyAdmin.owner();
    //     // vm.startBroadcast();
    //     vm.startPrank(admin);
    //     IFeeProvider feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
    //     YieldStakingVault newImpl =
    //         new YieldStakingVault(IERC20Metadata(vault.asset()), vault.staking(), feeProvider, feeRecipient);
    //     console.log("Upgrading vault", address(vault));
    //     console.log("\n  new impl", address(newImpl));

    //     proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(vault)), address(newImpl), new bytes(0));
    //     console.log("staking", address(vault.staking()));
    //     vm.assertEq(address(vault.staking()), staking_);
    //     vm.assertEq(address(vault.feeProvider()), address(feeProvider));
    //     vm.assertEq(vault.feeRecipient(), feeRecipient);
    //     console.log("balanceOf investor AFTER", vault.balanceOf(address(0x00658B1C845CE3FcAfe1390DdEa9f5907e12803F)));
    //     console.log("totalSupply AFTER", vault.totalSupply());
    //     console.log("totalAssets AFTER", vault.totalAssets());
    //     vm.stopPrank();
    //     // vm.stopBroadcast();
    // }
}
