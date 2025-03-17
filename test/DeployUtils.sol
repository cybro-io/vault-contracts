// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

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
import {GammaAlgebraVault, IUniProxy, IHypervisor} from "../src/vaults/GammaAlgebraVault.sol";

contract DeployUtils {
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

    IERC20Metadata usdt_ARBITRUM = IERC20Metadata(address(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9));
    IERC20Metadata weth_ARBITRUM = IERC20Metadata(address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1));
    IERC20Metadata usdc_ARBITRUM = IERC20Metadata(address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831));

    IERC20Metadata weth_BASE = IERC20Metadata(address(0x4200000000000000000000000000000000000006));
    IERC20Metadata usdc_BASE = IERC20Metadata(address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913));

    IERC20Metadata usdb_BLAST = IERC20Metadata(address(0x4300000000000000000000000000000000000003));
    IERC20Metadata weth_BLAST = IERC20Metadata(address(0x4300000000000000000000000000000000000004));
    IERC20Metadata wbtc_BLAST = IERC20Metadata(address(0xF7bc58b8D8f97ADC129cfC4c9f45Ce3C0E1D2692));
    IERC20Metadata blast_BLAST = IERC20Metadata(address(0xb1a5700fA2358173Fe465e6eA4Ff52E36e88E2ad));

    IChainlinkOracle oracle_ETH_BLAST = IChainlinkOracle(address(0x0af23B08bcd8AD35D1e8e8f2D2B779024Bd8D24A));
    IChainlinkOracle oracle_USDB_BLAST = IChainlinkOracle(address(0x3A236F67Fce401D87D7215695235e201966576E4));
    IChainlinkOracle oracle_BTC_BLAST = IChainlinkOracle(address(0x7262c8C5872A4Aa0096A8817cF61f5fa3c537330));

    IChainlinkOracle oracle_ETH_BASE = IChainlinkOracle(address(0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70));
    IChainlinkOracle oracle_USDT_BASE = IChainlinkOracle(address(0xf19d560eB8d2ADf07BD6D13ed03e1D11215721F9));
    IChainlinkOracle oracle_USDC_BASE = IChainlinkOracle(address(0x7e860098F58bBFC8648a4311b374B1D669a2bc6B));

    IChainlinkOracle oracle_ETH_ARBITRUM = IChainlinkOracle(address(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612));
    IChainlinkOracle oracle_USDC_ARBITRUM = IChainlinkOracle(address(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3));
    IChainlinkOracle oracle_USDT_ARBITRUM = IChainlinkOracle(address(0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7));

    IUniswapV3Factory factory_UNI_ARB = IUniswapV3Factory(address(0x1F98431c8aD98523631AE4a59f267346ea31F984));
    IUniswapV3Factory factory_UNI_BASE = IUniswapV3Factory(address(0x33128a8fC17869897dcE68Ed026d694621f6FDfD));
    IUniswapV3Pool pool_USDC_WETH_BASE = IUniswapV3Pool(address(0xd0b53D9277642d899DF5C87A3966A349A798F224));
    IUniswapV3Pool pool_USDC_USDT_ARBITRUM = IUniswapV3Pool(address(0xbE3aD6a5669Dc0B8b12FeBC03608860C31E2eef6));

    address assetProvider_USDB_BLAST = address(0x4BeD2A922654cAcC2Be974689619768FaBF24855);
    address assetProvider_WETH_BLAST = address(0x66714DB8F3397c767d0A602458B5b4E3C0FE7dd1);
    address assetProvider_BLAST_BLAST = address(0xeC1f5118d558050908122A7B84B10580818B68Da);
    address assetProvider_WBTC_BLAST = address(0x2D509190Ed0172ba588407D4c2df918F955Cc6E1);

    address assetProvider_USDT_ARBITRUM = address(0xF977814e90dA44bFA03b6295A0616a897441aceC);
    address assetProvider_USDC_ARBITRUM = address(0x2Df1c51E09aECF9cacB7bc98cB1742757f163dF7);
    address assetProvider_WETH_ARBITRUM = address(0x70d95587d40A2caf56bd97485aB3Eec10Bee6336);

    address assetProvider_WETH_BASE = address(0x6446021F4E396dA3df4235C62537431372195D38);
    address assetProvider_USDC_BASE = address(0x0B0A5886664376F59C351ba3f598C8A8B4D0A6f3);

    uint256 lastCachedBlockid_BLAST = 14284818;
    uint256 lastCachedBlockid_ARBITRUM = 300132227;
    uint256 lastCachedBlockid_BASE = 25292162;

    IStargatePool stargate_usdtPool_ARBITRUM =
        IStargatePool(payable(address(0xcE8CcA271Ebc0533920C83d39F417ED6A0abB7D0)));
    IStargatePool stargate_wethPool_ARBITRUM =
        IStargatePool(payable(address(0xA45B5130f36CDcA45667738e2a258AB09f4A5f7F)));
    IStargatePool stargate_usdcPool_ARBITRUM =
        IStargatePool(payable(address(0xe8CDF27AcD73a434D661C84887215F7598e7d0d3)));

    IStargatePool stargate_usdcPool_BASE = IStargatePool(payable(address(0x27a16dc786820B16E5c9028b75B99F6f604b5d26)));
    IStargatePool stargate_wethPool_BASE = IStargatePool(payable(address(0xdc181Bd607330aeeBEF6ea62e03e5e1Fb4B6F7C7)));

    IAavePool aave_usdbPool_BLAST = IAavePool(address(0xd2499b3c8611E36ca89A70Fda2A72C49eE19eAa8));
    IAavePool aave_zerolendPool_BLAST = IAavePool(address(0xa70B0F3C2470AbBE104BdB3F3aaa9C7C54BEA7A8));
    IAavePool aave_pool_ARBITRUM = IAavePool(address(0x794a61358D6845594F94dc1DB02A252b5b4814aD));
    IAavePool aave_pool_BASE = IAavePool(address(0xA238Dd80C259a72e81d7e4664a9801593F98d1c5));

    CErc20 compound_moonwellUSDC_BASE = CErc20(address(0xEdc817A28E8B93B03976FBd4a3dDBc9f7D176c22));

    IUniProxy uniProxy_gamma_ARBITRUM = IUniProxy(address(0x1F1Ca4e8236CD13032653391dB7e9544a6ad123E));
    IHypervisor hypervisor_gamma_ARBITRUM = IHypervisor(address(0xd7Ef5Ac7fd4AAA7994F3bc1D273eAb1d1013530E));

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
                            vaultData.feeRecipient
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
}
