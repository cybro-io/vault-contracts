// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {BaseVault} from "../src/BaseVault.sol";
import {DeployUtils} from "./DeployUtils.sol";
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

contract HackTest is Test, DeployUtils {
    using SafeERC20 for IERC20Metadata;

    GammaAlgebraVault gammaVault;
    BlasterSwapV2Vault blasterVault;
    AlgebraVault algebraVault;
    address constant user = address(10001);
    address constant user2 = address(10002);
    address constant user3 = address(10003);

    uint256 public snapshotId;
    uint256 public amount0;
    uint256 public amount1;
    IERC20Metadata asset;

    function setUp() public {
        gammaVault = GammaAlgebraVault(0x1310b9de457675D65F3838C1E9d19a5ca6619440);
        blasterVault = BlasterSwapV2Vault(0xBFb18Eda8961ee33e38678caf2BcEB2D23aEdfea);
        algebraVault = AlgebraVault(0xE9041d3483A760c7D5F8762ad407ac526fbe144f);
    }

    function _testVaultNotWorks(IVault vault) internal {
        uint256 underlyingTvl_ = vault.underlyingTVL();
        console.log("underlyingTvl", underlyingTvl_);
        uint256 totalAssetsBefore = vault.totalAssets();
        console.log("totalAssetsBefore", totalAssetsBefore);
        asset = IERC20Metadata(vault.asset());
        uint256 decimals_ = 10 ** vault.decimals();
        amount0 = 200 * decimals_;
        amount1 = 400 * decimals_;
        dealTokens(asset, user, amount0);
        dealTokens(asset, user2, amount1);
        dealTokens(asset, user3, amount0);

        vm.prank(user);
        asset.approve(address(vault), type(uint256).max);
        vm.prank(user2);
        asset.approve(address(vault), type(uint256).max);
        snapshotId = vm.snapshotState();

        vm.startPrank(user);
        uint256 shares0_ = vault.deposit(amount0, user, 0);
        vm.stopPrank();

        vm.startPrank(user2);
        uint256 shares1_ = vault.deposit(amount1, user2, 0);
        uint256 assets1_ = vault.redeem(shares1_, user2, user2, 0);
        vm.stopPrank();

        vm.startPrank(user);
        uint256 assets0_ = vault.redeem(shares0_, user, user, 0);
        vm.stopPrank();

        console.log("\nassets user after redeem", assets0_);
        console.log("assets user diff", int256(assets0_) - int256(amount0));
        console.log("\nassets user2 after redeem", assets1_);
        console.log("assets user2 diff", int256(assets1_) - int256(amount1));
        vm.revertToState(snapshotId);
    }

    function _testVaultWorks(IVault vault) internal {
        vm.startPrank(user);
        uint256 shares0_ = vault.deposit(amount0, user, 0);
        uint256 assets0_ = vault.redeem(shares0_, user, user, 0);
        vm.stopPrank();

        vm.startPrank(user2);
        uint256 shares1_ = vault.deposit(amount1, user2, 0);
        uint256 assets1_ = vault.redeem(shares1_, user2, user2, 0);
        vm.assertLt(asset.balanceOf(user2), amount1);
        vm.stopPrank();

        vm.startPrank(user3);
        asset.approve(address(vault), type(uint256).max);
        uint256 shares2_ = vault.deposit(amount0, user3, 0);
        uint256 assets2_ = vault.redeem(shares2_, user3, user3, 0);
        vm.stopPrank();

        console.log("\nassets user after redeem", assets0_);
        console.log("assets user diff", int256(assets0_) - int256(amount0));
        console.log("\nassets user2 after redeem", assets1_);
        console.log("assets user2 diff", int256(assets1_) - int256(amount1));
        console.log("\nassets user3 after redeem", assets2_);
        console.log("assets user3 diff", int256(assets2_) - int256(amount0));
    }

    function test_blasterV2() public {
        vm.createSelectFork("blast");
        vm.startPrank(address(0x4739fEFA6949fcB90F56a9D6defb3e8d3Fd282F6));
        blasterVault.unpause();
        blasterVault.feeProvider().setFees(0, 0, 0);
        vm.stopPrank();

        (ProxyAdmin proxyAdmin, address admin_) = _getProxyAdmin(address(blasterVault));
        console.log("proxyAdmin", address(proxyAdmin));
        console.log("admin_", admin_);

        _testVaultNotWorks(IVault(address(blasterVault)));

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

        _testVaultWorks(IVault(address(blasterVault)));
    }

    function test_algebra() public {
        vm.createSelectFork("blast");
        vm.startPrank(address(0x4739fEFA6949fcB90F56a9D6defb3e8d3Fd282F6));
        algebraVault.unpause();
        algebraVault.feeProvider().setFees(0, 0, 0);
        vm.stopPrank();

        (ProxyAdmin proxyAdmin, address admin_) = _getProxyAdmin(address(algebraVault));
        console.log("proxyAdmin", address(proxyAdmin));
        console.log("admin_", admin_);

        _testVaultNotWorks(IVault(address(algebraVault)));

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

        _testVaultWorks(IVault(address(algebraVault)));
    }

    function test_gamma() public {
        vm.createSelectFork("arbitrum");
        vm.startPrank(address(0x4739fEFA6949fcB90F56a9D6defb3e8d3Fd282F6));
        gammaVault.unpause();
        vm.stopPrank();

        (ProxyAdmin proxyAdmin, address admin_) = _getProxyAdmin(address(gammaVault));
        console.log("proxyAdmin", address(proxyAdmin));
        console.log("admin_", admin_);

        _testVaultNotWorks(IVault(address(gammaVault)));

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

        _testVaultWorks(IVault(address(gammaVault)));
    }
}
