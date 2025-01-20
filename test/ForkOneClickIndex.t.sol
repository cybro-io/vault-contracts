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
            asset = usdbBlast;
            lendingShares.push(lendingShare);
            lendingShares.push(lendingShare);
            lendingShares.push(lendingShare2);
            // lendingShares.push(lendingShare2);

            tokens.push(address(usdbBlast));
            oracles.push(oracle_USDB_BLAST);
            tokens.push(address(wethBlast));
            oracles.push(oracle_ETH_BLAST);
            tokens.push(address(wbtcBlast));
            oracles.push(oracle_BTC_BLAST);

            vaults.push(
                address(
                    _deployAave(
                        VaultSetup(
                            usdbBlast,
                            address(0xd2499b3c8611E36ca89A70Fda2A72C49eE19eAa8),
                            address(0),
                            address(0),
                            "nameVault",
                            "symbolVault",
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
                            usdbBlast,
                            address(0x4A1d9220e11a47d8Ab22Ccd82DA616740CF0920a),
                            address(0),
                            address(0),
                            "nameVault",
                            "symbolVault",
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
                            usdbBlast,
                            address(0x0E84461a00C661A18e00Cab8888d146FDe10Da8D),
                            address(0),
                            address(0),
                            "nameVault",
                            "symbolVault",
                            admin,
                            admin
                        )
                    )
                )
            );
            additionalVault = address(
                _deployBuffer(
                    VaultSetup(usdbBlast, address(0), address(0), address(0), "nameVault", "symbolVault", admin, admin)
                )
            );
        } else if (block.chainid == 42161) {
            // arbitrum
            asset = usdtArbitrum;
            amount = 1e9; // decimals = 6
            lendingShares.push(lendingShare);
            vaults.push(
                address(
                    _deployStargate(
                        VaultSetup(
                            usdtArbitrum,
                            address(0xcE8CcA271Ebc0533920C83d39F417ED6A0abB7D0),
                            address(0),
                            address(0),
                            "nameVault",
                            "symbolVault",
                            admin,
                            admin
                        )
                    )
                )
            );

            additionalVault = address(
                _deployBuffer(
                    VaultSetup(
                        usdtArbitrum, address(0), address(0), address(0), "nameVault", "symbolVault", admin, admin
                    )
                )
            );
        } else if (block.chainid == 8453) {
            // base
            asset = usdcBase;
            amount = 1e9; // decimals = 6
            fromSwap.push(address(usdcBase));
            toSwap.push(address(wethBase));
            swapPools.push(pool_USDC_WETH_BASE);

            lendingShares.push(lendingShare);
            lendingShares.push(lendingShare2);

            tokens.push(address(usdcBase));
            oracles.push(oracle_USDC_BASE);
            tokens.push(address(wethBase));
            oracles.push(oracle_ETH_BASE);

            vaults.push(
                address(
                    _deployStargate(
                        VaultSetup(
                            usdcBase,
                            address(0x27a16dc786820B16E5c9028b75B99F6f604b5d26),
                            address(0),
                            address(0),
                            "nameVault",
                            "symbolVault",
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
                            wethBase,
                            address(0xdc181Bd607330aeeBEF6ea62e03e5e1Fb4B6F7C7),
                            address(0),
                            address(0),
                            "nameVault",
                            "symbolVault",
                            admin,
                            admin
                        )
                    )
                )
            );
            additionalVault = address(
                _deployBuffer(
                    VaultSetup(usdcBase, address(0), address(0), address(0), "nameVault", "symbolVault", admin, admin)
                )
            );
            vm.label(additionalVault, "AdditionalVault");
        }
        vault = IVault(
            address(
                new TransparentUpgradeableProxy(
                    address(new OneClickIndex(asset, feeProvider, feeRecipient)),
                    admin,
                    abi.encodeCall(OneClickIndex.initialize, (admin, "nameVault", "symbolVault", admin, admin))
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
        vm.assertApproxEqAbs(balanceBefore, lending.getBalanceOfPool(vaults[0]), 1e8);
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
