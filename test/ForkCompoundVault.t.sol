// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {CErc20} from "../src/interfaces/compound/IcERC.sol";
import {CEth} from "../src/interfaces/compound/IcETH.sol";
import {CompoundVault, IERC20Metadata} from "../src/vaults/CompoundVaultErc20.sol";
import {CompoundVaultETH} from "../src/vaults/CompoundVaultEth.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IFeeProvider} from "../src/FeeProvider.sol";
import {AbstractBaseVaultTest, IVault} from "./AbstractBaseVault.t.sol";

// 0x8C415331761063E5D6b1c8E700f996b13603Fc2E Orbit WBTC decimals 8
// 0x0872b71EFC37CB8DdE22B2118De3d800427fdba0 oEther V2 decimals 18
// 0x9aECEdCD6A82d26F2f86D331B17a1C1676442A87 Orbit USDB decimals 18

contract CompoundVaultTest is AbstractBaseVaultTest {
    CErc20 usdbPool;
    CErc20 wbtcPool;
    CEth ethPool;
    uint256 wbtcAmount;
    uint256 ethAmount;

    function setUp() public override {
        forkId = vm.createSelectFork("blast", lastCachedBlockid_BLAST);
        super.setUp();
        usdbPool = CErc20(address(0x9aECEdCD6A82d26F2f86D331B17a1C1676442A87));
        wbtcPool = CErc20(address(0x8C415331761063E5D6b1c8E700f996b13603Fc2E));
        ethPool = CEth(address(0x0872b71EFC37CB8DdE22B2118De3d800427fdba0));
        amount = 1e19;
        wbtcAmount = 1 * 1e6;
        ethAmount = 1e18;
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        if (asset == wethBlast) {
            vault = CompoundVaultETH(
                payable(
                    address(
                        new TransparentUpgradeableProxy(
                            address(new CompoundVaultETH(wethBlast, ethPool, IFeeProvider(feeProvider), feeRecipient)),
                            admin,
                            abi.encodeCall(CompoundVaultETH.initialize, (admin, "nameVault", "symbolVault", admin))
                        )
                    )
                )
            );
        } else {
            vault = CompoundVault(
                address(
                    new TransparentUpgradeableProxy(
                        address(
                            new CompoundVault(
                                asset, asset == usdbBlast ? usdbPool : wbtcPool, IFeeProvider(feeProvider), feeRecipient
                            )
                        ),
                        admin,
                        abi.encodeCall(CompoundVault.initialize, (admin, "nameVault", "symbolVault", admin))
                    )
                )
            );
        }
        vm.stopPrank();
    }

    function _increaseVaultAssets() internal pure override returns (bool) {
        return false;
    }

    function test_usdb() public {
        asset = usdbBlast;
        baseVaultTest(true);
    }

    function test_wbtc() public {
        asset = wbtcBlast;
        amount = wbtcAmount;
        baseVaultTest(true);
    }

    function test_eth() public {
        asset = wethBlast;
        amount = ethAmount;
        baseVaultTest(true);
    }
}
