// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StargateVault, IERC20Metadata, IStargatePool} from "../src/vaults/StargateVault.sol";
import {IStargateStaking} from "../src/interfaces/stargate/IStargateStaking.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {AbstractBaseVaultTest} from "./AbstractBaseVault.t.sol";

// StargateMultirewarder 0x146c8e409C113ED87C6183f4d25c50251DFfbb3a
// STG Token 0x296F55F8Fb28E498B858d0BcDA06D955B2Cb3f97

abstract contract StargateVaultTest is AbstractBaseVaultTest {
    IStargatePool usdtPool;
    IStargatePool usdcPool;
    IStargatePool wethPool;

    IStargateStaking staking;

    StargateVault usdtVault;
    StargateVault usdcVault;
    StargateVault wethVault;
    IERC20Metadata stg;

    IUniswapV3Pool swapPool;
    IUniswapV3Pool swapPoolUSDTWETH;
    IUniswapV3Pool swapPoolUSDCWETH;
    IUniswapV3Factory factory;

    IERC20Metadata usdt;
    address usdtPrank;
    IERC20Metadata weth;
    address wethPrank;
    IERC20Metadata usdc;
    address usdcPrank;

    uint256 amountEth;

    IUniswapV3Pool currentSwapPool;
    IStargatePool currentPool;

    function setUp() public virtual override(AbstractBaseVaultTest) {
        super.setUp();
        amount = 1e8;
        amountEth = 1e16;
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = StargateVault(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(
                            new StargateVault(
                                currentPool, feeProvider, feeRecipient, staking, stg, weth, swapPool, currentSwapPool
                            )
                        ),
                        admin,
                        abi.encodeCall(StargateVault.initialize, (admin, "nameVault", "symbolVault", admin))
                    )
                )
            )
        );
        vm.stopPrank();
    }

    function _increaseVaultAssets() internal override returns (bool) {
        vm.warp(block.timestamp + 1000);
        vm.startPrank(admin);
        StargateVault(payable(address(vault))).claimReinvest(0);
        vm.assertEq(stg.balanceOf(address(vault)), 0);
        vm.stopPrank();
        return asset == weth ? false : true;
    }

    function _checkStargateGetters() internal view {
        StargateVault stargateVault = StargateVault(payable(address(vault)));
        vm.assertEq(address(stargateVault.stg()), address(stg));
        vm.assertEq(address(stargateVault.weth()), address(weth));
        vm.assertEq(address(stargateVault.stgWethPool()), address(swapPool));
        vm.assertEq(address(stargateVault.assetWethPool()), address(currentSwapPool));
        vm.assertEq(address(stargateVault.pool()), address(currentPool));
    }

    function test_usdt() public fork {
        if (block.chainid == 8453) {
            return;
        }
        asset = usdt;
        currentPool = usdtPool;
        currentSwapPool = swapPoolUSDTWETH;
        baseVaultTest(usdtPrank, true);
        _checkStargateGetters();
    }

    function test_weth() public {
        amount = amountEth;
        asset = weth;
        currentPool = wethPool;
        currentSwapPool = IUniswapV3Pool(address(0));
        baseVaultTest(wethPrank, true);
        _checkStargateGetters();
    }

    function test_usdc() public {
        asset = usdc;
        currentPool = usdcPool;
        currentSwapPool = swapPoolUSDCWETH;
        baseVaultTest(usdcPrank, true);
        _checkStargateGetters();
    }
}

contract StargateVaultArbitrumTest is StargateVaultTest {
    function setUp() public override(StargateVaultTest) {
        forkId = vm.createSelectFork("arbitrum", 296398139);
        super.setUp();
        usdt = IERC20Metadata(address(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9));
        weth = IERC20Metadata(address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1));
        usdc = IERC20Metadata(address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831));
        usdtPrank = address(0xF977814e90dA44bFA03b6295A0616a897441aceC);
        wethPrank = address(0x70d95587d40A2caf56bd97485aB3Eec10Bee6336);
        usdcPrank = address(0x2Df1c51E09aECF9cacB7bc98cB1742757f163dF7);
        usdtPool = IStargatePool(payable(address(0xcE8CcA271Ebc0533920C83d39F417ED6A0abB7D0)));
        wethPool = IStargatePool(payable(address(0xA45B5130f36CDcA45667738e2a258AB09f4A5f7F)));
        usdcPool = IStargatePool(payable(address(0xe8CDF27AcD73a434D661C84887215F7598e7d0d3)));
        staking = IStargateStaking(payable(address(0x3da4f8E456AC648c489c286B99Ca37B666be7C4C)));
        stg = IERC20Metadata(address(0x6694340fc020c5E6B96567843da2df01b2CE1eb6));
        factory = IUniswapV3Factory(address(0x1F98431c8aD98523631AE4a59f267346ea31F984));
        swapPool = IUniswapV3Pool(factory.getPool(address(stg), address(weth), 3000));
        swapPoolUSDTWETH = IUniswapV3Pool(factory.getPool(address(usdt), address(weth), 500));
        swapPoolUSDCWETH = IUniswapV3Pool(factory.getPool(address(usdc), address(weth), 500));
        console.log(address(stg) < address(weth));
        console.log(address(usdt) < address(weth));
        console.log("swapPool", address(swapPool));
        console.log("swapPoolUSDTWETH", address(swapPoolUSDTWETH));
    }
}

contract StargateVaultBaseTest is StargateVaultTest {
    function setUp() public override {
        forkId = vm.createSelectFork("base", 21285741);
        super.setUp();
        // base doesn't have usdt stargate pool
        amount = 1e8;
        amountEth = 1e13;
        weth = IERC20Metadata(address(0x4200000000000000000000000000000000000006));
        usdc = IERC20Metadata(address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913));
        wethPrank = address(0x6446021F4E396dA3df4235C62537431372195D38);
        usdcPrank = address(0xF977814e90dA44bFA03b6295A0616a897441aceC);
        wethPool = IStargatePool(payable(address(0xdc181Bd607330aeeBEF6ea62e03e5e1Fb4B6F7C7)));
        usdcPool = IStargatePool(payable(address(0x27a16dc786820B16E5c9028b75B99F6f604b5d26)));
        staking = IStargateStaking(payable(address(0xDFc47DCeF7e8f9Ab19a1b8Af3eeCF000C7ea0B80)));
        stg = IERC20Metadata(address(0xE3B53AF74a4BF62Ae5511055290838050bf764Df));
        factory = IUniswapV3Factory(address(0x33128a8fC17869897dcE68Ed026d694621f6FDfD));
        swapPool = IUniswapV3Pool(factory.getPool(address(stg), address(weth), 10000));
        swapPoolUSDCWETH = IUniswapV3Pool(factory.getPool(address(usdc), address(weth), 500));
        console.log(address(stg) < address(weth));
        console.log(address(usdt) < address(weth));
        console.log("swapPool", address(swapPool));
        console.log("swapPoolUSDTWETH", address(swapPoolUSDTWETH));
        console.log("swapPoolUSDCWETH", address(swapPoolUSDCWETH));
    }
}
