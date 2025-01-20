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

contract VaultsDeploy {
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

    IERC20Metadata usdtArbitrum = IERC20Metadata(address(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9));
    IERC20Metadata wethArbitrum = IERC20Metadata(address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1));
    IERC20Metadata usdcArbitrum = IERC20Metadata(address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831));

    IERC20Metadata wethBase = IERC20Metadata(address(0x4200000000000000000000000000000000000006));
    IERC20Metadata usdcBase = IERC20Metadata(address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913));

    IERC20Metadata usdbBlast = IERC20Metadata(address(0x4300000000000000000000000000000000000003));
    IERC20Metadata wethBlast = IERC20Metadata(address(0x4300000000000000000000000000000000000004));
    IERC20Metadata wbtcBlast = IERC20Metadata(address(0xF7bc58b8D8f97ADC129cfC4c9f45Ce3C0E1D2692));
    IERC20Metadata blastBlast = IERC20Metadata(address(0xb1a5700fA2358173Fe465e6eA4Ff52E36e88E2ad));

    IChainlinkOracle oracle_ETH_BLAST = IChainlinkOracle(address(0x0af23B08bcd8AD35D1e8e8f2D2B779024Bd8D24A));
    IChainlinkOracle oracle_USDB_BLAST = IChainlinkOracle(address(0x3A236F67Fce401D87D7215695235e201966576E4));
    IChainlinkOracle oracle_BTC_BLAST = IChainlinkOracle(address(0x7262c8C5872A4Aa0096A8817cF61f5fa3c537330));

    IChainlinkOracle oracle_ETH_BASE = IChainlinkOracle(address(0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70));
    IChainlinkOracle oracle_USDT_BASE = IChainlinkOracle(address(0xf19d560eB8d2ADf07BD6D13ed03e1D11215721F9));
    IChainlinkOracle oracle_USDC_BASE = IChainlinkOracle(address(0x7e860098F58bBFC8648a4311b374B1D669a2bc6B));

    IChainlinkOracle oracle_ETH_ARB = IChainlinkOracle(address(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612));
    IChainlinkOracle oracle_USDC_ARB = IChainlinkOracle(address(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3));
    IChainlinkOracle oracle_USDT_ARB = IChainlinkOracle(address(0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7));

    IUniswapV3Factory factory_UNI_ARB = IUniswapV3Factory(address(0x1F98431c8aD98523631AE4a59f267346ea31F984));
    IUniswapV3Factory factory_UNI_BASE = IUniswapV3Factory(address(0x33128a8fC17869897dcE68Ed026d694621f6FDfD));
    IUniswapV3Pool pool_USDC_WETH_BASE = IUniswapV3Pool(address(0xd0b53D9277642d899DF5C87A3966A349A798F224));

    address assetProvider_USDB_BLAST = address(0x4BeD2A922654cAcC2Be974689619768FaBF24855);
    address assetProvider_WETH_BLAST = address(0x66714DB8F3397c767d0A602458B5b4E3C0FE7dd1);
    address assetProvider_BLAST_BLAST = address(0xeC1f5118d558050908122A7B84B10580818B68Da);
    address assetProvider_WBTC_BLAST = address(0x2D509190Ed0172ba588407D4c2df918F955Cc6E1);

    address assetProvider_USDT_ARB = address(0xF977814e90dA44bFA03b6295A0616a897441aceC);
    address assetProvider_USDC_ARB = address(0x2Df1c51E09aECF9cacB7bc98cB1742757f163dF7);
    address assetProvider_WETH_ARB = address(0x70d95587d40A2caf56bd97485aB3Eec10Bee6336);

    address assetProvider_WETH_BASE = address(0x6446021F4E396dA3df4235C62537431372195D38);
    address assetProvider_USDC_BASE = address(0x0B0A5886664376F59C351ba3f598C8A8B4D0A6f3);

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
            stargateSetup.weth = wethBase;
            stargateSetup.staking = IStargateStaking(payable(address(0xDFc47DCeF7e8f9Ab19a1b8Af3eeCF000C7ea0B80)));
            stargateSetup.swapPool =
                IUniswapV3Pool(factory.getPool(address(stargateSetup.stg), address(stargateSetup.weth), 10000));
            if (vaultData.pool == address(0x27a16dc786820B16E5c9028b75B99F6f604b5d26)) {
                stargateSetup.currentSwapPool =
                    IUniswapV3Pool(factory.getPool(address(usdcBase), address(wethBase), 500));
            }
        } else if (block.chainid == 42161) {
            // arbitrum
            IUniswapV3Factory factory = IUniswapV3Factory(address(0x1F98431c8aD98523631AE4a59f267346ea31F984));
            stargateSetup.stg = IERC20Metadata(address(0x6694340fc020c5E6B96567843da2df01b2CE1eb6));
            stargateSetup.weth = wethArbitrum;
            stargateSetup.staking = IStargateStaking(payable(address(0x3da4f8E456AC648c489c286B99Ca37B666be7C4C)));
            stargateSetup.swapPool =
                IUniswapV3Pool(factory.getPool(address(stargateSetup.stg), address(stargateSetup.weth), 3000));
            if (vaultData.pool == address(0xe8CDF27AcD73a434D661C84887215F7598e7d0d3)) {
                stargateSetup.currentSwapPool =
                    IUniswapV3Pool(factory.getPool(address(usdcArbitrum), address(wethArbitrum), 500));
            } else if (vaultData.pool == address(0xcE8CcA271Ebc0533920C83d39F417ED6A0abB7D0)) {
                stargateSetup.currentSwapPool =
                    IUniswapV3Pool(factory.getPool(address(usdtArbitrum), address(wethArbitrum), 500));
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
}
