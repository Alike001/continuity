# Sealed-journal reference extension

This Go extension is Continuity's stateful FCC reference application. It keeps a small private journal in enclave memory, exports a complete encrypted snapshot for a registered recovery TEE, and restores only a canonical snapshot whose digest, application ID, epoch, and state root all match.

## FCC routes

- `GET /state` returns the 96-byte ABI encoding of `applicationId`, `epoch`, and `stateRoot`. The patched tee-node adapter puts these exact values into FCC availability attestations.
- `POST /action` accepts the current tee-node `Action` envelope. `SNAPSHOT` decrypts one private journal entry through tee-node, extends the journal, and encrypts the full snapshot to the recovery TEE public key supplied by `FlareTeeManager`. `RESTORE` decrypts and validates the snapshot schema, application, epoch, root, digest, counters, and ordered entries before changing memory.

The extension emits the flat ABI tuples consumed by `ContinuityController`. It checks the FCC instruction ID and target TEE ID before processing either command.

## Safety bounds

- one mutation at a time
- 4 KiB maximum plaintext entry
- 64 journal entries
- 256 KiB maximum encoded snapshot
- 1 MiB maximum action and tee-node decrypt response
- strict JSON fields, one JSON value, loopback-only decryption, no redirects, and fixed timeouts

The journal is deliberately small. These limits keep signed FCC result payloads bounded and make the first recovery product easy to reason about.

## Configuration

The process needs:

```text
APPLICATION_ID=0x...  # exact 32-byte application hash
TEE_ID=0x...          # exact nonzero 20-byte FCC machine address
EXTENSION_PORT=8080   # optional
SIGN_PORT=9090        # optional tee-node signing and decryption port
```

No private key enters the extension configuration. tee-node owns the TEE identity key and exposes decryption only on enclave-local loopback.

## Local verification

With Go 1.25.1:

```bash
go test ./...
go test -race ./...
go vet ./...
go build ./cmd/extension
```

The tests generate two fresh secp256k1 identities and complete a real ECIES snapshot and restore round trip. They also cover replay, stale state, competing roots, wrong recipients, ciphertext tampering, malformed requests, size limits, timeouts, and exact Go to Solidity ABI parity.

This local suite proves the cryptographic and state-machine boundary. The product claim still depends on the separate two-TEE Coston2 acceptance run described in the repository architecture.
