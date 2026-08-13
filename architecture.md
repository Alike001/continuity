# Continuity architecture

Status: approved for Phase 4 implementation on 2026-08-13.

## Product invariant

A journal write is durable only after its encrypted snapshot is stored and its exact lineage is accepted on Coston2. The interface must keep earlier states visible as pending or failed. It must never acknowledge an unanchored TEE mutation as durable.

## Current FCC boundary

The live Coston2 `FlareTeeManager` delegates custom extension-state validation to:

```solidity
function verifyTeeState(
    address teeId,
    bytes32 stateVersion,
    bytes calldata state
) external view returns (bool isValid);
```

The current official extension scaffold registers the zero address as its state verifier. The pinned `tee-node v0.0.24` also initializes extension machines with `ZeroState`, so custom extension state does not reach availability attestations through the reference path. FCC supplies machine identity, code and platform registration, instruction routing, signed results, availability proofs, and the verifier hook. Continuity supplies arbitrary application-state export, encrypted transport, restoration, and deterministic lineage control.

## Components

### Sealed-journal extension

The reference application keeps a small private journal with:

- application ID
- state schema version
- monotonic epoch
- previous state root
- current state root
- ordered journal entries

Every mutation receives the current onchain anchor as an expected parent. A local state that no longer matches that anchor cannot accept another mutation. It may only re-export its current unanchored snapshot for recovery of an interrupted commit.

### Extension-state provider

The extension exposes ABI-encoded state through `GET /state`. A narrow adapter in the current `tee-node` extension startup path reads this state and supplies it to the FCC attestation payload instead of `ZeroState`.

The adapter rejects malformed JSON, non-hex state, incorrect byte lengths, unknown fields, oversized responses, non-success HTTP responses, timeouts, and a zero schema version paired with non-empty state.

### Continuity controller and state verifier

One Coston2 contract serves as the extension's instruction sender, lineage registry, signed-result consumer, and `ITeeExtensionStateVerifier` implementation.

It stores:

- extension ID
- application ID and state schema version
- active and recovery TEE IDs
- expected attested root for each approved TEE
- latest epoch, state root, parent root, and ciphertext digest
- operation nonces and consumed result IDs
- recovery and rejection receipts

It reads `FlareTeeManager` as the authority for machine extension ID, status, public key, code hash, platform, and currently supported code and platform combinations.

### Snapshot store and orchestrator

The orchestrator polls the target proxy for signed FCC results. It verifies the result before storage, writes ciphertext under its content digest, then submits the signed result to the controller. Commit submission is permissionless, so a compromised or unavailable operator can be replaced.

The database stores polling jobs, storage metadata, indexed contract events, and transaction receipts. Contract events can rebuild every derived record. The encrypted snapshot blob is the only irreducible offchain data and must be downloadable for operator backup.

### Recovery Runbook

The application shell is the landing experience. It reads indexed state and presents one primary recovery action. Every stage comes from extension, storage, proxy result, transaction receipt, availability proof, or contract state. Timers never manufacture progress.

## Forward paths

### Journal mutation

1. The frontend reads the active TEE public key and current anchor from indexed contract state.
2. The user encrypts the private entry to the active TEE identity key.
3. The wallet calls the Continuity controller with the ciphertext and operation nonce.
4. The controller validates the target and current lineage, then calls `FlareTeeManager.sendInstructions` with that explicit TEE ID.
5. Flare data providers relay the instruction through the TEE proxy and `tee-node` to the extension.
6. The extension decrypts the entry, checks the expected parent, mutates the journal, and encrypts a complete snapshot to the recovery TEE public key.
7. The TEE signs the result containing the application ID, operation nonce, epoch, parent root, state root, recovery TEE ID, ciphertext digest, and ciphertext.
8. The orchestrator verifies the signed result, stores the ciphertext by digest, and submits the result to the controller.
9. The controller verifies FCC identity and lineage, consumes the result once, and advances the anchor.

### Recovery

1. The operator selects the latest stored snapshot already committed by the controller.
2. The controller sends an explicit restore instruction to the registered recovery TEE. The message is built from the current onchain anchor.
3. The recovery extension decrypts the snapshot, validates its application ID, schema, epoch, parent, state root, and ciphertext digest, then imports it.
4. The recovery TEE returns a signed restore result.
5. The controller records the expected recovered root for that TEE.
6. A fresh FCC availability proof carries the recovery TEE's ABI-encoded application state through `verifyTeeState`.
7. The controller activates the recovery TEE only in the same successful transaction path that confirms the availability proof.
8. The next journal mutation targets the replacement TEE and must extend the recovered root.

## Reverse path

1. Controller and manager transactions emit instruction, anchor, restore, activation, and rejection events.
2. The indexer consumes logs after confirmation and deduplicates by chain ID, transaction hash, and log index.
3. The database stores derived operation and receipt records.
4. The backend exposes those records to the Recovery Runbook.
5. The frontend reconciles pending wallet submissions with indexed receipts and never treats submission alone as success.

## State placement

| State | Placement | Reason |
| --- | --- | --- |
| Journal plaintext | Active TEE | Sensitive application data |
| Encrypted snapshot | Offchain content-addressed storage | Durable payload is too large for routine onchain storage |
| Epoch, roots, ciphertext digest | Coston2 controller | Rollback and fork control must be trustless |
| Active and recovery TEE IDs | Coston2 controller and FlareTeeManager | Target selection and machine identity affect trust |
| Code hash, platform, status, public key | FlareTeeManager | FCC is authoritative for registered machines |
| Operation and result replay state | Coston2 controller | Duplicate execution must be rejected consistently |
| Jobs, cached reads, receipts | Database | Fast reads and restartable processing |
| Wallet and service secrets | Ignored server environment | Secrets must never enter browser code or Git history |

## Lineage rules

A new snapshot is accepted only when:

```text
epoch = latestEpoch + 1
previousRoot = latestRoot
sourceTEE = activeTEE
recoveryTEE = configuredRecoveryTEE
snapshotDigest = keccak256(ciphertext)
operationNonce = nextOperationNonce
```

The controller also requires a valid signed FCC result from the exact target machine, the configured extension ID, a production machine, and a currently supported code hash and platform.

An exact already-committed result is idempotent. An older epoch is stale. A future epoch is an epoch gap. A second state root extending a parent that has already advanced is a competing fork.

## Trust boundaries

- Coston2 contracts are authoritative for accepted lineage and replay state.
- FlareTeeManager is authoritative for FCC machine identity, extension membership, status, code hash, and platform.
- The backend may schedule, store, and submit. It cannot invent accepted state or signatures.
- The frontend is untrusted. Contracts derive the current anchor and verify targets independently.
- The snapshot store is untrusted for integrity. Ciphertext digest and decrypted state-root checks detect substitution. Storage can still censor or lose a blob.
- Simulated TEE proves the current FCC integration and state protocol. It does not prove hardware confidentiality.

## Failure behavior

| Failure | Required behavior |
| --- | --- |
| Wallet or controller transaction fails | Keep the operation pending or failed. Retry with the same nonce. |
| RPC unavailable | Show cached data as stale and retain retryable work. Do not infer completion. |
| Storage fails after TEE mutation | Do not anchor or acknowledge the write. Block later mutations and retry export. |
| TEE dies before result | Keep the last committed anchor. The attempted write was never durable. |
| TEE dies after mutation but before storage | Recover only the last committed anchor. Clearly mark the interrupted write as uncommitted. |
| Database crashes after an onchain transaction | Replay confirmed events from the last indexed block. |
| Event arrives twice | Ignore the duplicate through the log identity constraint. |
| Result is submitted twice | Return the recorded outcome or reject it without changing state. |
| Snapshot is modified | Reject its digest or decrypted state-root mismatch. |
| Stale snapshot is restored | Return and record a deterministic stale-snapshot rejection. |
| Two branches extend one parent | Accept the first valid commit and reject the second as a fork. |
| Frontend is modified | Contract-side target, nonce, manager, signature, and lineage checks remain binding. |
| Backend is compromised | It can delay or withhold work but cannot decrypt, forge, reorder, or overwrite accepted lineage. |
| Both TEEs are unavailable | Report recovery unavailable until an approved machine returns. |
| Availability proof is pending | Show restored but not active. Do not route new writes to the replacement. |

## Hard acceptance gate

Before the product claims recovery works, two simulated TEEs registered through the current Coston2 manager must complete this sequence:

1. Commit a real encrypted journal snapshot from the primary TEE.
2. Restore it on the second TEE through an explicit FCC instruction.
3. Confirm the recovered application state through a fresh availability proof and the custom state verifier.
4. Activate the replacement and commit one new journal entry.
5. Reject one older valid snapshot.
6. Reject one competing branch extending an already-consumed parent.

Local tests, generated calldata, or unsigned extension output cannot satisfy this gate.
