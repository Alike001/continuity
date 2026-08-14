# Continuity

Continuity is a rollback-safe recovery primitive for stateful applications built with Flare Confidential Compute.

A custom FCC extension can keep private application state in memory, but that state is lost when the extension restarts. Continuity exports encrypted snapshots, anchors their ordered state commitments on Coston2, restores the latest approved state on a replacement extension, and rejects stale or competing histories.

## Current status

Phase 2 scope, Phase 3 design, and the Phase 4 architecture are approved. Recovery Runbook is the selected product surface. The extension-state adapter, controller, and sealed-journal reference extension are implemented. The two-TEE Coston2 path is complete through recovery activation. The post-recovery continuation and live adversarial rejection portions of the hard acceptance gate remain open.

The first release is limited to one reference extension, two registered simulated TEE instances on Coston2, manual recovery, and deterministic lineage rejection. The current implementation includes a tested [tee-node extension-state adapter](fcc/tee-node/README.md) pinned to v0.0.24, a tested [Continuity controller](contracts/README.md) that verifies FCC state and enforces snapshot lineage, and a tested [sealed-journal extension](extension/README.md) with encrypted recovery. Simulated TEE proves the FCC integration and state protocol behavior. It does not provide hardware-backed confidentiality.

The guarded live acceptance runner is `scripts/fcc/live-acceptance.sh`. It is resumable and dry-run by default. It stores its manifest and signed FCC responses under ignored `.fcc-work/acceptance/`. A broadcast requires both `--execute` and `CONFIRM_COSTON2_TX=I_UNDERSTAND`, so reviewing or testing the command cannot send a Coston2 transaction accidentally. Run the stages in order: `snapshot-request`, `snapshot-commit`, `recovery-request`, `recovery-arm`, `recovery-activate`, then `continuation-request` and `continuation-commit`. The recovery machine must be paused and then promoted through the existing FCC registration flow between the arm and activation stages. The continuation stages target the newly active recovery TEE and require the same explicit transaction approval.

Live Coston2 evidence includes a successful snapshot commit at epoch 1, an encrypted recovery accepted by the replacement TEE, a signed restore result, a fresh availability proof carrying the restored root, and final activation. Snapshot commit transaction: `0x727de8eef0845f557011e7893438ae428af196922bd2af98bd56a26749f4f839`. Recovery activation transaction: `0xb40a59a408aa31afeab5258679cb74d6c5cb7363da1abfe3690264e205c94e6d`. Stale, competing-fork, and exact-ciphertext rejection are covered by deterministic controller tests. Live Coston2 receipts for the negative cases and epoch 2 continuation are still required before submission. The live deployment uses simulated attestation, which proves protocol integration but does not claim hardware-backed confidentiality.

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
