// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {OneClickIndex} from "../src/OneClickIndex.sol";
import {FeeProvider, IFeeProvider} from "../src/FeeProvider.sol";
import {BufferVaultMock} from "../src/mocks/BufferVaultMock.sol";
import {AbstractBaseVaultTest} from "./AbstractBaseVault.t.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {IChainlinkOracle} from "../src/interfaces/IChainlinkOracle.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

abstract contract OneClickIndexBaseTest is AbstractBaseVaultTest {
    address usdbPrank = address(0x3Ba925fdeAe6B46d0BB4d424D829982Cb2F7309e);
    uint256 amount2;

    OneClickIndex lending;
    uint256 lendingShare;
    uint256 lendingShare2;
    uint8 precision;
    address[] vaults;
    uint256[] lendingShares;
    address[] tokens;
    IChainlinkOracle[] oracles;

    address[] fromSwap;
    address[] toSwap;
    IUniswapV3Pool[] swapPools;

    address additionalVault;

    function setUp() public virtual override(AbstractBaseVaultTest) {
        super.setUp();
        amount = 1e20;
        amount2 = 2e21;
        precision = 20;
        lendingShare = 25 * 10 ** (precision - 2);
        lendingShare2 = 50 * 10 ** (precision - 2);
    }

    function _setOracles() internal {
        if (tokens.length == 0) return;
        vm.startPrank(user5);
        vm.expectRevert();
        lending.setOracles(tokens, oracles);
        vm.stopPrank();

        vm.startPrank(admin);
        lending.setOracles(tokens, oracles);
        vm.stopPrank();
    }

    function _setSwapPools() internal {
        if (fromSwap.length == 0) return;
        vm.startPrank(user5);
        vm.expectRevert();
        lending.setSwapPools(fromSwap, toSwap, swapPools);
        vm.stopPrank();

        vm.startPrank(admin);
        lending.setSwapPools(fromSwap, toSwap, swapPools);
        vm.stopPrank();
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        if (block.chainid == 81457) {
            // blast
            asset = usdb_BLAST;
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

            vaults.push(
                address(
                    _deployAave(
                        VaultSetup(
                            usdb_BLAST,
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
                            usdb_BLAST,
                            address(0x4A1d9220e11a47d8Ab22Ccd82DA616740CF0920a),
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
                        VaultSetup(
                            usdb_BLAST,
                            address(0x0E84461a00C661A18e00Cab8888d146FDe10Da8D),
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
            additionalVault = address(
                _deployBuffer(VaultSetup(usdb_BLAST, address(0), address(0), address(0), name, symbol, admin, admin))
            );
        } else if (block.chainid == 42161) {
            // arbitrum
            asset = usdt_ARBITRUM;
            amount = 1e9; // decimals = 6
            lendingShares.push(lendingShare);
            vaults.push(
                address(
                    _deployStargate(
                        VaultSetup(
                            usdt_ARBITRUM,
                            address(stargate_usdtPool_ARBITRUM),
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

            additionalVault = address(
                _deployBuffer(VaultSetup(usdt_ARBITRUM, address(0), address(0), address(0), name, symbol, admin, admin))
            );
        } else if (block.chainid == 8453) {
            // base
            asset = usdc_BASE;
            amount = 1e9; // decimals = 6
            fromSwap.push(address(usdc_BASE));
            toSwap.push(address(weth_BASE));
            swapPools.push(pool_USDC_WETH_BASE);

            lendingShares.push(lendingShare);
            lendingShares.push(lendingShare2);

            tokens.push(address(usdc_BASE));
            oracles.push(oracle_USDC_BASE);
            tokens.push(address(weth_BASE));
            oracles.push(oracle_ETH_BASE);

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
            vaults.push(
                address(
                    _deployStargate(
                        VaultSetup(
                            weth_BASE,
                            address(stargate_wethPool_BASE),
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
            additionalVault = address(
                _deployBuffer(VaultSetup(usdc_BASE, address(0), address(0), address(0), name, symbol, admin, admin))
            );
            vm.label(additionalVault, "AdditionalVault");
        }
        vault = IVault(
            address(
                new TransparentUpgradeableProxy(
                    address(new OneClickIndex(asset, feeProvider, feeRecipient)),
                    admin,
                    abi.encodeCall(OneClickIndex.initialize, (admin, name, symbol, admin, admin))
                )
            )
        );
        vaultAddress = address(vault);
        address[] memory whitelistedContracts = new address[](1);
        whitelistedContracts[0] = vaultAddress;
        bool[] memory isWhitelisted = new bool[](1);
        isWhitelisted[0] = true;
        feeProvider.setWhitelistedContracts(whitelistedContracts, isWhitelisted);
        lending = OneClickIndex(address(vault));
        lending.addLendingPools(vaults);
        lending.setLendingShares(vaults, lendingShares);
        lending.setMaxSlippage(100);
        vm.stopPrank();
        _setOracles();
        _setSwapPools();
    }

    function _middleInteractions() internal override {
        vm.startPrank(admin);
        uint256 totalLendingSharesBefore = lending.totalLendingShares();
        uint256 totalAssetBefore = lending.totalAssets();
        uint256 balanceBefore = lending.getBalanceOfPool(vaults[0]);
        address[] memory vaults_ = new address[](1);
        vaults_[0] = additionalVault;
        uint256[] memory lendingShares_ = new uint256[](1);
        lendingShares_[0] = lendingShare2;
        lending.addLendingPools(vaults_);
        lending.setLendingShares(vaults_, lendingShares_);
        lending.rebalanceAuto();
        vm.assertEq(lending.totalLendingShares(), totalLendingSharesBefore + lendingShare2);
        vm.assertLt(lending.getBalanceOfPool(vaults[0]), balanceBefore);
        vm.assertGt(lending.getBalanceOfPool(additionalVault), 0);

        lendingShares_[0] = 0;
        lending.setLendingShares(vaults_, lendingShares_);
        lending.rebalanceAuto();
        lending.removeLendingPools(vaults_);
        vm.assertEq(totalLendingSharesBefore, lending.totalLendingShares());
        vm.assertEq(IERC20Metadata(lending.asset()).balanceOf(address(lending)), 0);
        vm.assertApproxEqAbs(lending.totalAssets(), totalAssetBefore, totalAssetBefore / 1e3);
        vm.assertApproxEqAbs(balanceBefore, lending.getBalanceOfPool(vaults[0]), balanceBefore / 1e3);
        vm.stopPrank();
    }

    function _increaseVaultAssets() internal pure override returns (bool) {
        return false;
    }

    function _checkOneClickGetters() internal view {
        vm.assertEq(lending.getLendingPoolCount(), vaults.length);
        for (uint256 i = 0; i < vaults.length; i++) {
            vm.assertEq(lending.getSharePriceOfPool(vaults[i]), IVault(vaults[i]).sharePrice());
        }
        vm.assertEq(lending.getPools().length, vaults.length);
    }

    function test() public {
        baseVaultTest(true);
        _checkOneClickGetters();
    }
}

contract OneClickIndexBaseChainTest is OneClickIndexBaseTest {
    function setUp() public override(OneClickIndexBaseTest) {
        forkId = vm.createSelectFork("base", lastCachedBlockid_BASE);
        super.setUp();
    }
}

contract OneClickIndexArbitrumTest is OneClickIndexBaseTest {
    function setUp() public override(OneClickIndexBaseTest) {
        vm.createSelectFork("arbitrum", lastCachedBlockid_ARBITRUM);
        super.setUp();
    }
}

contract OneClickIndexBlastTest is OneClickIndexBaseTest {
    function setUp() public override(OneClickIndexBaseTest) {
        vm.createSelectFork("blast", lastCachedBlockid_BLAST);
        super.setUp();
    }
}
