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

contract Upgrade is Script {
    uint32 public constant feePrecision = 10000;
    address public constant feeRecipient = address(0x66E424337c0f888DCCbCf2e0730A00A526D716f6);
    address public constant cybroWallet = address(0xE1066Cb8c18c408525Ca98C7B0ad70be8D5608CB);
    address public constant cybroManager = address(0xD06Fd4465CdEdD4D8e01ec7ebd5F835cbb22cF01);
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant STRATEGIST_ROLE = keccak256("STRATEGIST_ROLE");

    function _getProxyAdmin(address vault) internal view returns (ProxyAdmin proxyAdmin, address admin_) {
        proxyAdmin = ProxyAdmin(address(uint160(uint256(vm.load(address(vault), ERC1967Utils.ADMIN_SLOT)))));
        admin_ = proxyAdmin.owner();
    }

    function _getAdmin(address vault) internal view returns (address admin_) {
        (, admin_) = _getProxyAdmin(vault);
    }

    function run() public {
        OneClickIndex index = OneClickIndex(0x4241F743678652E4e38385C54033D0BBB243BF5d);
        (ProxyAdmin proxyAdmin, address admin_) = _getProxyAdmin(address(index));

        vm.startBroadcast(admin_);
        OneClickIndex newImpl = new OneClickIndex(
            IERC20Metadata(index.asset()),
            index.feeProvider(),
            index.feeRecipient()
        );
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(index)), address(newImpl), bytes(""));
        vm.stopBroadcast();
        // check if rebalanceAuto is working
        // vm.startPrank(0xD06Fd4465CdEdD4D8e01ec7ebd5F835cbb22cF01);
        // index.rebalanceAuto();
        // address[] memory vaults = index.getPools();
        // for (uint256 i = 0; i < vaults.length; i++) {
        //     console.log(index.lendingShares(vaults[i]));
        //     console.log(index.getBalanceOfPool(vaults[i]), "\n");
        // }
        // vm.stopPrank();
    }
}
