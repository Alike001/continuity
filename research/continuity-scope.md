# Continuity Approved Scope

Date: 2026-08-13
Status: Phase 2 approved

## Target user

The first user is a developer building a stateful custom extension with Flare Confidential Compute. The developer needs private application state to survive the loss or restart of one extension instance without accepting an older valid snapshot or a competing state history.

## Ten-second story

Stateful FCC apps lose private state when an enclave dies. Continuity restores the latest encrypted state and proves it was not rolled back or forked.

## Smallest complete release

Continuity will prove one recovery path on Coston2:

1. A primary registered simulated TEE runs a private sealed-journal reference extension.
2. Each accepted mutation advances a monotonic epoch and produces an encrypted snapshot linked to the previous state commitment.
3. A small Coston2 registry anchors the latest accepted epoch, state root, previous root, application identity, and approved extension identity or code measurement required by the current FCC verification path.
4. A second registered simulated TEE restores the latest encrypted snapshot after the primary instance stops.
5. The recovered extension continues from the exact restored state.
6. A restore from an older valid snapshot is rejected.
7. A competing branch from an already advanced epoch is rejected.

The reference extension stays deliberately simple. It stores private append-only journal entries and exposes only enough public information to prove that the recovered state commitment and entry count match. The continuity protocol, verification path, and failure handling carry the technical depth.

## Included

- Current Coston2 FCC deployment only.
- Two registered simulated TEE instances.
- One encrypted snapshot envelope for one reference extension.
- One minimal onchain state-root and epoch registry.
- Manual snapshot export and recovery.
- Approved recovery under the required current FCC identity or code-measurement check.
- Stale snapshot rejection.
- Competing-fork rejection.
- Honest pending, failed, stale, forked, restored, and continued states.
- A small operator interface that makes the recovery proof understandable within 30 seconds.

## Excluded

- Flare Mainnet and other networks.
- Hardware TEE confidentiality claims.
- Automatic failover or leader election.
- Multi-application hosting or tenancy.
- SDKs in several languages.
- General backup storage marketplace or storage quorum product.
- Extension code upgrades, migrations, or governance.
- Broad monitoring, analytics, alerting, or billing.
- A consumer application whose feature set hides the continuity primitive.

## Hard technical acceptance gate

Before building around the assumption, register two simulated TEE instances against the current Coston2 `FlareTeeManager` and verify that the current FCC result and identity path can support:

1. Real snapshot export from the primary extension.
2. Restore by an approved recovery extension.
3. Rejection of an older valid snapshot.
4. Rejection of a competing state branch.
5. Signed extension results that a Coston2 contract can verify or bind to the current FCC trust path.

If the current contracts or extension result format cannot support that path without inventing an unverifiable identity claim, stop and rescope before implementation.

## Competitive bar

The submission clears the bar only if a judge can stop the primary extension, restore the exact latest state on a second registered extension, continue the application, and watch both rollback and fork attempts fail through real Coston2 transactions or verified FCC results. A local-only snapshot demonstration does not clear the bar.
