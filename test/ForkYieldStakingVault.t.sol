// // SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {YieldStakingVault, IERC20Metadata, IYieldStaking} from "../src/YieldStakingVault.sol";
import {YieldStaking} from "@blastup/launchpad-contracts/YieldStaking.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract ForkYieldStakingTest is Test {
    YieldStakingVault vault;
    IYieldStaking staking;
    IERC20Metadata token;
    uint256 amount;
    uint256 forkId;
    address user;

    address internal admin;
    uint256 internal adminPrivateKey;

    function setUp() public {
        adminPrivateKey = 0xba132ce;
        admin = vm.addr(adminPrivateKey);
        forkId = vm.createSelectFork("https://rpc.blast.io/");
        user = address(100);
        amount = 1e20;
        staking = IYieldStaking(address(0x0E84461a00C661A18e00Cab8888d146FDe10Da8D));
    }

    modifier fork() {
        vm.selectFork(forkId);
        _;
    }

    function _deposit() internal returns (uint256 shares) {
        vm.startPrank(admin);
        vault = YieldStakingVault(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(new YieldStakingVault(token, IYieldStaking(staking))),
                        admin,
                        abi.encodeCall(YieldStakingVault.initialize, (admin, "Yield Staking Vault", "YVLT"))
                    )
                )
            )
        );
        vm.stopPrank();
        vm.startPrank(user);
        token.approve(address(vault), amount);
        shares = vault.deposit(amount, user);
        vm.stopPrank();
    }

    function _redeem(uint256 shares) internal returns (uint256 assets) {
        vm.startPrank(user);
        assets = vault.redeem(shares, user, user);
        vm.stopPrank();
    }

    function test_usdb() public fork {
        token = IERC20Metadata(address(0x4300000000000000000000000000000000000003));
        vm.prank(address(0x236F233dBf78341d25fB0F1bD14cb2bA4b8a777c));
        token.transfer(user, amount);
        uint256 shares = _deposit();

        _redeem(shares);
        console.log(token.balanceOf(user));
    }

    function test_weth() public fork {
        token = IERC20Metadata(address(0x4300000000000000000000000000000000000004));
        vm.prank(address(0x44f33bC796f7d3df55040cd3C631628B560715C2));
        token.transfer(user, amount);
        uint256 shares = _deposit();

        _redeem(shares);
        console.log(token.balanceOf(user));
    }
}
