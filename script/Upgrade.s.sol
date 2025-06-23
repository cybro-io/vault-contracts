// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.29;

import "forge-std/Script.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {BaseVault} from "../src/BaseVault.sol";
import {DeployUtils} from "../test/DeployUtils.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    TransparentUpgradeableProxy,
    ProxyAdmin,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {SeasonalVault} from "../src/SeasonalVault.sol";
import {SeasonalVault4626} from "../src/4626/SeasonalVault4626.sol";
import {FeeProvider} from "../src/FeeProvider.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC4626Mixin} from "../src/ERC4626Mixin.sol";

contract Upgrade is Script, StdCheats, DeployUtils {
    function upgradeSeasonalBaseCBWBTC() public {
        SeasonalVault seasonalVault = SeasonalVault(0xdD996648B02Bf22d9C348e11d470938f8aE50F2b);
        (ProxyAdmin proxyAdmin, address admin_) = _getProxyAdmin(address(seasonalVault));
        console.log("proxyAdmin", address(proxyAdmin));
        console.log("admin_", admin_, "\n");
        uint256 totalAssetsBefore = seasonalVault.totalAssets();
        address cybroWallet = address(0xE1066Cb8c18c408525Ca98C7B0ad70be8D5608CB);
        vm.startBroadcast(cybroWallet);
        FeeProvider feeProvider = FeeProvider(address(seasonalVault.feeProvider()));
        feeProvider.setFees(feeProvider.getDepositFee(address(0)), feeProvider.getWithdrawalFee(address(0)), 0);
        vm.stopBroadcast();

        vm.startBroadcast(admin_);
        SeasonalVault4626 newImpl = new SeasonalVault4626(
            payable(address(seasonalVault.positionManager())),
            IERC20Metadata(seasonalVault.asset()),
            address(seasonalVault.token0()),
            address(seasonalVault.token1()),
            seasonalVault.feeProvider(),
            seasonalVault.feeRecipient(),
            seasonalVault.token0Vault(),
            seasonalVault.token1Vault()
        );
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(seasonalVault)), address(newImpl), bytes(""));
        vm.stopBroadcast();
        vm.assertApproxEqAbs(seasonalVault.totalAssets(), totalAssetsBefore, totalAssetsBefore / 10000);
        vm.assertEq(seasonalVault.getPerformanceFee(address(admin_)), 0);
        _testVaultWorks(BaseVault(address(seasonalVault)), 400 * (10 ** seasonalVault.decimals()));
    }

    function _testVaultWorks(BaseVault vault, uint256 amount) internal {
        console.log("\nTESTS:");
        IERC20Metadata token = IERC20Metadata(vault.asset());
        IERC4626 vault4626 = IERC4626(address(vault));
        address user = address(100);
        dealTokens(token, user, amount);

        vm.startPrank(user);
        token.approve(address(vault), amount);
        uint256 shares = vault.deposit(amount, user, 0);
        uint256 assets = vault.redeem(shares, user, user, 0);
        vm.stopPrank();
        console.log("balance of user before", amount);
        console.log("Shares after deposit", shares, "Redeemed assets", assets);

        address user2 = address(101);
        dealTokens(token, user2, amount);
        vm.startPrank(user2);
        token.approve(address(vault), amount);
        // test 4626
        uint256 previewDeposit = vault4626.previewDeposit(amount);
        uint256 shares2 = vault4626.deposit(amount, user2);
        vm.assertEq(vault4626.maxRedeem(user2), shares2);
        uint256 previewRedeem = vault4626.previewRedeem(shares2);
        uint256 assets2 = vault4626.redeem(shares2, user2, user2);

        uint32 maxSlippageForPreview = ERC4626Mixin(address(vault4626)).getMaxSlippageForPreview();
        (bool success, bytes memory returnData) = address(vault).call(abi.encodeWithSignature("maxSlippage()"));
        if (success) {
            vm.assertEq(abi.decode(returnData, (uint32)), maxSlippageForPreview);
        }
        if (maxSlippageForPreview > 0) {
            vm.assertLt(previewDeposit, shares2);
            vm.assertLt(previewRedeem, assets2);
        }
        vm.assertEq(vault4626.maxDeposit(user2), type(uint256).max);
        console.log("balance of user2 before", amount);
        console.log("Shares after deposit", shares2, "Redeemed assets", assets2);
        console.log();
        vm.stopPrank();
    }
}
