// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {IFeeProvider} from "../src/FeeProvider.sol";
import {AbstractBaseVaultTest, IVault} from "./AbstractBaseVault.t.sol";

contract GammaAlgebraVaultTest is AbstractBaseVaultTest {
    address hypervisor;

    function setUp() public virtual override {
        forkId = vm.createSelectFork("arbitrum", lastCachedBlockid_ARBITRUM);
        super.setUp();
        hypervisor = address(hypervisor_gamma_ARBITRUM);
        name = "Cybro Gamma Algebra USDC";
        symbol = "cygUSDC";
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = IVault(
            _deployGammaAlgebra(
                VaultSetup({
                    asset: asset,
                    pool: hypervisor,
                    feeProvider: address(feeProvider),
                    feeRecipient: feeRecipient,
                    name: name,
                    symbol: symbol,
                    admin: admin,
                    manager: admin
                })
            )
        );
        vm.stopPrank();
    }

    function _increaseVaultAssets() internal pure override returns (bool) {
        return false;
    }

    function test_usdc() public {
        asset = usdc_ARBITRUM;
        amount = 1e9;
        baseVaultTest(true);
    }

    function test_weth() public {
        asset = weth_ARBITRUM;
        amount = 1e18;
        baseVaultTest(true);
    }
}
