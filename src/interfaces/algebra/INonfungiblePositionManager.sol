// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

/// @dev Obtained via `cast interface 0x8881b3Fb762d1D50e6172f621F107E24299AA1Cd --chain blast`
/// @notice INonfungiblePositionManager for Fenix Finance

interface INonfungiblePositionManager {
    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct IncreaseLiquidityParams {
        uint256 tokenId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct MintParams {
        address token0;
        address token1;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    error AddressZero();
    error tickOutOfRange();

    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event Collect(uint256 indexed tokenId, address recipient, uint256 amount0, uint256 amount1);
    event DecreaseLiquidity(uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    event FarmingCenter(address farmingCenterAddress);
    event FarmingFailed(uint256 indexed tokenId);
    event IncreaseLiquidity(
        uint256 indexed tokenId,
        uint128 liquidityDesired,
        uint128 actualLiquidity,
        uint256 amount0,
        uint256 amount1,
        address pool
    );
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    receive() external payable;

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function NONFUNGIBLE_POSITION_MANAGER_ADMINISTRATOR_ROLE() external view returns (bytes32);
    function PERMIT_TYPEHASH() external view returns (bytes32);
    function WNativeToken() external view returns (address);
    function algebraMintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes memory data) external;
    function approve(address to, uint256 tokenId) external;
    function approveForFarming(uint256 tokenId, bool approve, address farmingAddress) external payable;
    function balanceOf(address owner) external view returns (uint256);
    function burn(uint256 tokenId) external payable;
    function collect(CollectParams memory params) external payable returns (uint256 amount0, uint256 amount1);
    function createAndInitializePoolIfNecessary(address token0, address token1, uint160 sqrtPriceX96)
        external
        payable
        returns (address pool);
    function decreaseLiquidity(DecreaseLiquidityParams memory params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);
    function factory() external view returns (address);
    function farmingApprovals(uint256 tokenId) external view returns (address farmingCenterAddress);
    function farmingCenter() external view returns (address);
    function getApproved(uint256 tokenId) external view returns (address);
    function increaseLiquidity(IncreaseLiquidityParams memory params)
        external
        payable
        returns (uint128 liquidity, uint256 amount0, uint256 amount1);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function isApprovedOrOwner(address spender, uint256 tokenId) external view returns (bool);
    function mint(MintParams memory params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    function multicall(bytes[] memory data) external payable returns (bytes[] memory results);
    function name() external view returns (string memory);
    function ownerOf(uint256 tokenId) external view returns (address);
    function permit(address spender, uint256 tokenId, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        payable;
    function poolDeployer() external view returns (address);
    function positions(uint256 tokenId)
        external
        view
        returns (
            uint88 nonce,
            address operator,
            address token0,
            address token1,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );
    function refundNativeToken() external payable;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) external;
    function selfPermit(address token, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        payable;
    function selfPermitAllowed(address token, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s)
        external
        payable;
    function selfPermitAllowedIfNecessary(address token, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s)
        external
        payable;
    function selfPermitIfNecessary(address token, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        payable;
    function setApprovalForAll(address operator, bool approved) external;
    function setFarmingCenter(address newFarmingCenter) external;
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
    function sweepToken(address token, uint256 amountMinimum, address recipient) external payable;
    function switchFarmingStatus(uint256 tokenId, bool toActive) external;
    function symbol() external view returns (string memory);
    function tokenByIndex(uint256 index) external view returns (uint256);
    function tokenFarmedIn(uint256 tokenId) external view returns (address farmingCenterAddress);
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);
    function tokenURI(uint256 tokenId) external view returns (string memory);
    function totalSupply() external view returns (uint256);
    function transferFrom(address from, address to, uint256 tokenId) external;
    function unwrapWNativeToken(uint256 amountMinimum, address recipient) external payable;
}
