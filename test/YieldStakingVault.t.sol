// // SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {YieldStakingVault, IERC20Metadata, IYieldStaking} from "../src/YieldStakingVault.sol";
import {YieldStaking, WadMath} from "@blastup/launchpad-contracts/YieldStaking.sol";
import {ERC20Mock} from "../src/mocks/ERC20Mock.sol";
import {OracleMock} from "@blastup/launchpad-contracts/mocks/OracleMock.sol";
import {WETHRebasingMock} from "@blastup/launchpad-contracts/mocks/WETHRebasingMock.sol";
import {ERC20RebasingMock} from "@blastup/launchpad-contracts/mocks/ERC20RebasingMock.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {BlastPointsMock} from "@blastup/launchpad-contracts/mocks/BlastPointsMock.sol";

contract YieldStakingVaultTest is Test {
    using WadMath for uint256;

    YieldStaking staking;
    YieldStakingVault vault;

    ERC20Mock testToken;

    OracleMock oracle;
    BlastPointsMock points;

    address internal admin;
    uint256 internal adminPrivateKey;
    address user;
    address user2;
    address user3;
    address user4;

    ERC20RebasingMock constant USDB = ERC20RebasingMock(0x4300000000000000000000000000000000000003);
    WETHRebasingMock constant WETH = WETHRebasingMock(0x4300000000000000000000000000000000000004);

    function setUp() public {
        adminPrivateKey = 0xb18dfe;
        admin = vm.addr(adminPrivateKey);
        user = address(10);
        user2 = address(11);
        user3 = address(12);
        user4 = address(13);

        vm.startPrank(admin);
        oracle = new OracleMock();
        points = new BlastPointsMock();

        ERC20RebasingMock usdb = new ERC20RebasingMock("USDB", "USDB", 18);
        bytes memory code = address(usdb).code;
        vm.etch(0x4300000000000000000000000000000000000003, code);

        WETHRebasingMock weth = new WETHRebasingMock("WETH", "WETH", 18);
        bytes memory code2 = address(weth).code;
        vm.etch(0x4300000000000000000000000000000000000004, code2);

        staking = YieldStaking(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(new YieldStaking(address(123), address(oracle), address(USDB), address(WETH))),
                        admin,
                        abi.encodeCall(YieldStaking.initialize, (admin, address(points), admin))
                    )
                )
            )
        );

        testToken = new ERC20Mock("Token", "TKN", 18);
        vault = YieldStakingVault(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(new YieldStakingVault(IERC20Metadata(USDB), IYieldStaking(address(staking)))),
                        admin,
                        abi.encodeCall(YieldStakingVault.initialize, (admin, "Yield Staking Vault USDB", "YUSDB"))
                    )
                )
            )
        );
        vm.stopPrank();
    }

    function test_stakeFuzz(uint256 amount) public {
        vm.assume(amount > 100 && amount < 1e50);
        vm.startPrank(user);

        USDB.mint(user, amount);
        USDB.approve(address(vault), type(uint256).max);

        vm.expectEmit();
        emit YieldStaking.Staked(address(USDB), address(vault), amount);
        vault.deposit(amount, user);
        vm.stopPrank();
    }

    function test_redeemFuzz(uint256 amountDeposit, uint256 addedRewards) public {
        vm.assume(amountDeposit > 1e3 && amountDeposit < 1e37);
        vm.assume(addedRewards > 1e3 && addedRewards < 1e20);
        vm.startPrank(user);

        USDB.mint(user, amountDeposit);
        USDB.approve(address(vault), type(uint256).max);

        vault.deposit(amountDeposit, user);
        uint256 shares = vault.balanceOf(user);
        USDB.addRewards(address(staking), 1e16);
        vault.redeem(shares, user, user);
        vm.assertGe(USDB.balanceOf(user), amountDeposit);
    }
}
