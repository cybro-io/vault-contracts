import {Script} from "forge-std/Script.sol";
import {CompoundVault, IERC20Metadata} from "../src/CompoundVaultErc20.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {ProxyAdmin, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract EmergencyUpgrade is Script {
    function run() public {
        CompoundVault vault = CompoundVault(0xB4e96a45699b4CfC08BB6dd71eb1276bfe4e26e7);
        ProxyAdmin proxyAdmin = ProxyAdmin(address(uint160(uint256(vm.load(address(vault), ERC1967Utils.ADMIN_SLOT)))));
        address admin = proxyAdmin.owner();

        vm.startBroadcast(admin);
        CompoundVault newImpl = new CompoundVault(IERC20Metadata(vault.asset()), vault.pool());

        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(vault)), address(newImpl), new bytes(0));

        address[] memory accounts = new address[](1);
        accounts[0] = 0x1838b71d2012E6d0bA6251df365bB74D9e3029Aa;
        vault.emergencyWithdraw(accounts);
    }
}
