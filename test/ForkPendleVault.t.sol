// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {AbstractBaseVaultTest, IVault} from "./AbstractBaseVault.t.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {PendleVault, IPMarket} from "../src/PendleVault.sol";
import "@pendle/core-v2/interfaces/IPAllActionTypeV3.sol";
import {IStandardizedYield} from "@pendle/core-v2/interfaces/IStandardizedYield.sol";
import {MarketState} from "@pendle/core-v2/interfaces/IPMarket.sol";
import {IPPrincipalToken} from "@pendle/core-v2/interfaces/IPPrincipalToken.sol";
import {MarketMathCore} from "@pendle/core-v2/core/Market/MarketMathCore.sol";
import {LogExpMath} from "@pendle/core-v2/core/libraries/math/LogExpMath.sol";
import {IPRouterStatic} from "@pendle/core-v2/interfaces/IPRouterStatic.sol";
import {PendleLpOracleLib} from "@pendle/core-v2/oracles/PtYtLpOracle/PendleLpOracleLib.sol";

contract PendleVaultTest is AbstractBaseVaultTest {
    address market;

    function setUp() public override {
        forkId = vm.createSelectFork("arbitrum", lastCachedBlockid_ARBITRUM);
        super.setUp();
        amount = 1e18;
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = _deployPendle(
            VaultSetup(
                asset, address(pendle_router_ARBITRUM), address(feeProvider), feeRecipient, name, symbol, admin, admin
            )
        );
        PendleVault(address(vault)).setNewMarket(market);
        vm.stopPrank();
    }

    function _increaseVaultAssets() internal pure override returns (bool) {
        return false;
    }

    // function test_weETH() public fork {
    //     asset = eETH_ARBITRUM;
    //     market = address(pendle_market_eETH_ARBITRUM);
    //     baseVaultTest(true);
    // }

    function test_wbtc() public fork {
        asset = wbtc_ARBITRUM;
        amount = 1e7;
        market = address(pendle_market_WBTC_ARBITRUM);
        baseVaultTest(true);
    }
}
