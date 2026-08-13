# Continuity

Continuity is a rollback-safe recovery primitive for stateful applications built with Flare Confidential Compute.

A custom FCC extension can keep private application state in memory, but that state is lost when the extension restarts. Continuity exports encrypted snapshots, anchors their ordered state commitments on Coston2, restores the latest approved state on a replacement extension, and rejects stale or competing histories.

## Current status

Phase 2 scope and Phase 3 design are approved. Recovery Runbook is the selected product surface. Phase 4 has not started, and no implementation claim has been made yet.

The first release is limited to one reference extension, two registered simulated TEE instances on Coston2, manual recovery, and real rollback and fork rejection checks. Simulated TEE proves the FCC integration and state protocol behavior. It does not provide hardware-backed confidentiality.

## Product story

Stateful FCC apps lose private state when an enclave dies. Continuity restores the latest encrypted state and proves it was not rolled back or forked.

See [the approved scope](research/continuity-scope.md) and [the Flare domain research](research/domain-knowledge.md).
