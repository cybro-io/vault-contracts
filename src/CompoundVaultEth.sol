// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {IERC20Metadata, ERC20} from "./BaseVault.sol";
import {IAavePool} from "./interfaces/aave/IPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {CEth} from "./interfaces/compound/IcETH.sol";

contract CompoundVaultETH is ERC20 {
    using SafeERC20 for IERC20Metadata;

    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    uint8 private immutable _decimals;
    CEth public immutable pool;

    constructor(CEth _pool, string memory name, string memory symbol) ERC20(name, symbol) {
        _decimals = 18;
        pool = _pool;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function _totalAssetsPrecise() internal virtual returns (uint256) {
        return pool.balanceOfUnderlying(address(this));
    }

    function sharePrice() public view virtual returns (uint256) {
        uint256 assets = totalAssets();
        uint256 supply = totalSupply();

        return supply == 0 ? (10 ** _decimals) : assets * (10 ** _decimals) / supply;
    }

    function totalAssets() public view returns (uint256) {
        return pool.balanceOf(address(this)) * pool.exchangeRateStored() / 1e18;
    }

    function _redeem(uint256 shares) internal {
        require(pool.redeem(shares * pool.balanceOf(address(this)) / totalSupply()) == 0, "Pool Error");
    }

    function depositEth(address receiver) public payable returns (uint256 shares) {
        if (msg.value == 0) {
            return 0;
        }
        uint256 totalAssetsBefore = _totalAssetsPrecise();

        pool.mint{value: msg.value}();

        uint256 totalAssetsAfter = _totalAssetsPrecise();
        uint256 increase = totalAssetsAfter - totalAssetsBefore;

        shares = totalAssetsBefore == 0 ? msg.value : totalSupply() * increase / totalAssetsBefore;

        _mint(receiver, shares);

        emit Deposit(_msgSender(), receiver, msg.value, shares);
    }

    function redeem(uint256 shares, address receiver, address owner) public returns (uint256 underlyingAssets) {
        if (_msgSender() != owner) {
            _spendAllowance(owner, _msgSender(), shares);
        }

        underlyingAssets = shares * _totalAssetsPrecise() / totalSupply();
        _redeem(shares);
        _burn(owner, shares);
        (bool success,) = payable(receiver).call{value: underlyingAssets}("");
        require(success, "failed to send ETH");

        emit Withdraw(_msgSender(), receiver, owner, underlyingAssets, shares);
    }

    receive() external payable {
        require(msg.sender == address(pool));
    }
}
