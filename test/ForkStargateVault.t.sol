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

// STG Token 0x296F55F8Fb28E498B858d0BcDA06D955B2Cb3f97

abstract contract StargateVaultTest is AbstractBaseVaultTest {
    IStargatePool usdtPool;
    IStargatePool usdcPool;
    IStargatePool wethPool;

    IStargateStaking staking;
    IERC20Metadata stg;

    IUniswapV3Pool swapPool;
    IUniswapV3Pool swapPoolUSDTWETH;
    IUniswapV3Pool swapPoolUSDCWETH;
    IUniswapV3Factory factory;

    IERC20Metadata usdt;
    IERC20Metadata weth;
    IERC20Metadata usdc;

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
        baseVaultTest(true);
        _checkStargateGetters();
    }

    function test_weth() public {
        amount = amountEth;
        asset = weth;
        currentPool = wethPool;
        currentSwapPool = IUniswapV3Pool(address(0));
        baseVaultTest(true);
        _checkStargateGetters();
    }

    function test_usdc() public {
        asset = usdc;
        currentPool = usdcPool;
        currentSwapPool = swapPoolUSDCWETH;
        baseVaultTest(true);
        _checkStargateGetters();
    }
}

contract StargateVaultArbitrumTest is StargateVaultTest {
    function setUp() public override(StargateVaultTest) {
        forkId = vm.createSelectFork("arbitrum", lastCachedBlockid_ARBITRUM);
        super.setUp();
        usdt = usdtArbitrum;
        weth = wethArbitrum;
        usdc = usdcArbitrum;
        usdtPool = IStargatePool(payable(address(0xcE8CcA271Ebc0533920C83d39F417ED6A0abB7D0)));
        wethPool = IStargatePool(payable(address(0xA45B5130f36CDcA45667738e2a258AB09f4A5f7F)));
        usdcPool = IStargatePool(payable(address(0xe8CDF27AcD73a434D661C84887215F7598e7d0d3)));
        staking = IStargateStaking(payable(address(0x3da4f8E456AC648c489c286B99Ca37B666be7C4C)));
        stg = IERC20Metadata(address(0x6694340fc020c5E6B96567843da2df01b2CE1eb6));
        factory = factory_UNI_ARB;
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
        forkId = vm.createSelectFork("base", lastCachedBlockid_BASE);
        super.setUp();
        // base doesn't have usdt stargate pool
        amount = 1e8;
        amountEth = 1e13;
        weth = wethBase;
        usdc = usdcBase;
        wethPool = IStargatePool(payable(address(0xdc181Bd607330aeeBEF6ea62e03e5e1Fb4B6F7C7)));
        usdcPool = IStargatePool(payable(address(0x27a16dc786820B16E5c9028b75B99F6f604b5d26)));
        staking = IStargateStaking(payable(address(0xDFc47DCeF7e8f9Ab19a1b8Af3eeCF000C7ea0B80)));
        stg = IERC20Metadata(address(0xE3B53AF74a4BF62Ae5511055290838050bf764Df));
        factory = factory_UNI_BASE;
        swapPool = IUniswapV3Pool(factory.getPool(address(stg), address(weth), 10000));
        swapPoolUSDCWETH = IUniswapV3Pool(factory.getPool(address(usdc), address(weth), 500));
        console.log(address(stg) < address(weth));
        console.log(address(usdt) < address(weth));
        console.log("swapPool", address(swapPool));
        console.log("swapPoolUSDTWETH", address(swapPoolUSDTWETH));
        console.log("swapPoolUSDCWETH", address(swapPoolUSDCWETH));
    }
}
