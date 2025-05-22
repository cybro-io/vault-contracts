// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.29;

import "forge-std/Script.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {BaseVault} from "../src/BaseVault.sol";
import {DeployUtils} from "../test/DeployUtils.sol";
import {GammaAlgebraVault, IUniProxy, IHypervisor} from "../src/vaults/GammaAlgebraVault.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BlasterSwapV2Vault} from "../src/dex/BlasterSwapV2Vault.sol";
import {AlgebraVault} from "../src/dex/AlgebraVault.sol";
import {
    TransparentUpgradeableProxy,
    ProxyAdmin,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IVault} from "../src/interfaces/IVault.sol";

contract Upgrade is Script, StdCheats, DeployUtils {
    function upgradeBlasterV2() public {
        BlasterSwapV2Vault blasterVault = BlasterSwapV2Vault(0xBFb18Eda8961ee33e38678caf2BcEB2D23aEdfea);
        (ProxyAdmin proxyAdmin, address admin_) = _getProxyAdmin(address(blasterVault));
        console.log("proxyAdmin", address(proxyAdmin));
        console.log("admin_", admin_, "\n");
        vm.startBroadcast(admin_);
        BlasterSwapV2Vault newImpl = new BlasterSwapV2Vault(
            payable(address(blasterVault.router())),
            blasterVault.token0(),
            blasterVault.token1(),
            IERC20Metadata(blasterVault.asset()),
            blasterVault.feeProvider(),
            blasterVault.feeRecipient(),
            address(blasterVault.oracleToken0()),
            address(blasterVault.oracleToken1())
        );
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(blasterVault)), address(newImpl), bytes(""));
        vm.stopBroadcast();
        _testVaultWorks(BaseVault(address(blasterVault)), 400 * (10 ** blasterVault.decimals()));
    }

    function upgradeAlgebra() public {
        AlgebraVault algebraVault = AlgebraVault(0xE9041d3483A760c7D5F8762ad407ac526fbe144f);
        (ProxyAdmin proxyAdmin, address admin_) = _getProxyAdmin(address(algebraVault));
        console.log("proxyAdmin", address(proxyAdmin));
        console.log("admin_", admin_, "\n");
        vm.startBroadcast(admin_);
        AlgebraVault newImpl = new AlgebraVault(
            payable(address(algebraVault.positionManager())),
            algebraVault.token0(),
            algebraVault.token1(),
            IERC20Metadata(algebraVault.asset()),
            algebraVault.feeProvider(),
            algebraVault.feeRecipient(),
            address(algebraVault.oracleToken0()),
            address(algebraVault.oracleToken1())
        );
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(algebraVault)), address(newImpl), bytes(""));
        vm.stopBroadcast();
        _testVaultWorks(BaseVault(address(algebraVault)), 400 * (10 ** algebraVault.decimals()));
    }

    function upgradeGamma() public {
        GammaAlgebraVault gammaVault = GammaAlgebraVault(0x1310b9de457675D65F3838C1E9d19a5ca6619440);
        (ProxyAdmin proxyAdmin, address admin_) = _getProxyAdmin(address(gammaVault));
        console.log("proxyAdmin", address(proxyAdmin));
        console.log("admin_", admin_, "\n");
        vm.startBroadcast(admin_);
        GammaAlgebraVault newImpl = new GammaAlgebraVault(
            address(gammaVault.hypervisor()),
            address(gammaVault.uniProxy()),
            IERC20Metadata(gammaVault.asset()),
            gammaVault.feeProvider(),
            gammaVault.feeRecipient(),
            address(oracle_ETH_ARBITRUM),
            address(oracle_USDC_ARBITRUM)
        );
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(gammaVault)), address(newImpl), bytes(""));
        vm.stopBroadcast();
        _testVaultWorks(BaseVault(address(gammaVault)), 400 * (10 ** gammaVault.decimals()));
    }

    function _testVaultWorks(BaseVault vault, uint256 amount) internal {
        console.log("\nTESTS:");
        vm.startPrank(address(0x4739fEFA6949fcB90F56a9D6defb3e8d3Fd282F6));
        try vault.unpause() {} catch {}
        try vault.feeProvider().setFees(0, 0, 0) {} catch {}
        IERC20Metadata token = IERC20Metadata(vault.asset());
        address user = address(100);
        dealTokens(token, user, amount);

        vm.startPrank(user);
        token.approve(address(vault), amount);
        uint256 shares = vault.deposit(amount, user, 0);
        uint256 assets = vault.redeem(shares, user, user, 0);
        vm.stopPrank();
        console.log("balance of user before", amount);
        console.log("Shares after deposit", shares, "Redeemed assets", assets);
    }
}
