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
import {DeployUtils} from "../test/DeployUtils.sol";
import {SeasonalVault} from "../src/SeasonalVault.sol";
import {BufferVault} from "../src/vaults/BufferVault.sol";

contract UpdatedDeployScript is Script, StdCheats, DeployUtils {
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

    struct DeployStargateVault {
        IStargatePool pool;
        IFeeProvider feeProvider;
        address feeRecipient;
        IStargateStaking staking;
        IERC20Metadata stg;
        IERC20Metadata weth;
        IUniswapV3Pool swapPool;
        IUniswapV3Pool assetWethPool;
        address admin;
        string name;
        string symbol;
        address manager;
    }

    uint32 public constant feePrecision = 10000;
    address public constant feeRecipient = address(0x66E424337c0f888DCCbCf2e0730A00A526D716f6);
    address public constant cybroWallet = address(0x4739fEFA6949fcB90F56a9D6defb3e8d3Fd282F6);
    address public constant cybroManager = address(0xD06Fd4465CdEdD4D8e01ec7ebd5F835cbb22cF01);
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    address[] vaults;
    address[] vaults2;
    uint256[] lendingShares;
    IUniswapV3Pool[] swapPools;
    address[] tokens;
    IChainlinkOracle[] oracles;
    address[] fromSwap;
    address[] toSwap;

    function _assertBaseVault(BaseVault vault, DeployVault memory vaultData) internal view {
        vm.assertEq(vault.asset(), address(vaultData.asset));
        vm.assertEq(address(vault.feeProvider()), address(vaultData.feeProvider));
        vm.assertEq(vault.feeRecipient(), vaultData.feeRecipient);
        vm.assertEq(vault.name(), vaultData.name);
        vm.assertEq(vault.symbol(), vaultData.symbol);
        vm.assertTrue(vault.hasRole(MANAGER_ROLE, vaultData.manager));
        vm.assertTrue(vault.hasRole(DEFAULT_ADMIN_ROLE, vaultData.admin));
    }

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

    function _updateFeeProviderWhitelistedAndOwnership(FeeProvider feeProvider_, address newAdmin, address whitelisted)
        internal
    {
        address[] memory whitelistedContracts = new address[](1);
        whitelistedContracts[0] = whitelisted;
        bool[] memory isWhitelisted = new bool[](1);
        isWhitelisted[0] = true;
        feeProvider_.setWhitelistedContracts(whitelistedContracts, isWhitelisted);
        feeProvider_.transferOwnership(newAdmin);
    }

    function _deployAaveVault(DeployVault memory vaultData) internal returns (AaveVault vault) {
        vault = AaveVault(
            address(
                _deployAave(
                    VaultSetup({
                        asset: vaultData.asset,
                        pool: vaultData.pool,
                        feeProvider: address(vaultData.feeProvider),
                        feeRecipient: vaultData.feeRecipient,
                        name: vaultData.name,
                        symbol: vaultData.symbol,
                        admin: vaultData.admin,
                        manager: vaultData.manager
                    })
                )
            )
        );
        _assertBaseVault(AaveVault(address(vault)), vaultData);
        vm.assertEq(address(vault.pool()), vaultData.pool);
        console.log("AaveVault", address(vault));
        console.log("  asset", vm.getLabel(address(vaultData.asset)), address(vaultData.asset));
    }

    function _deployJuiceVault(DeployVault memory vaultData) internal returns (JuiceVault vault) {
        vault = JuiceVault(
            address(
                _deployJuice(
                    VaultSetup({
                        asset: vaultData.asset,
                        pool: vaultData.pool,
                        feeProvider: address(vaultData.feeProvider),
                        feeRecipient: vaultData.feeRecipient,
                        name: vaultData.name,
                        symbol: vaultData.symbol,
                        admin: vaultData.admin,
                        manager: vaultData.manager
                    })
                )
            )
        );

        _assertBaseVault(JuiceVault(address(vault)), vaultData);
        vm.assertEq(address(vault.pool()), vaultData.pool);
        console.log("JuiceVault", address(vault));
        console.log("  asset", vm.getLabel(address(vaultData.asset)), address(vaultData.asset));
    }

    function _deployYieldStakingVault(DeployVault memory vaultData) internal returns (YieldStakingVault vault) {
        vault = YieldStakingVault(
            address(
                _deployYieldStaking(
                    VaultSetup({
                        asset: vaultData.asset,
                        pool: vaultData.pool,
                        feeProvider: address(vaultData.feeProvider),
                        feeRecipient: vaultData.feeRecipient,
                        name: vaultData.name,
                        symbol: vaultData.symbol,
                        admin: vaultData.admin,
                        manager: vaultData.manager
                    })
                )
            )
        );

        _assertBaseVault(BaseVault(address(vault)), vaultData);
        vm.assertEq(address(vault.staking()), address(vaultData.pool));
        console.log("YieldStakingVault", address(vault));
        console.log("  asset", vm.getLabel(address(vaultData.asset)), address(vaultData.asset));
    }

    function _deployCompoundVault(DeployVault memory vaultData) internal returns (CompoundVault vault) {
        vault = CompoundVault(
            address(
                new TransparentUpgradeableProxy(
                    address(
                        new CompoundVault(
                            vaultData.asset, CErc20(vaultData.pool), vaultData.feeProvider, vaultData.feeRecipient
                        )
                    ),
                    vaultData.admin,
                    abi.encodeCall(
                        CompoundVault.initialize, (vaultData.admin, vaultData.name, vaultData.symbol, vaultData.manager)
                    )
                )
            )
        );
        _assertBaseVault(BaseVault(address(vault)), vaultData);
        vm.assertEq(address(vault.pool()), address(vaultData.pool));
        console.log("CompoundVault", address(vault));
        console.log("  asset", vm.getLabel(address(vaultData.asset)), address(vaultData.asset));
    }

    function _deployCompoundVaultETH(DeployVault memory vaultData) internal returns (CompoundVaultETH vault) {
        vault = CompoundVaultETH(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(
                            new CompoundVaultETH(
                                vaultData.asset, CEth(vaultData.pool), vaultData.feeProvider, vaultData.feeRecipient
                            )
                        ),
                        vaultData.admin,
                        abi.encodeCall(
                            CompoundVaultETH.initialize,
                            (vaultData.admin, vaultData.name, vaultData.symbol, vaultData.manager)
                        )
                    )
                )
            )
        );
        _assertBaseVault(BaseVault(address(vault)), vaultData);
        vm.assertEq(address(vault.pool()), address(vaultData.pool));
        console.log("CompoundVaultETH", address(vault));
        console.log("  asset", vm.getLabel(address(vaultData.asset)), address(vaultData.asset));
    }

    function _deployInitVault(DeployVault memory vaultData) internal returns (InitVault vault) {
        vault = InitVault(
            address(
                _deployInit(
                    VaultSetup({
                        asset: vaultData.asset,
                        pool: vaultData.pool,
                        feeProvider: address(vaultData.feeProvider),
                        feeRecipient: vaultData.feeRecipient,
                        name: vaultData.name,
                        symbol: vaultData.symbol,
                        admin: vaultData.admin,
                        manager: vaultData.manager
                    })
                )
            )
        );

        _assertBaseVault(BaseVault(address(vault)), vaultData);
        vm.assertEq(address(vault.pool()), address(vaultData.pool));
        console.log("InitVault", address(vault));
        console.log("  asset", vm.getLabel(address(vaultData.asset)), address(vaultData.asset));
    }

    function _deployStargateVault(DeployVault memory vaultData) internal returns (StargateVault vault) {
        vault = StargateVault(
            payable(
                address(
                    _deployStargate(
                        VaultSetup({
                            asset: vaultData.asset,
                            pool: vaultData.pool,
                            feeProvider: address(vaultData.feeProvider),
                            feeRecipient: vaultData.feeRecipient,
                            name: vaultData.name,
                            symbol: vaultData.symbol,
                            admin: vaultData.admin,
                            manager: vaultData.manager
                        })
                    )
                )
            )
        );
        _assertBaseVault(BaseVault(address(vault)), vaultData);
        console.log("StargateVault", address(vault));
        console.log("  asset", vm.getLabel(address(vaultData.asset)), address(vaultData.asset));
    }

    function _deployBufferVault(DeployVault memory vaultData) internal returns (BufferVault vault) {
        vault = BufferVault(
            address(
                _deployBuffer(
                    VaultSetup({
                        asset: vaultData.asset,
                        pool: vaultData.pool,
                        feeProvider: address(vaultData.feeProvider),
                        feeRecipient: vaultData.feeRecipient,
                        name: vaultData.name,
                        symbol: vaultData.symbol,
                        admin: vaultData.admin,
                        manager: vaultData.manager
                    })
                )
            )
        );
        _assertBaseVault(BaseVault(address(vault)), vaultData);
        console.log("BufferVault", address(vault));
        console.log("  asset", vm.getLabel(address(vaultData.asset)), address(vaultData.asset));
    }
    // Examples for deploying other vaults

    // feeProvider = _deployFeeProvider(admin, 0, 0, 0);
    // pool = address(0x0E84461a00C661A18e00Cab8888d146FDe10Da8D);
    // YieldStakingVault yieldVault = _deployYieldStakingVault(
    //     DeployVault(usdb, pool, feeProvider, feeRecipient, "Yield Staking USDB", "cysUSDB", admin, admin)
    // );

    // feeProvider = _deployFeeProvider(admin, 0, 0, 0);
    // pool = address(0x9aECEdCD6A82d26F2f86D331B17a1C1676442A87);
    // CompoundVault compVault = _deployCompoundVault(
    //     DeployVault(usdb, pool, feeProvider, feeRecipient, "Compound USDB", "cycUSDB", admin, admin)
    // );

    // feeProvider = _deployFeeProvider(admin, 0, 0, 0);
    // pool = address(0x0872b71EFC37CB8DdE22B2118De3d800427fdba0);
    // CompoundVaultETH compETHVault = _deployCompoundVaultETH(
    //     DeployVault(usdb, pool, feeProvider, feeRecipient, "Compound ETH USDB", "cycETHUSDB", admin, admin)
    // );

    // feeProvider = _deployFeeProvider(admin, 0, 0, 0);
    // pool = address(0xc5EaC92633aF47c0023Afa0116500ab86FAB430F);
    // InitVault initVault =
    //     _deployInitVault(DeployVault(usdb, pool, feeProvider, feeRecipient, "Init USDB", "cyiUSDB", admin, admin));

    function deployBlast() external {
        vm.startBroadcast();
        (, address admin,) = vm.readCallers();

        IERC20Metadata usdb = IERC20Metadata(address(0x4300000000000000000000000000000000000003));
        vm.label(address(usdb), "USDB");

        // Zerolend USDB
        FeeProvider feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        address pool = address(0xa70B0F3C2470AbBE104BdB3F3aaa9C7C54BEA7A8);
        vaults.push(
            address(
                _deployAaveVault(
                    DeployVault({
                        asset: usdb,
                        pool: pool,
                        feeProvider: feeProvider,
                        feeRecipient: feeRecipient,
                        name: "Zerolend USDB",
                        symbol: "cyzlUSDB",
                        manager: cybroManager,
                        admin: admin
                    })
                )
            )
        );
        _updateFeeProviderWhitelistedAndOwnership(feeProvider, cybroWallet, vaults[0]);

        // Pac USDB
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        pool = address(0xd2499b3c8611E36ca89A70Fda2A72C49eE19eAa8);
        vaults.push(
            address(
                _deployAaveVault(
                    DeployVault({
                        asset: usdb,
                        pool: pool,
                        feeProvider: feeProvider,
                        feeRecipient: feeRecipient,
                        name: "Pac USDB",
                        symbol: "cypcUSDB",
                        manager: cybroManager,
                        admin: admin
                    })
                )
            )
        );
        _updateFeeProviderWhitelistedAndOwnership(feeProvider, cybroWallet, vaults[1]);

        // Juice USDB
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        pool = address(0x4A1d9220e11a47d8Ab22Ccd82DA616740CF0920a);
        vaults.push(
            address(
                _deployJuiceVault(
                    DeployVault({
                        asset: usdb,
                        pool: pool,
                        feeProvider: feeProvider,
                        feeRecipient: feeRecipient,
                        name: "Juice USDB",
                        symbol: "cyjceUSDB",
                        manager: cybroManager,
                        admin: admin
                    })
                )
            )
        );
        _updateFeeProviderWhitelistedAndOwnership(feeProvider, cybroWallet, vaults[2]);

        // OneClick Lending Fund
        feeProvider = _deployFeeProvider(admin, 0, 30, 500, 0);
        OneClickIndex fundLending = OneClickIndex(
            address(
                new TransparentUpgradeableProxy(
                    address(new OneClickIndex(usdb, feeProvider, feeRecipient)),
                    admin,
                    abi.encodeCall(OneClickIndex.initialize, (admin, "Lending Index", "usdbLendingIndex", admin, admin))
                )
            )
        );
        _updateFeeProviderWhitelistedAndOwnership(feeProvider, cybroWallet, address(fundLending));
        lendingShares.push(4000);
        lendingShares.push(4000);
        lendingShares.push(2000);
        fundLending.addLendingPools(vaults);
        fundLending.setLendingShares(vaults, lendingShares);
        vm.assertTrue(fundLending.hasRole(MANAGER_ROLE, admin));
        vm.assertTrue(fundLending.hasRole(DEFAULT_ADMIN_ROLE, admin));
        vm.assertTrue(fundLending.hasRole(fundLending.STRATEGIST_ROLE(), admin));

        vm.stopBroadcast();

        console.log("OneClickIndex USDB", address(fundLending));
        _testVaultWorks(BaseVault(vaults[0]), 1e19, false);
        _testVaultWorks(BaseVault(vaults[1]), 1e19, false);
        _testVaultWorks(BaseVault(vaults[2]), 1e19, false);
        _testVaultWorks(BaseVault(address(fundLending)), 1e19, true);

        vm.startBroadcast();
        fundLending.grantRole(DEFAULT_ADMIN_ROLE, cybroWallet);
        fundLending.revokeRole(fundLending.STRATEGIST_ROLE(), admin);
        fundLending.revokeRole(MANAGER_ROLE, admin);
        fundLending.revokeRole(DEFAULT_ADMIN_ROLE, admin);
        _grantAndRevokeRoles(admin);
        vm.stopBroadcast();
    }

    function deployStargate_Arbitrum() public {
        vm.createSelectFork("arbitrum");
        vm.startBroadcast();
        (, address admin,) = vm.readCallers();

        vm.label(address(usdt_ARBITRUM), "USDT");
        vm.label(address(weth_ARBITRUM), "WETH");
        vm.label(address(usdc_ARBITRUM), "USDC");

        FeeProvider feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        vaults.push(
            address(
                _deployStargateVault(
                    DeployVault({
                        asset: usdt_ARBITRUM,
                        pool: address(stargate_usdtPool_ARBITRUM),
                        feeProvider: feeProvider,
                        feeRecipient: feeRecipient,
                        name: "Stargate USDT",
                        symbol: "stgUSDT",
                        admin: admin,
                        manager: cybroManager
                    })
                )
            )
        );
        _updateFeeProviderWhitelistedAndOwnership(feeProvider, cybroWallet, vaults[0]);

        // Stargate USDC
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        vaults.push(
            address(
                _deployStargateVault(
                    DeployVault({
                        asset: usdc_ARBITRUM,
                        pool: address(stargate_usdcPool_ARBITRUM),
                        feeProvider: feeProvider,
                        feeRecipient: feeRecipient,
                        name: "Stargate USDC",
                        symbol: "stgUSDC",
                        admin: admin,
                        manager: cybroManager
                    })
                )
            )
        );
        _updateFeeProviderWhitelistedAndOwnership(feeProvider, cybroWallet, vaults[1]);

        // Stargate WETH
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        vaults.push(
            address(
                _deployStargateVault(
                    DeployVault({
                        asset: weth_ARBITRUM,
                        pool: address(stargate_wethPool_ARBITRUM),
                        feeProvider: feeProvider,
                        feeRecipient: feeRecipient,
                        name: "Stargate WETH",
                        symbol: "stgWETH",
                        admin: admin,
                        manager: cybroManager
                    })
                )
            )
        );
        _updateFeeProviderWhitelistedAndOwnership(feeProvider, cybroWallet, vaults[2]);
        vm.stopBroadcast();
        _testVaultWorks(BaseVault(address(vaults[0])), 1e18, false);
        _testVaultWorks(BaseVault(address(vaults[1])), 1e18, false);
        _testVaultWorks(BaseVault(address(vaults[2])), 1e18, false);
        vm.startBroadcast();
        _grantAndRevokeRoles(admin);
        vm.stopBroadcast();
    }

    function deployStargate_Base() public {
        vm.createSelectFork("base");
        vm.startBroadcast();
        (, address admin,) = vm.readCallers();

        vm.label(address(weth_BASE), "WETH");
        vm.label(address(usdc_BASE), "USDC");

        FeeProvider feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        vaults.push(
            address(
                _deployStargateVault(
                    DeployVault({
                        asset: usdc_BASE,
                        pool: address(stargate_usdcPool_BASE),
                        feeProvider: feeProvider,
                        feeRecipient: feeRecipient,
                        name: "Stargate USDC",
                        symbol: "stgUSDC",
                        admin: admin,
                        manager: cybroManager
                    })
                )
            )
        );
        _updateFeeProviderWhitelistedAndOwnership(feeProvider, cybroWallet, vaults[0]);

        // Stargate WETH
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        vaults.push(
            address(
                _deployStargateVault(
                    DeployVault({
                        asset: weth_BASE,
                        pool: address(stargate_wethPool_BASE),
                        feeProvider: feeProvider,
                        feeRecipient: feeRecipient,
                        name: "Stargate WETH",
                        symbol: "stgWETH",
                        admin: admin,
                        manager: cybroManager
                    })
                )
            )
        );
        _updateFeeProviderWhitelistedAndOwnership(feeProvider, cybroWallet, vaults[1]);
        vm.stopBroadcast();
        _testVaultWorks(BaseVault(address(vaults[0])), 1e18, false);
        _testVaultWorks(BaseVault(address(vaults[1])), 1e18, false);
        vm.startBroadcast();
        _grantAndRevokeRoles(admin);
        vm.stopBroadcast();
    }

    function deployOneClickBase() public {
        vm.createSelectFork("base");
        vm.startBroadcast();
        (, address admin,) = vm.readCallers();

        vm.label(address(usdc_BASE), "USDC");

        FeeProvider feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        vaults.push(
            address(
                _deployStargateVault(
                    DeployVault({
                        asset: usdc_BASE,
                        pool: address(stargate_usdcPool_BASE),
                        feeProvider: feeProvider,
                        feeRecipient: feeRecipient,
                        name: "Cybro Stargate USDC",
                        symbol: "cystgUSDC",
                        admin: admin,
                        manager: cybroManager
                    })
                )
            )
        );
        _updateFeeProviderWhitelistedAndOwnership(feeProvider, cybroWallet, vaults[0]);

        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        vaults.push(
            address(
                _deployAaveVault(
                    DeployVault({
                        asset: usdc_BASE,
                        pool: address(aave_pool_BASE),
                        feeProvider: feeProvider,
                        feeRecipient: feeRecipient,
                        name: "Cybro Aave USDC",
                        symbol: "cyaUSDC",
                        admin: admin,
                        manager: cybroManager
                    })
                )
            )
        );
        _updateFeeProviderWhitelistedAndOwnership(feeProvider, cybroWallet, vaults[1]);

        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        vaults.push(
            address(
                _deployCompoundVault(
                    DeployVault({
                        asset: usdc_BASE,
                        pool: address(compound_moonwellUSDC_BASE),
                        feeProvider: feeProvider,
                        feeRecipient: feeRecipient,
                        name: "Cybro Moonwell USDC",
                        symbol: "cymUSDC",
                        admin: admin,
                        manager: cybroManager
                    })
                )
            )
        );
        _updateFeeProviderWhitelistedAndOwnership(feeProvider, cybroWallet, vaults[2]);

        feeProvider = _deployFeeProvider(admin, 0, 30, 500, 0);
        OneClickIndex fundLending = OneClickIndex(
            address(
                new TransparentUpgradeableProxy(
                    address(new OneClickIndex(usdc_BASE, feeProvider, feeRecipient)),
                    admin,
                    abi.encodeCall(OneClickIndex.initialize, (admin, "Lending Index", "usdcLendingIndex", admin, admin))
                )
            )
        );
        _updateFeeProviderWhitelistedAndOwnership(feeProvider, cybroWallet, address(fundLending));
        lendingShares.push(3000);
        lendingShares.push(4000);
        lendingShares.push(3000);
        fundLending.addLendingPools(vaults);
        fundLending.setLendingShares(vaults, lendingShares);
        vm.assertTrue(fundLending.hasRole(MANAGER_ROLE, admin));
        vm.assertTrue(fundLending.hasRole(DEFAULT_ADMIN_ROLE, admin));
        vm.assertTrue(fundLending.hasRole(fundLending.STRATEGIST_ROLE(), admin));
        vm.stopBroadcast();

        console.log("OneClickIndex USDC Base", address(fundLending));
        _testVaultWorks(BaseVault(vaults[0]), 1e10, false);
        _testVaultWorks(BaseVault(vaults[1]), 1e10, false);
        _testVaultWorks(BaseVault(vaults[2]), 1e10, false);
        _testVaultWorks(BaseVault(address(fundLending)), 1e10, true);

        vm.startBroadcast();
        fundLending.grantRole(DEFAULT_ADMIN_ROLE, cybroWallet);
        fundLending.revokeRole(fundLending.STRATEGIST_ROLE(), admin);
        fundLending.revokeRole(MANAGER_ROLE, admin);
        fundLending.revokeRole(DEFAULT_ADMIN_ROLE, admin);
        _grantAndRevokeRoles(admin);
        vm.stopBroadcast();
    }

    function deployOneClickArbitrum() public {
        vm.createSelectFork("arbitrum");
        vm.startBroadcast();
        (, address admin,) = vm.readCallers();

        vm.label(address(usdc_ARBITRUM), "USDC");

        FeeProvider feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        vaults.push(
            address(
                _deployAaveVault(
                    DeployVault({
                        asset: usdc_ARBITRUM,
                        pool: address(aave_pool_ARBITRUM),
                        feeProvider: feeProvider,
                        feeRecipient: feeRecipient,
                        name: "Cybro Aave USDC",
                        symbol: "cyaUSDC",
                        admin: admin,
                        manager: cybroManager
                    })
                )
            )
        );
        _updateFeeProviderWhitelistedAndOwnership(feeProvider, cybroWallet, vaults[0]);

        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        vaults.push(
            address(
                _deployAaveVault(
                    DeployVault({
                        asset: usdt_ARBITRUM,
                        pool: address(aave_pool_ARBITRUM),
                        feeProvider: feeProvider,
                        feeRecipient: feeRecipient,
                        name: "Cybro Aave USDT",
                        symbol: "cyaUSDT",
                        admin: admin,
                        manager: cybroManager
                    })
                )
            )
        );
        _updateFeeProviderWhitelistedAndOwnership(feeProvider, cybroWallet, vaults[1]);

        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        vaults.push(
            address(
                _deployStargateVault(
                    DeployVault({
                        asset: usdc_ARBITRUM,
                        pool: address(stargate_usdcPool_ARBITRUM),
                        feeProvider: feeProvider,
                        feeRecipient: feeRecipient,
                        name: "Cybro Stargate USDC",
                        symbol: "cystgUSDC",
                        admin: admin,
                        manager: cybroManager
                    })
                )
            )
        );
        _updateFeeProviderWhitelistedAndOwnership(feeProvider, cybroWallet, vaults[2]);

        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        vaults.push(
            address(
                _deployStargateVault(
                    DeployVault({
                        asset: usdt_ARBITRUM,
                        pool: address(stargate_usdtPool_ARBITRUM),
                        feeProvider: feeProvider,
                        feeRecipient: feeRecipient,
                        name: "Cybro Stargate USDT",
                        symbol: "cystgUSDT",
                        admin: admin,
                        manager: cybroManager
                    })
                )
            )
        );
        _updateFeeProviderWhitelistedAndOwnership(feeProvider, cybroWallet, vaults[3]);

        feeProvider = _deployFeeProvider(admin, 0, 30, 500, 0);
        OneClickIndex fundLending = OneClickIndex(
            address(
                new TransparentUpgradeableProxy(
                    address(new OneClickIndex(usdc_ARBITRUM, feeProvider, feeRecipient)),
                    admin,
                    abi.encodeCall(OneClickIndex.initialize, (admin, "Lending Index", "usdcLendingIndex", admin, admin))
                )
            )
        );
        _updateFeeProviderWhitelistedAndOwnership(feeProvider, cybroWallet, address(fundLending));
        lendingShares.push(2500);
        lendingShares.push(2500);
        lendingShares.push(2500);
        lendingShares.push(2500);
        fundLending.addLendingPools(vaults);
        fundLending.setLendingShares(vaults, lendingShares);
        tokens.push(address(usdc_ARBITRUM));
        oracles.push(oracle_USDC_ARBITRUM);
        tokens.push(address(usdt_ARBITRUM));
        oracles.push(oracle_USDT_ARBITRUM);
        swapPools.push(pool_USDC_USDT_ARBITRUM);
        fromSwap.push(address(usdc_ARBITRUM));
        toSwap.push(address(usdt_ARBITRUM));
        fundLending.setSwapPools(fromSwap, toSwap, swapPools);
        fundLending.setOracles(tokens, oracles);
        fundLending.setMaxSlippage(10);
        vm.assertTrue(fundLending.hasRole(MANAGER_ROLE, admin));
        vm.assertTrue(fundLending.hasRole(DEFAULT_ADMIN_ROLE, admin));
        vm.assertTrue(fundLending.hasRole(fundLending.STRATEGIST_ROLE(), admin));
        vm.stopBroadcast();

        console.log("OneClickIndex USDC Arbitrum", address(fundLending));
        _testVaultWorks(BaseVault(vaults[0]), 1e10, false);
        _testVaultWorks(BaseVault(vaults[1]), 1e10, false);
        _testVaultWorks(BaseVault(vaults[2]), 1e10, false);
        _testVaultWorks(BaseVault(vaults[3]), 1e10, false);
        _testVaultWorks(BaseVault(address(fundLending)), 1e10, true);

        vm.startBroadcast();
        fundLending.grantRole(DEFAULT_ADMIN_ROLE, cybroWallet);
        fundLending.revokeRole(fundLending.STRATEGIST_ROLE(), admin);
        fundLending.revokeRole(MANAGER_ROLE, admin);
        fundLending.revokeRole(DEFAULT_ADMIN_ROLE, admin);
        _grantAndRevokeRoles(admin);
        vm.stopBroadcast();
    }

    function deploySeasonalArbitrum() public {
        vm.startBroadcast();
        (, address admin,) = vm.readCallers();

        vm.label(address(usdt_ARBITRUM), "USDT");
        vm.label(address(usdc_ARBITRUM), "USDC");
        vm.label(address(wbtc_ARBITRUM), "WBTC");

        FeeProvider feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        vaults2.push(
            address(
                _deployBufferVault(
                    DeployVault({
                        asset: wbtc_ARBITRUM,
                        pool: address(0),
                        feeProvider: feeProvider,
                        feeRecipient: feeRecipient,
                        name: "Cybro Buffer WBTC",
                        symbol: "cyWBTC",
                        admin: admin,
                        manager: cybroManager
                    })
                )
            )
        );
        _updateFeeProviderWhitelistedAndOwnership(feeProvider, cybroWallet, vaults2[0]);

        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        vaults.push(
            address(
                _deployAaveVault(
                    DeployVault({
                        asset: usdc_ARBITRUM,
                        pool: address(aave_pool_ARBITRUM),
                        feeProvider: feeProvider,
                        feeRecipient: feeRecipient,
                        name: "Cybro Aave USDC",
                        symbol: "cyaUSDC",
                        admin: admin,
                        manager: cybroManager
                    })
                )
            )
        );
        _updateFeeProviderWhitelistedAndOwnership(feeProvider, cybroWallet, vaults[0]);

        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        vaults.push(
            address(
                _deployAaveVault(
                    DeployVault({
                        asset: usdt_ARBITRUM,
                        pool: address(aave_pool_ARBITRUM),
                        feeProvider: feeProvider,
                        feeRecipient: feeRecipient,
                        name: "Cybro Aave USDT",
                        symbol: "cyaUSDT",
                        admin: admin,
                        manager: cybroManager
                    })
                )
            )
        );
        _updateFeeProviderWhitelistedAndOwnership(feeProvider, cybroWallet, vaults[1]);

        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        vaults.push(
            address(
                _deployStargateVault(
                    DeployVault({
                        asset: usdc_ARBITRUM,
                        pool: address(stargate_usdcPool_ARBITRUM),
                        feeProvider: feeProvider,
                        feeRecipient: feeRecipient,
                        name: "Cybro Stargate USDC",
                        symbol: "cystgUSDC",
                        admin: admin,
                        manager: cybroManager
                    })
                )
            )
        );
        _updateFeeProviderWhitelistedAndOwnership(feeProvider, cybroWallet, vaults[2]);

        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        vaults.push(
            address(
                _deployStargateVault(
                    DeployVault({
                        asset: usdt_ARBITRUM,
                        pool: address(stargate_usdtPool_ARBITRUM),
                        feeProvider: feeProvider,
                        feeRecipient: feeRecipient,
                        name: "Cybro Stargate USDT",
                        symbol: "cystgUSDT",
                        admin: admin,
                        manager: cybroManager
                    })
                )
            )
        );
        _updateFeeProviderWhitelistedAndOwnership(feeProvider, cybroWallet, vaults[3]);

        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        OneClickIndex fundLendingWbtc = OneClickIndex(
            address(
                new TransparentUpgradeableProxy(
                    address(new OneClickIndex(wbtc_ARBITRUM, feeProvider, feeRecipient)),
                    admin,
                    abi.encodeCall(OneClickIndex.initialize, (admin, "Lending Index", "wbtcLendingIndex", admin, admin))
                )
            )
        );
        _updateFeeProviderWhitelistedAndOwnership(feeProvider, cybroWallet, address(fundLendingWbtc));
        lendingShares.push(10000);
        fundLendingWbtc.addLendingPools(vaults2);
        fundLendingWbtc.setLendingShares(vaults2, lendingShares);

        tokens.push(address(usdc_ARBITRUM));
        oracles.push(oracle_USDC_ARBITRUM);
        tokens.push(address(usdt_ARBITRUM));
        oracles.push(oracle_USDT_ARBITRUM);
        tokens.push(address(wbtc_ARBITRUM));
        oracles.push(oracle_BTC_ARBITRUM);

        fundLendingWbtc.setOracles(tokens, oracles);
        vm.assertTrue(fundLendingWbtc.hasRole(MANAGER_ROLE, admin));
        vm.assertTrue(fundLendingWbtc.hasRole(DEFAULT_ADMIN_ROLE, admin));
        vm.assertTrue(fundLendingWbtc.hasRole(fundLendingWbtc.STRATEGIST_ROLE(), admin));
        console.log("OneClickIndex WBTC Arbitrum", address(fundLendingWbtc));

        delete lendingShares;
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        OneClickIndex fundLending = OneClickIndex(
            address(
                new TransparentUpgradeableProxy(
                    address(new OneClickIndex(usdc_ARBITRUM, feeProvider, feeRecipient)),
                    admin,
                    abi.encodeCall(OneClickIndex.initialize, (admin, "Lending Index", "usdcLendingIndex", admin, admin))
                )
            )
        );
        _updateFeeProviderWhitelistedAndOwnership(feeProvider, cybroWallet, address(fundLending));
        lendingShares.push(2500);
        lendingShares.push(2500);
        lendingShares.push(2500);
        lendingShares.push(2500);
        fundLending.addLendingPools(vaults);
        fundLending.setLendingShares(vaults, lendingShares);

        swapPools.push(pool_USDC_USDT_ARBITRUM);
        fromSwap.push(address(usdc_ARBITRUM));
        toSwap.push(address(usdt_ARBITRUM));
        fundLending.setSwapPools(fromSwap, toSwap, swapPools);
        fundLending.setOracles(tokens, oracles);
        fundLending.setMaxSlippage(10);
        vm.assertTrue(fundLending.hasRole(MANAGER_ROLE, admin));
        vm.assertTrue(fundLending.hasRole(DEFAULT_ADMIN_ROLE, admin));
        vm.assertTrue(fundLending.hasRole(fundLending.STRATEGIST_ROLE(), admin));
        console.log("OneClickIndex USDC Arbitrum", address(fundLending));

        feeProvider = _deployFeeProvider(admin, 10, 20, 500, 100);
        SeasonalVault seasonal = SeasonalVault(
            address(
                new TransparentUpgradeableProxy(
                    address(
                        new SeasonalVault(
                            payable(address(positionManager_UNI_ARB)),
                            usdc_ARBITRUM,
                            address(wbtc_ARBITRUM),
                            address(usdc_ARBITRUM),
                            feeProvider,
                            feeRecipient,
                            fundLendingWbtc,
                            fundLending
                        )
                    ),
                    admin,
                    abi.encodeCall(SeasonalVault.initialize, (admin, "Cybro Seasonal Vault", "cySEAS", admin))
                )
            )
        );
        _updateFeeProviderWhitelistedAndOwnership(feeProvider, cybroWallet, address(seasonal));
        seasonal.setTickDiff(1823); // approximately equals to 20% of price diff
        seasonal.setFeeForSwaps(500);
        seasonal.setOracles(tokens, oracles);
        seasonal.setTreasureToken(address(wbtc_ARBITRUM));
        seasonal.setMaxSlippage(100);
        vm.stopBroadcast();

        console.log("Seasonal Vault USDC/WBTC Arbitrum", address(seasonal));
        _testVaultWorks(BaseVault(vaults[0]), 1e10, false);
        _testVaultWorks(BaseVault(vaults[1]), 1e10, false);
        _testVaultWorks(BaseVault(vaults[2]), 1e10, false);
        _testVaultWorks(BaseVault(vaults[3]), 1e10, false);
        _testVaultWorks(BaseVault(address(fundLending)), 1e10, true);
        _testVaultWorks(BaseVault(vaults2[0]), 1e10, false);
        _testVaultWorks(BaseVault(address(fundLendingWbtc)), 1e10, true);
        _testVaultWorks(BaseVault(address(seasonal)), 1e10, false);

        vm.startBroadcast();
        fundLending.grantRole(DEFAULT_ADMIN_ROLE, cybroWallet);
        fundLending.revokeRole(fundLending.STRATEGIST_ROLE(), admin);
        fundLending.revokeRole(MANAGER_ROLE, admin);
        fundLending.revokeRole(DEFAULT_ADMIN_ROLE, admin);

        fundLendingWbtc.grantRole(DEFAULT_ADMIN_ROLE, cybroWallet);
        fundLendingWbtc.revokeRole(fundLending.STRATEGIST_ROLE(), admin);
        fundLendingWbtc.revokeRole(MANAGER_ROLE, admin);
        fundLendingWbtc.revokeRole(DEFAULT_ADMIN_ROLE, admin);

        vaults.push(address(seasonal));
        vaults.push(vaults2[0]);
        _grantAndRevokeRoles(admin);
        vm.stopBroadcast();
    }

    function _testVaultWorks(BaseVault vault, uint256 amount, bool isOneClick) internal {
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

        console.log("balance of user", token.balanceOf(user));

        vm.startPrank(user);
        token.approve(address(vault), amount);
        uint256 shares;
        uint256 assets;
        if (isOneClick) {
            OneClickIndex lending = OneClickIndex(address(vault));
            shares = lending.deposit(amount, user, 0);
            assets = lending.redeem(shares, user, user, 0);
        } else {
            shares = vault.deposit(amount, user, 0);
            assets = vault.redeem(shares, user, user, 0);
        }
        console.log("Vault name", vault.name());
        console.log("Shares after deposit", shares);
        console.log("Redeemed assets", assets);
        vm.stopPrank();
    }

    function _grantAndRevokeRoles(address admin_) internal {
        for (uint256 i = 0; i < vaults.length; i++) {
            BaseVault vault_ = BaseVault(vaults[i]);
            vault_.grantRole(DEFAULT_ADMIN_ROLE, cybroWallet);
            vault_.revokeRole(MANAGER_ROLE, admin_);
            vault_.revokeRole(DEFAULT_ADMIN_ROLE, admin_);
            vm.assertTrue(vault_.hasRole(DEFAULT_ADMIN_ROLE, cybroWallet));
            vm.assertFalse(vault_.hasRole(DEFAULT_ADMIN_ROLE, admin_));
            vm.assertFalse(vault_.hasRole(MANAGER_ROLE, admin_));
        }
    }
}
