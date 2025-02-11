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

contract ForkSeasonalVaultTest is AbstractBaseVaultTest {
    IERC20Metadata token0;
    IERC20Metadata token1;
    INonfungiblePositionManager positionManager;
    uint256 wbtcAmount;
    uint256 wethAmount;
    IVault token0Vault;
    IVault token1Vault;

    address[] tokens;
    IChainlinkOracle[] oracles;

    SeasonalVault seasonalVault;
    uint24 poolFee;

    function setUp() public override {
        forkId = vm.createSelectFork("blast", lastCachedBlockid_BLAST);
        super.setUp();
        positionManager = INonfungiblePositionManager(payable(address(0xB218e4f7cF0533d4696fDfC419A0023D33345F28)));
        amount = 2e21;
        token0 = usdb_BLAST;
        token1 = weth_BLAST;
        wbtcAmount = 1e6;
        wethAmount = 1e18;
        poolFee = 3000;
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        token0Vault = IVault(vm.computeCreateAddress(admin, vm.getNonce(admin) + 3));
        token1Vault = IVault(vm.computeCreateAddress(admin, vm.getNonce(admin) + 5));
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
        IVault checkusdb = _deployBufferVaultMock(
            VaultSetup({
                asset: token0,
                pool: address(0),
                feeProvider: address(0),
                feeRecipient: address(0),
                manager: address(0),
                name: name,
                symbol: symbol,
                admin: admin
            })
        );
        IVault checkwbtc = _deployBufferVaultMock(
            VaultSetup({
                asset: token1,
                pool: address(0),
                feeProvider: address(0),
                feeRecipient: address(0),
                manager: address(0),
                name: name,
                symbol: symbol,
                admin: admin
            })
        );
        vm.assertEq(address(token0Vault), address(checkusdb));
        vm.assertEq(address(token1Vault), address(checkwbtc));
        vm.stopPrank();
    }

    function _increaseVaultAssets() internal pure override returns (bool) {
        return false;
    }

    function test() public fork {
        asset = usdb_BLAST;
        _initializeNewVault();
        _provideAndApprove(true);
        _provideAndApproveSpecific(true, weth_BLAST, wethAmount);
        _checkPause();

        vm.startPrank(admin);
        seasonalVault.setFeeForSwaps(poolFee);
        tokens.push(address(usdb_BLAST));
        oracles.push(oracle_USDB_BLAST);
        tokens.push(address(weth_BLAST));
        oracles.push(oracle_ETH_BLAST);
        tokens.push(address(wbtc_BLAST));
        oracles.push(oracle_BTC_BLAST);
        seasonalVault.setOracles(tokens, oracles);
        seasonalVault.setTreasureToken(address(weth_BLAST));
        vm.stopPrank();

        vm.startPrank(user);
        weth_BLAST.transfer(address(vault), wethAmount);
        usdb_BLAST.transfer(address(vault), amount);
        vm.stopPrank();

        vm.assertGt(vault.totalAssets(), 0);
        vm.startPrank(admin);
        seasonalVault.updatePoolForFee(poolFee);
        console.log("getCurrentTick", seasonalVault.getCurrentTick(seasonalVault.pools(poolFee)));
        console.log("partof", seasonalVault.getNettoPartForTokenOptimistic());
        console.log("price", seasonalVault.getCurrentSqrtPrice(seasonalVault.pools(poolFee)));
        uint256 currentPrice = seasonalVault.getCurrentSqrtPrice(seasonalVault.pools(poolFee));
        seasonalVault.openPositionIfNeed(9e23, currentPrice, currentPrice + currentPrice / 95, poolFee);

        console.log("totalAssets", vault.totalAssets());

        seasonalVault.claimDEX();
        seasonalVault.closePositionsWorkedOut();
        seasonalVault.closePositionsBadMarket();
        console.log("totalAssets", vault.totalAssets());
        console.log("nettoPart", seasonalVault.getNettoPartForTokenOptimistic());
        seasonalVault.investFreeMoney();
        console.log("totalAssets", vault.totalAssets());
        vm.assertGt(vault.underlyingTVL(), 0);
        seasonalVault.closePositionsAll();
        seasonalVault.openPositionIfNeed(9e23, currentPrice * 11 / 8, currentPrice * 12 / 8, poolFee);
        console.log("nettoPart before bad market", seasonalVault.getNettoPartForTokenOptimistic());
        seasonalVault.closePositionsBadMarket();
        console.log("nettoPart after bad market", seasonalVault.getNettoPartForTokenOptimistic());
        vm.stopPrank();
    }
}
