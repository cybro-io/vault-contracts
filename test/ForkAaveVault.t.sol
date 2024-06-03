// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {IAavePool} from "../src/interfaces/aave/IPool.sol";
import {AaveVault, IERC20Metadata} from "../src/AaveVault.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mock is ERC20 {
    uint8 private immutable _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 value) public virtual {
        _mint(to, value);
    }

    function burn(address from, uint256 value) public virtual {
        _burn(from, value);
    }
}


contract AaaveVaultTest is Test {
    IAavePool aavePool;
    AaveVault vault;
    IERC20Metadata token;
    uint256 amount;
    uint256 forkId;
    address user;

    function setUp() public {
        forkId = vm.createSelectFork("https://blast.blockpi.network/v1/rpc/public");
        aavePool = IAavePool(address(0xd2499b3c8611E36ca89A70Fda2A72C49eE19eAa8));
        amount = 1e20;
        user = address(100);
    }

    modifier deposit() {
        vm.selectFork(forkId);
        _;
        vault = new AaveVault(token, aavePool, "nameVault", "symbolVault");
        vm.startPrank(user);
        token.approve(address(vault), amount);
        vault.deposit(amount, user);
        vm.stopPrank();
    }

    function test_usdb_deposit() public deposit {
        token = IERC20Metadata(address(0x4300000000000000000000000000000000000003));
        vm.prank(address(0x3Ba925fdeAe6B46d0BB4d424D829982Cb2F7309e));
        token.transfer(user, amount);
    }

    function test_weth_deposit() public deposit {
        token = IERC20Metadata(address(0x4300000000000000000000000000000000000004));
        vm.prank(address(0x44f33bC796f7d3df55040cd3C631628B560715C2));
        token.transfer(user, amount);
    }

    function test_otherTokens_deposit() public deposit {
        token = IERC20Metadata(address(0x66714DB8F3397c767d0A602458B5b4E3C0FE7dd1));
        deal(address(token), user, amount);
    }

}