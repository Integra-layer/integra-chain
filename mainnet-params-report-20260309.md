# Integra Mainnet Parameter Verification Report

**Date:** 2026-03-09 13:32:01 UTC
**Endpoints:** REST=https://mainnet.integralayer.com/api | RPC=https://mainnet.integralayer.com/rpc | EVM=https://mainnet.integralayer.com/evm

## 1. Chain Identity

| Parameter | Expected | Actual | Status |
|-----------|----------|--------|--------|
| node_info.network | `integra-1` | `integra-1` | ✅ PASS |
| node_info.moniker | — | `Integra-Gateway` | 📋 RECORD |
| latest_block_height | — | `1065` | 📋 RECORD |
| catching_up | `false` | `false` | ✅ PASS |
| eth_chainId | `0x6669` | `0x6669` | ✅ PASS |
| net_version | `26217` | `26217` | ✅ PASS |
| web3_clientVersion | — | `Version dev ()
Compiled at  using Go go1.23.8 (amd64)` | 📋 RECORD |

## 2. Consensus Params

| Parameter | Expected | Actual | Status |
|-----------|----------|--------|--------|
| block.max_bytes | — | `22020096` | 📋 RECORD |
| block.max_gas | — | `-1` | 📋 RECORD |
| evidence.max_age_num_blocks | — | `100000` | 📋 RECORD |
| evidence.max_age_duration | — | `172800000000000` | 📋 RECORD |
| validator.pub_key_types | `["ed25519"]` | `["ed25519"]` | ✅ PASS |

## 3. Staking

| Parameter | Expected | Actual | Status |
|-----------|----------|--------|--------|
| bond_denom | `airl` | `airl` | ✅ PASS |
| unbonding_time | `1814400s` | `1814400s` | ✅ PASS |
| max_validators | `100` | `100` | ✅ PASS |
| max_entries | `7` | `7` | ✅ PASS |
| historical_entries | `10000` | `10000` | ✅ PASS |
| min_commission_rate | `0.000000000000000000` | `0.000000000000000000` | ✅ PASS |

### Validators

**Bonded validators:** 4

| Moniker | Operator Address | Tokens | Commission |
|---------|-----------------|--------|------------|
| Integra-Gateway | integravaloper188hxs6r3nzv8xl4glkuxzcewn09x4usd86pqp8 | 999000000000000000000000 | 0.050000000000000000 |
| Integra-Archive | integravaloper13q6sj0yandc7kmha339222yrax5zym0dtp74wz | 999000000000000000000000 | 0.050000000000000000 |
| Integra-Signer1 | integravaloper14uuepyevsxs54j3gffyl5r5vpjfymmjkd76mps | 999000000000000000000000 | 0.050000000000000000 |
| Integra-Signer2 | integravaloper1k7ghd60lqucwgk9xgxnmuvn5a40wzarnx7xwme | 999000000000000000000000 | 0.050000000000000000 |

**Staking pool:** bonded=`3996000000000000000000000` not_bonded=`0`

## 4. Mint

| Parameter | Expected | Actual | Status |
|-----------|----------|--------|--------|
| mint_denom | `airl` | `airl` | ✅ PASS |
| inflation_rate_change | `0.000000000000000000` | `0.000000000000000000` | ✅ PASS |
| inflation_max | `0.030000000000000000` | `0.030000000000000000` | ✅ PASS |
| inflation_min | `0.030000000000000000` | `0.030000000000000000` | ✅ PASS |
| goal_bonded | `0.010000000000000000` | `0.010000000000000000` | ✅ PASS |
| blocks_per_year | `6311520` | `6311520` | ✅ PASS |
| current_inflation | `0.030000000000000000` | `0.030000000000000000` | ✅ PASS |
| annual_provisions | — | `3000015186554487224144325815.490000000000000000` | 📋 RECORD |

## 5. Governance

| Parameter | Expected | Actual | Status |
|-----------|----------|--------|--------|
| min_deposit (airl) | `100000000000000000000000000` | `100000000000000000000000000` | ✅ PASS |
| min_deposit denom | `airl` | `airl` | ✅ PASS |
| expedited_min_deposit (airl) | `500000000000000000000000000` | `500000000000000000000000000` | ✅ PASS |
| max_deposit_period | `604800s` | `604800s` | ✅ PASS |
| voting_period | `604800s` | `604800s` | ✅ PASS |
| expedited_voting_period | `259200s` | `259200s` | ✅ PASS |
| quorum | `0.334000000000000000` | `0.334000000000000000` | ✅ PASS |
| threshold | `0.500000000000000000` | `0.500000000000000000` | ✅ PASS |
| veto_threshold | `0.334000000000000000` | `0.334000000000000000` | ✅ PASS |
| min_initial_deposit_ratio | `0.250000000000000000` | `0.250000000000000000` | ✅ PASS |
| burn_vote_veto | `true` | `true` | ✅ PASS |

## 6. Slashing

| Parameter | Expected | Actual | Status |
|-----------|----------|--------|--------|
| signed_blocks_window | `10000` | `10000` | ✅ PASS |
| min_signed_per_window | `0.050000000000000000` | `0.050000000000000000` | ✅ PASS |
| downtime_jail_duration | `600s` | `600s` | ✅ PASS |
| slash_fraction_double_sign | `0.050000000000000000` | `0.050000000000000000` | ✅ PASS |
| slash_fraction_downtime | `0.000100000000000000` | `0.000100000000000000` | ✅ PASS |

### Validator Signing Infos

| Validator | Missed Blocks | Tombstoned |
|-----------|--------------|------------|
| integravalcons1fw88gkrxzpagr2g0l0ktyndhdueqlxfr2csm0r | 0 | 1970-01-01T00:00:00Z |
| integravalcons120ghrnnzs42nyhjx3d0r86ehuk8szjfckaglx2 | 0 | 1970-01-01T00:00:00Z |
| integravalcons1kvm2vdk4pwee8knfwqam4tpje40dxt9gnq95ck | 12 | 1970-01-01T00:00:00Z |
| integravalcons170jl9cj5g2pvglcuk5kx7q7yfurn6grqljpv2s | 0 | 1970-01-01T00:00:00Z |

## 7. Distribution

| Parameter | Expected | Actual | Status |
|-----------|----------|--------|--------|
| community_tax | `0.000000000000000000` | `0.000000000000000000` | ✅ PASS |
| withdraw_addr_enabled | `true` | `true` | ✅ PASS |
| community_pool | — | `0` | 📋 RECORD |

## 8. Bank

| Parameter | Expected | Actual | Status |
|-----------|----------|--------|--------|
| total_supply (airl) | — | `100000506693806630846272699208` | 📋 RECORD |
| denom_metadata.base | `airl` | `airl` | ✅ PASS |
| denom_metadata.display | `irl` | `irl` | ✅ PASS |
| denom_metadata.name | `IRL` | `IRL` | ✅ PASS |
| denom_metadata.symbol | `IRL` | `IRL` | ✅ PASS |
| denom_metadata.description | `Integra Layer Native Token` | `Integra Layer Native Token` | ✅ PASS |
| denom_unit exponent=0 | `airl` | `airl` | ✅ PASS |
| denom_unit exponent=18 | `irl` | `irl` | ✅ PASS |

## 9. Auth

| Parameter | Expected | Actual | Status |
|-----------|----------|--------|--------|
| max_memo_characters | — | `256` | 📋 RECORD |
| tx_sig_limit | — | `7` | 📋 RECORD |
| tx_size_cost_per_byte | — | `10` | 📋 RECORD |
| sig_verify_cost_ed25519 | — | `590` | 📋 RECORD |
| sig_verify_cost_secp256k1 | — | `1000` | 📋 RECORD |

## 10. EVM Module

| Parameter | Expected | Actual | Status |
|-----------|----------|--------|--------|
| evm_denom | `airl` | `airl` | ✅ PASS |
| extra_eips | `[]` | `[]` | ✅ PASS |
| active_static_precompiles count | `9` | `9` | ✅ PASS |
| precompile: P256 | `0x0000000000000000000000000000000000000100` | present | ✅ PASS |
| precompile: Bech32 | `0x0000000000000000000000000000000000000400` | present | ✅ PASS |
| precompile: Staking | `0x0000000000000000000000000000000000000800` | present | ✅ PASS |
| precompile: Distribution | `0x0000000000000000000000000000000000000801` | present | ✅ PASS |
| precompile: ICS20 | `0x0000000000000000000000000000000000000802` | present | ✅ PASS |
| precompile: Vesting | `0x0000000000000000000000000000000000000803` | present | ✅ PASS |
| precompile: Bank | `0x0000000000000000000000000000000000000804` | present | ✅ PASS |
| precompile: Governance | `0x0000000000000000000000000000000000000805` | present | ✅ PASS |
| precompile: Slashing | `0x0000000000000000000000000000000000000806` | present | ✅ PASS |
| access_control.create | contains `ACCESS_TYPE_PERMISSIONLESS` | `ACCESS_TYPE_PERMISSIONLESS` | ✅ PASS |
| access_control.call | contains `ACCESS_TYPE_PERMISSIONLESS` | `ACCESS_TYPE_PERMISSIONLESS` | ✅ PASS |

## 11. Fee Market

| Parameter | Expected | Actual | Status |
|-----------|----------|--------|--------|
| no_base_fee | `false` | `false` | ✅ PASS |
| base_fee_change_denominator | `8` | `8` | ✅ PASS |
| elasticity_multiplier | `2` | `2` | ✅ PASS |
| base_fee | `5000000000000` | `5000000000000` | ✅ PASS |
| min_gas_price | `5000000000000.000000000000000000` | `5000000000000.000000000000000000` | ✅ PASS |
| min_gas_multiplier | `0.500000000000000000` | `0.500000000000000000` | ✅ PASS |
| enable_height | `0` | `0` | ✅ PASS |

## 12. ERC-20

| Parameter | Expected | Actual | Status |
|-----------|----------|--------|--------|
| enable_erc20 | `true` | `true` | ✅ PASS |
| permissionless_registration | `false` | `false` | ✅ PASS |

### Token Pairs

| WIRL erc20_address | `0xD4949664cD82660AaE99bEdc034a0deA8A0bd517` | `0xD4949664cD82660AaE99bEdc034a0deA8A0bd517` | ✅ PASS |
| WIRL denom | `airl` | `airl` | ✅ PASS |
| WIRL enabled | `true` | `true` | ✅ PASS |
| WIRL contract_owner | `OWNER_MODULE` | `OWNER_MODULE` | ✅ PASS |

## 13. IBC

| Parameter | Expected | Actual | Status |
|-----------|----------|--------|--------|
| ibc_clients | — | `0` | 📋 RECORD |
| ibc_connections | — | `1` | 📋 RECORD |
| ibc_channels | — | `0` | 📋 RECORD |

## 14. EVM Verification

### Gas Prices

| Parameter | Expected | Actual | Status |
|-----------|----------|--------|--------|
| eth_gasPrice (gwei) | >= `5000` | `5625` | ✅ PASS |
| eth_maxPriorityFeePerGas | — | `0x9184e72a00` | 📋 RECORD |

### Precompile Code Verification

| Parameter | Expected | Actual | Status |
|-----------|----------|--------|--------|
| P256 (0x0000000000000000000000000000000000000100) | responds | `0x` | ✅ PASS |
| Bech32 (0x0000000000000000000000000000000000000400) | responds | `0x` | ✅ PASS |
| Staking (0x0000000000000000000000000000000000000800) | responds | `0x` | ✅ PASS |
| Distribution (0x0000000000000000000000000000000000000801) | responds | `0x` | ✅ PASS |
| ICS20 (0x0000000000000000000000000000000000000802) | responds | `0x` | ✅ PASS |
| Vesting (0x0000000000000000000000000000000000000803) | responds | `0x` | ✅ PASS |
| Bank (0x0000000000000000000000000000000000000804) | responds | `0x` | ✅ PASS |
| Governance (0x0000000000000000000000000000000000000805) | responds | `0x` | ✅ PASS |
| Slashing (0x0000000000000000000000000000000000000806) | responds | `0x` | ✅ PASS |

### Preinstalled Contract Code Verification

| Parameter | Expected | Actual | Status |
|-----------|----------|--------|--------|
| Create2 | has code | `0x7fffffffffffffffff...` (140 chars) | ✅ PASS |
| Multicall3 | has code | `0x608060405260043610...` (7618 chars) | ✅ PASS |
| Permit2 | has code | `0x604060808152600490...` (18306 chars) | ✅ PASS |
| Safe singleton factory | has code | `0x7fffffffffffffffff...` (140 chars) | ✅ PASS |
| EIP-2935 | has code | `0x3373ffffffffffffff...` (168 chars) | ✅ PASS |

### WIRL Contract Verification

| Parameter | Expected | Actual | Status |
|-----------|----------|--------|--------|
| WIRL contract code | non-empty | `0x608060405234801561001057600080fd5b50600436106101da5760003560e01c80635c975abb11...` | ✅ PASS |
| WIRL name() | — | `IRL` | 📋 RECORD |
| WIRL symbol() | — | `IRL` | 📋 RECORD |
| WIRL decimals() | `18` | `18` | ✅ PASS |

## 15. WebSocket

| Parameter | Expected | Actual | Status |
|-----------|----------|--------|--------|
| ws eth_chainId | `0x6669` | `error` (Node built-in WS may not support wss://) | ⚠️ WARN |

## 16. Node Config (via SSH)

| Parameter | Expected | Actual | Status |
|-----------|----------|--------|--------|
| minimum-gas-prices | — | `0airl` | 📋 RECORD |
| pruning | — | `default` | 📋 RECORD |
| json-rpc api | — | `eth,txpool,personal,net,debug,web3` | 📋 RECORD |
| telemetry.enabled | — | `` | 📋 RECORD |

---

## Summary

| Status | Count |
|--------|-------|
| ✅ PASS | 87 |
| ❌ FAIL | 0 |
| ⚠️ WARN | 1 |
| 📋 RECORD | 25 |
| **Total** | **113** |

**Result: ALL CHECKS PASSED** ✅
