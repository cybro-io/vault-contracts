// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StargateVault, IERC20Metadata, IStargatePool} from "../src/StargateVault.sol";
import {IStargateStaking} from "../src/interfaces/stargate/IStargateStaking.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
    TransparentUpgradeableProxy,
    ProxyAdmin
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {FeeProvider, IFeeProvider} from "../src/FeeProvider.sol";
import {IStargateMultiRewarder} from "../src/interfaces/stargate/IStargateMultirewarder.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

// StargateMultirewarder 0x146c8e409C113ED87C6183f4d25c50251DFfbb3a
// getRewards()
// STG Token 0x296F55F8Fb28E498B858d0BcDA06D955B2Cb3f97

abstract contract StargateVaultTest is Test {
    IStargatePool usdtPool;
    // IInitLendingPool wethPool;
    // IInitLendingPool blastPool;
    IStargateStaking staking;
    IStargateMultiRewarder rewarder;
    StargateVault usdtVault;
    StargateVault wethVault;
    IERC20Metadata token;
    uint256 amount;
    uint256 forkId;
    address user;
    address user2;
    IERC20Metadata stg;

    address internal admin;
    uint256 internal adminPrivateKey;

    uint8 precision;
    address feeRecipient;
    IFeeProvider feeProvider;

    uint32 depositFee;
    uint32 withdrawalFee;
    uint32 performanceFee;
    uint32 feePrecision;

    IUniswapV3Pool swapPool;
    IUniswapV3Pool swapPoolUSDTWETH;
    IUniswapV3Factory factory;

    IERC20Metadata usdt;
    address usdtPrank;
    IERC20Metadata weth;
    address wethPrank;

    function setUp() public virtual {
        adminPrivateKey = 0xba132ce;
        admin = vm.addr(adminPrivateKey);
        amount = 1e8;
        user = address(100);
        user2 = address(101);
        feeRecipient = address(102);
        depositFee = 100;
        withdrawalFee = 200;
        performanceFee = 300;
        feePrecision = 1e5;
        vm.startPrank(admin);
        feeProvider = FeeProvider(
            address(
                new TransparentUpgradeableProxy(
                    address(new FeeProvider(feePrecision)), admin, abi.encodeCall(FeeProvider.initialize, (admin))
                )
            )
        );
        feeProvider.setFees(depositFee, withdrawalFee, performanceFee);
        vm.stopPrank();
    }

    modifier fork() {
        vm.selectFork(forkId);
        _;
    }

    function _initializeNewVault(IStargatePool _pool) internal returns (StargateVault vault) {
        vm.startPrank(admin);
        vault = StargateVault(
            address(
                new TransparentUpgradeableProxy(
                    address(new StargateVault(_pool, feeProvider, feeRecipient, staking, stg, weth)),
                    admin,
                    abi.encodeCall(StargateVault.initialize, (admin, "nameVault", "symbolVault"))
                )
            )
        );
        vault.setSwapPools(swapPool, swapPoolUSDTWETH);
        vm.stopPrank();
    }

    function _deposit(StargateVault vault) internal returns (uint256 shares) {
        vm.startPrank(user);
        token.approve(address(vault), amount);
        shares = vault.deposit(amount, user);
        vm.stopPrank();
    }

    function _redeem(uint256 shares, StargateVault vault) internal returns (uint256 assets) {
        vm.startPrank(user);
        assets = vault.redeem(shares, user, user);
        vm.stopPrank();
    }

    function test_usdt() public fork {
        token = usdt;
        usdtVault = _initializeNewVault(usdtPool);
        vm.prank(usdtPrank);
        token.transfer(user, amount);

        // // tests pause
        vm.prank(admin);
        usdtVault.pause();
        vm.startPrank(user);
        token.approve(address(usdtVault), amount);
        vm.expectRevert();
        usdtVault.deposit(amount, user);
        vm.stopPrank();
        vm.prank(admin);
        usdtVault.unpause();

        address[] memory tokens = staking.tokens();
        console.log("tokens", tokens[2]);
        // console.log("rewarder", staking.rewarder(address(0x9f58A79D81477130C0C6D74b96e1397db9765ab1)));

        uint256 shares = _deposit(usdtVault);
        console.log("shares", shares);
        // console.log("balance", usdt.balanceOf(address(usdbVault)));
        // vm.assertApproxEqAbs(usdbVault.sharePrice(), 1e18, 100);
        // console.log("share price", usdbVault.sharePrice());
        // decimals of pool's lp = usdb.decimals + 16 = wusdb.decimlas + 8
        // wusdb.decimals = usdb.decimals + 8
        // (, uint256[] memory rewards) = rewarder.getRewards(usdtVault.lpToken(), address(usdtVault));
        // console.log(rewards[0]);
        vm.warp(block.timestamp + 100);

        vm.startPrank(admin);
        usdtVault.claimReinvest(0, 0);
        vm.stopPrank();
        // (, rewards) = rewarder.getRewards(usdtVault.lpToken(), address(usdtVault));
        // console.log(rewards[0]);
        // IStargatePool(address(usdtPool)).accrueInterest();
        uint256 assets = _redeem(shares, usdtVault);
        console.log(token.balanceOf(user));
        // vm.assertApproxEqAbs(usdbVault.sharePrice(), 1e18, 100);
        console.log("share price", usdtVault.sharePrice());
        // vm.assertGt(stg.balanceOf(address(usdtVault)), 0);
        console.log(stg.balanceOf(address(usdtVault)));
    }

    // function test_weth() public fork {
    //     token = IERC20Metadata(address(0x4300000000000000000000000000000000000004));
    //     wethVault = _initializeNewVault(wethPool);
    //     vm.prank(address(0x66714DB8F3397c767d0A602458B5b4E3C0FE7dd1));
    //     token.transfer(user, amount);
    //     uint256 shares = _deposit(wethVault);
    //     console.log("shares", shares);
    //     console.log("underlying", address(wethVault.underlying()));
    //     console.log("share price", wethVault.sharePrice());
    //     vm.assertApproxEqAbs(wethVault.sharePrice(), 1e18, 10);

    //     vm.warp(block.timestamp + 100);
    //     IInitLendingPool(address(wethPool)).accrueInterest();
    //     uint256 assets = _redeem(shares, wethVault);
    //     console.log(token.balanceOf(user));
    //     vm.assertApproxEqAbs(wethVault.sharePrice(), 1e18, 100);
    //     console.log("share price", wethVault.sharePrice());
    //     vm.assertGt(assets, amount);
    // }
}

// contract StargateVaultOptimismTest is StargateVaultTest {
//     function setUp() public override {
//         forkId = vm.createSelectFork("optimism", 126796973);
//         super.setUp();
//         usdt = IERC20Metadata(address(0x94b008aA00579c1307B0EF2c499aD98a8ce58e58));
//         weth = IERC20Metadata(address(0x4200000000000000000000000000000000000006));
//         usdtPrank = address(0xF977814e90dA44bFA03b6295A0616a897441aceC);
//         wethPrank = address(0x86E715415D8C8435903d1e8204fA1e9784Aa7305);
//         usdtPool = IStargatePool(payable(address(0x19cFCE47eD54a88614648DC3f19A5980097007dD)));
//         // wethPool = IInitLendingPool(address(0xD20989EB39348994AA99F686bb4554090d0C09F3));
//         // blastPool = IInitLendingPool(address(0xdafB6929442303e904A2f673A0E7EB8753Bab571));
//         staking = IStargateStaking(payable(address(0xFBb5A71025BEf1A8166C9BCb904a120AA17d6443)));
//         // rewarder = IStargateMultiRewarder(staking.rewarder(address(0x9f58A79D81477130C0C6D74b96e1397db9765ab1)));
//         stg = IERC20Metadata(address(0x296F55F8Fb28E498B858d0BcDA06D955B2Cb3f97));
//         factory = IUniswapV3Factory(address(0x1A8027625C830aAC43aD82a3f7cD6D5fdCE89d78));
//         // swapPool = IUniswapV3Pool(factory.getPool(address(usdt), address(stg), 3000));
//         // console.log("swapPool", address(swapPool));
//     }
// }

contract StargateVaultArbitrumTest is StargateVaultTest {
    function setUp() public override {
        forkId = vm.createSelectFork("arbitrum", 265204481);
        super.setUp();
        usdt = IERC20Metadata(address(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9));
        weth = IERC20Metadata(address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1));
        usdtPrank = address(0xF977814e90dA44bFA03b6295A0616a897441aceC);
        wethPrank = address(0x70d95587d40A2caf56bd97485aB3Eec10Bee6336);
        usdtPool = IStargatePool(payable(address(0xcE8CcA271Ebc0533920C83d39F417ED6A0abB7D0)));
        // wethPool = IInitLendingPool(address(0xD20989EB39348994AA99F686bb4554090d0C09F3));
        // blastPool = IInitLendingPool(address(0xdafB6929442303e904A2f673A0E7EB8753Bab571));
        staking = IStargateStaking(payable(address(0x3da4f8E456AC648c489c286B99Ca37B666be7C4C)));
        // rewarder = IStargateMultiRewarder(staking.rewarder(address(0x9f58A79D81477130C0C6D74b96e1397db9765ab1)));
        stg = IERC20Metadata(address(0x6694340fc020c5E6B96567843da2df01b2CE1eb6));
        factory = IUniswapV3Factory(address(0x1F98431c8aD98523631AE4a59f267346ea31F984));
        swapPool = IUniswapV3Pool(factory.getPool(address(stg), address(weth), 3000));
        swapPoolUSDTWETH = IUniswapV3Pool(factory.getPool(address(usdt), address(weth), 500));
        console.log(address(stg) < address(weth));
        console.log(address(usdt) < address(weth));
        console.log("swapPool", address(swapPool));
        console.log("swapPoolUSDTWETH", address(swapPoolUSDTWETH));
    }
}
