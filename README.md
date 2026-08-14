# Continuity

Continuity is a rollback-safe recovery primitive for stateful applications built with Flare Confidential Compute.

A custom FCC extension can keep private application state in memory, but that state is lost when the extension restarts. Continuity exports encrypted snapshots, anchors their ordered state commitments on Coston2, restores the latest approved state on a replacement extension, and rejects stale or competing histories.

## Current status

Phase 2 scope, Phase 3 design, and the Phase 4 architecture are approved. Recovery Runbook is the selected product surface. The extension-state adapter, controller, and sealed-journal reference extension are implemented. The final two-TEE Coston2 path is complete through recovery activation and a successful epoch-2 continuation.

The first release is limited to one reference extension, two registered simulated TEE instances on Coston2, manual recovery, and deterministic lineage rejection. The current implementation includes a tested [tee-node extension-state adapter](fcc/tee-node/README.md) pinned to v0.0.24, a tested [Continuity controller](contracts/README.md) that verifies FCC state and enforces snapshot lineage, and a tested [sealed-journal extension](extension/README.md) with encrypted recovery. Simulated TEE proves the FCC integration and state protocol behavior. It does not provide hardware-backed confidentiality.

The guarded live acceptance runner is `scripts/fcc/live-acceptance.sh`. It is resumable and dry-run by default. It stores its manifest and signed FCC responses under ignored `.fcc-work/acceptance/`. A broadcast requires both `--execute` and `CONFIRM_COSTON2_TX=I_UNDERSTAND`, so reviewing or testing the command cannot send a Coston2 transaction accidentally. Run the stages in order: `snapshot-request`, `snapshot-commit`, `recovery-request`, `recovery-arm`, `recovery-activate`, then `continuation-request` and `continuation-commit`. The recovery machine must be paused and then promoted through the existing FCC registration flow between the arm and activation stages. The continuation stages target the newly active recovery TEE and require the same explicit transaction approval.

For a non-mutating failure proof, the runner also has `snapshot-error-request` and `snapshot-error-commit`. These send a deliberately non-decryptable, non-empty payload, collect the real FCC-signed error from the active proxy, and clear the pending action with `failSnapshot`. Set `ERROR_PROXY_URL` to the proxy for the currently active TEE, and use a separate ignored acceptance state directory. This path proves terminal FCC error handling without changing the committed state root. It does not claim a stale or competing successful result.

Live Coston2 evidence on the final controller includes a successful epoch-1 snapshot commit, encrypted recovery, signed restore result, manager pause, recovery arm, fresh availability proof, activation, and an epoch-2 continuation commit. Final controller: `0x50D2871f491EC42F2a4fB5198308Dcf9A5c532fC`. Snapshot commit: `0xe911f8884151c62d2dc8f2a0dacc3057191a32c6bc60b6d21962f1e401f59a51`. Recovery activation: `0xfd10d1e98cadd4448264a682503142eb1fe87ce31741d7d583a72821570d12e6`. Continuation commit: `0x2b829d7688596bfe7fcfb2cf38355afe421834a29433e47253bc8cb19c5432c3`. Live replay protection reverted at `0x148a99f6de94d37a6de0609a1fc0f51cf6b60d7da937d08ac205956b3e44ca6f`, and exact-ciphertext substitution reverted at `0x8fc86bb1ed736b4c90993fac2a9e1cb6ea15c879a052b6e8576e5786f7f3d83b`. Stale and competing-fork live receipts remain pending because they require a valid FCC signature over deliberately stale or competing state. The live deployment uses simulated attestation, which proves protocol integration but does not claim hardware-backed confidentiality.

## Product story

Stateful FCC apps lose private state when an enclave dies. Continuity restores the latest encrypted state and proves it was not rolled back or forked.

See [the approved scope](research/continuity-scope.md), [the architecture](architecture.md), [the Flare domain research](research/domain-knowledge.md), and [the judging-criteria map](judging-criteria.md).

The sanitized public acceptance record is [evidence/coston2-acceptance.json](evidence/coston2-acceptance.json). It includes the final controller state, transaction hashes, signed-result hashes, live negative receipts, and explicit unproven claims. Private keys, FCC credentials, and encrypted payloads are excluded.

## Recovery Runbook frontend

The presentable operator surface lives in `frontend/` and is intentionally a single recovery runbook rather than a generic dashboard. It opens a recorded Coston2 acceptance path, exposes full public identifiers through the evidence inspector, and labels deterministic stale-restore and competing-branch checks as local controller-test evidence until live receipts exist. The browser is read-only and never sends a wallet transaction.

```bash
cd frontend
npm install
npm run dev
```

For a local backend boundary, start the read-only Coston2 state service in a second terminal before opening the runbook:

```bash
node scripts/state-service.mjs
```

It polls the deployed controller and FlareTeeManager, writes the last verified response to ignored `.fcc-work/indexer-state.json`, indexes controller lineage events to `.fcc-work/indexer-events.json`, and serves `/health`, `/api/state`, and `/api/events` on `http://127.0.0.1:8787`. Coston2 limits log queries to 30 blocks, so the indexer scans in safe chunks. Set `CONTINUITY_FROM_BLOCK` to the deployment or first-event block when operating beyond the default bounded lookback. The browser uses this cached service for live verification and reports how many controller events were indexed. It falls back to a direct public RPC read if the service is unavailable. This service is intentionally read-only. It does not submit wallet transactions or claim to be the finished recovery orchestrator.

The opaque snapshot store is a separate local service. It verifies Ethereum Keccak-256 against the digest supplied by a signed FCC result, writes ciphertext atomically under that digest, and never decrypts or signs payloads:

```bash
cd extension
CONTINUITY_SNAPSHOT_DIR=../.fcc-work/snapshots go run ./cmd/snapshot-store.go
```

It exposes `PUT` and `GET /snapshots/<0x-digest>` on `127.0.0.1:8790`. The current service is intentionally local and unauthenticated. Permissioned operator submission and production authentication are still unimplemented.
