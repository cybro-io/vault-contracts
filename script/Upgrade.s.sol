// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import "forge-std/Script.sol";
import {DeployUtils} from "../test/DeployUtils.sol";
import {OneClickIndex} from "../src/OneClickIndex.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {
    TransparentUpgradeableProxy,
    ProxyAdmin,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract Upgrade is Script, StdCheats, DeployUtils {
    uint32 public constant feePrecision = 10000;
    address public constant feeRecipient = address(0x66E424337c0f888DCCbCf2e0730A00A526D716f6);
    address public constant cybroWallet = address(0xE1066Cb8c18c408525Ca98C7B0ad70be8D5608CB);
    address public constant cybroManager = address(0xD06Fd4465CdEdD4D8e01ec7ebd5F835cbb22cF01);
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant STRATEGIST_ROLE = keccak256("STRATEGIST_ROLE");
    address[] public managers = [
        address(0x4739fEFA6949fcB90F56a9D6defb3e8d3Fd282F6),
        address(0xEFCFA8a86970fD14Ea9AB593716C2544cedC4Ff7),
        address(0xE1066Cb8c18c408525Ca98C7B0ad70be8D5608CB),
        address(0xD06Fd4465CdEdD4D8e01ec7ebd5F835cbb22cF01)
    ];

    function _getProxyAdmin(address vault) internal view returns (ProxyAdmin proxyAdmin, address admin_) {
        proxyAdmin = ProxyAdmin(address(uint160(uint256(vm.load(address(vault), ERC1967Utils.ADMIN_SLOT)))));
        admin_ = proxyAdmin.owner();
    }

    function _getAdmin(address vault) internal view returns (address admin_) {
        (, admin_) = _getProxyAdmin(vault);
    }

    function _hasManagerRole(OneClickIndex index_, address manager_) internal view returns (bool) {
        return index_.hasRole(MANAGER_ROLE, manager_);
    }

    function _upgrade(OneClickIndex index_) internal {
        console.log("Upgrading index: ", index_.name(), address(index_));
        (ProxyAdmin proxyAdmin, address admin_) = _getProxyAdmin(address(index_));
        address indexManager;
        for (uint256 i = 0; i < managers.length; i++) {
            if (_hasManagerRole(index_, managers[i])) {
                indexManager = managers[i];
                break;
            }
        }
        if (indexManager == address(0)) {
            revert("Member with manager role not found");
        }
        // console.log("Proxy admin: ", address(proxyAdmin));
        // console.log("Admin: ", admin_);
        IERC20Metadata asset = IERC20Metadata(index_.asset());
        console.log("Vault's asset: ", asset.name(), address(asset), "\n");
        vm.startBroadcast(admin_);
        OneClickIndex newImpl = new OneClickIndex(asset, index_.feeProvider(), index_.feeRecipient());
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(index_)), address(newImpl), bytes(""));
        vm.stopBroadcast();

        uint256 decimals = 10 ** index_.decimals();
        _testVaultWorks(index_, decimals);

        vm.startPrank(indexManager);
        index_.rebalanceAuto();
        address[] memory vaults = index_.getPools();
        uint256 totalLendingShares = index_.totalLendingShares();
        console.log("Vault's total assets: ", index_.totalAssets());
        console.log("Vault's total lending shares: ", totalLendingShares, "\n");
        for (uint256 i = 0; i < vaults.length; i++) {
            uint256 vaultBal = index_.getBalanceOfPool(vaults[i]);
            uint256 vaultShares = index_.lendingShares(vaults[i]);
            vm.assertApproxEqAbs(vaultShares * index_.totalAssets() / totalLendingShares, vaultBal, 1 * decimals);
            console.log("Vault's balance", IVault(vaults[i]).name(), vaultBal);
            console.log("Vault's shares: ", vaultShares, "\n");
        }
        vm.stopPrank();
        _testVaultWorks(index_, decimals);
        console.log("TESTS PASSED\n");

        console.log("\n==============================================\n");
    }

    function upgradeBlast() public {
        OneClickIndex index;
        // upgrade Blast Index
        index = OneClickIndex(0xb3E2099b135B12139C4eB774F84a5808FB25c67d);
        _upgrade(index);

        // upgrade Blast Index WETH OLD
        index = OneClickIndex(0xb81d975CC7F80Ede476C1a930720378bda4092A2);
        _upgrade(index);

        // upgrade Blast Index WETH
        index = OneClickIndex(0x6CC97A7eD30242101DeEfD86240aff9E0254EE1d);
        _upgrade(index);
    }

    function upgradeBase() public {
        // upgrade Base Index
        OneClickIndex index = OneClickIndex(0x0655e391e0c6e0b8cBe8C2747Ae15c67c37583B9);
        _upgrade(index);
    }

    function upgradeArbitrum() public {
        // upgrade Arbitrum Index
        OneClickIndex index = OneClickIndex(0x4e433ae90F0D1BE9D88Bed9f7707fcFF20a455aC);
        _upgrade(index);
    }

    function upgradeBSC() public {
        // upgrade BSC Index
        OneClickIndex index = OneClickIndex(0x5351d748eB97116755B423bCC207F3613B487aDe);
        _upgrade(index);
    }

    function _testVaultWorks(OneClickIndex vault, uint256 amount) internal {
        IERC20Metadata token = IERC20Metadata(vault.asset());
        address user = address(100);
        if (vault.asset() == address(usdb_BLAST)) {
            vm.startPrank(assetProvider_USDB_BLAST);
            token.transfer(user, amount);
            vm.stopPrank();
        } else if (vault.asset() == address(weth_BLAST)) {
            vm.startPrank(assetProvider_WETH_BLAST);
            token.transfer(user, amount);
            vm.stopPrank();
        } else {
            deal(vault.asset(), user, amount);
        }

        vm.startPrank(user);
        token.approve(address(vault), amount);
        uint256 shares = vault.deposit(amount, user, 0);
        uint256 assets = vault.redeem(shares, user, user, 0);
        vm.stopPrank();
        console.log("balance of user before", amount);
        console.log("Shares after deposit", shares, "Redeemed assets", assets);
    }
}
