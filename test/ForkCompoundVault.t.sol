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
    IERC20Metadata usdb;
    IERC20Metadata wbtc;
    IERC20Metadata weth;
    uint256 wbtcAmount;
    uint256 ethAmount;

    function setUp() public override {
        forkId = vm.createSelectFork("blast", 8149175);
        super.setUp();
        usdbPool = CErc20(address(0x9aECEdCD6A82d26F2f86D331B17a1C1676442A87));
        wbtcPool = CErc20(address(0x8C415331761063E5D6b1c8E700f996b13603Fc2E));
        ethPool = CEth(address(0x0872b71EFC37CB8DdE22B2118De3d800427fdba0));
        usdb = IERC20Metadata(address(0x4300000000000000000000000000000000000003));
        wbtc = IERC20Metadata(address(0xF7bc58b8D8f97ADC129cfC4c9f45Ce3C0E1D2692));
        weth = IERC20Metadata(address(0x4300000000000000000000000000000000000004));
        amount = 1e19;
        wbtcAmount = 1 * 1e6;
        ethAmount = 1e18;
    }

    function _initializeNewVault() internal override {
        vm.startPrank(admin);
        if (asset == weth) {
            vault = CompoundVaultETH(
                payable(
                    address(
                        new TransparentUpgradeableProxy(
                            address(new CompoundVaultETH(weth, ethPool, IFeeProvider(feeProvider), feeRecipient)),
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
                                asset, asset == usdb ? usdbPool : wbtcPool, IFeeProvider(feeProvider), feeRecipient
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
        asset = usdb;
        baseVaultTest(address(0x3Ba925fdeAe6B46d0BB4d424D829982Cb2F7309e), true);
    }

    function test_wbtc() public {
        asset = wbtc;
        amount = wbtcAmount;
        baseVaultTest(address(0xecb1c17a51D782aC2757e2AB568d159854b9B4BD), true);
    }

    function test_eth() public fork {
        asset = weth;
        amount = ethAmount;
        baseVaultTest(address(0xecb1c17a51D782aC2757e2AB568d159854b9B4BD), true);
    }
}
