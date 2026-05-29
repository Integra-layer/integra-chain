# 2026-05-29 — Testnet EVM RPC flapping (Ethernal explorer overloading the single gateway intgd)

## Summary
`https://testnet.integralayer.com/evm` flapped DOWN with "Unexpected end of JSON input". Root cause:
the Ethernal explorer was the dominant load on the **single** gateway intgd. Fixed same day —
config/infra only, no consensus impact, **no intgd restart**, fully reversible.

## Symptom
- Status monitor: `DOWN` then `FLAPPING` on Testnet EVM RPC, message `Unexpected end of JSON input`.
- That string = a Caddy **504 Gateway Timeout** returns an empty body → the monitor's `JSON.parse()`
  fails on empty input.

## Investigation (primary evidence)
- **intgd healthy**: `active`, synced (`catching_up=false`), local `:8545` answered `eth_blockNumber`
  in ~2ms. **Caddy healthy**: custom xcaddy v2.11.3 with rate_limit/crowdsec modules, config valid.
- **Access log was ~99.8% `504` on `/evm`**: 29,959 of 29,970 recent `/evm` requests came from
  `91.99.208.48` (the explorer), all timing out at exactly the Caddy `response_header_timeout`.
- **504 durations ≥24s** (upstream-slow), zero dial failures → intgd saturated, not down.
- **Explorer DB `workspaces.rpcServer = http://46.225.231.81:8545`** → the indexer hit the gateway
  **directly on :8545, bypassing every Caddy control** (rate_limit, crowdsec, logging, autoblocker).
  The explorer-UI `/evm` also proxied to the gateway (`https://46.225.231.81`, `response_header_timeout 12s`).
- The single gateway intgd serves public users + indexer + UI; the explorer is **whitelisted** from
  all rate limits.
- The indexer was **tip-following** (lag ≈ 0); the storms were a **retry-amplification spiral**
  (504 → block fails → re-queue → retry → more load).

## Root cause
One gateway intgd shared by everyone; the explorer (the heaviest consumer) hammered it directly and
was exempt from rate limits. Amplified by the gateway Caddy `/evm` `response_header_timeout` having
drifted to 25s (holding stuck slots 6× longer than the 2026-05-14 design).

## Fix (all reversible; no intgd restart)
| # | Action | Rollback |
|---|---|---|
| A1 | Repoint **indexer**: explorer DB `UPDATE workspaces SET "rpcServer"='https://rpc-internal.testnet.integralayer.com/evm' WHERE id=1;` then `docker restart integra-explorer-worker-{low,medium,high}` | set `rpcServer` back to `http://46.225.231.81:8545`, restart workers |
| A2 | Repoint **explorer-UI `/evm`** → signer LB (`45.77.139.208:8645 159.223.206.94:8645`, `least_conn`); removed the 12s timeout-stacking | restore `/etc/caddy/Caddyfile.bak.*.pre-rpc-flap-fix` on 91.99.208.48 + `systemctl reload caddy` |
| A3 | Gateway Caddy `/evm` `response_header_timeout` **25s → 18s** (read/write left 25s) | restore `/etc/caddy/Caddyfile.bak.*.pre-rpc-flap-fix` on 46.225.231.81 + reload |
| A4 | `systemctl disable intgd-throttle.service` (boot-safe; tighten-on-saturation backfires) | `systemctl enable intgd-throttle.service` (only after redesigning its logic) |

## Verification (all CONFIRMED from primaries)
- Explorer `rpcServer` = the LB; indexer lag **0**, no connection errors in worker logs.
- Gateway: **0** established connections from the explorer on `:8545`; **0** 504s in the last 15 min.
- Public `/evm`, explorer-UI `/evm`, the signer LB, and both signers `:8645` → all **200**.
- intgd never restarted (gateway PID `2647652` unchanged); no validator touched.

## Corrected topology discovered (the docs were stale — reconciled in CLAUDE.md)
- **All three Integra nodes are validators** (including the gateway, Integra-Helsinki). 4 bonded
  validators total + an external `integra-validator` (~50M, quorum cushion) + a jailed
  `integralayer-local`. Total VP ≈ 651M; ⅔ ≈ 434M.
- **Signers DO serve EVM RPC** on `:8645` (own Caddy → local intgd, json-rpc `enable=true`) — the old
  CLAUDE.md said `enable=false`.
- The `rpc-internal` signer LB already existed (INT-636/655/657/659) but the indexer + UI had never
  been repointed onto it until this fix.

## Remaining hardening (NOT done — needs deliberate validator restarts / external setup)
- **Signer RPC hardening**: drop `debug,txpool` from the signer `api`; set a finite
  `max-open-connections`. Requires restarting each signer's intgd **one at a time** (each misses
  ~tens of blocks and briefly trips the monitor; quorum stays > ⅔ with ~69% online). **NEVER restart
  two ~200M validators at once.**
- **Gateway** intgd `max-open-connections` 0 → bounded (also needs a gateway restart).
- **Cloudflare edge** (hide the origin — highest-leverage missing control), per-method cost
  weighting, JSON-RPC batch-size cap.
