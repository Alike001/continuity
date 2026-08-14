# Continuity

Continuity is a rollback-safe recovery primitive for stateful applications built with Flare Confidential Compute.

A custom FCC extension can keep private application state in memory, but that state is lost when the extension restarts. Continuity exports encrypted snapshots, anchors their ordered state commitments on Coston2, restores the latest approved state on a replacement extension, and rejects stale or competing histories.

## Current status

Phase 2 scope, Phase 3 design, and the Phase 4 architecture are approved. Recovery Runbook is the selected product surface. The extension-state adapter, controller, and sealed-journal reference extension are implemented. The final two-TEE Coston2 path is complete through recovery activation and a successful epoch-2 continuation.

The first release is limited to one reference extension, two registered simulated TEE instances on Coston2, manual recovery, and deterministic lineage rejection. The current implementation includes a tested [tee-node extension-state adapter](fcc/tee-node/README.md) pinned to v0.0.24, a tested [Continuity controller](contracts/README.md) that verifies FCC state and enforces snapshot lineage, and a tested [sealed-journal extension](extension/README.md) with encrypted recovery. Simulated TEE proves the FCC integration and state protocol behavior. It does not provide hardware-backed confidentiality.

The guarded live acceptance runner is `scripts/fcc/live-acceptance.sh`. It is resumable and dry-run by default. It stores its manifest and signed FCC responses under ignored `.fcc-work/acceptance/`. A broadcast requires both `--execute` and `CONFIRM_COSTON2_TX=I_UNDERSTAND`, so reviewing or testing the command cannot send a Coston2 transaction accidentally. Run the stages in order: `snapshot-request`, `snapshot-commit`, `recovery-request`, `recovery-arm`, `recovery-activate`, then `continuation-request` and `continuation-commit`. The recovery machine must be paused and then promoted through the existing FCC registration flow between the arm and activation stages. The continuation stages target the newly active recovery TEE and require the same explicit transaction approval.

Live Coston2 evidence on the final controller includes a successful epoch-1 snapshot commit, encrypted recovery, signed restore result, manager pause, recovery arm, fresh availability proof, activation, and an epoch-2 continuation commit. Final controller: `0x50D2871f491EC42F2a4fB5198308Dcf9A5c532fC`. Snapshot commit: `0xe911f8884151c62d2dc8f2a0dacc3057191a32c6bc60b6d21962f1e401f59a51`. Recovery activation: `0xfd10d1e98cadd4448264a682503142eb1fe87ce31741d7d583a72821570d12e6`. Continuation commit: `0x2b829d7688596bfe7fcfb2cf38355afe421834a29433e47253bc8cb19c5432c3`. Stale, competing-fork, and exact-ciphertext rejection remain covered by deterministic controller tests while live rejection receipts are still pending. The live deployment uses simulated attestation, which proves protocol integration but does not claim hardware-backed confidentiality.

## Product story

Stateful FCC apps lose private state when an enclave dies. Continuity restores the latest encrypted state and proves it was not rolled back or forked.

See [the approved scope](research/continuity-scope.md), [the architecture](architecture.md), and [the Flare domain research](research/domain-knowledge.md).

## Recovery Runbook frontend

The presentable operator surface lives in `frontend/` and is intentionally a single recovery runbook rather than a generic dashboard. It opens a recorded Coston2 acceptance path, exposes full public identifiers through the evidence inspector, and labels deterministic stale-restore and competing-branch checks as local controller-test evidence until live receipts exist. The browser is read-only and never sends a wallet transaction.

```bash
cd frontend
npm install
npm run dev
```
