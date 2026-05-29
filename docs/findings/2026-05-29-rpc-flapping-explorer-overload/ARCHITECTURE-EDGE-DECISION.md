# 2026-05-29 — Architecture: edge + origin decoupling (Phase 3L/3M) — DECISION + runbook

> Status: **3N (configs in git + drift CI) DONE.** 3L (Cloudflare) = **NOT done — skip (decided 2026-05-29):
> CF free can't do testnet-only (subdomain zones are Enterprise-only, verified error 1116); the only free
> path is a full apex migration the user declined. See the 2026-05-29 UPDATE at the bottom.**
> 3M (move public origin off the explorer) = **re-scoped — do NOT move it onto the validator gateway.**

## Goal-file intent
- 3L: put a Cloudflare edge in front of `testnet.integralayer.com` (+ explorer hostnames) — hide the
  origin IP, edge WAF + rate-limiting (replaces unwinnable Referer whack-a-mole), authenticated origin pulls.
- 3M: move the public website/TLS origin OFF the explorer box (so a Postgres meltdown can't take the
  public surface down) — the goal suggested "onto the gateway (or a lightweight setup)".

## What changed since the goal was written (verified this run)
1. **The explorer overload is fixed.** The load-48 fire was the missing `idx_token_transfers_txid`
   index (+ 256MB shared_buffers). After the index + 4GB shared_buffers + pgbouncer, load is ~2 and
   the box is healthy. So "explorer meltdown takes down public RPC" is far less likely now.
2. **`/evm` and `/rpc` are already decoupled at the proxy layer** (/evm→signer LB, /rpc,/api,/ws→gateway).
   The remaining coupling is that the **Caddy that serves them is co-resident on the explorer** — if the
   explorer box itself is CPU-pegged, that Caddy can't proxy.

## Why 3M (origin → gateway) is re-scoped, NOT executed
Moving the public website + TLS + the /evm proxy onto the **gateway** puts public, abusable traffic
directly on a **~200M-VP validator**. That is the exact failure mode that already hurt us: signer-1
showed RPC-contention starving consensus (elevated missed blocks). Concentrating the public surface on
a validator **increases** consensus risk — the opposite of this run's goal. The other option in the
goal ("a lightweight setup" = a dedicated tiny proxy box) is out of scope (budget: no new server).

**Conclusion:** Do not move the origin onto the validator. The correct decoupling is the **edge (3L)**:
with Cloudflare in front, the origin IP is hidden and floods are absorbed at the edge, so the origin's
location stops mattering and the explorer-box-as-origin is no longer a single point of public failure.
3L makes 3M unnecessary. If a dedicated proxy box is ever budgeted, revisit moving the origin there
(NOT onto a validator).

## 3L — Cloudflare runbook (needs-credentials: CF account + API token for the zone)
No Cloudflare token/credential exists in this environment (checked: no CF env vars, no `~/.cloudflared`,
no `cloudflared` on any host, no `cloudflare` directive in any Caddyfile). Provide a CF API token scoped
to the `integralayer.com` zone (Zone.DNS edit + SSL edit) to execute. Then:

1. **Add the zone** in Cloudflare (if not already) and point the registrar NS to Cloudflare.
2. **DNS (proxied / orange-cloud)** for the public hostnames → current origin IP (explorer 91.99.208.48):
   `testnet.integralayer.com`, `testnet.explorer.integralayer.com`, `admin.testnet.explorer.integralayer.com`.
   Keep `rpc-internal.testnet.integralayer.com` **DNS-only/grey** (it must stay internal/403; or remove
   it from public DNS entirely). Do NOT proxy raw P2P (26656) — that's gateway, not in DNS.
3. **SSL/TLS mode = Full (strict)**; issue a Cloudflare **Origin CA cert** for the origin and install it
   in Caddy, OR keep Caddy's LE cert and use Full(strict). Enable **Authenticated Origin Pulls** so the
   origin (Caddy) only accepts connections bearing Cloudflare's client cert — then lock the origin
   firewall to Cloudflare IP ranges (so the origin IP, once rotated, is no longer directly reachable).
4. **WAF / rate-limiting at the edge**: a rate-limit rule on `/evm`,`/rpc` (e.g. per-IP burst), and a
   managed ruleset; this replaces the brittle Caddy `@flood_referer` regex whack-a-mole.
5. **Rotate the origin IP** after cutover (or at minimum rely on Authenticated Origin Pulls) so the
   real origin is no longer discoverable.
6. **Caching:** bypass cache for `/evm`,`/rpc`,`/api`,`/ws` (JSON-RPC must not be cached); cache static
   explorer assets.
7. **Verify:** `dig testnet.integralayer.com` returns Cloudflare IPs (origin hidden); `/evm`,`/rpc`,`/ws`
   still 200 through the edge; a flood from a single IP is rate-limited at the edge (origin logs quiet);
   direct-to-origin-IP requests are refused (authenticated origin pulls / firewall).

## 3N — DONE
- Configs checked in: `infra/validators/{gateway,signer-1,signer-2}/{app.toml,config.toml}`.
- Drift check: `infra/validators/check-drift.sh` (tested: exit 0, all match baseline).
- CI: `.github/workflows/validator-config-drift.yml` (PR + daily; needs repo secret
  `INTEGRA_VALIDATOR_SSH_KEY` to do the live SSH diff — skips as a no-op guard until set).

## UPDATE 2026-05-29 — Cloudflare attempted; subdomain-only is NOT possible on Free (verified)
User provided a CF token + AWS/R53 access and chose "testnet subdomain only". Findings from live API testing:
- `integralayer.com` authoritative DNS = **Route 53** (hosted zone `Z07594511H8QLFFDPQYUJ`, 86 records),
  registered at **Amazon Registrar** (so NS can be flipped via `aws route53domains update-domain-nameservers`).
- CF's apex "add site" auto-import captured only **36 of 86** records — activating it (NS cutover) would have
  broken email auth (SES/Mailmodo DKIM, bounce) + ~30 prod/dev apps (CloudFront/ALB/AppRunner) + ALL testnet
  endpoints. (The pending apex zone was removed — inactive, production unaffected, re-addable anytime.)
- **Creating `testnet.integralayer.com` as a CF zone is REJECTED** (`error 1116`: must be root domain).
  Cloudflare subdomain zones ("subdomain setup") are **Enterprise-only**. CNAME/partial setup is Business
  ($200/mo). So on the **Free plan the ONLY way to use CF is the full apex-zone migration** — which the user
  declined (email/prod blast radius).
- **DECISION: skip Cloudflare for now.** The testnet origin is already hardened (Caddy @flood_* incl turfdex,
  per-IP/per-/24 rate limits, bounded RPC, ufw, CrowdSec). CF's only unique free benefit (origin-IP hiding +
  edge flood absorption) is a nice-to-have, not the instability cause. **Revoke the CF token.**

### If full apex migration is ever wanted (opt-in; the only CF path on Free), do it as a maintenance window:
1. In CF, add `integralayer.com`; **replicate ALL 86 R53 records** (script the diff from
   `aws route53 list-resource-record-sets --hosted-zone-id Z07594511H8QLFFDPQYUJ`). Convert the **11 R53
   ALIAS** records (CloudFront/ALB/AppRunner) to **CNAME** (non-apex) / CNAME-flattening (apex). Keep MX +
   all TXT/DKIM/DMARC/SPF + ACM `_*.acm-validations.aws` CNAMEs as **DNS-only (grey)**. Proxy ONLY the web/RPC
   hostnames you want edged (e.g. `testnet`), and even then verify CloudFront/ALB origins don't double-proxy.
2. SSL/TLS = **Full (strict)**; install a CF **Origin CA cert** in the origin Caddy for proxied hostnames
   (free, 15-yr — avoids LE HTTP-01 renewal breaking behind the proxy).
3. Verify EVERY record resolves correctly against CF's NS (`dig @<cf-ns>`), esp. email + apps, BEFORE cutover.
4. Cutover: `aws route53domains update-domain-nameservers --domain-name integralayer.com --nameservers <CF NS>`.
   Rollback = set the NS back to the 4 awsdns servers (R53 zone kept intact = instant revert).
