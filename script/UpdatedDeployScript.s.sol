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

contract UpdatedDeployScript is Script, StdCheats {
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

    address[] vaults;
    uint256[] lendingShares;
    IUniswapV3Pool[] swapPools;

    function _assertBaseVault(BaseVault vault, DeployVault memory vaultData) internal view {
        vm.assertEq(vault.asset(), address(vaultData.asset));
        vm.assertEq(address(vault.feeProvider()), address(vaultData.feeProvider));
        vm.assertEq(vault.feeRecipient(), vaultData.feeRecipient);
        vm.assertEq(vault.name(), vaultData.name);
        vm.assertEq(vault.symbol(), vaultData.symbol);
        vm.assertTrue(vault.hasRole(vault.MANAGER_ROLE(), vaultData.manager));
        vm.assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), vaultData.admin));
    }

    function _deployFeeProvider(
        address admin,
        uint32 depositFee,
        uint32 withdrawalFee,
        uint32 performanceFee,
        uint32 administrationFee
    ) internal returns (FeeProvider feeProvider) {
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
        vm.assertEq(feeProvider.getFeePrecision(), feePrecision);
        vm.assertEq(feeProvider.getDepositFee(admin), depositFee);
        vm.assertEq(feeProvider.getWithdrawalFee(admin), withdrawalFee);
        vm.assertEq(feeProvider.getPerformanceFee(admin), performanceFee);
        console.log("FeeProvider", address(feeProvider), "feePrecision", feePrecision);
        console.log("  with fees", depositFee, withdrawalFee, performanceFee);
        return feeProvider;
    }

    function _deployAaveVault(DeployVault memory vaultData) internal returns (AaveVault vault) {
        vault = AaveVault(
            address(
                new TransparentUpgradeableProxy(
                    address(
                        new AaveVault(
                            vaultData.asset, IAavePool(vaultData.pool), vaultData.feeProvider, vaultData.feeRecipient
                        )
                    ),
                    vaultData.admin,
                    abi.encodeCall(
                        AaveVault.initialize, (vaultData.admin, vaultData.name, vaultData.symbol, vaultData.manager)
                    )
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
                new TransparentUpgradeableProxy(
                    address(
                        new JuiceVault(
                            vaultData.asset, IJuicePool(vaultData.pool), vaultData.feeProvider, vaultData.feeRecipient
                        )
                    ),
                    vaultData.admin,
                    abi.encodeCall(
                        JuiceVault.initialize, (vaultData.admin, vaultData.name, vaultData.symbol, vaultData.manager)
                    )
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
                new TransparentUpgradeableProxy(
                    address(
                        new YieldStakingVault(
                            vaultData.asset,
                            IYieldStaking(payable(vaultData.pool)),
                            vaultData.feeProvider,
                            vaultData.feeRecipient
                        )
                    ),
                    vaultData.admin,
                    abi.encodeCall(
                        YieldStakingVault.initialize,
                        (vaultData.admin, vaultData.name, vaultData.symbol, vaultData.manager)
                    )
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
                new TransparentUpgradeableProxy(
                    address(
                        new InitVault(
                            vaultData.asset,
                            IInitLendingPool(vaultData.pool),
                            vaultData.feeProvider,
                            vaultData.feeRecipient
                        )
                    ),
                    vaultData.admin,
                    abi.encodeCall(
                        InitVault.initialize, (vaultData.admin, vaultData.name, vaultData.symbol, vaultData.manager)
                    )
                )
            )
        );

        _assertBaseVault(BaseVault(address(vault)), vaultData);
        vm.assertEq(address(vault.pool()), address(vaultData.pool));
        console.log("InitVault", address(vault));
        console.log("  asset", vm.getLabel(address(vaultData.asset)), address(vaultData.asset));
    }

    function _deployStargateVault(DeployStargateVault memory vaultData, address asset)
        internal
        returns (StargateVault vault)
    {
        vault = StargateVault(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(
                            new StargateVault(
                                vaultData.pool,
                                vaultData.feeProvider,
                                vaultData.feeRecipient,
                                vaultData.staking,
                                vaultData.stg,
                                vaultData.weth,
                                vaultData.swapPool,
                                vaultData.assetWethPool
                            )
                        ),
                        vaultData.admin,
                        abi.encodeCall(
                            StargateVault.initialize,
                            (vaultData.admin, vaultData.name, vaultData.symbol, vaultData.manager)
                        )
                    )
                )
            )
        );
        vm.assertEq(vault.asset(), asset);
        vm.assertEq(address(vault.pool()), address(vaultData.pool));
        vm.assertEq(address(vault.feeProvider()), address(vaultData.feeProvider));
        vm.assertEq(vault.feeRecipient(), vaultData.feeRecipient);
        vm.assertEq(address(vault.staking()), address(vaultData.staking));
        vm.assertEq(address(vault.stg()), address(vaultData.stg));
        vm.assertEq(address(vault.weth()), address(vaultData.weth));
        vm.assertEq(address(vault.stgWethPool()), address(vaultData.swapPool));
        vm.assertEq(address(vault.assetWethPool()), address(vaultData.assetWethPool));
        vm.assertTrue(vault.hasRole(vault.MANAGER_ROLE(), vaultData.manager));
        vm.assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), vaultData.admin));
        console.log("StargateVault", address(vault));
        console.log("  asset", vm.getLabel(asset), asset);
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

    function deployMainnet() external {
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
                        manager: admin,
                        admin: admin
                    })
                )
            )
        );

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
                        manager: admin,
                        admin: admin
                    })
                )
            )
        );

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
                        manager: admin,
                        admin: admin
                    })
                )
            )
        );

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
        lendingShares.push(4000);
        lendingShares.push(4000);
        lendingShares.push(2000);
        fundLending.addLendingPools(vaults);
        fundLending.setLendingShares(vaults, lendingShares);
        vm.assertTrue(fundLending.hasRole(fundLending.MANAGER_ROLE(), admin));
        vm.assertTrue(fundLending.hasRole(fundLending.DEFAULT_ADMIN_ROLE(), admin));
        vm.assertTrue(fundLending.hasRole(fundLending.STRATEGIST_ROLE(), admin));

        vm.stopBroadcast();

        console.log("OneClickIndex USDB", address(fundLending));
        _testVaultWorks(BaseVault(vaults[0]), 1e19, false);
        _testVaultWorks(BaseVault(vaults[1]), 1e19, false);
        _testVaultWorks(BaseVault(vaults[2]), 1e19, false);
        _testVaultWorks(BaseVault(address(fundLending)), 1e19, true);
    }

    function deployStargate_Arbitrum() public {
        vm.createSelectFork("arbitrum");
        vm.startBroadcast();
        (, address admin,) = vm.readCallers();

        IERC20Metadata usdt = IERC20Metadata(address(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9));
        IERC20Metadata weth = IERC20Metadata(address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1));
        IERC20Metadata usdc = IERC20Metadata(address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831));
        vm.label(address(usdt), "USDT");
        vm.label(address(weth), "WETH");
        vm.label(address(usdc), "USDC");

        IStargateStaking staking = IStargateStaking(payable(address(0x3da4f8E456AC648c489c286B99Ca37B666be7C4C)));
        IERC20Metadata stg = IERC20Metadata(address(0x6694340fc020c5E6B96567843da2df01b2CE1eb6));
        IUniswapV3Factory factory = IUniswapV3Factory(address(0x1F98431c8aD98523631AE4a59f267346ea31F984));
        swapPools.push(IUniswapV3Pool(factory.getPool(address(stg), address(weth), 3000)));
        swapPools.push(IUniswapV3Pool(factory.getPool(address(usdt), address(weth), 500)));
        swapPools.push(IUniswapV3Pool(factory.getPool(address(usdc), address(weth), 500)));

        FeeProvider feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        IStargatePool pool = IStargatePool(payable(address(0xcE8CcA271Ebc0533920C83d39F417ED6A0abB7D0)));
        vaults.push(
            address(
                _deployStargateVault(
                    DeployStargateVault({
                        pool: pool,
                        feeProvider: feeProvider,
                        feeRecipient: feeRecipient,
                        staking: staking,
                        stg: stg,
                        weth: weth,
                        swapPool: swapPools[0],
                        assetWethPool: swapPools[1],
                        admin: admin,
                        name: "Stargate USDT",
                        symbol: "stgUSDT",
                        manager: admin
                    }),
                    address(usdt)
                )
            )
        );

        // Stargate USDC
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        pool = IStargatePool(payable(address(0xe8CDF27AcD73a434D661C84887215F7598e7d0d3)));
        vaults.push(
            address(
                _deployStargateVault(
                    DeployStargateVault({
                        pool: pool,
                        feeProvider: feeProvider,
                        feeRecipient: feeRecipient,
                        staking: staking,
                        stg: stg,
                        weth: weth,
                        swapPool: swapPools[0],
                        assetWethPool: swapPools[2],
                        admin: admin,
                        name: "Stargate USDC",
                        symbol: "stgUSDC",
                        manager: admin
                    }),
                    address(usdc)
                )
            )
        );

        // Stargate WETH
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        pool = IStargatePool(payable(address(0xA45B5130f36CDcA45667738e2a258AB09f4A5f7F)));
        vaults.push(
            address(
                _deployStargateVault(
                    DeployStargateVault({
                        pool: pool,
                        feeProvider: feeProvider,
                        feeRecipient: feeRecipient,
                        staking: staking,
                        stg: stg,
                        weth: weth,
                        swapPool: swapPools[0],
                        assetWethPool: IUniswapV3Pool(address(0)),
                        admin: admin,
                        name: "Stargate WETH",
                        symbol: "stgWETH",
                        manager: admin
                    }),
                    address(weth)
                )
            )
        );
        vm.stopBroadcast();
        _testVaultWorks(BaseVault(address(vaults[0])), 1e18, false);
        _testVaultWorks(BaseVault(address(vaults[1])), 1e18, false);
        _testVaultWorks(BaseVault(address(vaults[2])), 1e18, false);
    }

    function deployStargate_Base() public {
        vm.createSelectFork("base");
        vm.startBroadcast();
        (, address admin,) = vm.readCallers();

        IERC20Metadata weth = IERC20Metadata(address(0x4200000000000000000000000000000000000006));
        IERC20Metadata usdc = IERC20Metadata(address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913));
        vm.label(address(weth), "WETH");
        vm.label(address(usdc), "USDC");
        IStargateStaking staking = IStargateStaking(payable(address(0xDFc47DCeF7e8f9Ab19a1b8Af3eeCF000C7ea0B80)));
        IERC20Metadata stg = IERC20Metadata(address(0xE3B53AF74a4BF62Ae5511055290838050bf764Df));
        IUniswapV3Factory factory = IUniswapV3Factory(address(0x33128a8fC17869897dcE68Ed026d694621f6FDfD));
        swapPools.push(IUniswapV3Pool(factory.getPool(address(stg), address(weth), 10000)));
        swapPools.push(IUniswapV3Pool(factory.getPool(address(usdc), address(weth), 500)));

        FeeProvider feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        IStargatePool pool = IStargatePool(payable(address(0x27a16dc786820B16E5c9028b75B99F6f604b5d26)));
        vaults.push(
            address(
                _deployStargateVault(
                    DeployStargateVault({
                        pool: pool,
                        feeProvider: feeProvider,
                        feeRecipient: feeRecipient,
                        staking: staking,
                        stg: stg,
                        weth: weth,
                        swapPool: swapPools[0],
                        assetWethPool: swapPools[1],
                        admin: admin,
                        name: "Stargate USDC",
                        symbol: "stgUSDC",
                        manager: admin
                    }),
                    address(usdc)
                )
            )
        );

        // Stargate WETH
        feeProvider = _deployFeeProvider(admin, 0, 0, 0, 0);
        pool = IStargatePool(payable(address(0xdc181Bd607330aeeBEF6ea62e03e5e1Fb4B6F7C7)));
        vaults.push(
            address(
                _deployStargateVault(
                    DeployStargateVault({
                        pool: pool,
                        feeProvider: feeProvider,
                        feeRecipient: feeRecipient,
                        staking: staking,
                        stg: stg,
                        weth: weth,
                        swapPool: swapPools[0],
                        assetWethPool: IUniswapV3Pool(address(0)),
                        admin: admin,
                        name: "Stargate WETH",
                        symbol: "stgWETH",
                        manager: admin
                    }),
                    address(weth)
                )
            )
        );
        vm.stopBroadcast();
        _testVaultWorks(BaseVault(address(vaults[0])), 1e18, false);
        _testVaultWorks(BaseVault(address(vaults[1])), 1e18, false);
    }

    function _testVaultWorks(BaseVault vault, uint256 amount, bool isOneClick) internal {
        IERC20Metadata token = IERC20Metadata(vault.asset());
        address user = address(100);
        if (
            vault.asset() == address(0x4300000000000000000000000000000000000003)
                || vault.asset() == address(0x4300000000000000000000000000000000000004)
        ) {
            vm.startPrank(address(0x3Ba925fdeAe6B46d0BB4d424D829982Cb2F7309e));
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
}
