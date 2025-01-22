// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {AbstractBaseVaultTest, IVault} from "./AbstractBaseVault.t.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract AaveVaultTest is AbstractBaseVaultTest {
    function setUp() public override {
        forkId = vm.createSelectFork("blast", lastCachedBlockid_BLAST);
        amount = 1e20;
        super.setUp();
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        vault = _deployAave(
            VaultSetup(
                asset, address(aave_zerolendPool_BLAST), address(feeProvider), feeRecipient, name, symbol, admin, admin
            )
        );
        vm.stopPrank();
    }

    function _increaseVaultAssets() internal pure override returns (bool) {
        return false;
    }

    function test_usdb() public {
        asset = usdb_BLAST;
        baseVaultTest(true);
    }

    function test_weth_deposit() public {
        asset = weth_BLAST;
        baseVaultTest(true);
    }
}
