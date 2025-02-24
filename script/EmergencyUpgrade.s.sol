pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {InitVault, IERC20Metadata} from "../src/InitVault.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {ProxyAdmin, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract EmergencyUpgrade is Script {
    function run() public {
        // vm.createSelectFork("blast");
        InitVault vault = InitVault(0xC66Fc517C8bf1c34Ae48529Df53dD84469e21dAa);
        ProxyAdmin proxyAdmin = ProxyAdmin(address(uint160(uint256(vm.load(address(vault), ERC1967Utils.ADMIN_SLOT)))));
        address admin = proxyAdmin.owner();

        vm.startBroadcast(admin);
        InitVault newImpl = new InitVault(vault.pool(), IERC20Metadata(vault.asset()));

        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(vault)), address(newImpl), new bytes(0));

        address[] memory accounts = new address[](1);
        accounts[0] = 0xAB14b95f5642990b339fEe733a1Be76ACeE980e9;
        vault.emergencyWithdraw(accounts);

        vm.stopBroadcast();
        vault = InitVault(0x24E72C2C7be9B07942F6f8D3cdce995DF699514d);
        proxyAdmin = ProxyAdmin(address(uint160(uint256(vm.load(address(vault), ERC1967Utils.ADMIN_SLOT)))));
        admin = proxyAdmin.owner();

        vm.startBroadcast(admin);
        newImpl = new InitVault(vault.pool(), IERC20Metadata(vault.asset()));

        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(vault)), address(newImpl), new bytes(0));

        accounts = new address[](2);
        accounts[0] = 0xAB14b95f5642990b339fEe733a1Be76ACeE980e9;
        vault.emergencyWithdraw(accounts);
    }
}
