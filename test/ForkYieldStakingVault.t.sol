// // SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {YieldStakingVault, IERC20Metadata, IYieldStaking, IFeeProvider} from "../src/YieldStakingVault.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IShares} from "../src/interfaces/IShares.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";

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
        forkId = vm.createSelectFork("blast", 8149175);
        user = address(100);
        amount = 1e20;
        staking = IYieldStaking(payable(address(0x0E84461a00C661A18e00Cab8888d146FDe10Da8D)));
    }

    modifier fork() {
        vm.selectFork(forkId);
        _;
    }

    function _deposit() internal returns (uint256 shares) {
        vm.prank(admin);
        vault = YieldStakingVault(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(
                            new YieldStakingVault(token, IYieldStaking(staking), IFeeProvider(address(0)), address(0))
                        ),
                        admin,
                        abi.encodeCall(YieldStakingVault.initialize, (admin, "Yield Staking Vault", "YVLT"))
                    )
                )
            )
        );
        vm.startPrank(user);
        token.approve(address(vault), amount);
        shares = vault.deposit(amount, user);
        vm.stopPrank();
    }

    function _redeem(uint256 shares) internal returns (uint256 assets) {
        vm.prank(user);
        assets = vault.redeem(shares, user, user);
    }

    function test_usdb() public fork {
        token = IERC20Metadata(address(0x4300000000000000000000000000000000000003));
        vm.prank(address(0x236F233dBf78341d25fB0F1bD14cb2bA4b8a777c));
        token.transfer(user, amount);
        uint256 shares = _deposit();

        vm.startPrank(address(0xB341285d5683C74935ad14c446E137c8c8829549));
        IShares(address(token)).addValue(IShares(address(token)).count() * 3);
        vm.stopPrank();

        _redeem(shares);
        vm.assertGt(token.balanceOf(user), amount);
    }

    function test_weth() public fork {
        token = IERC20Metadata(address(0x4300000000000000000000000000000000000004));
        vm.prank(address(0x44f33bC796f7d3df55040cd3C631628B560715C2));
        token.transfer(user, amount);
        uint256 shares = _deposit();

        vm.deal(address(token), address(token).balance * 101 / 100);

        vm.prank(address(0x4300000000000000000000000000000000000000));
        IShares(address(token)).addValue(0);

        _redeem(shares);
        vm.assertGt(token.balanceOf(user), amount);
    }
}
