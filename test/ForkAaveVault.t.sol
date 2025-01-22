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
                asset, address(aave_usdbPool_BLAST), address(feeProvider), feeRecipient, name, symbol, admin, admin
            )
        );
        vm.stopPrank();
    }

    function _increaseVaultAssets() internal pure override returns (bool) {
        return false;
    }

    function _checkEmergencyWithdraw(address _user) internal override {
        address[] memory accounts = new address[](2);
        accounts[0] = _user;
        accounts[1] = user5;

        vm.startPrank(user5);
        vm.expectRevert();
        vault.emergencyWithdraw(accounts);
        vm.stopPrank();
    }

    function test_usdb() public {
        asset = usdb_BLAST;
        baseVaultTest(true);
    }

    function test_weth_deposit() public {
        asset = weth_BLAST;
        baseVaultTest(true);
    }

    function test_otherTokens_deposit() public {
        asset = IERC20Metadata(address(0x66714DB8F3397c767d0A602458B5b4E3C0FE7dd1));
        deal(address(asset), user, amount);
        deal(address(asset), user2, amount);
        deal(address(asset), admin, amount);
        baseVaultTest(false);
    }
}
