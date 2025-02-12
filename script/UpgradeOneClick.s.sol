// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {CompoundVault, IERC20Metadata} from "../src/CompoundVaultErc20.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {ProxyAdmin, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {OneClickLending} from "../src/OneClickLending.sol";
import {StargateVault} from "../src/StargateVault.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

contract EmergencyUpgrade is Script {
    function run() public {
        StargateVault vault = StargateVault(payable(0x36E1e81062d842bf3a910732C5Ee1DC9457663E7));
        ProxyAdmin proxyAdmin = ProxyAdmin(address(uint160(uint256(vm.load(address(vault), ERC1967Utils.ADMIN_SLOT)))));
        address admin = proxyAdmin.owner();

        IERC20Metadata weth = IERC20Metadata(address(0x4200000000000000000000000000000000000006));
        IUniswapV3Pool assetWethPool = IUniswapV3Pool(0xCf58eaC3C7D16796Aea617a7E2461c99CaCDFf1D);

        vm.startBroadcast(admin);
        StargateVault newImpl = new StargateVault(
            vault.pool(),
            vault.feeProvider(),
            vault.feeRecipient(),
            vault.staking(),
            vault.stg(),
            weth,
            vault.stgWethPool(),
            assetWethPool
        );

        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(vault)), address(newImpl), new bytes(0));
    }
}
