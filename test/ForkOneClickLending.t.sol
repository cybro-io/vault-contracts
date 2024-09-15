// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {IAavePool} from "../src/interfaces/aave/IPool.sol";
import {AaveVault, IERC20Metadata} from "../src/AaveVault.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
    TransparentUpgradeableProxy,
    ProxyAdmin
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {JuiceVault} from "../src/JuiceVault.sol";
import {IJuicePool} from "../src/interfaces/juice/IJuicePool.sol";
import {OneClickLending} from "../src/OneClickLending.sol";

contract OneClickLendingTest is Test {
    IAavePool aavePool;
    IJuicePool usdbJuicePool;
    JuiceVault juiceVault;
    AaveVault aaveVault;
    IERC20Metadata usdb = IERC20Metadata(address(0x4300000000000000000000000000000000000003));
    uint256 amount;
    uint256 amount2;
    uint256 forkId;
    address user;
    address user2;

    OneClickLending lending;
    uint256 lendingShare;
    uint256 lendingShare2;
    uint8 precision;

    address internal admin;
    uint256 internal adminPrivateKey;

    function setUp() public {
        adminPrivateKey = 0xba132ce;
        admin = vm.addr(adminPrivateKey);
        forkId = vm.createSelectFork("blast", 8149175);
        aavePool = IAavePool(address(0xd2499b3c8611E36ca89A70Fda2A72C49eE19eAa8));
        usdbJuicePool = IJuicePool(address(0x4A1d9220e11a47d8Ab22Ccd82DA616740CF0920a));
        amount = 1e20;
        amount2 = 2e21;
        precision = 20;
        lendingShare = 25 * 10 ** (precision - 2);
        lendingShare2 = 50 * 10 ** (precision - 2);
        user = address(100);
        user2 = address(101);
        vm.startPrank(admin);
        lending = OneClickLending(
            address(
                new TransparentUpgradeableProxy(
                    address(new OneClickLending(usdb)),
                    admin,
                    abi.encodeCall(OneClickLending.initialize, (admin, "nameVault", "symbolVault"))
                )
            )
        );
        vm.stopPrank();
    }

    modifier fork() {
        vm.selectFork(forkId);
        _;
    }

    function _initializeUSDBVaults() internal {
        aaveVault = AaveVault(
            address(
                new TransparentUpgradeableProxy(
                    address(new AaveVault(usdb, aavePool)),
                    admin,
                    abi.encodeCall(AaveVault.initialize, (admin, "nameVault", "symbolVault"))
                )
            )
        );

        juiceVault = JuiceVault(
            address(
                new TransparentUpgradeableProxy(
                    address(new JuiceVault(usdb, usdbJuicePool)),
                    admin,
                    abi.encodeCall(JuiceVault.initialize, (admin, "nameVault", "symbolVault"))
                )
            )
        );
        vm.startPrank(admin);
        address[] memory vaults = new address[](2);
        vaults[0] = address(aaveVault);
        vaults[1] = address(juiceVault);
        uint256[] memory lendingShares = new uint256[](2);
        lendingShares[0] = lendingShare;
        lendingShares[1] = lendingShare2;
        lending.addLendingPools(vaults);
        lending.setLendingShares(vaults, lendingShares);
        vm.stopPrank();
    }

    function test() public {
        _initializeUSDBVaults();
        vm.startPrank(address(0x236F233dBf78341d25fB0F1bD14cb2bA4b8a777c));
        usdb.transfer(user, amount);
        usdb.transfer(user2, amount2);
        vm.stopPrank();

        vm.startPrank(user);
        usdb.approve(address(lending), amount);
        uint256 userShares = lending.deposit(amount, user);
        console.log("user shares", userShares);
        vm.stopPrank();

        vm.startPrank(user2);
        usdb.approve(address(lending), amount2);
        uint256 user2Shares = lending.deposit(amount2, user2);
        console.log("user2 shares", user2Shares);
        vm.stopPrank();

        // update lending share
        vm.startPrank(admin);
        address[] memory vaults = new address[](1);
        vaults[0] = address(aaveVault);
        uint256[] memory lendingShares = new uint256[](1);
        lendingShares[0] = lendingShare2;
        lending.setLendingShares(vaults, lendingShares);
        lending.rebalance(address(juiceVault), address(aaveVault), juiceVault.balanceOf(address(lending)) / 4 - 1000);
        vm.stopPrank();
        // redeem
        vm.startPrank(user);
        lending.redeem(userShares / 2, user, user);
        vm.assertApproxEqAbs(usdb.balanceOf(user), amount / 2, amount / 1e10);
        vm.stopPrank();
        vm.startPrank(user2);
        lending.redeem(user2Shares / 2, user2, user2);
        vm.assertApproxEqAbs(usdb.balanceOf(user2), amount2 / 2, amount2 / 1e10);
        vm.stopPrank();
    }
}
