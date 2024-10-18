// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {MockVault, IERC20Metadata} from "../src/mocks/MockVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {WETHMock, ERC20Mock} from "../src/mocks/WETHMock.sol";
import {
    TransparentUpgradeableProxy,
    ProxyAdmin
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IFeeProvider} from "../src/interfaces/IFeeProvider.sol";

contract DeployScript is Script {
    function deployMock() public {
        vm.startBroadcast();
        (, address admin,) = vm.readCallers();

        ERC20Mock usdb = new ERC20Mock("USDB", "USDB", 18);
        MockVault vaultUSDB = MockVault(
            address(
                new TransparentUpgradeableProxy(
                    address(new MockVault(usdb, IFeeProvider(address(0)), address(0))),
                    admin,
                    abi.encodeCall(MockVault.initialize, (admin, "USDB vault", "USDBV"))
                )
            )
        );

        WETHMock weth = new WETHMock("WETH", "WETH", 18);
        MockVault vaultWETH = MockVault(
            address(
                new TransparentUpgradeableProxy(
                    address(new MockVault(usdb, IFeeProvider(address(0)), address(0))),
                    admin,
                    abi.encodeCall(MockVault.initialize, (admin, "WETH vault", "WETHV"))
                )
            )
        );

        ERC20Mock wbtc = new ERC20Mock("WBTC", "WBTC", 8);
        MockVault vaultWBTC = MockVault(
            address(
                new TransparentUpgradeableProxy(
                    address(new MockVault(usdb, IFeeProvider(address(0)), address(0))),
                    admin,
                    abi.encodeCall(MockVault.initialize, (admin, "WBTC vault", "WBTCV"))
                )
            )
        );

        console.log("USDB", address(usdb));
        console.log("weth", address(weth));
        console.log("wbtc", address(wbtc));
        console.log("usdb vault", address(vaultUSDB));
        console.log("weth vault", address(vaultWETH));
        console.log("wbtc vault", address(vaultWBTC));
    }
}
