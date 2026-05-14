# Migration plan — move the public testnet RPC origin off the bonded validator

**Status:** PLAN ONLY — not executed. For operator review.
**Authored:** 2026-05-14 (immediately after the explorer migration + the removeStalledBlock incident).
**Owner:** TBD (operator to assign before execution).

---

## 1. Why this migration

`testnet.integralayer.com` (the public testnet RPC origin) is currently served by
**testnet-gateway (46.225.231.81)** — the *same box that runs a bonded validator*
(`intgd.service`, currently PID 329272, moniker **Integra-Helsinki**).

Caddy on testnet-gateway reverse-proxies the public hostname straight into the
**validator's own `intgd` process**:

| Public path | Backend (on testnet-gateway) | Served by |
|---|---|---|
| `/rpc/*`, `/rpc` | `localhost:26657` | validator intgd (CometBFT RPC) |
| `/api/*`, `/api` | `localhost:1317` | validator intgd (Cosmos REST) |
| `/evm/*`, `/evm` | `localhost:8545` | validator intgd (EVM JSON-RPC) |
| `/ws` | `localhost:8546` | validator intgd (EVM WebSocket) |
| `/api/faucet`, everything else | `localhost:3000` | Portal (Next.js) |

This is the **root structural risk** behind the two most recent incidents:

- **2026-05-13** — an `eth_getLogs` storm against the public EVM RPC drove
  `intgd` memory/CPU up on testnet-gateway; the `intgd-throttle.service`
  autoscaler had to be built to clamp Caddy `max_conns_per_host` so public RPC
  load could not OOM the validator.
- **2026-05-14** — the Ethernal explorer (then co-located on testnet-gateway)
  was migrated *off* onto a dedicated box for exactly the same reason. The
  config audit that followed (`docs/findings/2026-05-14-explorer-migration-config-audit.md`)
  flagged the RPC origin as **"the next migration target"** (Risk #4).

A bonded validator that shares CPU, RAM, page cache, file descriptors and
network with an unauthenticated public RPC endpoint can be starved into
**missed blocks → downtime slashing** (testnet slashing window is 10,000
blocks at 5% min-signed) by ordinary public traffic. The throttle autoscaler
is a *mitigation*; decoupling is the *fix*.

> Note: signer-1 (45.77.139.208) and signer-2 (159.223.206.94) already bind
> their `intgd` RPC to `127.0.0.1` and run EVM RPC with `enable = false` —
> they are not exposed. Only testnet-gateway's validator is exposed, *because*
> it doubles as the public RPC origin. This migration makes testnet-gateway's
> validator look like the other two.

## 2. Target architecture

Stand up a **new dedicated box** — call it `testnet-rpc` — that runs its own
**non-validator full node** plus the public edge:

```
                          ┌─────────────────────────────────────────┐
   Internet ──HTTPS──▶ Caddy (testnet-rpc) ──▶ intgd full node (testnet-rpc)
                          │   testnet.integralayer.com               │  - NOT a validator
                          │   /rpc /api /evm /ws                     │  - EVM RPC enable=true
                          │   /api/faucet, / → Portal (see §6)        │  - RPC 0.0.0.0 (behind Caddy only)
                          └─────────────────────────────────────────┘
                                                                       peers with ▼
   testnet-gateway (46.225.231.81)         signer-1            signer-2
   intgd VALIDATOR — RPC now 127.0.0.1     (validator)         (validator)
   only, EVM RPC enable=false              (unchanged)         (unchanged)
```

After cutover:
- **testnet-gateway** keeps running its validator `intgd`, but its RPC is
  rebound to `127.0.0.1` and EVM RPC `enable=false` — identical posture to
  signer-1/signer-2. It is no longer a public endpoint. The
  `intgd-throttle.service` autoscaler can be **retired** (its job — protecting
  the validator from public RPC load — no longer exists).
- **testnet-rpc** absorbs all public RPC traffic on a node whose worst-case
  failure mode is "the public RPC is slow", not "a validator gets slashed".

### Sizing

Reference the explorer box (Hetzner CCX23: 4 dedicated vCPU / 16 GB / 160 GB
NVMe) — adequate, but the public EVM RPC is heavier than the explorer's DB box
under `eth_getLogs`/large view-call load. **Recommend CCX33 (8 vCPU / 32 GB)**
or larger, NVMe, same region family as the validators for low peer latency.
Disk must fit the full (non-pruned) chain + headroom; confirm current
`~/.intgd/data` size on testnet-gateway before ordering.

## 3. Non-negotiables / safety rails

- **Do NOT touch the validator's consensus state.** The new node is a fresh,
  independent full node. Never copy `priv_validator_key.json` or
  `priv_validator_state.json` from any validator to `testnet-rpc`. The new
  node MUST come up with `intgd init` + a *fresh* node key and an empty/zeroed
  validator state — it is a full node, not a validator.
- **No coordinated-upgrade / consensus-breaking changes.** `testnet-rpc` runs
  the **exact same `intgd` binary** as the live validators (same tag, same
  Go 1.23.8 / CometBFT v0.38.19 / Cosmos SDK v0.53.5). Build/SCP the identical
  binary; verify the hash before starting.
- **DNS flip is the only user-visible cutover step** and it is instant +
  reversible. Keep TTL low (≤60s) for the migration window.
- **testnet-gateway's validator `intgd.service` is not restarted until the
  very last step** (§5.6), and only to rebind its RPC — schedule that for a
  low-risk window and confirm it rejoins consensus and signs before
  considering the migration done.
- The OLD explorer rollback volumes on testnet-gateway are preserved until
  2026-06-15 (separate concern) — this migration must not `docker` anything on
  testnet-gateway that touches those.

## 4. Pre-flight checklist

1. Provision `testnet-rpc` (see §2 sizing). Record IP, provider, region.
2. Confirm the canonical `intgd` binary + hash currently on the validators
   (`md5sum /usr/local/bin/intgd` on all 3 testnet hosts — they must match).
3. Capture testnet-gateway's `~/.intgd/config/{config.toml,app.toml}` as the
   template for `testnet-rpc` (the public-facing `[json-rpc]` tuning lives
   here: `gas-cap = 300000000`, `evm-timeout = "15s"` — these MUST carry over;
   see CLAUDE.md).
4. Decide sync strategy: **state-sync** (fast, needs a trusted RPC + trust
   height/hash) vs **full sync from genesis** (slow but zero assumptions).
   State-sync off the existing validators is recommended.
5. Inventory everything that currently hits `testnet.integralayer.com/*`:
   the explorer box (`91.99.208.48` indexer + Caddy `/evm` proxy), the Portal,
   the faucet, the `chain-id-card` site, external integrators, wallets.
   The explorer's indexer `rpcServer` is `https://testnet.integralayer.com/evm`
   — it will follow the DNS automatically (good), but note it for the runbook.
6. Get the Route 53 hosted zone ID for `integralayer.com` and confirm which
   record `testnet.integralayer.com` is (A vs CNAME, current value, TTL).
7. Decide the fate of the **Portal / faucet** (`localhost:3000` on
   testnet-gateway) — see §6. This plan can move it or leave it; recommend
   moving it too so testnet-gateway becomes a pure validator.

## 5. Migration phases

### 5.1 — Provision & base-config `testnet-rpc`
- OS, users, SSH key (`~/.ssh/integra`), firewall (allow 443; allow P2P
  26656; RPC/EVM/REST ports bound to `127.0.0.1` only — Caddy is the only
  public entrypoint), swap, `OOMScoreAdjust` is **not** needed (no validator
  here), unattended-upgrades.
- Install the **identical** `intgd` binary; verify hash against §4.2.

### 5.2 — Bring up the full node (no public traffic yet)
- `intgd init testnet-rpc --chain-id integra-testnet-1`, drop in genesis,
  set `persistent_peers` to the 3 validators, copy the `[json-rpc]` /
  `app.toml` tuning from §4.3.
- `config.toml`: RPC `laddr = tcp://127.0.0.1:26657`; `app.toml`
  `[json-rpc] enable = true`, `address = 127.0.0.1:8545`, `ws-address =
  127.0.0.1:8546`; `[api] enable = true` on `127.0.0.1:1317`.
- State-sync (or genesis-sync) to the chain tip. **Wait until fully caught
  up** (`catching_up: false`) and verify it produces the same block hashes
  as the validators for recent heights.
- Run it as a `systemd` unit (`intgd.service`, bare `ExecStart`, mirrors the
  validator hosts' unit convention).

### 5.3 — Stand up Caddy on `testnet-rpc`
- Port the `testnet.integralayer.com` site block from testnet-gateway's
  `/etc/caddy/Caddyfile` *verbatim* (the §1 routing table), pointing at the
  new local `intgd` ports. Keep the `/evm` `transport http` tuning
  (`max_conns_per_host`, `dial_timeout 3s`, `response_header_timeout 12s`,
  `read_timeout`/`write_timeout 14s`).
- Real Let's Encrypt cert via HTTP-01 (the explorer migration learned that
  TLS-ALPN-01 had a 100% failure rate here — use
  `acme { disable_tlsalpn_challenge }`).
- Test by sending `Host: testnet.integralayer.com` requests directly to the
  box IP *before* any DNS change.

### 5.4 — Parallel-run validation
- With `testnet-rpc` fully synced and Caddy answering on its own IP, run a
  diff harness: same `eth_blockNumber`, `eth_getBlockByNumber`,
  `eth_getLogs`, CometBFT `/status`, Cosmos REST queries against BOTH origins;
  results must match (modulo tip lag).
- Load-test the new box's `/evm` with a representative `eth_getLogs` /
  view-call enumeration workload (the 2026-05-13 storm shape) and confirm it
  stays healthy — this is the whole point.

### 5.5 — DNS cutover
- Lower `testnet.integralayer.com` TTL to ≤60s at least 1 hour ahead.
- Flip the Route 53 record to `testnet-rpc`'s IP.
- Watch: explorer indexer keeps syncing, Portal/faucet still work, external
  integrators unaffected. Keep testnet-gateway's Caddy block live during the
  rollback window (DNS-only rollback = revert the record).

### 5.6 — Decommission the public edge on testnet-gateway *(last, scheduled)*
- Only after a clean soak (recommend ≥48h):
  - Edit testnet-gateway `~/.intgd/config/{config.toml,app.toml}`: RPC
    `laddr → 127.0.0.1`, `[json-rpc] enable = false`, `[api] enable = false`
    — matching signer-1/signer-2. **Back up both files first**
    (`*.bak.pre-rpc-decomm.<ts>`).
  - Restart testnet-gateway `intgd.service` in a low-risk window. **Verify it
    rejoins consensus and signs blocks** before proceeding.
  - Remove the `testnet.integralayer.com` site block from testnet-gateway's
    `/etc/caddy/Caddyfile` (back it up). **Caution:** this removes the last
    2 `max_conns_per_host` directives — coordinate with the next step.
  - **Retire `intgd-throttle.service`** on testnet-gateway: stop+disable it.
    Its reason for existing (protecting the validator from public RPC load)
    is gone. (If kept temporarily, its `EXPECTED_OCCURRENCES` constant must be
    updated to match the new `max_conns_per_host` count — but retiring is
    cleaner. See `~/.claude/.../memory/project_throttle_autoscaler_deployed.md`.)
  - Update CLAUDE.md: testnet-gateway is now a pure validator; the public RPC
    origin is `testnet-rpc`.

## 6. Open decisions for the operator

1. **Portal / faucet (`localhost:3000`).** Move it to `testnet-rpc` (so
   testnet-gateway becomes a pure validator) or leave it on testnet-gateway
   and have `testnet-rpc`'s Caddy proxy `/api/faucet` + `/` back to it? Moving
   is cleaner and finishes the decoupling; leaving it is less work but keeps a
   public service on the validator box.
2. **State-sync vs genesis sync** for the new node (§4.4).
3. **`testnet-rpc` sizing** — CCX33 vs larger (§2).
4. **Keep one warm spare?** Consider a second RPC node behind the same Caddy /
   a load balancer so RPC is no longer a single point of failure. Out of scope
   for v1 but worth deciding now.
5. **Naming / DNS:** keep the single `testnet.integralayer.com`, or also
   introduce a dedicated `rpc.testnet.integralayer.com` for integrators while
   keeping the old name as an alias?

## 7. Rollback

Every phase before §5.6 is rollback-by-DNS: revert the Route 53 record to
testnet-gateway's IP; testnet-gateway's Caddy + validator-served RPC are
untouched until §5.6, so rollback is instant. §5.6 is the only irreversible-ish
step and is gated behind a ≥48h soak; even then, re-enabling RPC on
testnet-gateway + restoring its Caddy block from backup is a documented revert.

## 8. Success criteria

- `testnet.integralayer.com/{rpc,api,evm,ws}` served entirely by `testnet-rpc`;
  a synced, non-validator full node.
- testnet-gateway's `intgd` RPC bound to `127.0.0.1`, EVM RPC disabled —
  identical exposure posture to signer-1/signer-2; validator signing
  uninterrupted across the whole migration.
- `intgd-throttle.service` retired.
- An `eth_getLogs` storm against the public RPC can no longer affect any
  validator's consensus participation.
- CLAUDE.md + the chain-id-card endpoints reflect the new topology.

---

*Cross-references: `docs/findings/2026-05-14-explorer-migration-config-audit.md`
(same migration pattern, Risk #4 named this), `docs/findings/2026-05-13-throttle-autoscaler-spec.md`
(the autoscaler this migration retires), CLAUDE.md "Testnet validators" +
"Testnet block explorer" sections.*
