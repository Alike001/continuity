# Continuity

Continuity is a rollback-safe recovery primitive for stateful applications built with Flare Confidential Compute.

A custom FCC extension can keep private application state in memory, but that state is lost when the extension restarts. Continuity exports encrypted snapshots, anchors their ordered state commitments on Coston2, restores the latest approved state on a replacement extension, and rejects stale or competing histories.

## Current status

Phase 2 scope, Phase 3 design, and the Phase 4 architecture are approved. Recovery Runbook is the selected product surface. The extension-state adapter, controller, and sealed-journal reference extension are implemented locally. No Coston2 recovery claim will be made until the two-TEE acceptance gate passes.

The first release is limited to one reference extension, two registered simulated TEE instances on Coston2, manual recovery, and real rollback and fork rejection checks. The current implementation includes a tested [tee-node extension-state adapter](fcc/tee-node/README.md) pinned to v0.0.24, a tested [Continuity controller](contracts/README.md) that verifies FCC state and enforces snapshot lineage, and a tested [sealed-journal extension](extension/README.md) with encrypted recovery. Simulated TEE proves the FCC integration and state protocol behavior. It does not provide hardware-backed confidentiality.

## Product story

Stateful FCC apps lose private state when an enclave dies. Continuity restores the latest encrypted state and proves it was not rolled back or forked.

See [the approved scope](research/continuity-scope.md), [the architecture](architecture.md), and [the Flare domain research](research/domain-knowledge.md).
