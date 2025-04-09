// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {IFeeProvider} from "../src/FeeProvider.sol";
import {AbstractBaseVaultTest, IVault} from "./AbstractBaseVault.t.sol";

contract SteerCamelotVaultTest is AbstractBaseVaultTest {
    address pool;

    function setUp() public override {
        forkId = vm.createSelectFork("arbitrum", 324543342);
        super.setUp();
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = IVault(
            _deploySteerCamelot(
                VaultSetup({
                    asset: asset,
                    feeRecipient: feeRecipient,
                    feeProvider: address(feeProvider),
                    pool: pool,
                    admin: admin,
                    manager: admin,
                    name: name,
                    symbol: symbol
                })
            )
        );
        vm.stopPrank();
    }

    function _increaseVaultAssets() internal pure override returns (bool) {
        return false;
    }

    function test_wethusdc() public {
        asset = weth_ARBITRUM;
        pool = address(steer_wethusdc_ARBITRUM);
        amount = 1e16;
        baseVaultTest(true);
    }

    function test_usdcweth() public {
        asset = usdc_ARBITRUM;
        pool = address(steer_wethusdc_ARBITRUM);
        amount = 1e9;
        baseVaultTest(true);
    }

    function test_daiusdc() public {
        asset = dai_ARBITRUM;
        pool = address(steer_usdcdai_ARBITRUM);
        amount = 1e20;
        baseVaultTest(true);
    }

    function test_usdcdai() public {
        asset = usdc_ARBITRUM;
        pool = address(steer_usdcdai_ARBITRUM);
        amount = 1e9;
        baseVaultTest(true);
    }
}
