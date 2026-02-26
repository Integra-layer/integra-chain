# Integra Layer

Integra Layer is an EVM-compatible Layer 1 blockchain built on the Cosmos SDK using the [Cosmos EVM](https://github.com/cosmos/evm) framework. It combines the interoperability of Cosmos (IBC) with full Ethereum tooling support — Solidity smart contracts, MetaMask, Blockscout, Foundry, Hardhat, and the entire EVM developer ecosystem.

## Networks

| Service | Mainnet | Testnet |
|---------|---------|---------|
| RPC | `https://mainnet.integralayer.com/rpc` | `https://testnet.integralayer.com/rpc` |
| REST | `https://mainnet.integralayer.com/api` | `https://testnet.integralayer.com/api` |
| EVM JSON-RPC | `https://mainnet.integralayer.com/evm` | `https://testnet.integralayer.com/evm` |
| WebSocket | `wss://mainnet.integralayer.com/ws` | `wss://testnet.integralayer.com/ws` |
| Blockscout | `https://blockscout.integralayer.com` | `https://testnet.blockscout.integralayer.com` |
| Explorer | [scan.integralayer.com](https://scan.integralayer.com) | — |

| Parameter | Mainnet | Testnet |
|-----------|---------|---------|
| Chain ID | `integra_26217-1` | `integra_26218-1` |
| EVM Chain ID | `26217` | `26218` |
| Token | IRL (18 decimals) | IRL (18 decimals) |
| Base Denom | `airl` | `airl` |

## Quick Start (Docker)

```bash
git clone https://github.com/Integra-layer/integra-chain.git
cd integra-chain
docker compose -f docker/docker-compose.validator.yml up
```

The setup wizard will launch automatically on first run — select your network, configure your validator, and follow the prompts.

## Build from Source

```bash
cd integra
go build -o intgd ./cmd/intgd
```

Or use Make:

```bash
make build
# Binary at build/intgd
```

### Prerequisites

- Go 1.22+
- GNU Make
- GCC (for CGO)

## Repository Structure

```
integra/          # Chain application (binary, genesis config, modules)
ops/              # Deployment runbook + automation scripts
docker/           # Dockerfile, setup wizard, docker-compose
tests/            # BATS integration tests
docs/             # Migration guides
```

## Documentation

- **[Chain Parameters](integra/README.md)** — genesis config, module params, network endpoints, EVM gotchas
- **[Deployment Runbook](ops/README.md)** — step-by-step guide to deploy mainnet/testnet from scratch
- **[EVM Tooling](https://github.com/Integra-layer/evm)** — Foundry + Hardhat compatibility tests, example contracts

## Testing

```bash
make test-unit          # Unit tests
make test-unit-cover    # Coverage report
make test-fuzz          # Fuzz tests
make test-solidity      # Solidity tests
make benchmark          # Benchmark tests
```

## License

Apache 2.0. Built on [Cosmos EVM](https://github.com/cosmos/evm) (originally [evmOS](https://github.com/evmos/OS) by Tharsis, funded by the Interchain Foundation).
