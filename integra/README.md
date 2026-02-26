# Integra Layer Chain

Integra Layer is an EVM-compatible blockchain built on the Cosmos SDK using the [cosmos/evm](https://github.com/cosmos/evm) framework (v0.5.1).

## Chain Configuration

| Parameter | Mainnet | Testnet |
|-----------|---------|---------|
| Binary | `intgd` | `intgd` |
| Chain ID | `integra_26217-1` | `integra_26218-1` |
| EVM Chain ID | `26217` | `26218` |
| Bech32 Prefix | `integra` | `integra` |
| Denom (base) | `airl` | `airl` |
| Denom (display) | `IRL` | `IRL` |
| Decimals | 18 | 18 |
| Home Directory | `~/.intgd` | `~/.intgd` |

## Genesis Parameters

### Mint
- **Inflation**: 1% fixed (min = max = 0.01, rate change = 0)
- **Mint Denom**: `airl`
- **Blocks/Year**: 6,311,520 (~5s block time)

### Fee Market (EIP-1559)
- **Base Fee**: 5,000 gwei (5,000,000,000,000 airl)
- **Min Gas Price**: 5,000 gwei
- **Base Fee Change Denominator**: 8
- **Elasticity Multiplier**: 2
- **Min Gas Multiplier**: 0.5

### Staking
- **Max Validators**: 100
- **Unbonding Period**: 21 days
- **Max Entries**: 7
- **Historical Entries**: 10,000
- **Min Commission Rate**: 0%
- **Bond Denom**: `airl`

### Governance
- **Min Deposit**: 1,000,000 IRL (1e24 airl)
- **Expedited Min Deposit**: 5,000,000 IRL (5e24 airl)
- **Max Deposit Period**: 7 days
- **Voting Period**: 5 days
- **Expedited Voting Period**: 1 day
- **Quorum**: 33.4%
- **Threshold**: 50%
- **Veto Threshold**: 33.4%
- **Min Initial Deposit Ratio**: 25%
- **Burn Vote Veto**: Yes

### Slashing
- **Signed Blocks Window**: 10,000
- **Min Signed Per Window**: 5%
- **Downtime Jail Duration**: 10 minutes
- **Double Sign Slash**: 5%
- **Downtime Slash**: 0.01%

### Distribution
- **Community Tax**: 0%
- **Withdraw Address Enabled**: Yes

### EVM
- **Precompiles**: All available static precompiles enabled
- **Preinstalls**: Default preinstalls enabled
- **ERC20 Token Pairs**: Native token pair + WIRL precompile

## Cosmos SDK Modules

- `auth`, `authz`, `bank`, `capability`, `consensus`
- `distribution`, `evidence`, `feegrant`, `genutil`, `gov`
- `mint`, `params`, `slashing`, `staking`, `upgrade`
- `evm`, `erc20`, `feemarket` (cosmos/evm modules)
- `ibc-transfer`, `ibc-core` (IBC modules)

## Building

```bash
cd integra
go build -o intgd ./cmd/intgd
```

## Changes from cosmos/evm v0.5.1

This directory was forked from the `evmd/` example chain in cosmos/evm v0.5.1 with the following changes:

- **Binary**: `evmd` -> `intgd`
- **Package**: `package evmd` -> `package integra`
- **Type**: `EVMD` -> `IntegraApp`, `NewExampleApp` -> `NewIntegraApp`
- **Bech32**: `cosmos` -> `integra`
- **Denom**: `atest`/`test` -> `airl`/`irl`/`IRL`
- **EVM Chain IDs**: 262144 -> 26217 (mainnet), 26218 (testnet)
- **Home Dir**: `.evmd` -> `.intgd`
- **Config**: All genesis parameters customized (see above)
- **New files**: `integra_config.go` (constants + helpers), `integra_config_test.go`, `genesis_test.go`
