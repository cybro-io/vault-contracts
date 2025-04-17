## Cybro Smart-Contracts

### Build & Test
We use Forge from Foundry to build and test our contracts. Check [official Foundry documentation](https://book.getfoundry.sh/getting-started/installation) to install Foundry and Forge.

To build the contracts, run the following command:
```bash
forge build
```

To test the contracts, run the following commands:
```bash
forge test
```

To deploy the stargate vaults on arbitrum chain, run the following command:
```bash
forge script UpdatedDeployScript --sig "deployStargate_Arbitrum()" --private-key <your_private_key>
```

To deploy the stargate vaults on base chain, run the following command:
```bash
forge script UpdatedDeployScript --sig "deployStargate_Base()" --private-key <your_private_key>
```

To deploy the other vaults, run the following command:
```bash
forge script UpdatedDeployScript --sig "deployMainnet()" --private-key <your_private_key> --rpc-url <your_rpc_url>
```

To deploy one click index with all the vaults, ont the base chain, run the following command:
```bash
forge script UpdatedDeployScript --sig "deployOneClickBase()" --private-key <your_private_key> --rpc-url <your_base_rpc_url>
```

To deploy one click index with all the vaults, on the arbitrum chain, run the following command:
```bash
forge script UpdatedDeployScript --sig "deployOneClickArbitrum()" --private-key <your_private_key> --rpc-url <your_arbitrum_rpc_url>
```

To deploy spark vault on the base chain, run the following command:
```bash
forge script UpdatedDeployScript --sig "deploySparkBase()" --private-key <your_private_key> --rpc-url <your_base_rpc_url>
```

To deploy one click index with all of the vaults, on the blast chain with WETH, run the following command:
```bash
forge script UpdatedDeployScript --sig "deployOneClickBlast_WETH()" --private-key <your_private_key> --rpc-url <your_blast_rpc_url>
```

To deploy seasonal vault on the arbitrum chain, run the following command:
```bash
forge script UpdatedDeployScript --sig "deploySeasonalArbitrum()"  --private-key <your_private_key> --rpc-url <your_arbitrum_rpc_url>
```

To deploy seasonal vault on the base chain, run the following command:
```bash
forge script UpdatedDeployScript --sig "deploySeasonalBase()"  --private-key <your_private_key> --rpc-url <your_arbitrum_rpc_url>
```

To deploy steer and jones vaults on the arbitrum chain, run the following command:
```bash
forge script UpdatedDeployScript --sig "deploySteerJonesArbitrum()"  --private-key <your_private_key> --rpc-url <your_arbitrum_rpc_url>
```

To deploy across vault on the ethereum chain, run the following command:
```bash
forge script UpdatedDeployScript --sig "deployEthereumAcross()"  --private-key <your_private_key> --rpc-url <your_ethereum_rpc_url>
```