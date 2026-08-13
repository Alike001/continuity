# Phase 2 Directions, Competitive Reset

Date: 2026-08-12

## Screening method

Fourteen raw directions were screened against the published judging criteria, the feasibility filter, current Flare documentation, the current Summer Signal field, and the past-winner bar in `research/domain-knowledge.md`. The first obvious directions were removed from the primary shortlist: another private orderbook, XRP ramp, generic preflight tool, lending dashboard, payment backend, proof checker, and yield directory all collide with stronger current entries.

The five finalists below are different product types. They include a consumer DeFi exit, protocol security infrastructure, an FCC continuity primitive, a private multiplayer game, and an XRPFi testing tool.

Scores use six dimensions worth five points each. The personal-excitement scores are provisional estimates based on the user's earlier preference for Proofline, Roundtrip, and the FCC sponsor gap. The user must correct those scores before selection if they do not fit.

## 1. FAsset Sentry

Product type: permissionless protocol-security keeper. Phase 4 collision preflight invalidated the original originality claim.

Ten-second story: FAssets depend on outside challengers to catch illegal XRP movements. FAsset Sentry watches every agent and submits the FDC proof that protects FXRP backing.

Specific Flare problem and validated pain: FAssets contracts cannot discover XRPL misconduct by themselves. Flare's own liquidation documentation assigns that job to external challengers and rewards valid illegal-payment, double-payment, and negative-balance challenges. A later Phase 4 preflight found that Flare had already published `fasset-bots` and `fasset-bots-deploy`, including a runnable challenger and Coston2 deployment profile. Both repositories are now archived, while the current FAssets repository retains the challenger actor. The earlier claim that no ready-to-run public challenger existed was incorrect.

Flare tools: FAssets agent registry and challenge contracts, FDC balance-decreasing transaction proofs, XRPL transaction streams, FTSO collateral prices, and Coston2 or Songbird for controlled acceptance tests.

Core technical mechanism: an indexer discovers official agent vaults and underlying addresses, an XRPL monitor classifies outgoing payments against open redemption and withdrawal references, a durable proof worker acquires the correct FDC attestation, and an idempotent executor simulates then submits the matching challenge. Every alert carries the XRPL transaction, expected protocol state, proof status, and Coston2 result.

Non-trivial engineering problem: correlating two chains without false liquidation attempts. The service must distinguish a valid but not-yet-confirmed payment from an illegal one, handle finality and FDC delay, detect duplicate references, survive reorgs or RPC failures, and prevent duplicate submissions from spending gas twice.

Feasibility: passes. It needs no custody, regulation, insurance, or permissioned partner. A controlled test agent can create a real invalid XRPL Testnet payment, while read-only simulation protects the executor before any challenge transaction.

Why this is not generic: the product exists because FAssets deliberately delegates a specific safety function to permissionless challengers. It has no useful equivalent on an ordinary EVM-only chain.

Past-winner test: not established. A controlled real challenge would be technically credible, but the core loop already exists in official archived software. A new build would need a separately validated missing layer that materially exceeds updated deployment and operator packaging.

Corrected score after collision preflight: user excitement 4, feasibility 4, wow factor 3, judging alignment 3, demo quality 5, technical depth 2. Total: 21/30.

Hard acceptance gate: prove that a newly created test agent can be monitored and challenged end to end on the current public stack. If the official test deployment cannot support that controlled path, do not substitute a local imitation.

## 2. ExitLane

Product type: consumer DeFi exit and refinancing application.

Ten-second story: entering XRPFi is easy, but leaving a loan still takes several risky steps. ExitLane closes one FXRP-backed Morpho position and starts the XRP redemption in one transaction.

Specific Flare problem and validated pain: Flare reports that more than 85 percent of FXRP is deployed in DeFi and openly says the user experience remains fragmented. A borrower who wants native XRP must repay debt, withdraw FXRP collateral, swap enough collateral to cover the debt, and separately begin an asynchronous FAssets redemption. Ballast proves live Morpho positions and liquidation risk exist, but it keeps positions safe rather than giving users a complete exit.

Flare tools: FXRP, Morpho on Flare, one liquid Flare DEX route, the FAssets `redeemAmount` path, FTSO price checks, and FDC-backed redemption completion.

Core technical mechanism: an atomic adapter flash-borrows the debt asset, repays the Morpho loan, withdraws FXRP collateral, swaps only the required FXRP to repay the flash liquidity under deterministic slippage bounds, and sends the remainder into FAssets redemption. An event indexer then follows the asynchronous XRPL payout or default path to a durable receipt.

Non-trivial engineering problem: combining an atomic EVM unwind with a non-atomic cross-chain payout. The quote must account for debt interest, DEX depth, FTSO deviation, redemption fee, executor fee, partial redemption, and replay-safe receipt reconciliation.

Feasibility: passes with a narrow market pair. It uses self-custodied contracts and existing liquidity. The acceptance path must first confirm one live Morpho FXRP market, a flash-liquidity source for its debt asset, and sufficient DEX depth.

Why this is not generic: it ends in native XRP through FAssets and reconciles the XRPL payment. A normal EVM refinance tool stops after withdrawing an ERC-20.

Past-winner test: yes, if it completes one real small-value position. It has the immediate consumer value of Vinca, the two-network evidence of Bridge.flare, and more coherent failure handling than the older bridge winners. It can also beat Ballast by showing the full close-to-XRP journey rather than a risk forecast.

Score: user excitement 5, feasibility 3, wow factor 5, judging alignment 5, demo quality 5, technical depth 5. Total: 28/30.

Hard acceptance gate: confirm one exact Morpho market, debt flash-liquidity path, DEX route, and FAssets redemption path before scope approval. No simulated liquidity assumptions.

## 3. Continuity

Product type: FCC application-state continuity primitive.

Ten-second story: a stateful FCC app can lose its private state when its enclave restarts. Continuity restores the latest encrypted state and proves it did not roll back or fork.

Specific Flare problem and validated pain: the current official extension scaffold says custom application state is in memory and must be encrypted and exported. `tee-node` supports managed-wallet key backup and restore, but the inspected tooling does not provide a general rollback-safe state protocol for custom extensions. This is the strongest verified sponsor gap, although first-user demand is less proven than the FAssets gaps.

Flare tools: FCC extension scaffold, `tee-node`, current Coston2 `FlareTeeManager`, enclave signing, data-provider relays, and a small onchain state-root registry.

Core technical mechanism: each state mutation creates an encrypted snapshot containing an application identifier, code hash, monotonic epoch, previous snapshot hash, and state root. A quorum-backed export stores the ciphertext offchain, while a contract anchors only the latest accepted epoch and root. Restore is allowed only for an approved code hash and must extend the anchored chain, so stale snapshots and competing forks are rejected.

Non-trivial engineering problem: preserving confidentiality while proving freshness. The system must recover after process or machine loss without exposing plaintext, prevent rollback to an older valid snapshot, detect two enclaves advancing the same epoch, and define what happens when storage succeeds but root anchoring fails, or the reverse.

Feasibility: passes as a narrow primitive plus one reference extension. Simulated TEE is explicitly allowed for Coston2 judging, but the product must label the attestation mode accurately and avoid claiming hardware confidentiality.

Why this is not generic: it fills the boundary between Flare's registered extension identity, signed FCC results, and the missing lifecycle for arbitrary private extension state.

Past-winner test: yes, if a judge can kill one extension, restart it under an approved code hash, restore the exact latest state, and watch a rollback attempt fail on Coston2. That is deeper Flare infrastructure than FireLink and addresses the continuity weakness behind many one-session hackathon apps. It also differentiates from Glassbox, which verifies current attestation rather than preserving private state.

Score: user excitement 5, feasibility 3, wow factor 5, judging alignment 5, demo quality 4, technical depth 5. Total: 27/30.

Hard acceptance gate: register two simulated TEE instances on the current manager and prove snapshot export, approved restore, stale restore rejection, and fork rejection using real signed extension results.

## 4. Fogline

Product type: privacy-native multiplayer strategy game.

Ten-second story: public-chain strategy games reveal every move before the round resolves. Fogline keeps both moves secret, resolves them together in FCC, and settles the signed result on Flare.

Specific Flare problem and validated pain: hidden simultaneous actions are impossible in a normal public mempool without commitments, reveal phases, or a trusted game server. The bounty explicitly calls for private applications where sensitive inputs stay inside a TEE. The current field is crowded with financial orderbooks and auctions, while the scanned entries do not show the same multiplayer game collision.

Flare tools: FCC for encrypted move processing, registered enclave identity and signed results, Flare contracts for escrow and settlement, and Flare secure randomness for map or tie-break seeds where needed.

Core technical mechanism: players encrypt signed moves to the approved extension, the enclave validates turn ownership and nonce, resolves both moves against a deterministic game engine, advances a hash-chained private state, and signs the public outcome and next-state root. The contract verifies the extension result, settles the round, and enforces timeout or refund rules.

Non-trivial engineering problem: a fair private state machine under missing or malicious players. The game must prevent replayed moves, early disclosure, selective aborts, state rollback, duplicate settlement, and an enclave inventing a move for a silent player.

Feasibility: passes with one two-player game loop and no token speculation. It requires only wallets and testnet funds. A full content-heavy game is out of scope.

Why this is not generic: privacy is the game mechanic. Removing FCC changes the rules because one player can see the other's move before resolution.

Past-winner test: yes, if two real wallets submit encrypted moves and the registered extension settles them. It advances beyond Block Roulette's secure random number by proving a multi-turn confidential state machine with adversarial timeout handling, while delivering a more memorable consumer experience than the older bridge interfaces.

Score: user excitement 3, feasibility 4, wow factor 5, judging alignment 4, demo quality 5, technical depth 4. Total: 25/30.

Hard acceptance gate: complete two rounds with real encrypted inputs, reject a replay, and demonstrate a timeout without leaking the unrevealed move.

## 5. RiftLab

Product type: XRPFi oracle and liquidation test infrastructure.

Ten-second story: XRPFi contracts are tested against today's price, then break during tomorrow's shock. RiftLab replays real FTSO rounds against a fork and shows which invariant fails first.

Specific Flare problem and validated pain: Flare reports more than 1,000 liquidations, while the FAssets repository documents liquidation slippage and integration hazards. FTSOv2 exposes round-specific historical feeds, but the inspected official tooling does not provide a product that turns those rounds into repeatable protocol failure scenarios for FXRP integrations.

Flare tools: FTSOv2 current and historical feeds, Flare mainnet or Coston2 fork state, FXRP and FAssets contracts, and protocol adapters for one selected lending or liquidity integration.

Core technical mechanism: a scenario compiler selects real FTSO voting rounds, snapshots relevant onchain positions from a pinned block, replays price and liquidity transitions through an instrumented fork, evaluates deterministic solvency, slippage, and accounting invariants, and emits a reproducible test bundle with block numbers, feed IDs, transactions, and failing traces.

Non-trivial engineering problem: reproducible time-dependent testing. The harness must align feed rounds with block state, isolate oracle movement from liquidity movement, preserve contract call ordering, and distinguish a genuine invariant failure from a fork or adapter artifact.

Feasibility: passes for one adapter and three historical scenarios. It makes no financial or insurance claim and needs no user custody. Hypothetical prices must be clearly separated from historical FTSO observations.

Why this is not generic: the scenarios are built from Flare's own FTSO round history and target FXRP protocol behavior, rather than fuzzing a generic EVM contract with invented prices.

Past-winner test: yes, if one public protocol can reproduce the report from a pinned block in one command. That supplies the production-grade tests and understandable failure evidence missing from Bridge.flare, FireLink, and Vinca, while adding a polished standalone developer tool that the past-winner sample lacks.

Score: user excitement 3, feasibility 4, wow factor 4, judging alignment 4, demo quality 4, technical depth 5. Total: 24/30.

Hard acceptance gate: reproduce one real historical FTSO window against a pinned Flare fork and demonstrate that the same scenario and trace are byte-stable across reruns.

## Recommendation

The Phase 4 collision preflight supersedes the original recommendation. FAsset Sentry is no longer the best competitive choice because official archived software already implements and deploys its core challenger loop. Continuity retains the clearest verified sponsor gap. ExitLane retains the strongest consumer story but needs a live-liquidity preflight.

The first instinct was another private orderbook or cross-chain recovery console. Neither appears in the top three because the current field already contains stronger versions of those obvious answers.
