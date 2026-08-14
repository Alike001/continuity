# Continuity

Continuity is a recovery primitive for stateful applications running in Flare Confidential Compute. It keeps an encrypted application journal recoverable across FCC machines and makes every accepted transition verifiable on Flare Coston2.

## The problem

An FCC extension loses private in-memory state when its machine restarts or becomes unavailable. A normal backup cannot prove that the restored state is the latest accepted state, or prevent an old snapshot from being replayed.

## What Continuity does

1. The active FCC machine encrypts a journal snapshot.
2. Flare Confidential Compute returns a signed result.
3. The Continuity controller verifies the result, epoch, parent root, nonce, and ciphertext digest on Coston2.
4. A registered standby machine restores the accepted ciphertext after a fresh availability proof.
5. The recovered journal continues at the next epoch.

The controller rejects replayed results, stale snapshots, competing branches, malformed state, and ciphertext substitution. The browser is an evidence-first, read-only runbook. It never contains an executor key or sends a wallet transaction.

## Verified Coston2 proof

The final controller is `0x50D2871f491EC42F2a4fB5198308Dcf9A5c532fC` on Flare Coston2, extension `66240`.

- Epoch-3 snapshot request: `0x51213a6785f361dcdc204b6f4a4950580a0f8949bdf7a9c74870564cebb8df9d`
- Epoch-3 guarded commit: `0x9fd3d2567d4346fea0591b774316625c65212815161160f48d75905c83de141a`
- Replay protection receipt: `0x148a99f6de94d37a6de0609a1fc0f51cf6b60d7da937d08ac205956b3e44ca6f`
- Ciphertext substitution receipt: `0x8fc86bb1ed736b4c90993fac2a9e1cb6ea15c879a052b6e8576e5786f7f3d83b`

The sanitized evidence bundle is [evidence/coston2-acceptance.json](evidence/coston2-acceptance.json). It contains public identifiers, transaction hashes, signed-result hashes, and explicit limitations. It does not contain keys, FCC credentials, or encrypted payloads.

FCC machines in this release are simulated TEEs. This proves Flare protocol integration and signed state transitions, not hardware-backed confidentiality.

## Run the frontend

```bash
cd frontend
npm install
npm run dev
```

The runbook reads a local state service when available and falls back to direct Coston2 RPC reads. The fallback is visible in the UI and is not treated as indexed-service health.

## Run the read-only state service

From the repository root:

```bash
node scripts/state-service.mjs
```

The service polls the deployed controller and FlareTeeManager, indexes controller events in safe 30-block chunks, and serves:

- `GET http://127.0.0.1:8787/health`
- `GET http://127.0.0.1:8787/api/state`
- `GET http://127.0.0.1:8787/api/events`

Set `CONTINUITY_RPC_URL` and `CONTINUITY_FROM_BLOCK` when using a different Coston2 RPC or scan start. The service is read-only and does not submit transactions.

## Run the local snapshot store

```bash
cd extension
CONTINUITY_SNAPSHOT_DIR=../.fcc-work/snapshots go run ./cmd/snapshot-store.go
```

The store accepts opaque ciphertext at `PUT /snapshots/<0x-digest>`, verifies Ethereum Keccak-256 against the path, writes atomically, and never decrypts or signs payloads.

## Stable FCC proxy exposure

Quick Cloudflare tunnels are for development only because their hostnames change on restart. If you do not own a domain, use one free ngrok assigned dev domain with the local path router:

```bash
node scripts/fcc/proxy-router.mjs
```

In a second terminal, start ngrok with your private authtoken and assigned dev domain. Keep the token out of Git and chat. Route the two FCC registrations to the same HTTPS hostname with different prefixes:

```text
PRIMARY_PROXY_URL=https://YOUR_ASSIGNED_DOMAIN.ngrok-free.app/primary
RECOVERY_PROXY_URL=https://YOUR_ASSIGNED_DOMAIN.ngrok-free.app/recovery
```

The router maps `/primary` to local port `6674` and `/recovery` to local port `6684`. Keep the router, both FCC machines, and ngrok running while the registered URLs are in use. Re-run the read-only machine preflight before changing any onchain registration.

## Test

```bash
forge test
cd extension && go test ./...
cd .. && node --test scripts/state-service.test.mjs scripts/orchestrator.test.mjs
cd frontend && npm run build && npm run test:smoke
```

The browser smoke test expects a Vite preview at `http://127.0.0.1:4173`. Start it with:

```bash
cd frontend
npm run preview -- --host 127.0.0.1 --port 4173
```

The FCC acceptance runner is dry-run by default. A Coston2 broadcast requires `--execute`, explicit confirmation, and an ignored local environment file. Never place private keys or FCC credentials in frontend code, Git, or chat.

## Architecture

Forward path: operator -> frontend or local service -> FCC proxy -> opaque snapshot store -> guarded orchestrator -> Continuity controller on Coston2.

Reverse path: controller event -> state service -> cached verified state and event history -> frontend.

Onchain state contains ownership, registered machines, epochs, roots, action gates, and accepted transitions. Encrypted payloads remain offchain because the chain needs their digest and signed proof, not plaintext custody.

## Limitations

- Simulated FCC machines are used for the hackathon proof.
- Stable named FCC proxy endpoints and a hosted frontend are not included in this repository state.
- The guarded submission service is designed for a localhost operator, not an internet-facing deployment.
- Stale-epoch and competing-fork rejection are covered by deterministic controller tests. Separate live receipts are not claimed.

## Links

- [Controller contract details](contracts/README.md)
- [Sealed journal extension](extension/README.md)
- [Flare tee-node adapter](fcc/tee-node/README.md)
- [Architecture](architecture.md)
- [Judging criteria mapping](judging-criteria.md)
- [Coston2 evidence](evidence/coston2-acceptance.json)
- [GitHub repository](https://github.com/Alike001/continuity)
