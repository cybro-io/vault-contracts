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
            // lendingShares.push(lendingShare2);

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
                // additionalVault = address(
                //     _deployBuffer(VaultSetup(asset_, address(0), address(0), address(0), name, symbol, admin, admin))
                // );
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
            // arbitrum
            amount = 1e9; // decimals = 6
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

            // additionalVault = address(
            //     _deployBuffer(VaultSetup(usdt_ARBITRUM, address(0), address(0), address(0), name, symbol, admin, admin))
            // );
        } else if (block.chainid == 8453) {
            // base// decimals = 6
            // fromSwap.push(address(usdc_BASE));
            // toSwap.push(address(weth_BASE));
            // swapPools.push(pool_USDC_WETH_BASE);
            // add wbtc

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
            // additionalVault = address(
            //     _deployBuffer(VaultSetup(usdc_BASE, address(0), address(0), address(0), name, symbol, admin, admin))
            // );
            // vm.label(additionalVault, "AdditionalVault");
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
        // vm.label(address(feeProvider), "Lending FeeProvider");
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

    // function _middleInteractionsOneClick() internal {
    //     vm.startPrank(admin);
    //     uint256 totalLendingSharesBefore = lending.totalLendingShares();
    //     uint256 totalAssetBefore = lending.totalAssets();
    //     uint256 balanceBefore = lending.getBalanceOfPool(vaults[0]);
    //     address[] memory vaults_ = new address[](1);
    //     vaults_[0] = additionalVault;
    //     uint256[] memory lendingShares_ = new uint256[](1);
    //     lendingShares_[0] = lendingShare2;
    //     lending.addLendingPools(vaults_);
    //     lending.setLendingShares(vaults_, lendingShares_);
    //     lending.rebalanceAuto();
    //     vm.assertEq(lending.totalLendingShares(), totalLendingSharesBefore + lendingShare2);
    //     vm.assertLt(lending.getBalanceOfPool(vaults[0]), balanceBefore);
    //     vm.assertGt(lending.getBalanceOfPool(additionalVault), 0);

    //     lendingShares_[0] = 0;
    //     lending.setLendingShares(vaults_, lendingShares_);
    //     lending.rebalanceAuto();
    //     lending.removeLendingPools(vaults_);
    //     vm.assertEq(totalLendingSharesBefore, lending.totalLendingShares());
    //     vm.assertEq(IERC20Metadata(lending.asset()).balanceOf(address(lending)), 0);
    //     vm.assertApproxEqAbs(lending.totalAssets(), totalAssetBefore, totalAssetBefore / 1e3);
    //     vm.assertApproxEqAbs(balanceBefore, lending.getBalanceOfPool(vaults[0]), balanceBefore / 1e3);
    //     vm.stopPrank();
    // }

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
        seasonalVault.setMaxSlippage(1000);
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
        vm.assertApproxEqAbs(newNettoPart, seasonalVault.getNettoPartForTokenOptimistic(), 1e21);
        vm.assertApproxEqAbs(totalAssetsBefore, seasonalVault.totalAssets(), 10 ** asset.decimals());
    }

    function _middleInteractions() internal override {
        vm.startPrank(admin);

        address pool = IUniswapV3Factory(positionManager.factory()).getPool(address(token0), address(token1), poolFee);

        int256 currentPrice = int256(seasonalVault.getCurrentSqrtPrice(pool));
        uint256 nettoPartOptimistic = seasonalVault.getNettoPartForTokenOptimistic();
        console.log("nettoPartOptimistic", nettoPartOptimistic);
        bool isToken0 = seasonalVault.isToken0();
        if (nettoPartOptimistic < 9e23) {
            uint256 newNettoPart = nettoPartOptimistic + 5e22;
            int256 price2;
            int256 price3;
            int256 delta;
            if (isToken0) {
                delta = 10;
                price2 = currentPrice + currentPrice / 95;
                price3 = price2 + currentPrice / 95 + delta;
            } else {
                delta = -10;
                price2 = currentPrice - currentPrice / 95;
                price3 = price2 - currentPrice / 95 - delta;
            }
            uint256 totalAssetsBefore = seasonalVault.totalAssets();
            seasonalVault.openPositionIfNeed(newNettoPart, uint256(currentPrice), uint256(price2), poolFee);
            _checkOpenPosition(newNettoPart, totalAssetsBefore);
            totalAssetsBefore = seasonalVault.totalAssets();
            seasonalVault.openPositionIfNeed(newNettoPart + 5e22, uint256(price2 + delta), uint256(price3), poolFee);
            _checkOpenPosition(newNettoPart + 5e22, totalAssetsBefore);

            // deposit for check swaps
            vm.stopPrank();
            vm.startPrank(user3);
            if (asset == token0) {
                token1.transfer(address(vault), token1.balanceOf(user3));
            } else {
                token0.transfer(address(vault), token0.balanceOf(user3));
            }
            vm.stopPrank();
            uint256 nettoPartReal = seasonalVault.getNettoPartForTokenReal(IERC20Metadata(tokenTreasure));
            uint256 shares3 = _deposit(user3, amount);
            console.log("user3 shares", shares3);
            vm.assertApproxEqAbs(
                seasonalVault.getNettoPartForTokenReal(IERC20Metadata(tokenTreasure)), nettoPartReal, 2e22
            );
            vm.startPrank(admin);
        }
        seasonalVault.closePositionsWorkedOut(); // how to check? // do nothing now
        seasonalVault.investFreeMoney();
        vm.warp(block.timestamp + 1000);
        seasonalVault.claimDEX();
        seasonalVault.closePositionsAll();
        // open position that will trigger closePositionBadMarket
        if (seasonalVault.getNettoPartForTokenOptimistic() < 9e23) {
            if (isToken0) {
                seasonalVault.openPositionIfNeed(
                    9e23, uint256(currentPrice * 8 / 11), uint256(currentPrice * 8 / 12), poolFee
                );
            } else {
                seasonalVault.openPositionIfNeed(
                    9e23, uint256(currentPrice * 11 / 8), uint256(currentPrice * 10 / 8), poolFee
                );
            }
            seasonalVault.closePositionsBadMarket();
        }
        seasonalVault.investFreeMoney();
        vm.stopPrank();
    }

    // function testBase() public fork {
    //     asset = usdb_BLAST;
    //     _provideAndApproveSpecific(true, weth_BLAST, wethAmount);
    //     baseVaultTest(true);
    // }

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

contract ForkSeasonalVaultTestBaseChain is ForkSeasonalVaultBaseTest {
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
    }
}

contract ForkSeasonalVaultTestArbitrum is ForkSeasonalVaultBaseTest {
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
    }
}

// on blast we haven't nice pools without huge slippage
