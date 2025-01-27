// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Exchange} from "../../src/Exchange.sol";
import {IWETH} from "../../src/interfaces/IWETH.sol";
import {IChainlinkOracle} from "../../src/interfaces/IChainlinkOracle.sol";
import {Oracle} from "../../src/Oracle.sol";
import {ERC20Mock} from "../../src/mocks/ERC20Mock.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract ExchangeTest is Test {
    Exchange exchange;
    IERC20Metadata usdb;
    IERC20Metadata weth;
    uint256 amount;
    uint256 amountEth;
    uint256 forkId;
    address user;
    address user2;

    address usdbGiver;
    address wethGiver;

    IChainlinkOracle oracle;
    Oracle oracleCybro;
    ERC20Mock cybro;

    uint32 spreadPrecision = 10000;
    uint32 spread;

    address internal admin;
    uint256 internal adminPrivateKey;

    function setUp() public {
        adminPrivateKey = 0xba132ce;
        admin = vm.addr(adminPrivateKey);
        forkId = vm.createSelectFork("blast", 12783864);
        usdbGiver = address(0x4BeD2A922654cAcC2Be974689619768FaBF24855);
        wethGiver = address(0x66714DB8F3397c767d0A602458B5b4E3C0FE7dd1);
        usdb = IERC20Metadata(address(0x4300000000000000000000000000000000000003));
        weth = IERC20Metadata(address(0x4300000000000000000000000000000000000004));
        amount = 1e20;
        amountEth = 1e18;
        user = address(100);
        user2 = address(101);
        spread = 1000;
        vm.startPrank(admin);
        cybro = new ERC20Mock("Cybro", "CYBRO", 18);
        oracle = IChainlinkOracle(address(0x0af23B08bcd8AD35D1e8e8f2D2B779024Bd8D24A));
        oracleCybro = Oracle(
            address(
                new TransparentUpgradeableProxy(
                    address(new Oracle(address(cybro), address(usdb))),
                    admin,
                    abi.encodeCall(Oracle.initialize, (admin))
                )
            )
        );
        exchange = Exchange(
            address(
                new TransparentUpgradeableProxy(
                    address(new Exchange(address(weth), address(usdb), address(oracle), address(oracleCybro))),
                    admin,
                    abi.encodeCall(Exchange.initialize, (admin, spread))
                )
            )
        );
        vm.stopPrank();
    }

    modifier fork() {
        vm.selectFork(forkId);
        _;
    }

    function _givesAndApproves() internal {
        vm.startPrank(usdbGiver);
        usdb.transfer(user, amount);
        usdb.transfer(user2, amount);
        usdb.transfer(admin, amount);
        vm.stopPrank();
        vm.startPrank(wethGiver);
        weth.transfer(user, amountEth);
        weth.transfer(user2, amountEth);
        weth.transfer(admin, amountEth);
        vm.stopPrank();

        vm.startPrank(user);
        usdb.approve(address(exchange), amount);
        weth.approve(address(exchange), amountEth);
        cybro.approve(address(exchange), 1e25);
        vm.stopPrank();

        vm.startPrank(user2);
        usdb.approve(address(exchange), amount);
        weth.approve(address(exchange), amountEth);
        cybro.approve(address(exchange), 1e25);
        vm.stopPrank();
    }

    function test() public fork {
        _givesAndApproves();
        vm.prank(admin);
        oracleCybro.updatePrice(2e18);

        vm.startPrank(user);
        vm.expectRevert();
        // insufficient liquidity
        exchange.buy(amount, user, true);
        vm.stopPrank();

        vm.assertEq(exchange.maxAmountToBuy(), 0);
        vm.assertEq(exchange.maxAmountToSell(true), 0);
        vm.assertEq(exchange.maxAmountToSell(false), 0);

        vm.startPrank(admin);
        usdb.transfer(address(exchange), amount);
        weth.transfer(address(exchange), amountEth);
        cybro.mint(address(exchange), 1e25);
        vm.stopPrank();

        uint256 expectedAmountOfCybro = exchange.viewBuyByToken(amount, true);
        uint256 expectedAmountOfCybroByWeth = exchange.viewBuyByToken(amountEth, false);

        vm.prank(user);
        exchange.buy(expectedAmountOfCybro, user, true);
        vm.prank(user2);
        exchange.buy(expectedAmountOfCybroByWeth, user2, false);

        vm.assertApproxEqAbs(cybro.balanceOf(user), expectedAmountOfCybro, 1e15);
        vm.assertApproxEqAbs(cybro.balanceOf(user2), expectedAmountOfCybroByWeth, 1e15);
        vm.assertApproxEqAbs(usdb.balanceOf(user), 0, 1e15);
        vm.assertApproxEqAbs(weth.balanceOf(user2), 0, 1e15);

        uint256 expectedAmountOfUSDB = exchange.viewSellByCybro(expectedAmountOfCybro, true);
        uint256 expectedAmountOfWeth = exchange.viewSellByCybro(expectedAmountOfCybroByWeth, false);

        vm.prank(user);
        exchange.sell(expectedAmountOfCybro, user, true);
        vm.prank(user2);
        exchange.sell(expectedAmountOfCybroByWeth, user2, false);

        vm.assertApproxEqAbs(usdb.balanceOf(user), expectedAmountOfUSDB, 1e15);
        vm.assertApproxEqAbs(weth.balanceOf(user2), expectedAmountOfWeth, 1e15);
    }
}
