// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.29;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {AaveVault, IERC20Metadata} from "../src/vaults/AaveVault.sol";
import {JuiceVault, IJuicePool} from "../src/vaults/JuiceVault.sol";
import {YieldStakingVault, IYieldStaking} from "../src/vaults/YieldStakingVault.sol";
import {BufferVaultMock} from "../src/mocks/BufferVaultMock.sol";
import {StargateVault, IStargateStaking, IERC20Metadata, IUniswapV3Pool} from "../src/vaults/StargateVault.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {IFeeProvider} from "../src/FeeProvider.sol";
import {IAavePool} from "../src/interfaces/aave/IPool.sol";
import {IStargatePool} from "../src/interfaces/stargate/IStargatePool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IChainlinkOracle} from "../src/interfaces/IChainlinkOracle.sol";
import {InitVault} from "../src/vaults/InitVault.sol";
import {CompoundVault} from "../src/vaults/CompoundVaultErc20.sol";
import {CompoundVaultETH} from "../src/vaults/CompoundVaultEth.sol";
import {IInitLendingPool} from "../src/interfaces/init/IInitLendingPool.sol";
import {CErc20} from "../src/interfaces/compound/IcERC.sol";
import {BufferVaultMock} from "../src/mocks/BufferVaultMock.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {CErc20} from "../src/interfaces/compound/IcERC.sol";
import {CEth} from "../src/interfaces/compound/IcETH.sol";
import {GammaAlgebraVault, IUniProxy, IHypervisor} from "../src/vaults/GammaAlgebraVault.sol";
import {IPSM3} from "../src/interfaces/spark/IPSM3.sol";
import {SparkVault} from "../src/vaults/SparkVault.sol";
import {SteerCamelotVault} from "../src/vaults/SteerCamelotVault.sol";
import {ICamelotMultiPositionLiquidityManager} from "../src/interfaces/steer/ICamelotMultiPositionLiquidityManager.sol";
import {IRouter} from "../src/interfaces/jones/IRouter.sol";
import {ICompounder} from "../src/interfaces/jones/ICompounder.sol";
import {IAlgebraLPManager} from "../src/interfaces/jones/IAlgebraLPManager.sol";
import {IRewardTracker} from "../src/interfaces/jones/IRewardTracker.sol";
import {IAlgebraPool} from "../src/interfaces/algebra/IAlgebraPoolV1_9.sol";
import {JonesCamelotVault} from "../src/vaults/JonesCamelotVault.sol";
import {IHubPool} from "../src/interfaces/across/IHubPool.sol";
import {AcrossVault} from "../src/vaults/AcrossVault.sol";
import {IAcceleratingDistributor} from "../src/interfaces/across/IAcceleratingDistributor.sol";
import {CompoundLayerbankVault} from "../src/vaults/CompoundLayerbankVault.sol";
import {ILToken} from "../src/interfaces/layerbank/ILToken.sol";
import {Vm} from "forge-std/Vm.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract DeployUtils is StdCheats {
    using SafeERC20 for IERC20Metadata;

    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct StargateSetup {
        IERC20Metadata weth;
        IERC20Metadata stg;
        IUniswapV3Pool swapPool;
        IUniswapV3Pool currentSwapPool;
        IStargateStaking staking;
    }

    struct VaultSetup {
        IERC20Metadata asset;
        address pool;
        address feeProvider;
        address feeRecipient;
        string name;
        string symbol;
        address admin;
        address manager;
    }

    uint256 internal constant baseAdminPrivateKey = 0xba132ce;
    address internal constant baseAdmin = address(0x4EaC6e0b2bFdfc22cD15dF5A8BADA754FeE6Ad00);

    function _getOracleForToken(address token) internal view returns (IChainlinkOracle) {
        if (block.chainid == 81457) {
            if (token == address(weth_BLAST)) {
                return oracle_ETH_BLAST;
            } else if (token == address(wbtc_BLAST)) {
                return oracle_BTC_BLAST;
            } else if (token == address(usdb_BLAST)) {
                return oracle_USDB_BLAST;
            } else if (token == address(blast_BLAST)) {
                return oracle_BLAST_BLAST;
            }
        } else if (block.chainid == 42161) {
            if (token == address(weth_ARBITRUM)) {
                return oracle_ETH_ARBITRUM;
            } else if (token == address(usdt_ARBITRUM)) {
                return oracle_USDT_ARBITRUM;
            } else if (token == address(usdc_ARBITRUM)) {
                return oracle_USDC_ARBITRUM;
            } else if (token == address(wbtc_ARBITRUM)) {
                return oracle_BTC_ARBITRUM;
            } else if (token == address(dai_ARBITRUM)) {
                return oracle_DAI_ARBITRUM;
            }
        }
        revert("Oracle not set for token");
    }

    function _getAssetProvider(IERC20Metadata asset_) internal view returns (address assetProvider_) {
        if (block.chainid == 81457) {
            if (asset_ == usdb_BLAST) {
                assetProvider_ = assetProvider_USDB_BLAST;
            } else if (asset_ == weth_BLAST) {
                assetProvider_ = assetProvider_WETH_BLAST;
            } else if (asset_ == blast_BLAST) {
                assetProvider_ = assetProvider_BLAST_BLAST;
            } else {
                assetProvider_ = assetProvider_WBTC_BLAST;
            }
        } else if (block.chainid == 42161) {
            if (asset_ == usdt_ARBITRUM) {
                assetProvider_ = assetProvider_USDT_ARBITRUM;
            } else if (asset_ == usdc_ARBITRUM) {
                assetProvider_ = assetProvider_USDC_ARBITRUM;
            } else if (asset_ == weth_ARBITRUM) {
                assetProvider_ = assetProvider_WETH_ARBITRUM;
            } else if (asset_ == wbtc_ARBITRUM) {
                assetProvider_ = assetProvider_WBTC_ARBITRUM;
            } else if (asset_ == dai_ARBITRUM) {
                assetProvider_ = assetProvider_DAI_ARBITRUM;
            } else if (asset_ == weeth_ARBITRUM) {
                assetProvider_ = assetProvider_WEETH_ARBITRUM;
            }
        } else if (block.chainid == 8453) {
            if (asset_ == usdc_BASE) {
                assetProvider_ = assetProvider_USDC_BASE;
            } else if (asset_ == weth_BASE) {
                assetProvider_ = assetProvider_WETH_BASE;
            } else if (asset_ == cbwbtc_BASE) {
                assetProvider_ = assetProvider_CBWBTC_BASE;
            }
        } else if (block.chainid == 1) {
            if (asset_ == usdt_ETHEREUM) {
                assetProvider_ = assetProvider_USDT_ETHEREUM;
            } else if (asset_ == weth_ETHEREUM) {
                assetProvider_ = assetProvider_WETH_ETHEREUM;
            } else if (asset_ == usdc_ETHEREUM) {
                assetProvider_ = assetProvider_USDC_ETHEREUM;
            } else if (asset_ == wbtc_ETHEREUM) {
                assetProvider_ = assetProvider_WBTC_ETHEREUM;
            }
        }
    }

    function dealTokens(IERC20Metadata token, address to, uint256 amount) public {
        if (token == weth_BLAST || token == usdb_BLAST) {
            vm.startPrank(_getAssetProvider(token));
            token.safeTransfer(to, amount);
            vm.stopPrank();
        } else {
            deal(address(token), to, amount);
        }
    }

    /* ========== ASSETS ========== */

    /* ARBITRUM */
    IERC20Metadata usdt_ARBITRUM = IERC20Metadata(address(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9));
    IERC20Metadata weth_ARBITRUM = IERC20Metadata(address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1));
    IERC20Metadata usdc_ARBITRUM = IERC20Metadata(address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831));
    IERC20Metadata wbtc_ARBITRUM = IERC20Metadata(address(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f));
    IERC20Metadata dai_ARBITRUM = IERC20Metadata(address(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1));
    IERC20Metadata weeth_ARBITRUM = IERC20Metadata(address(0x35751007a407ca6FEFfE80b3cB397736D2cf4dbe));

    /* BASE */
    IERC20Metadata weth_BASE = IERC20Metadata(address(0x4200000000000000000000000000000000000006));
    IERC20Metadata usdc_BASE = IERC20Metadata(address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913));
    IERC20Metadata wbtc_BASE = IERC20Metadata(address(0x0555E30da8f98308EdB960aa94C0Db47230d2B9c));
    // coinbase wrapped btc
    IERC20Metadata cbwbtc_BASE = IERC20Metadata(address(0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf));
    IERC20Metadata susds_BASE = IERC20Metadata(address(0x5875eEE11Cf8398102FdAd704C9E96607675467a));

    /* BLAST */
    IERC20Metadata usdb_BLAST = IERC20Metadata(address(0x4300000000000000000000000000000000000003));
    IERC20Metadata weth_BLAST = IERC20Metadata(address(0x4300000000000000000000000000000000000004));
    IERC20Metadata wbtc_BLAST = IERC20Metadata(address(0xF7bc58b8D8f97ADC129cfC4c9f45Ce3C0E1D2692));
    IERC20Metadata blast_BLAST = IERC20Metadata(address(0xb1a5700fA2358173Fe465e6eA4Ff52E36e88E2ad));
    IERC20Metadata weeth_BLAST = IERC20Metadata(address(0x04C0599Ae5A44757c0af6F9eC3b93da8976c150A));

    /* ETHEREUM */
    IERC20Metadata weth_ETHEREUM = IERC20Metadata(address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
    IERC20Metadata usdt_ETHEREUM = IERC20Metadata(address(0xdAC17F958D2ee523a2206206994597C13D831ec7));
    IERC20Metadata usdc_ETHEREUM = IERC20Metadata(address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48));
    IERC20Metadata wbtc_ETHEREUM = IERC20Metadata(address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599));
    IERC20Metadata paxg_ETHEREUM = IERC20Metadata(address(0x45804880De22913dAFE09f4980848ECE6EcbAf78));

    /* AVALANCHE */
    IERC20Metadata frax_AVALANCHE = IERC20Metadata(address(0xD24C2Ad096400B6FBcd2ad8B24E7acBc21A1da64));
    IERC20Metadata weth_AVALANCHE = IERC20Metadata(address(0x49D5c2BdFfac6CE2BFdB6640F4F80f226bc10bAB));

    /* METIS */
    IERC20Metadata dai_METIS = IERC20Metadata(address(0x4c078361FC9BbB78DF910800A991C7c3DD2F6ce0));

    /* SONIC */
    IERC20Metadata weth_SONIC = IERC20Metadata(address(0x50c42dEAcD8Fc9773493ED674b675bE577f2634b));

    /* BSC */
    IERC20Metadata btcb_BSC = IERC20Metadata(address(0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c));

    /* OPTIMISM */
    IERC20Metadata weth_OPTIMISM = IERC20Metadata(address(0x4200000000000000000000000000000000000006));
    IERC20Metadata usdc_OPTIMISM = IERC20Metadata(address(0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85));
    IERC20Metadata wsteth_OPTIMISM = IERC20Metadata(address(0x1F32b1c2345538c0c6f582fCB022739c4A194Ebb));
    IERC20Metadata usdt_OPTIMISM = IERC20Metadata(address(0x94b008aA00579c1307B0EF2c499aD98a8ce58e58));

    /* SCROLL */
    IERC20Metadata wsteth_SCROLL = IERC20Metadata(address(0xf610A9dfB7C89644979b4A0f27063E9e7d7Cda32));

    /* MODE */
    IERC20Metadata usdc_MODE = IERC20Metadata(address(0xd988097fb8612cc24eeC14542bC03424c656005f));

    /* B2 */
    IERC20Metadata usdt_B2 = IERC20Metadata(address(0x681202351a488040Fa4FdCc24188AfB582c9DD62));

    /* UNICHAIN */
    IERC20Metadata usdc_UNICHAIN = IERC20Metadata(address(0x078D782b760474a361dDA0AF3839290b0EF57AD6));

    /* CORE */
    IERC20Metadata wbtc_CORE = IERC20Metadata(address(0x5832f53d147b3d6Cd4578B9CBD62425C7ea9d0Bd));
    IERC20Metadata usdt_CORE = IERC20Metadata(address(0x900101d06A7426441Ae63e9AB3B9b0F63Be145F1));
    IERC20Metadata usdc_CORE = IERC20Metadata(address(0xa4151B2B3e269645181dCcF2D426cE75fcbDeca9));

    /* ========== CHAINLINK ORACLES ========== */

    /* BLAST */
    IChainlinkOracle oracle_ETH_BLAST = IChainlinkOracle(address(0x0af23B08bcd8AD35D1e8e8f2D2B779024Bd8D24A));
    IChainlinkOracle oracle_USDB_BLAST = IChainlinkOracle(address(0x3A236F67Fce401D87D7215695235e201966576E4));
    IChainlinkOracle oracle_BTC_BLAST = IChainlinkOracle(address(0x7262c8C5872A4Aa0096A8817cF61f5fa3c537330));
    // api3 oracle; not chainlink/redstone
    IChainlinkOracle oracle_BLAST_BLAST = IChainlinkOracle(address(0x54E4aFa5084C347370e4D14a3b3d4191765115f2));

    /* BASE */
    IChainlinkOracle oracle_ETH_BASE = IChainlinkOracle(address(0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70));
    IChainlinkOracle oracle_USDT_BASE = IChainlinkOracle(address(0xf19d560eB8d2ADf07BD6D13ed03e1D11215721F9));
    IChainlinkOracle oracle_USDC_BASE = IChainlinkOracle(address(0x7e860098F58bBFC8648a4311b374B1D669a2bc6B));
    IChainlinkOracle oracle_BTC_BASE = IChainlinkOracle(address(0x64c911996D3c6aC71f9b455B1E8E7266BcbD848F));
    IChainlinkOracle oracle_CBWBTC_BASE = IChainlinkOracle(address(0x07DA0E54543a844a80ABE69c8A12F22B3aA59f9D));

    /* ARBITRUM */
    IChainlinkOracle oracle_ETH_ARBITRUM = IChainlinkOracle(address(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612));
    IChainlinkOracle oracle_USDC_ARBITRUM = IChainlinkOracle(address(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3));
    IChainlinkOracle oracle_USDT_ARBITRUM = IChainlinkOracle(address(0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7));
    IChainlinkOracle oracle_BTC_ARBITRUM = IChainlinkOracle(address(0x6ce185860a4963106506C203335A2910413708e9));
    IChainlinkOracle oracle_DAI_ARBITRUM = IChainlinkOracle(address(0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB));

    /* ETHEREUM */
    IChainlinkOracle oracle_ETHUSD_ETHEREUM = IChainlinkOracle(address(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419));
    IChainlinkOracle oracle_USDTUSD_ETHEREUM = IChainlinkOracle(address(0x3E7d1eAB13ad0104d2750B8863b489D65364e32D));
    IChainlinkOracle oracle_BTCUSD_ETHEREUM = IChainlinkOracle(address(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c));
    IChainlinkOracle oracle_USDCUSD_ETHEREUM = IChainlinkOracle(address(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6));
    IChainlinkOracle oracle_PAXGUSD_ETHEREUM = IChainlinkOracle(address(0x9944D86CEB9160aF5C5feB251FD671923323f8C3));

    /* OPTIMISM */
    IChainlinkOracle oracle_USDCUSD_OPTIMISM = IChainlinkOracle(address(0x16a9FA2FDa030272Ce99B29CF780dFA30361E0f3));
    IChainlinkOracle oracle_USDTUSD_OPTIMISM = IChainlinkOracle(address(0xECef79E109e997bCA29c1c0897ec9d7b03647F5E));

    /* CORE */
    IChainlinkOracle oracle_USDCUSD_CORE = IChainlinkOracle(address(0xD3C586Eec1C6C3eC41D276a23944dea080eDCf7f));
    IChainlinkOracle oracle_USDTUSD_CORE = IChainlinkOracle(address(0x4eadC6ee74b7Ceb09A4ad90a33eA2915fbefcf76));

    /* ========== DEXES ========== */

    /* UNISWAP */

    IUniswapV3Factory factory_UNI_ETHEREUM = IUniswapV3Factory(address(0x1F98431c8aD98523631AE4a59f267346ea31F984));
    IUniswapV3Factory factory_UNI_ARB = IUniswapV3Factory(address(0x1F98431c8aD98523631AE4a59f267346ea31F984));
    IUniswapV3Factory factory_UNI_BASE = IUniswapV3Factory(address(0x33128a8fC17869897dcE68Ed026d694621f6FDfD));
    IUniswapV3Pool pool_USDC_WETH_BASE = IUniswapV3Pool(address(0xd0b53D9277642d899DF5C87A3966A349A798F224));
    IUniswapV3Pool pool_USDC_USDT_ARBITRUM = IUniswapV3Pool(address(0xbE3aD6a5669Dc0B8b12FeBC03608860C31E2eef6));
    IUniswapV3Pool pool_ACX_WETH_ETHEREUM = IUniswapV3Pool(address(0x508acdC358be2ed126B1441F0Cff853dEc49d40F));
    IUniswapV3Pool pool_USDT_WETH_ETHEREUM = IUniswapV3Pool(address(0x4e68Ccd3E89f51C3074ca5072bbAC773960dFa36));
    IUniswapV3Pool pool_USDC_WETH_ETHEREUM = IUniswapV3Pool(address(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640));
    IUniswapV3Pool pool_WBTC_WETH_ETHEREUM = IUniswapV3Pool(address(0xCBCdF9626bC03E24f779434178A73a0B4bad62eD));
    IUniswapV3Pool pool_USDT_USDC_ETHEREUM = IUniswapV3Pool(address(0x3416cF6C708Da44DB2624D63ea0AAef7113527C6));
    IUniswapV3Pool pool_USDC_USDT_OPTIMISM = IUniswapV3Pool(address(0xA73C628eaf6e283E26A7b1f8001CF186aa4c0E8E));
    IUniswapV3Pool pool_USDC_USDT_CORE = IUniswapV3Pool(address(0x74B8d6eA8E0284C2619922FC0F5d872Fe32CEc2f));
    IUniswapV3Pool pool_USDC_PAXG_ETHEREUM = IUniswapV3Pool(address(0xB431c70f800100D87554ac1142c4A94C5Fe4C0C4));
    INonfungiblePositionManager positionManager_UNI_BLAST =
        INonfungiblePositionManager(payable(address(0xB218e4f7cF0533d4696fDfC419A0023D33345F28)));
    INonfungiblePositionManager positionManager_UNI_ARB =
        INonfungiblePositionManager(payable(address(0xC36442b4a4522E871399CD717aBDD847Ab11FE88)));
    INonfungiblePositionManager positionManager_UNI_BASE =
        INonfungiblePositionManager(payable(address(0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1)));

    /* ALGEBRA */

    /* ========== ASSET PROVIDERS ========== */

    /* BLAST */

    address assetProvider_USDB_BLAST = address(0x4BeD2A922654cAcC2Be974689619768FaBF24855);
    address assetProvider_WETH_BLAST = address(0x66714DB8F3397c767d0A602458B5b4E3C0FE7dd1);
    address assetProvider_BLAST_BLAST = address(0xeC1f5118d558050908122A7B84B10580818B68Da);
    address assetProvider_WBTC_BLAST = address(0x2D509190Ed0172ba588407D4c2df918F955Cc6E1);
    address assetProvider_WEETH_BLAST = address(0x0817b88a528E2F5F980d26e98fC950CbD6aE31Ef);

    /* ARBITRUM */

    address assetProvider_USDT_ARBITRUM = address(0xF977814e90dA44bFA03b6295A0616a897441aceC);
    address assetProvider_USDC_ARBITRUM = address(0x2Df1c51E09aECF9cacB7bc98cB1742757f163dF7);
    address assetProvider_WETH_ARBITRUM = address(0x70d95587d40A2caf56bd97485aB3Eec10Bee6336);
    address assetProvider_WBTC_ARBITRUM = address(0x078f358208685046a11C85e8ad32895DED33A249);
    address assetProvider_DAI_ARBITRUM = address(0x82E64f49Ed5EC1bC6e43DAD4FC8Af9bb3A2312EE);
    address assetProvider_WEETH_ARBITRUM = address(0x8437d7C167dFB82ED4Cb79CD44B7a32A1dd95c77);

    /* BASE */

    address assetProvider_WETH_BASE = address(0x6446021F4E396dA3df4235C62537431372195D38);
    address assetProvider_USDC_BASE = address(0x0B0A5886664376F59C351ba3f598C8A8B4D0A6f3);
    address assetProvider_CBWBTC_BASE = address(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb); // 2,459 WBTC

    /* ETHEREUM */

    address assetProvider_WETH_ETHEREUM = address(0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E);
    address assetProvider_USDT_ETHEREUM = address(0x2933782B5A8d72f2754103D1489614F29bfA4625);
    address assetProvider_USDC_ETHEREUM = address(0x37305B1cD40574E4C5Ce33f8e8306Be057fD7341);
    address assetProvider_WBTC_ETHEREUM = address(0x5Ee5bf7ae06D1Be5997A1A72006FE6C607eC6DE8);
    address assetProvider_PAXG_ETHEREUM = address(0xF977814e90dA44bFA03b6295A0616a897441aceC);

    /* AVALANCHE */

    address assetProvider_FRAX_AVALANCHE = address(0x65BAB4f268286b9005D6053a177948dDdC29BAD3);
    address assetProvider_WETH_AVALANCHE = address(0xB510DAFC381524d391855F7386f2A2d05E9a7E65);

    /* METIS */

    address assetProvider_DAI_METIS = address(0x0CAd02c4c6fB7c0d403aF74Ba9adA3bf40df6478);

    /* SONIC */

    address assetProvider_WETH_SONIC = address(0xC291CA0a0a0e793dC6A0442a34E1607Ce1905389);

    /* BSC */

    address assetProvider_BTCB_BSC = address(0x8F73b65B4caAf64FBA2aF91cC5D4a2A1318E5D8C);

    /* OPTIMISM */

    address assetProvider_WETH_OPTIMISM = address(0x73B14a78a0D396C521f954532d43fd5fFe385216);
    address assetProvider_USDC_OPTIMISM = address(0x8aF3827a41c26C7F32C81E93bb66e837e0210D5c);
    address assetProvider_WSTETH_OPTIMISM = address(0xbb0b4642492b275F154e415fc52Dacc931103fD9);
    address assetProvider_USDT_OPTIMISM = address(0xF977814e90dA44bFA03b6295A0616a897441aceC);

    /* SCROLL */

    address assetProvider_WSTETH_SCROLL = address(0x2A0dc9044bf0A455568019D741130A87e74eE888);

    /* MODE */

    address assetProvider_USDC_MODE = address(0xF043AF653c1c770433C7c6f8123ece51d79496F7);

    /* B2 */

    address assetProvider_USDT_B2 = address(0x9683826a04DB8Ae2e256e6a14b87d440C7105824);

    /* UNICHAIN */

    address assetProvider_USDC_UNICHAIN = address(0xB5A2a236581dbd6BCECD8A25EeBFF140595f138C);

    /* CORE */

    address assetProvider_USDT_CORE = address(0xa8eC7b7b51DBaEd615Cb4fF495eeCFD949e1Afc0);
    address assetProvider_USDC_CORE = address(0xB9EFb3ABfd12649faF03D360818D66e62592262c);
    address assetProvider_WBTC_CORE = address(0x1305ec07e6fa94aF76fD15C02747e1FeB17951EA);

    /* ========== CACHED BLOCKIDS ========== */

    uint256 lastCachedBlockid_BLAST = 14284818;
    uint256 lastCachedBlockid_ARBITRUM = 300132227;
    uint256 lastCachedBlockid_BASE = 25292162;
    uint256 lastCachedBlockid_ETHEREUM = 22052977;
    uint256 lastCachedBlockid_AVALANCHE = 60675615;
    uint256 lastCachedBlockid_METIS = 20244437;
    uint256 lastCachedBlockid_SONIC = 21383387;
    uint256 lastCachedBlockid_BSC = 48554343;
    uint256 lastCachedBlockid_OPTIMISM = 134823726;
    uint256 lastCachedBlockid_SCROLL = 14892975;
    uint256 lastCachedBlockid_MODE = 22540097;
    uint256 lastCachedBlockid_B2 = 16044183;
    uint256 lastCachedBlockid_UNICHAIN = 14499700;
    uint256 lastCachedBlockid_CORE = 23985246;

    /* ========== POOLS ========== */

    IStargatePool stargate_usdtPool_ARBITRUM =
        IStargatePool(payable(address(0xcE8CcA271Ebc0533920C83d39F417ED6A0abB7D0)));
    IStargatePool stargate_wethPool_ARBITRUM =
        IStargatePool(payable(address(0xA45B5130f36CDcA45667738e2a258AB09f4A5f7F)));
    IStargatePool stargate_usdcPool_ARBITRUM =
        IStargatePool(payable(address(0xe8CDF27AcD73a434D661C84887215F7598e7d0d3)));

    IStargatePool stargate_usdcPool_BASE = IStargatePool(payable(address(0x27a16dc786820B16E5c9028b75B99F6f604b5d26)));
    IStargatePool stargate_wethPool_BASE = IStargatePool(payable(address(0xdc181Bd607330aeeBEF6ea62e03e5e1Fb4B6F7C7)));

    IAavePool aave_pool_BLAST = IAavePool(address(0xd2499b3c8611E36ca89A70Fda2A72C49eE19eAa8));
    IAavePool aave_zerolendPool_BLAST = IAavePool(address(0xa70B0F3C2470AbBE104BdB3F3aaa9C7C54BEA7A8));
    IAavePool aave_pool_ARBITRUM = IAavePool(address(0x794a61358D6845594F94dc1DB02A252b5b4814aD));
    IAavePool aave_pool_BASE = IAavePool(address(0xA238Dd80C259a72e81d7e4664a9801593F98d1c5));
    IAavePool aave_pool_AVALANCHE = IAavePool(address(0x794a61358D6845594F94dc1DB02A252b5b4814aD));
    IAavePool aave_pool_METIS = IAavePool(address(0x90df02551bB792286e8D4f13E0e357b4Bf1D6a57));
    IAavePool aave_pool_SONIC = IAavePool(address(0x5362dBb1e601abF3a4c14c22ffEdA64042E5eAA3));
    IAavePool aave_avalonPool_BSC = IAavePool(address(0xf9278C7c4AEfAC4dDfd0D496f7a1C39cA6BCA6d4));

    /* COLEND AAVE */

    IAavePool aave_colendPool_CORE = IAavePool(address(0x0CEa9F0F49F30d376390e480ba32f903B43B19C5));

    /* MOONWELL COMPOUND */

    CErc20 compound_moonwellUSDC_BASE = CErc20(address(0xEdc817A28E8B93B03976FBd4a3dDBc9f7D176c22));
    CErc20 compound_moonwellUSDC_OPTIMISM = CErc20(address(0x8E08617b0d66359D73Aa11E11017834C29155525));
    CErc20 compound_moonwellUSDT_OPTIMISM = CErc20(address(0xa3A53899EE8f9f6E963437C5B3f805FEc538BF84));
    CErc20 compound_moonwellWSTETH_OPTIMISM = CErc20(address(0xbb3b1aB66eFB43B10923b87460c0106643B83f9d));

    /* LAYERBANK COMPOUND */

    ILToken compound_layerbankWSTETH_SCROLL = ILToken(payable(address(0xB6966083c7b68175B4BF77511608AEe9A80d2Ca4)));
    ILToken compound_layerbankUSDC_MODE = ILToken(payable(address(0xBa6e89c9cDa3d72B7D8D5B05547a29f9BdBDBaec)));
    ILToken compound_layerbankUSDT_B2 = ILToken(payable(address(0xA9Be5906974698A9C743E881B0ACc2954399ff2a)));

    /* VENUS COMPOUND */

    CErc20 compound_venusUSDC_UNICHAIN = CErc20(address(0xB953f92B9f759d97d2F2Dec10A8A3cf75fcE3A95));

    /* ASO (compound) */

    CEth aso_weth_BLAST = CEth(address(0x001FF326A2836bdD77B28E992344983681071f87));

    /* JUICE */

    IJuicePool juice_usdbPool_BLAST = IJuicePool(address(0x4A1d9220e11a47d8Ab22Ccd82DA616740CF0920a));
    IJuicePool juice_wethPool_BLAST = IJuicePool(address(0x44f33bC796f7d3df55040cd3C631628B560715C2));

    IYieldStaking blastupYieldStaking_BLAST =
        IYieldStaking(payable(address(0x0E84461a00C661A18e00Cab8888d146FDe10Da8D)));
    IYieldStaking blastupYieldStaking_WETH_BLAST =
        IYieldStaking(payable(address(0x4E5Ed7a628760f7c60b4A9DA0A25c28BB024F787)));

    /* INIT */

    IInitLendingPool init_usdbPool_BLAST =
        IInitLendingPool(payable(address(0xc5EaC92633aF47c0023Afa0116500ab86FAB430F)));
    IInitLendingPool init_blastPool_BLAST =
        IInitLendingPool(payable(address(0xdafB6929442303e904A2f673A0E7EB8753Bab571)));
    IInitLendingPool init_wethPool_BLAST =
        IInitLendingPool(payable(address(0xD20989EB39348994AA99F686bb4554090d0C09F3)));

    CErc20 compound_usdbPool_BLAST = CErc20(address(0x9aECEdCD6A82d26F2f86D331B17a1C1676442A87));
    CErc20 compound_wbtcPool_BLAST = CErc20(address(0x8C415331761063E5D6b1c8E700f996b13603Fc2E));
    CEth compound_ethPool_BLAST = CEth(address(0x0872b71EFC37CB8DdE22B2118De3d800427fdba0));

    IUniProxy uniProxy_gamma_ARBITRUM = IUniProxy(address(0x1F1Ca4e8236CD13032653391dB7e9544a6ad123E));
    IHypervisor hypervisor_gamma_ARBITRUM = IHypervisor(address(0xd7Ef5Ac7fd4AAA7994F3bc1D273eAb1d1013530E));

    /* SPARK */

    IPSM3 psm3Pool_BASE = IPSM3(address(0x1601843c5E9bC251A3272907010AFa41Fa18347E));
    IPSM3 psm3Pool_ARBITRUM = IPSM3(address(0x2B05F8e1cACC6974fD79A673a341Fe1f58d27266));

    /* LODESTAR */

    CErc20 compound_lodestarUSDC_ARBITRUM = CErc20(address(0x4C9aAed3b8c443b4b634D1A189a5e25C604768dE));

    /* STEER */

    ICamelotMultiPositionLiquidityManager steer_wethusdc_ARBITRUM =
        ICamelotMultiPositionLiquidityManager(address(0x801B4184de0CDF298ce933b042911500FADA1de6));
    ICamelotMultiPositionLiquidityManager steer_usdcdai_ARBITRUM =
        ICamelotMultiPositionLiquidityManager(address(0x5f033d4d786eC5592FDbb5B289000A2B9A466D32));

    /* JONES */

    ICompounder compounder_jones_ARBITRUM = ICompounder(address(0xEE1ACCcf0d92814BECF74773B466Db68A0752d10));
    IAlgebraPool pool_jones_weethWeth_ARBITRUM = IAlgebraPool(address(0x293DFD996d5cd72Bed712B0EEAb96DBE400c0416));

    /* ACROSS */

    IHubPool across_hubPool_ETHEREUM = IHubPool(payable(address(0xc186fA914353c44b2E33eBE05f21846F1048bEda)));
    IAcceleratingDistributor across_acceleratingDistributor_ETHEREUM =
        IAcceleratingDistributor(address(0x9040e41eF5E8b281535a96D9a48aCb8cfaBD9a48));

    function _deployAave(VaultSetup memory vaultData) internal returns (IVault aaveVault_) {
        aaveVault_ = IVault(
            address(
                new TransparentUpgradeableProxy(
                    address(
                        new AaveVault(
                            vaultData.asset,
                            IAavePool(vaultData.pool),
                            IFeeProvider(vaultData.feeProvider),
                            vaultData.feeRecipient
                        )
                    ),
                    vaultData.admin,
                    abi.encodeCall(
                        AaveVault.initialize, (vaultData.admin, vaultData.name, vaultData.symbol, vaultData.manager)
                    )
                )
            )
        );
    }

    function _deployJuice(VaultSetup memory vaultData) internal returns (IVault juiceVault_) {
        juiceVault_ = IVault(
            address(
                new TransparentUpgradeableProxy(
                    address(
                        new JuiceVault(
                            vaultData.asset,
                            IJuicePool(vaultData.pool),
                            IFeeProvider(vaultData.feeProvider),
                            vaultData.feeRecipient
                        )
                    ),
                    vaultData.admin,
                    abi.encodeCall(
                        JuiceVault.initialize, (vaultData.admin, vaultData.name, vaultData.symbol, vaultData.manager)
                    )
                )
            )
        );
    }

    function _deployYieldStaking(VaultSetup memory vaultData) internal returns (IVault yieldStakingVault_) {
        yieldStakingVault_ = IVault(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(
                            new YieldStakingVault(
                                vaultData.asset,
                                IYieldStaking(payable(vaultData.pool)),
                                IFeeProvider(vaultData.feeProvider),
                                vaultData.feeRecipient
                            )
                        ),
                        vaultData.admin,
                        abi.encodeCall(
                            YieldStakingVault.initialize,
                            (vaultData.admin, vaultData.name, vaultData.symbol, vaultData.manager)
                        )
                    )
                )
            )
        );
    }

    function _deployInit(VaultSetup memory vaultData) internal returns (IVault initVault_) {
        initVault_ = IVault(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(
                            new InitVault(
                                vaultData.asset,
                                IInitLendingPool(vaultData.pool),
                                IFeeProvider(vaultData.feeProvider),
                                vaultData.feeRecipient
                            )
                        ),
                        vaultData.admin,
                        abi.encodeCall(
                            InitVault.initialize, (vaultData.admin, vaultData.name, vaultData.symbol, vaultData.manager)
                        )
                    )
                )
            )
        );
    }

    function _deployBuffer(VaultSetup memory vaultData) internal returns (IVault bufferVault_) {
        bufferVault_ = IVault(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(
                            new BufferVaultMock(
                                vaultData.asset, IFeeProvider(vaultData.feeProvider), vaultData.feeRecipient
                            )
                        ),
                        vaultData.admin,
                        abi.encodeCall(
                            BufferVaultMock.initialize_mock,
                            (vaultData.admin, vaultData.name, vaultData.symbol, vaultData.manager)
                        )
                    )
                )
            )
        );
    }

    function _deployStargate(VaultSetup memory vaultData) internal returns (IVault stargateVault_) {
        StargateSetup memory stargateSetup;
        if (block.chainid == 8453) {
            // base
            IUniswapV3Factory factory = IUniswapV3Factory(address(0x33128a8fC17869897dcE68Ed026d694621f6FDfD));
            stargateSetup.stg = IERC20Metadata(address(0xE3B53AF74a4BF62Ae5511055290838050bf764Df));
            stargateSetup.weth = weth_BASE;
            stargateSetup.staking = IStargateStaking(payable(address(0xDFc47DCeF7e8f9Ab19a1b8Af3eeCF000C7ea0B80)));
            stargateSetup.swapPool =
                IUniswapV3Pool(factory.getPool(address(stargateSetup.stg), address(stargateSetup.weth), 10000));
            if (vaultData.pool == address(0x27a16dc786820B16E5c9028b75B99F6f604b5d26)) {
                stargateSetup.currentSwapPool =
                    IUniswapV3Pool(factory.getPool(address(usdc_BASE), address(weth_BASE), 500));
            }
        } else if (block.chainid == 42161) {
            // arbitrum
            IUniswapV3Factory factory = IUniswapV3Factory(address(0x1F98431c8aD98523631AE4a59f267346ea31F984));
            stargateSetup.stg = IERC20Metadata(address(0x6694340fc020c5E6B96567843da2df01b2CE1eb6));
            stargateSetup.weth = weth_ARBITRUM;
            stargateSetup.staking = IStargateStaking(payable(address(0x3da4f8E456AC648c489c286B99Ca37B666be7C4C)));
            stargateSetup.swapPool =
                IUniswapV3Pool(factory.getPool(address(stargateSetup.stg), address(stargateSetup.weth), 3000));
            if (vaultData.pool == address(0xe8CDF27AcD73a434D661C84887215F7598e7d0d3)) {
                stargateSetup.currentSwapPool =
                    IUniswapV3Pool(factory.getPool(address(usdc_ARBITRUM), address(weth_ARBITRUM), 500));
            } else if (vaultData.pool == address(0xcE8CcA271Ebc0533920C83d39F417ED6A0abB7D0)) {
                stargateSetup.currentSwapPool =
                    IUniswapV3Pool(factory.getPool(address(usdt_ARBITRUM), address(weth_ARBITRUM), 500));
            }
        }

        stargateVault_ = IVault(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(
                            new StargateVault(
                                IStargatePool(payable(vaultData.pool)),
                                IFeeProvider(vaultData.feeProvider),
                                vaultData.feeRecipient,
                                stargateSetup.staking,
                                stargateSetup.stg,
                                stargateSetup.weth,
                                stargateSetup.swapPool,
                                stargateSetup.currentSwapPool
                            )
                        ),
                        vaultData.admin,
                        abi.encodeCall(
                            StargateVault.initialize,
                            (vaultData.admin, vaultData.name, vaultData.symbol, vaultData.manager)
                        )
                    )
                )
            )
        );
    }

    function _deployGammaAlgebra(VaultSetup memory vaultData) internal returns (IVault gammaVault_) {
        address uniProxy_;
        if (block.chainid == 42161) {
            // arbitrum
            uniProxy_ = address(uniProxy_gamma_ARBITRUM);
        } else {
            revert();
        }
        gammaVault_ = IVault(
            address(
                new TransparentUpgradeableProxy(
                    address(
                        new GammaAlgebraVault(
                            vaultData.pool,
                            uniProxy_,
                            vaultData.asset,
                            IFeeProvider(vaultData.feeProvider),
                            vaultData.feeRecipient,
                            address(_getOracleForToken(IHypervisor(vaultData.pool).token0())),
                            address(_getOracleForToken(IHypervisor(vaultData.pool).token1()))
                        )
                    ),
                    vaultData.admin,
                    abi.encodeCall(
                        GammaAlgebraVault.initialize,
                        (vaultData.admin, vaultData.name, vaultData.symbol, vaultData.manager)
                    )
                )
            )
        );
    }

    function _deploySpark(VaultSetup memory vaultData) internal returns (IVault sparkVault_) {
        sparkVault_ = IVault(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(
                            new SparkVault(
                                vaultData.asset,
                                IPSM3(vaultData.pool),
                                IFeeProvider(vaultData.feeProvider),
                                vaultData.feeRecipient
                            )
                        ),
                        vaultData.admin,
                        abi.encodeCall(
                            SparkVault.initialize,
                            (vaultData.admin, vaultData.name, vaultData.symbol, vaultData.manager)
                        )
                    )
                )
            )
        );
    }

    function _deploySteerCamelot(VaultSetup memory vaultData) internal returns (IVault steerCamelotVault_) {
        steerCamelotVault_ = IVault(
            address(
                new TransparentUpgradeableProxy(
                    address(
                        new SteerCamelotVault(
                            vaultData.asset,
                            vaultData.feeRecipient,
                            IFeeProvider(vaultData.feeProvider),
                            vaultData.pool,
                            address(_getOracleForToken(ICamelotMultiPositionLiquidityManager(vaultData.pool).token0())),
                            address(_getOracleForToken(ICamelotMultiPositionLiquidityManager(vaultData.pool).token1()))
                        )
                    ),
                    vaultData.admin,
                    abi.encodeCall(
                        SteerCamelotVault.initialize,
                        (vaultData.admin, vaultData.name, vaultData.symbol, vaultData.manager)
                    )
                )
            )
        );
    }

    function _deployJonesCamelot(VaultSetup memory vaultData) internal returns (IVault jonesCamelotVault_) {
        jonesCamelotVault_ = IVault(
            address(
                new TransparentUpgradeableProxy(
                    address(
                        new JonesCamelotVault(
                            vaultData.asset,
                            vaultData.feeRecipient,
                            IFeeProvider(vaultData.feeProvider),
                            vaultData.pool, // compounder
                            address(pool_jones_weethWeth_ARBITRUM), // pool
                            address(0),
                            address(0)
                        )
                    ),
                    vaultData.admin,
                    abi.encodeCall(
                        JonesCamelotVault.initialize,
                        (vaultData.admin, vaultData.name, vaultData.symbol, vaultData.manager)
                    )
                )
            )
        );
    }

    function _deployAcross(VaultSetup memory vaultData) internal returns (IVault acrossVault_) {
        address assetWethPool;
        if (vaultData.asset == weth_ETHEREUM) {
            assetWethPool = address(0);
        } else if (vaultData.asset == usdc_ETHEREUM) {
            assetWethPool = address(pool_USDC_WETH_ETHEREUM);
        } else if (vaultData.asset == wbtc_ETHEREUM) {
            assetWethPool = address(pool_WBTC_WETH_ETHEREUM);
        } else if (vaultData.asset == usdt_ETHEREUM) {
            assetWethPool = address(pool_USDT_WETH_ETHEREUM);
        } else {
            revert();
        }
        IChainlinkOracle assetOracle;
        if (vaultData.asset == weth_ETHEREUM) {
            assetOracle = IChainlinkOracle(address(0));
        } else if (vaultData.asset == usdc_ETHEREUM) {
            assetOracle = oracle_USDCUSD_ETHEREUM;
        } else if (vaultData.asset == wbtc_ETHEREUM) {
            assetOracle = oracle_BTCUSD_ETHEREUM;
        } else if (vaultData.asset == usdt_ETHEREUM) {
            assetOracle = oracle_USDTUSD_ETHEREUM;
        } else {
            revert();
        }
        acrossVault_ = IVault(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(
                            new AcrossVault(
                                vaultData.asset,
                                address(across_hubPool_ETHEREUM),
                                IFeeProvider(vaultData.feeProvider),
                                vaultData.feeRecipient,
                                address(across_acceleratingDistributor_ETHEREUM),
                                address(pool_ACX_WETH_ETHEREUM),
                                assetWethPool,
                                address(weth_ETHEREUM),
                                vaultData.asset == weth_ETHEREUM ? IChainlinkOracle(address(0)) : oracle_ETHUSD_ETHEREUM,
                                assetOracle
                            )
                        ),
                        vaultData.admin,
                        abi.encodeCall(
                            AcrossVault.initialize,
                            (vaultData.admin, vaultData.name, vaultData.symbol, vaultData.manager)
                        )
                    )
                )
            )
        );
    }

    function _deployCompound(VaultSetup memory vaultData) internal returns (IVault compoundVault_) {
        compoundVault_ = IVault(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(
                            new CompoundVault(
                                vaultData.asset,
                                CErc20(vaultData.pool),
                                IFeeProvider(vaultData.feeProvider),
                                vaultData.feeRecipient
                            )
                        ),
                        vaultData.admin,
                        abi.encodeCall(
                            CompoundVault.initialize,
                            (vaultData.admin, vaultData.name, vaultData.symbol, vaultData.manager)
                        )
                    )
                )
            )
        );
    }

    function _deployCompoundETH(VaultSetup memory vaultData) internal returns (IVault compoundVault_) {
        compoundVault_ = IVault(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(
                            new CompoundVaultETH(
                                vaultData.asset,
                                CEth(vaultData.pool),
                                IFeeProvider(vaultData.feeProvider),
                                vaultData.feeRecipient
                            )
                        ),
                        vaultData.admin,
                        abi.encodeCall(
                            CompoundVaultETH.initialize,
                            (vaultData.admin, vaultData.name, vaultData.symbol, vaultData.manager)
                        )
                    )
                )
            )
        );
    }

    function _deployCompoundLayerbank(VaultSetup memory vaultData) internal returns (IVault compoundVault_) {
        compoundVault_ = IVault(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(
                            new CompoundLayerbankVault(
                                vaultData.asset,
                                ILToken(payable(vaultData.pool)),
                                IFeeProvider(vaultData.feeProvider),
                                vaultData.feeRecipient
                            )
                        ),
                        vaultData.admin,
                        abi.encodeCall(
                            CompoundLayerbankVault.initialize,
                            (vaultData.admin, vaultData.name, vaultData.symbol, vaultData.manager)
                        )
                    )
                )
            )
        );
    }
}
