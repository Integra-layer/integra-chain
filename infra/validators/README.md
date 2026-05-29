# Validator config baseline + drift control

Checked-in copies of the **live** `app.toml` / `config.toml` for the three Integra-operated
`integra-testnet-1` validators, captured 2026-05-29 after the permanent-fix run. These are the
**declared baseline**: the live nodes must match them, and any intentional change must be made here
in the same PR. A CI job (and `check-drift.sh`) fails on undeclared live-vs-repo drift.

> These files contain **no secrets** — validator/node keys live in separate
> `priv_validator_key.json` / `node_key.json` (never committed). `app.toml`/`config.toml` are pure
> operational config (public peer addresses, RPC knobs, pruning, etc.).

## Layout
```
infra/validators/
  gateway/   app.toml config.toml   # 46.225.231.81  Integra-Helsinki  (public /rpc,/api,/ws backend + validator)
  signer-1/  app.toml config.toml   # 45.77.139.208  Integra-Amsterdam (validator + EVM RPC via Caddy :8645)
  signer-2/  app.toml config.toml   # 159.223.206.94 Integra-SantaClara (validator + EVM RPC via Caddy :8645)
  check-drift.sh                    # diff live vs baseline; exit!=0 on drift
```

## Intentional per-node differences (NOT drift)
Each node is diffed against **its own** baseline, so these are never flagged:

| key | gateway | signers (1 & 2) | why |
|---|---|---|---|
| `[json-rpc] gas-cap` | `300000000` | `50000000` | gateway runs the ~22k-element IRWAWrapper enumeration (load-bearing — do NOT lower) |
| `[json-rpc] evm-timeout` | `15s` | `8s` | matches the gas-cap headroom; gateway proxy timeouts must sit above 15s |
| `[json-rpc] address` | `0.0.0.0:8545` | `127.0.0.1:8545` | gateway :8545 is ufw-locked to signers+explorer; signers are loopback behind Caddy :8645 |
| `[json-rpc] ws-address` | `127.0.0.1:8546` | `127.0.0.1:8546` | loopback on all (2026-05-29) — Caddy fronts /ws |
| `[json-rpc] max-open-connections` | `600` | `200` | bounded pools (2026-05-29) — gateway carries more direct callers |
| `[json-rpc] batch-request-limit` | `10` | `100` | gateway is abuse-exposed; signers serve the trusted indexer which may batch |
| `[state-sync] snapshot-interval` | `0` | `0` | snapshots disabled everywhere (kills the 60-min CPU grind) |
| `[json-rpc] api` | `eth,net,web3` | `eth,net,web3` | debug,txpool dropped from signers 2026-05-29 (were exposed) |

Everything else should be identical across nodes (same binary sha256 `527fc04e…`, SDK v0.53.5,
CometBFT v0.38.19). If a non-listed field drifts on one node, reconcile it.

## Run the drift check
```bash
INTEGRA_SSH_KEY=~/.ssh/integra ./infra/validators/check-drift.sh
```
Exit 0 = all match. Exit 1 = drift (the diff is printed; reconcile baseline or revert the live change).

## CI
`.github/workflows/validator-config-drift.yml` runs `check-drift.sh` on a schedule + on PRs that
touch `infra/validators/**`. It needs an SSH deploy key with read access to the validators, provided
as the `INTEGRA_VALIDATOR_SSH_KEY` repo secret (see the workflow). Until that secret is set the
workflow is a no-op guard (skips with a notice) — set the secret to activate live drift detection.

## Known open item (NOT drift)
The gateway IAVL store (`application.db`) is bloated (~54G vs signers ~18G) because its pruning has
been failing (`Error while pruning err="version does not exist"`). This is **not** a config drift —
the `pruning`/`snapshot-interval` settings are correct. The fix is an **offline** `intgd prune`
during a scheduled maintenance window (gateway down ~10-40 min — follow the validator restart safety
protocol; omeljan must stay signing throughout). See
`docs/findings/2026-05-29-rpc-flapping-explorer-overload/`.
