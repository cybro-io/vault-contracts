// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StargateVault, IERC20Metadata, IStargatePool} from "../src/vaults/StargateVault.sol";
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
    IStargatePool usdcPool;
    IStargatePool wethPool;

    IStargateStaking staking;
    IStargateMultiRewarder rewarder;

    StargateVault usdtVault;
    StargateVault usdcVault;
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
    uint32 administrationFee;
    uint32 maxAdministrationFee;
    uint32 feePrecision;

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

    function setUp() public virtual {
        adminPrivateKey = 0xba132ce;
        admin = vm.addr(adminPrivateKey);
        amount = 1e8;
        amountEth = 1e16;
        user = address(100);
        user2 = address(101);
        feeRecipient = address(102);
        depositFee = 100;
        withdrawalFee = 200;
        performanceFee = 300;
        administrationFee = 100;
        maxAdministrationFee = 1000;
        feePrecision = 1e5;
        vm.startPrank(admin);
        feeProvider = FeeProvider(
            address(
                new TransparentUpgradeableProxy(
                    address(new FeeProvider(feePrecision, maxAdministrationFee)),
                    admin,
                    abi.encodeCall(
                        FeeProvider.initialize, (admin, depositFee, withdrawalFee, performanceFee, administrationFee)
                    )
                )
            )
        );
        vm.stopPrank();
    }

    modifier fork() {
        vm.selectFork(forkId);
        _;
    }

    function _initializeNewVault(IStargatePool _pool, IUniswapV3Pool _assetWethPool)
        internal
        returns (StargateVault vault)
    {
        vm.startPrank(admin);
        address vaultAddress = vm.computeCreateAddress(admin, vm.getNonce(admin) + 1);
        token.approve(vaultAddress, 10 ** token.decimals() * 2);
        vault = StargateVault(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(
                            new StargateVault(
                                _pool, feeProvider, feeRecipient, staking, stg, weth, swapPool, _assetWethPool
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

    function _deposit(StargateVault vault, uint256 _amount) internal returns (uint256 shares) {
        vm.startPrank(user);
        token.approve(address(vault), _amount);
        shares = vault.deposit(_amount, user, 0);
        vm.stopPrank();
    }

    function _redeem(uint256 shares, StargateVault vault) internal returns (uint256 assets) {
        vm.startPrank(user);
        assets = vault.redeem(shares, user, user, 0);
        vm.stopPrank();
    }

    function _calculateDepositFee(uint256 _amount) internal view returns (uint256) {
        return (_amount * feeProvider.getDepositFee(user)) / feePrecision;
    }

    function _calculateWithdrawalFee(uint256 _amount) internal view returns (uint256) {
        return (_amount * feeProvider.getWithdrawalFee(user)) / feePrecision;
    }

    function test_usdt() public fork {
        if (block.chainid == 8453) {
            return;
        }
        token = usdt;
        vm.startPrank(usdtPrank);
        token.transfer(user, amount);
        token.transfer(admin, 10 ** token.decimals() * 2);
        vm.stopPrank();
        usdtVault = _initializeNewVault(usdtPool, swapPoolUSDTWETH);
        vm.assertEq(usdtVault.getDepositFee(user), depositFee);
        vm.assertEq(usdtVault.getWithdrawalFee(user), withdrawalFee);
        vm.assertEq(usdtVault.getPerformanceFee(user), performanceFee);
        vm.assertEq(usdtVault.feePrecision(), feePrecision);

        // tests pause
        vm.prank(admin);
        usdtVault.pause();
        vm.startPrank(user);
        token.approve(address(usdtVault), amount);
        vm.expectRevert();
        usdtVault.deposit(amount, user, 0);
        vm.stopPrank();
        vm.prank(admin);
        usdtVault.unpause();

        uint256 shares = _deposit(usdtVault, amount);
        console.log("shares", shares);
        vm.warp(block.timestamp + 100);

        uint256 sharePriceBefore = usdtVault.sharePrice();
        vm.startPrank(admin);
        usdtVault.claimReinvest(0);
        vm.assertEq(stg.balanceOf(address(usdtVault)), 0);
        vm.stopPrank();
        assert(usdtVault.sharePrice() >= sharePriceBefore);

        vm.startPrank(admin);
        uint256 depositedBalanceBefore = usdtVault.getWaterline(user);
        address[] memory users = new address[](2);
        users[0] = user;
        usdtVault.collectPerformanceFee(users);
        assert(usdtVault.getWaterline(user) >= depositedBalanceBefore);
        vm.stopPrank();

        uint256 assets = _redeem(shares, usdtVault);
        vm.assertEq(assets, token.balanceOf(user));
        vm.assertGt(token.balanceOf(user), _calculateWithdrawalFee(_calculateDepositFee(amount)));
        console.log(token.balanceOf(user));
        console.log("share price", usdtVault.sharePrice());
        console.log(stg.balanceOf(address(usdtVault)));
    }

    function test_weth() public fork {
        token = weth;
        vm.startPrank(wethPrank);
        token.transfer(user, amountEth);
        token.transfer(admin, 10 ** token.decimals() * 2);
        vm.stopPrank();
        wethVault = _initializeNewVault(wethPool, IUniswapV3Pool(address(0)));
        vm.assertEq(wethVault.getDepositFee(user), depositFee);
        vm.assertEq(wethVault.getWithdrawalFee(user), withdrawalFee);
        vm.assertEq(wethVault.getPerformanceFee(user), performanceFee);
        vm.assertEq(wethVault.feePrecision(), feePrecision);
        uint256 shares = _deposit(wethVault, amountEth);
        console.log("shares", shares);
        console.log("share price", wethVault.sharePrice());

        vm.warp(block.timestamp + 100);
        uint256 sharePriceBefore = wethVault.sharePrice();
        vm.startPrank(admin);
        wethVault.claimReinvest(0);
        vm.assertEq(stg.balanceOf(address(wethVault)), 0);
        vm.stopPrank();
        assert(wethVault.sharePrice() >= sharePriceBefore);

        uint256 assets = _redeem(shares, wethVault);
        assert(assets <= token.balanceOf(user));
        vm.assertGt(token.balanceOf(user), _calculateWithdrawalFee(_calculateDepositFee(amount)));
    }

    function test_usdc() public fork {
        token = usdc;
        vm.startPrank(usdcPrank);
        token.transfer(user, amount);
        token.transfer(admin, 10 ** token.decimals() * 2);
        vm.stopPrank();
        usdcVault = _initializeNewVault(usdcPool, swapPoolUSDCWETH);
        vm.assertEq(usdcVault.getDepositFee(user), depositFee);
        vm.assertEq(usdcVault.getWithdrawalFee(user), withdrawalFee);
        vm.assertEq(usdcVault.getPerformanceFee(user), performanceFee);
        vm.assertEq(usdcVault.feePrecision(), feePrecision);

        // tests pause
        vm.prank(admin);
        usdcVault.pause();
        vm.startPrank(user);
        token.approve(address(usdcVault), amount);
        vm.expectRevert();
        usdcVault.deposit(amount, user, 0);
        vm.stopPrank();
        vm.prank(admin);
        usdcVault.unpause();

        uint256 shares = _deposit(usdcVault, amount);
        console.log("shares", shares);
        vm.assertGt(usdcVault.balanceOf(user), 0);
        vm.assertGt(usdcVault.totalSupply(), 0);
        vm.assertGt(usdcVault.sharePrice(), 0);
        vm.assertGt(usdcVault.getBalanceInUnderlying(user), 0);
        vm.assertEq(usdcVault.getProfit(user), 0);

        vm.warp(block.timestamp + 100);
        uint256 sharePriceBefore = usdcVault.sharePrice();
        vm.startPrank(admin);
        usdcVault.claimReinvest(0);
        vm.assertEq(stg.balanceOf(address(usdcVault)), 0);
        vm.stopPrank();
        assert(usdcVault.sharePrice() >= sharePriceBefore);

        uint256 assets = _redeem(shares, usdcVault);
        vm.assertEq(assets, token.balanceOf(user));
        vm.assertGt(token.balanceOf(user), _calculateWithdrawalFee(_calculateDepositFee(amount)));
        console.log(token.balanceOf(user));
        console.log("share price", usdcVault.sharePrice());
        console.log(stg.balanceOf(address(usdcVault)));
    }
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
        forkId = vm.createSelectFork("arbitrum", 267245449);
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
