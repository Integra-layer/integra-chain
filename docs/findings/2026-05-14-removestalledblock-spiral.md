# Finding — the `removeStalledBlock` failure spiral (testnet explorer, 2026-05-14)

**Date:** 2026-05-14 (diagnosed + remediated in the post-cutover follow-up session)
**Box:** testnet explorer, `91.99.208.48` (the dedicated box from the 2026-05-14 migration)
**Severity:** high — was pinning Postgres (load 55–70 on a 4-core box) and blocking the
live chain indexer; not user-facing breakage, but actively degrading and non-converging.
**Status:** RESOLVED.

---

## Symptom

The `removeStalledBlock` BullMQ queue had a backlog of ~6,800 jobs in
`bull:removeStalledBlock:wait` that was slowly **growing** (~+25/min), never draining.
The box load average was ~20 at handoff and climbed to **55–70** during investigation.

## Root cause — three compounding defects

1. **The cascade-delete never completes (the core defect).**
   `removeStalledBlock` → `block.revertIfPartial()` → `block.safeDestroy()` →
   `transaction.safeDestroy()` deletes the receipt / logs / trace steps / token
   transfers / contract link — but **not the `transaction_events` row**. The FK
   `transaction_events.transactionId → transactions` is `ON DELETE NO ACTION`
   (siblings like `transaction_receipts`, `transaction_trace_steps`,
   `token_balance_changes` are `CASCADE`). So `block.safeDestroy()`'s final
   `DELETE FROM transactions` always failed with `SequelizeForeignKeyConstraintError`
   (PG 23503) — or hit the 90 s `statement_timeout` mid-cascade and rolled back.
   **0 reverts ever succeeded** (553 `removeStalledBlock` log mentions, 0
   "Removed stalled block" lines). Most likely a regression from the
   TimescaleDB-2.11 hypertable rebuild during the migration (same class as the
   `isReward` column / 4 indexes that the migration audit already caught), or a
   latent design fragility — the app relied on `getEvent().destroy()` succeeding,
   which is not guaranteed under load and races the indexer.

2. **`revertIfPartial`'s `isSyncing` check is wrong.**
   `models/block.js`: `transactions.map(t => t.isSyncing).length > 0` is true for
   *any* block with ≥1 transaction (`.map` preserves array length — it should be
   `.filter`). Would mass-destroy healthy blocks if the cascade ever worked.
   Not caught by tests: `tests/jobs/removeStalledBlock.test.js` *mocks*
   `revertIfPartial`, so neither the `.map` bug nor the real `safeDestroy`
   cascade is exercised.

3. **Operationally pathological.**
   `block.js` `afterCreate()` enqueues one `removeStalledBlock` job per block
   (5-min delay). `workers/lowPriority.js` gives the job its own Worker at
   concurrency 10. `timeout: 30000` in the job opts is a **no-op** in BullMQ 5.
   `revertIfPartial` wraps `safeDestroy` in
   `sequelize.transaction({ deferrable: SET_DEFERRED })`, so all FK checks run at
   `COMMIT` — producing 6–16 min `COMMIT;` transactions that held row locks the
   whole time. 10 of these ran concurrently and **blocked the live indexer's
   `UPDATE transactions SET state` queries**; `backend-api` then piled up behind
   the locks (114 active queries), giving 144 active Postgres backends thrashing
   `LWLock:BufferMapping` on a 4-core box.

The feedback loop: doomed `safeDestroy` holds locks → indexer can't finish blocks
→ more blocks have `syncing` transactions past the 5-min mark → more
`removeStalledBlock` jobs hit the revert path → more lock-holding doomed
transactions. Net: `:wait` grows unbounded, load never settles.

## Evidence trail

- `bull:removeStalledBlock:failed` job hashes → `failedReason` was
  `SequelizeForeignKeyConstraintError` / `the database system is in recovery mode`
  (the latter being an older batch from a Postgres restart during the migration).
- `pg_stat_activity`: every transaction older than 2 min was
  `application_name=low-priority-worker` running the exact `safeDestroy` query
  sequence (`DELETE FROM transaction_receipts`, `SELECT FROM transaction_logs`,
  `SELECT FROM token_transfers`, long `COMMIT;`).
- `pg_blocking_pids`: ~12 backends (incl. the indexer's
  `UPDATE transactions SET state`) blocked behind those low-priority-worker PIDs.

## Remediation (applied 2026-05-14)

1. **Stopped the bleeding (reversible):** paused the `removeStalledBlock` BullMQ
   queue (`Queue.pause()`), then restarted the `worker-low` container to kill the
   10 in-flight doomed transactions (Postgres rolled them back cleanly — no
   partial deletes). Verified: lock contention cleared, `backend-api` drained
   54→2 active queries, load 55→~20 within ~4 min — confirming `removeStalledBlock`
   was the contention driver and `backend-api` was a victim, not an independent
   problem.
2. **Permanent fix (image rebuild):** `models/block.js` — disabled the per-block
   `enqueue('removeStalledBlock', ...)` in `afterCreate()` and bumped
   `STALLED_BLOCK_REMOVAL_DELAY` (5 min → 6 h) as a backstop. Rebuilt
   `integra-explorer-backend:latest`, recreated backend + 3 workers. Confirmed the
   enqueue stopped (`paused + delayed` total held flat — zero new jobs entering).
3. **Drained** the `removeStalledBlock` queue via BullMQ `drain()` + `clean()`
   (8,872 jobs — all confirmed no-op-or-doomed, not genuine work). Queue left
   **paused** as a defensive measure.
4. Backups: `models/block.js.bak.pre-rsb-disable.<ts>` on the explorer box.

## Still open — for a future maintenance window (operator decision)

The `removeStalledBlock` feature is **disabled, not fixed.** To safely re-enable it:
- Fix the `transaction_events` FK / make `transaction.safeDestroy` actually delete
  the `transaction_events` row (and verify the FK `ON DELETE` behaviour against
  upstream — likely a migration regression to repair like `isReward` was).
- Fix `revertIfPartial`'s `.map` → `.filter` bug.
- Give the cascade a real timeout / batching and bound concurrency.
- Add an integration test that exercises the *real* `revertIfPartial` +
  `safeDestroy` (the current unit test mocks them).
- `revertIfPartial` has two other callers (`models/workspace.js`,
  `lib/firebase.js`) — the `.map` bug affects them too.

Only after that: un-comment the `block.js` enqueue and `Queue.resume()` the queue.

## Related

- `docs/findings/2026-05-14-explorer-migration-config-audit.md` — the migration
  whose hypertable rebuild is the suspected origin of the FK regression.
- `docs/plans/2026-rpc-origin-migration.md` — the next structural decoupling.
