# Continuity controller

`ContinuityController` is the first onchain boundary for the sealed-journal reference extension. It serves as both the FCC instructions sender and the custom extension-state verifier.

## State encoding

The extension returns this exact 96-byte body from `GET /state`:

```solidity
abi.encode(applicationId, uint64(epoch), stateRoot)
```

`stateVersion` is `bytes32("CONTINUITY_STATE_V1")`. The controller rejects another version, another application, a non-canonical epoch word, the wrong length, an unknown TEE, or a root that has not been assigned to that TEE.

## Snapshot admission

`requestSnapshot` checks that both machines still belong to the registered extension, are in `PRODUCTION`, and use a code-hash and platform pair that FlareTeeManager currently supports. It records the exact active TEE, recovery TEE, nonce, next epoch, and parent root before asking the manager to dispatch the instruction. `commitSnapshot` then reconstructs the current FCC `ActionResult.Hash()` and `TEE_ACTION_RESULT` signing domain. It accepts only the matching TEE signature and one child of the current root.

Only one snapshot mutation can be in flight. A second request is rejected before it can race against the same parent. A signed terminal error releases the gate. The owner may abandon a missing result only after the source TEE has left `PRODUCTION`, so cancellation cannot race a machine that may still execute.

The contract keeps the ciphertext digest onchain while the encrypted ciphertext stays offchain. The snapshot payload itself is never stored in contract state.

## Recovery handshake

Recovery uses the Flare machine state model as a proof boundary:

1. The recovery TEE returns a signed result for the exact committed snapshot.
2. The machine owner pauses that TEE.
3. `armRecovery` records the expected restored state while the TEE is `PAUSED`.
4. The manager can return the TEE to `PRODUCTION` only through a fresh availability proof.
5. That proof calls `verifyTeeState` and must contain the armed epoch and root.
6. `activateRecovery` swaps the active and recovery roles only after the manager reports `PRODUCTION`.

The same rule applies at initialization. Both TEEs must be configured while `INITIALIZED`, then each proves the deterministic genesis state while entering `PRODUCTION`.

## Verify locally

```bash
forge fmt --check
forge test -vv
forge lint --severity high
```

The tests use local signing keys only. They cover initialization, signed snapshot commit, replay, failed results, wrong signer, stale state, epoch gaps, competing forks, in-flight request exclusion, safe abandonment, malformed attested state, wrong machine and extension state, unsupported code and platform state, ciphertext substitution, signed recovery, the paused recovery gate, and the fresh production transition.

## Current boundary

These tests prove the deterministic contract rules and Flare ABI compatibility. They do not prove live recovery. The project clears that gate only after two registered simulated TEEs execute the full sequence on Coston2 with real FCC signed results and availability proofs.
