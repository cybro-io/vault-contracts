// // SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {SeasonalVault} from "../src/SeasonalVault.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {DeployUtils} from "./DeployUtils.sol";
import {AbstractBaseVaultTest} from "./AbstractBaseVault.t.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MockVault} from "../src/mocks/MockVault.sol";
import {IChainlinkOracle} from "../src/interfaces/IChainlinkOracle.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool, IStargatePool, IJuicePool, IYieldStaking, IFeeProvider} from "./DeployUtils.sol";
import {OneClickIndex} from "../src/OneClickIndex.sol";
import {FeeProvider} from "../src/FeeProvider.sol";
import {Swapper} from "./libraries/Swapper.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";

abstract contract ForkSeasonalVaultBaseTest is AbstractBaseVaultTest {
    IERC20Metadata token0;
    IERC20Metadata token1;
    INonfungiblePositionManager positionManager;
    uint256 public constant wbtcAmount = 1e6;
    uint256 public constant wethAmount = 1e18;
    IVault token0Vault;
    IVault token1Vault;

    address[] tokens;
    IChainlinkOracle[] oracles;

    SeasonalVault seasonalVault;
    uint24 poolFee;
    uint24[] poolsFees;

    uint256 amount0;
    uint256 amount1;

    address tokenTreasure;

    Swapper swapper;

    /* ========== ONECLICK ========== */

    OneClickIndex lendingToken0;
    OneClickIndex lendingToken1;
    uint256 lendingShare;
    uint256 lendingShare2;
    uint8 precision;
    address[] vaults;
    uint256[] lendingShares;
    address[] fromSwap;
    address[] toSwap;
    IUniswapV3Pool[] swapPools;

    address additionalVault;
    IFeeProvider lendingFeeProvider;

    /* =============================== */

    function setUp() public virtual override {
        super.setUp();
        amount = 1e21;
        amount0 = amount;
        amount1 = wbtcAmount;
        poolFee = 3000;
        precision = 20;
        lendingShare = 25 * 10 ** (precision - 2);
        lendingShare2 = 50 * 10 ** (precision - 2);
    }

    /* ========== ONECLICK ========== */

    function _setOracles(OneClickIndex lending_) internal {
        if (tokens.length == 0) return;
        vm.startPrank(user5);
        vm.expectRevert();
        lending_.setOracles(tokens, oracles);
        vm.stopPrank();

        vm.startPrank(admin);
        lending_.setOracles(tokens, oracles);
        vm.stopPrank();
    }

    function _setSwapPools(OneClickIndex lending_) internal {
        if (fromSwap.length == 0) return;
        vm.startPrank(user5);
        vm.expectRevert();
        lending_.setSwapPools(fromSwap, toSwap, swapPools);
        vm.stopPrank();

        vm.startPrank(admin);
        lending_.setSwapPools(fromSwap, toSwap, swapPools);
        vm.stopPrank();
    }

    function _initializeNewVaultOneClick(IERC20Metadata asset_) internal returns (IVault vault_) {
        address vaultAddress;
        delete vaults;
        delete lendingShares;
        delete tokens;
        delete oracles;
        delete fromSwap;
        delete toSwap;
        delete swapPools;
        vm.startPrank(admin);
        if (block.chainid == 81457) {
            // blast
            lendingShares.push(lendingShare);
            lendingShares.push(lendingShare);
            lendingShares.push(lendingShare2);

            tokens.push(address(usdb_BLAST));
            oracles.push(oracle_USDB_BLAST);
            tokens.push(address(weth_BLAST));
            oracles.push(oracle_ETH_BLAST);
            tokens.push(address(wbtc_BLAST));
            oracles.push(oracle_BTC_BLAST);

            if (asset_ == usdb_BLAST) {
                vaults.push(
                    address(
                        _deployAave(
                            VaultSetup(
                                asset_,
                                address(aave_zerolendPool_BLAST),
                                address(0),
                                address(0),
                                name,
                                symbol,
                                admin,
                                admin
                            )
                        )
                    )
                );
                vaults.push(
                    address(
                        _deployJuice(
                            VaultSetup(
                                asset_,
                                address(juice_usdbPool_BLAST),
                                address(0),
                                address(0),
                                name,
                                symbol,
                                admin,
                                admin
                            )
                        )
                    )
                );
                vaults.push(
                    address(
                        _deployYieldStaking(
                            VaultSetup({
                                asset: asset_,
                                pool: address(blastupYieldStaking_BLAST),
                                feeProvider: address(0),
                                feeRecipient: address(0),
                                name: name,
                                symbol: symbol,
                                admin: admin,
                                manager: admin
                            })
                        )
                    )
                );
            } else if (asset_ == weth_BLAST) {
                vaults.push(
                    address(
                        _deployJuice(
                            VaultSetup({
                                asset: weth_BLAST,
                                pool: address(juice_wethPool_BLAST),
                                feeProvider: address(0),
                                feeRecipient: address(0),
                                name: name,
                                symbol: symbol,
                                admin: admin,
                                manager: admin
                            })
                        )
                    )
                );
                vaults.push(
                    address(
                        _deployYieldStaking(
                            VaultSetup({
                                asset: weth_BLAST,
                                pool: address(blastupYieldStaking_BLAST),
                                feeProvider: address(0),
                                feeRecipient: address(0),
                                name: name,
                                symbol: symbol,
                                admin: admin,
                                manager: admin
                            })
                        )
                    )
                );
                vaults.push(
                    address(
                        _deployAave(
                            VaultSetup({
                                asset: weth_BLAST,
                                pool: address(aave_pool_BLAST),
                                feeProvider: address(0),
                                feeRecipient: address(0),
                                name: name,
                                symbol: symbol,
                                admin: admin,
                                manager: admin
                            })
                        )
                    )
                );
            }
        } else if (block.chainid == 42161) {
            lendingShares.push(lendingShare);

            tokens.push(address(usdt_ARBITRUM));
            oracles.push(oracle_USDT_ARBITRUM);
            tokens.push(address(weth_ARBITRUM));
            oracles.push(oracle_ETH_ARBITRUM);
            tokens.push(address(usdc_ARBITRUM));
            oracles.push(oracle_USDC_ARBITRUM);
            tokens.push(address(wbtc_ARBITRUM));
            oracles.push(oracle_BTC_ARBITRUM);

            if (asset_ == usdt_ARBITRUM) {
                vaults.push(
                    address(
                        _deployStargate(
                            VaultSetup({
                                asset: usdt_ARBITRUM,
                                pool: address(stargate_usdtPool_ARBITRUM),
                                feeProvider: address(0),
                                feeRecipient: address(0),
                                name: name,
                                symbol: symbol,
                                admin: admin,
                                manager: admin
                            })
                        )
                    )
                );
            } else if (asset_ == weth_ARBITRUM) {
                vaults.push(
                    address(
                        _deployAave(
                            VaultSetup({
                                asset: weth_ARBITRUM,
                                pool: address(aave_pool_ARBITRUM),
                                feeProvider: address(0),
                                feeRecipient: address(0),
                                name: name,
                                symbol: symbol,
                                admin: admin,
                                manager: admin
                            })
                        )
                    )
                );
            } else if (asset_ == usdc_ARBITRUM) {
                vaults.push(
                    address(
                        _deployAave(
                            VaultSetup({
                                asset: usdc_ARBITRUM,
                                pool: address(aave_pool_ARBITRUM),
                                feeProvider: address(0),
                                feeRecipient: address(0),
                                name: name,
                                symbol: symbol,
                                admin: admin,
                                manager: admin
                            })
                        )
                    )
                );
            } else if (asset_ == wbtc_ARBITRUM) {
                vaults.push(
                    address(
                        _deployAave(
                            VaultSetup({
                                asset: wbtc_ARBITRUM,
                                pool: address(aave_pool_ARBITRUM),
                                feeProvider: address(0),
                                feeRecipient: address(0),
                                name: name,
                                symbol: symbol,
                                admin: admin,
                                manager: admin
                            })
                        )
                    )
                );
            }
        } else if (block.chainid == 8453) {
            lendingShares.push(lendingShare);

            tokens.push(address(usdc_BASE));
            oracles.push(oracle_USDC_BASE);
            tokens.push(address(weth_BASE));
            oracles.push(oracle_ETH_BASE);
            tokens.push(address(wbtc_BASE));
            oracles.push(oracle_BTC_BASE);

            if (asset_ == usdc_BASE) {
                vaults.push(
                    address(
                        _deployStargate(
                            VaultSetup(
                                usdc_BASE,
                                address(stargate_usdcPool_BASE),
                                address(0),
                                address(0),
                                name,
                                symbol,
                                admin,
                                admin
                            )
                        )
                    )
                );
            } else if (asset_ == cbwbtc_BASE) {
                vaults.push(
                    address(
                        _deployAave(
                            VaultSetup({
                                asset: cbwbtc_BASE,
                                pool: address(aave_pool_BASE),
                                feeProvider: address(0),
                                feeRecipient: address(0),
                                name: name,
                                symbol: symbol,
                                admin: admin,
                                manager: admin
                            })
                        )
                    )
                );
            } else if (asset_ == weth_BASE) {
                vaults.push(
                    address(
                        _deployStargate(
                            VaultSetup({
                                asset: weth_BASE,
                                pool: address(stargate_wethPool_BASE),
                                feeProvider: address(0),
                                feeRecipient: address(0),
                                name: name,
                                symbol: symbol,
                                admin: admin,
                                manager: admin
                            })
                        )
                    )
                );
            }
        }
        lendingFeeProvider = FeeProvider(
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
        OneClickIndex lending = OneClickIndex(
            address(
                new TransparentUpgradeableProxy(
                    address(new OneClickIndex(asset_, lendingFeeProvider, feeRecipient)),
                    admin,
                    abi.encodeCall(OneClickIndex.initialize, (admin, name, symbol, admin, admin))
                )
            )
        );
        vaultAddress = address(lending);
        address[] memory whitelistedContracts = new address[](1);
        whitelistedContracts[0] = vaultAddress;
        bool[] memory isWhitelisted = new bool[](1);
        isWhitelisted[0] = true;
        lendingFeeProvider.setWhitelistedContracts(whitelistedContracts, isWhitelisted);
        lending.addLendingPools(vaults);
        lending.setLendingShares(vaults, lendingShares);
        lending.setMaxSlippage(100);
        vm.stopPrank();
        _setOracles(lending);
        _setSwapPools(lending);
        console.log("getLendingPoolCount", lending.getLendingPoolCount());
        return IVault(vaultAddress);
    }

    /* ========== MAIN TESTS ========== */

    function _initializeNewVault() internal override {
        token0Vault = _initializeNewVaultOneClick(token0);
        token1Vault = _initializeNewVaultOneClick(token1);
        console.log("asset", address(asset));
        vm.startPrank(admin);
        vault = IVault(
            address(
                new TransparentUpgradeableProxy(
                    address(
                        new SeasonalVault(
                            payable(address(positionManager)),
                            asset,
                            address(token0),
                            address(token1),
                            feeProvider,
                            feeRecipient,
                            token0Vault,
                            token1Vault
                        )
                    ),
                    admin,
                    abi.encodeCall(SeasonalVault.initialize, (admin, name, symbol, admin))
                )
            )
        );
        seasonalVault = SeasonalVault(payable(address(vault)));
        vaultAddress = address(vault);
        address[] memory whitelistedContracts = new address[](1);
        whitelistedContracts[0] = vaultAddress;
        bool[] memory isWhitelisted = new bool[](1);
        isWhitelisted[0] = true;
        feeProvider.setWhitelistedContracts(whitelistedContracts, isWhitelisted);
        seasonalVault.setTickDiff(1823); // approximately equals to 20% of price diff
        seasonalVault.setFeeForSwaps(poolFee);
        seasonalVault.setOracles(tokens, oracles);
        seasonalVault.setTreasureToken(tokenTreasure);
        seasonalVault.setMaxSlippage(100);
        // we need to initialize swapper contract to move pool price
        swapper = new Swapper();
        vm.stopPrank();
    }

    function _increaseVaultAssets() internal override returns (bool) {
        vm.startPrank(assetProvider);
        asset.transfer(address(vault), 1e6);
        vm.stopPrank();
        vm.warp(block.timestamp + 1000);
        return true;
    }

    function _checkOpenPosition(uint256 newNettoPart, uint256 totalAssetsBefore) internal view {
        console.log("newNettoPart", newNettoPart);
        console.log("NettoPartForTokenOptimistic", seasonalVault.getNettoPartForTokenOptimistic());
        vm.assertApproxEqAbs(newNettoPart, seasonalVault.getNettoPartForTokenOptimistic(), 1e20);
        vm.assertApproxEqAbs(totalAssetsBefore, seasonalVault.totalAssets(), 10 ** asset.decimals());
    }

    function _openPositions() internal {
        address pool = IUniswapV3Factory(positionManager.factory()).getPool(address(token0), address(token1), poolFee);
        uint256 nettoPartOptimistic = seasonalVault.getNettoPartForTokenOptimistic();
        (uint160 currentPrice_,) = seasonalVault.getPoolState(pool);
        int160 currentPrice = int160(currentPrice_);
        console.log("currentPrice", currentPrice);
        console.log("nettoPartOptimistic", nettoPartOptimistic);
        if (nettoPartOptimistic < 9e23) {
            // 5e22 equals to 5%
            uint256 newNettoPart = nettoPartOptimistic + 5e22;
            int160 price2;
            int160 price3;
            int160 delta = 3e21;
            if (!seasonalVault.isToken0()) {
                price2 = currentPrice + currentPrice / 95;
                price3 = price2 + currentPrice / 95 + delta;
            } else {
                delta = -delta;
                price2 = currentPrice - currentPrice / 95;
                price3 = price2 - currentPrice / 95 + delta;
            }
            console.log("delta", delta);
            console.log();
            console.log("price2", price2);
            console.log("tick at price2", TickMath.getTickAtSqrtRatio(uint160(price2)));
            console.log("price3", price3);
            console.log();
            uint256 totalAssetsBefore = seasonalVault.totalAssets();
            seasonalVault.openPositionIfNeed(newNettoPart, uint160(currentPrice), uint160(price2), poolFee);
            _checkOpenPosition(newNettoPart, totalAssetsBefore);
            totalAssetsBefore = seasonalVault.totalAssets();
            seasonalVault.openPositionIfNeed(newNettoPart + 5e22, uint160(price2 + delta), uint160(price3), poolFee);
            _checkOpenPosition(newNettoPart + 5e22, totalAssetsBefore);

            (currentPrice_,) = seasonalVault.getPoolState(pool);
            currentPrice = int160(currentPrice_);
            console.log("POOL PRICE BEFORE MOVE", currentPrice);
            swapper.movePoolPrice(positionManager, address(token0), address(token1), poolFee, uint160(price3 - delta));
            console.log("nettoPartOptimistic after move", seasonalVault.getNettoPartForTokenOptimistic());

            uint256 countBefore = positionManager.balanceOf(address(vault));
            seasonalVault.closePositionsWorkedOut();
            vm.assertEq(positionManager.balanceOf(address(vault)), countBefore - 1);
            console.log("position worked out");

            (currentPrice_,) = seasonalVault.getPoolState(pool);
            console.log("POOL PRICE BEFORE MOVE", currentPrice_);
            swapper.movePoolPrice(positionManager, address(token0), address(token1), poolFee, uint160(currentPrice));
        } else {
            return;
        }
    }

    function _middleInteractions() internal override {
        vm.startPrank(admin);

        address pool = IUniswapV3Factory(positionManager.factory()).getPool(address(token0), address(token1), poolFee);
        console.log("pool", pool);

        (uint160 currentPrice_,) = seasonalVault.getPoolState(pool);
        int160 currentPrice = int160(currentPrice_);
        console.log("nettoPartOptimistic", seasonalVault.getNettoPartForTokenOptimistic());
        bool isToken0 = seasonalVault.isToken0();

        _openPositions();

        // deposit to check swaps
        vm.stopPrank();
        vm.startPrank(user3);
        if (asset == token0) {
            token1.transfer(address(vault), token1.balanceOf(user3));
        } else {
            token0.transfer(address(vault), token0.balanceOf(user3));
        }
        vm.stopPrank();
        console.log("balanceOf treasure", IERC20Metadata(tokenTreasure).balanceOf(address(vault)));
        uint256 nettoPartReal = seasonalVault.getNettoPartForTokenReal(IERC20Metadata(tokenTreasure));

        uint256 shares3 = _deposit(user3, amount);
        console.log("balanceOf treasure", IERC20Metadata(tokenTreasure).balanceOf(address(vault)));
        console.log("user3 shares", shares3);
        vm.assertApproxEqAbs(seasonalVault.getNettoPartForTokenReal(IERC20Metadata(tokenTreasure)), nettoPartReal, 2e22);
        vm.startPrank(admin);

        uint256 balanceToken0Before = token0.balanceOf(address(vault));
        uint256 balanceToken1Before = token1.balanceOf(address(vault));
        seasonalVault.investFreeMoney();
        if (balanceToken0Before != 0) vm.assertGt(balanceToken0Before, token0.balanceOf(address(vault)));
        if (balanceToken1Before != 0) vm.assertGt(balanceToken1Before, token1.balanceOf(address(vault)));

        vm.warp(block.timestamp + 1000);
        seasonalVault.claimDEX();
        seasonalVault.closePositionsAll();
        // open position that will trigger closePositionBadMarket
        if (seasonalVault.getNettoPartForTokenOptimistic() < 9e23) {
            if (isToken0) {
                seasonalVault.openPositionIfNeed(
                    9e23, uint160(currentPrice * 8 / 11), uint160(currentPrice * 8 / 12), poolFee
                );
            } else {
                seasonalVault.openPositionIfNeed(
                    9e23, uint160(currentPrice * 11 / 8), uint160(currentPrice * 10 / 8), poolFee
                );
            }
            uint256 countBefore = positionManager.balanceOf(address(vault));
            seasonalVault.closePositionsBadMarket();
            vm.assertEq(positionManager.balanceOf(address(vault)), countBefore - 1);
        }
        balanceToken0Before = token0.balanceOf(address(vault));
        balanceToken1Before = token1.balanceOf(address(vault));
        seasonalVault.investFreeMoney();
        if (balanceToken0Before != 0) vm.assertGt(balanceToken0Before, token0.balanceOf(address(vault)));
        if (balanceToken1Before != 0) vm.assertGt(balanceToken1Before, token1.balanceOf(address(vault)));

        seasonalVault.claimDEX();
        seasonalVault.closePositionsAll();

        uint256 nettoPartOptimistic = seasonalVault.getNettoPartForTokenOptimistic();
        seasonalVault.setTreasureToken(address(isToken0 ? token1 : token0));
        vm.assertApproxEqAbs(seasonalVault.getNettoPartForTokenOptimistic(), 1e24 - nettoPartOptimistic, 1e20);

        _openPositions();
        seasonalVault.closePositionsAll();
        vm.stopPrank();
    }

    function test_token0() public fork {
        asset = token0;
        amount = amount0;
        console.log("amount", amount);
        _provideAndApproveSpecific(true, token1, amount1);
        baseVaultTest(true);
    }

    function test_token1() public fork {
        asset = token1;
        amount = amount1;
        _provideAndApproveSpecific(true, token0, amount0);
        baseVaultTest(true);
    }
}

contract ForkSeasonalVaultTestBaseChainWeth is ForkSeasonalVaultBaseTest {
    function setUp() public override(ForkSeasonalVaultBaseTest) {
        forkId = vm.createSelectFork("base", lastCachedBlockid_BASE);
        super.setUp();
        positionManager = positionManager_UNI_BASE;
        token0 = usdc_BASE;
        token1 = weth_BASE;
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);
        vm.label(address(token0), "token0");
        vm.label(address(token1), "token1");
        (amount0, amount1) = token0 == usdc_BASE ? (uint256(1e9), wethAmount) : (wethAmount, 1e9);
        console.log("amount0", amount0);
        console.log("amount1", amount1);
        tokenTreasure = address(weth_BASE);
        poolFee = 3000;
    }
}

contract ForkSeasonalVaultTestArbitrumBtc is ForkSeasonalVaultBaseTest {
    function setUp() public override(ForkSeasonalVaultBaseTest) {
        vm.createSelectFork("arbitrum", lastCachedBlockid_ARBITRUM);
        super.setUp();
        positionManager = positionManager_UNI_ARB;
        amount = 1e9;
        token0 = usdt_ARBITRUM;
        token1 = wbtc_ARBITRUM;
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);
        vm.label(address(token0), "token0");
        vm.label(address(token1), "token1");
        (amount0, amount1) = token0 == usdt_ARBITRUM ? (amount, wbtcAmount) : (wbtcAmount, amount);
        console.log("amount0", amount0);
        console.log("amount1", amount1);
        tokenTreasure = address(wbtc_ARBITRUM);
        poolFee = 500;
    }
}

// we haven't nice pools for BTCUSDC pair with uniswap v3 on arbitrum

contract ForkSeasonalVaultTestArbitrumWeth is ForkSeasonalVaultBaseTest {
    function setUp() public override(ForkSeasonalVaultBaseTest) {
        vm.createSelectFork("arbitrum", lastCachedBlockid_ARBITRUM);
        super.setUp();
        positionManager = positionManager_UNI_ARB;
        amount = 1e9;
        token0 = usdt_ARBITRUM;
        token1 = weth_ARBITRUM;
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);
        vm.label(address(token0), "token0");
        vm.label(address(token1), "token1");
        (amount0, amount1) = token0 == usdt_ARBITRUM ? (amount, wethAmount) : (wethAmount, amount);
        tokenTreasure = address(weth_ARBITRUM);
        poolFee = 3000;
    }
}

contract ForkSeasonalVaultTestArbitrumWethUsdc is ForkSeasonalVaultBaseTest {
    function setUp() public override(ForkSeasonalVaultBaseTest) {
        vm.createSelectFork("arbitrum", lastCachedBlockid_ARBITRUM);
        super.setUp();
        positionManager = positionManager_UNI_ARB;
        amount = 1e9;
        token0 = usdc_ARBITRUM;
        token1 = weth_ARBITRUM;
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);
        vm.label(address(token0), "token0");
        vm.label(address(token1), "token1");
        (amount0, amount1) = token0 == usdc_ARBITRUM ? (amount, wethAmount) : (wethAmount, amount);
        tokenTreasure = address(weth_ARBITRUM);
        poolFee = 500;
    }
}

// on blast we haven't nice pools without huge slippage
