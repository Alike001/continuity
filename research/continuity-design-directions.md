# Continuity Phase 3 Design Directions

Date: 2026-08-13
Status: Awaiting user selection

## Judging priority

Design and UX are not standalone judging dimensions for Flare Summer Signal. Product usefulness, Flare integration quality, technical execution, evidence of new work, clarity, and future potential are scored. The interface therefore needs to be clean, presentable, and shaped around the real recovery job, while implementation depth stays ahead of decorative polish.

Continuity should not start with a separate marketing site. The application itself should explain the product in one sentence and expose the real recovery action in the first viewport. A small later landing surface may reuse the same product shell after the recovery path is proven.

## Product needs before visual research

### Primary user

The primary user is a developer or operator running a stateful Flare Confidential Compute extension. A hackathon judge is the secondary reader and must understand the problem and proof within 30 seconds.

### One primary action

Recover the latest anchored encrypted state from a stopped primary extension onto an approved recovery extension, then verify that the application can continue without accepting an older snapshot or a competing branch.

### What belongs in the first viewport

- One sentence explaining the state-loss problem and recovery promise.
- `Coston2` and `simulated TEE` environment labels.
- Primary and recovery extension identities and current states.
- Latest anchored epoch and shortened state root.
- One dominant `Recover latest state` action.
- Current outcome in plain language: ready, snapshot pending, anchor pending, primary stopped, restoring, restored, stale rejected, fork rejected, or failed.
- Direct access to the real signed result and Coston2 transaction.

Ciphertext metadata, full state roots, code measurement, raw signed payload, registry calldata, event logs, retry history, and storage diagnostics can wait for deeper inspection.

### Product shape and data depth

This is a single-focus operational task with a short state history. It is not a broad monitoring dashboard. The interface needs one dominant recovery path, one visible state lineage, and a detailed evidence surface. KPI cards, chart grids, broad navigation, and a general analytics home are unjustified.

## Reference findings

- [Restate's durable execution UI](https://docs.restate.dev/quickstart) shows execution steps, retries, persisted progress, and recovery after a service restart. Borrow the clear journal of what survived and what resumed.
- [Inngest Traces](https://www.inngest.com/docs/platform/monitor/traces) uses a resizable two-panel view with an execution timeline and contextual input, output, error, and metadata details. Borrow the connection between one selected state transition and its raw evidence.
- [Stripe Workbench](https://docs.stripe.com/workbench/overview) keeps developer inspection and safe retry controls near the object being debugged. Borrow the inspector model and evidence proximity.
- [Subtrace on Product Hunt](https://www.producthunt.com/products/subtrace) packages full payloads, status, headers, logs, and latency in a Chrome DevTools-like interface. Borrow dense technical legibility without turning the first screen into a metrics dashboard.
- [GitKraken Commit Graph](https://www.gitkraken.com/features/commit-graph) makes ordered history, branches, merges, and selected-commit detail readable in one view. Borrow the visual grammar for the accepted state chain and rejected fork.
- [Synergy Codes' data-lineage concept on Dribbble](https://dribbble.com/shots/17720351-Data-lineage-interactive-ER-diagram-tool) uses a relationship canvas with detail-on-demand. Borrow the focus and inspection behavior, while avoiding its soft purple card treatment.
- [Terminal on Godly](https://godly.website/website/terminal-922) demonstrates restrained large type, minimal chrome, and an unusual editorial composition in a different product domain. Borrow its confidence and whitespace, not its fashion content.

## Direction A: Recovery Runbook

### Paradigm and hierarchy

Single-focus runbook. The first screen is organized around the current recovery decision and one action. A compact identity strip sits above a vertical runbook that expands only the active stage. The evidence receipt appears beside or beneath the active stage, depending on viewport width.

The hierarchy is:

1. Product promise and environment truth.
2. Primary stopped, recovery ready, latest anchored epoch.
3. `Recover latest state`.
4. Real recovery stages and their evidence.
5. Adversarial checks for stale state and a competing fork.

The runbook uses square stage bars separated by rules. It does not use numbered circles, checklist rows, or staged timer animation.

### Named style mix

Monochrome docs-style Swiss terminal with institutional protocol restraint.

### Structured direction

Create a monochrome docs-style Swiss terminal single-focus runbook for an FCC state-recovery primitive. Use a neutral grotesk interface face, compact monospace evidence, a strong sentence-sized product statement, one centered recovery action, square runbook stages, black and cold-white surfaces, Flare magenta only for protocol identity, amber for a real pending state, red for rejected history, green only for verified recovery, and short state-driven transitions. Avoid the generic compliance dashboard, serif-plus-sans cream card layouts, status-pill collections, checklist rows, numbered-circle timelines, gradient-purple SaaS heroes, rounded cards with soft shadows, glowing backgrounds, stock icon grids, AI illustrations, fake terminal typing, and fake progress animation.

### Reference principles

- Restate: show what persisted and where execution resumed.
- Stripe Workbench: keep retry or recovery action beside inspectable evidence.
- Terminal on Godly: use typography and whitespace to create confidence without a separate SaaS hero.
- Inngest: expose input, output, error, and metadata after a stage is selected.

### Why it can beat the visual bar

It makes Continuity's core action as immediate as Block Roulette's spin while exposing substantially stronger proof. It is more productized than FireLink and the older bridges, and clearer in the first viewport than a broad developer dashboard. Against current entries, it matches Glassbox's single testable action and Offset's job-specific console without copying either layout.

### Main risk

A runbook can look staged. Every visual transition must come from real extension, storage, signed-result, or contract state, and the interface must allow the judge to inspect those sources.

## Direction B: State Lineage

### Paradigm and hierarchy

Spatial lineage canvas. The accepted epoch chain occupies the center of the first screen. The primary extension sits at the beginning of the visible history, the recovery extension continues the accepted line, and stale or competing restores appear as rejected side branches. Selecting a node opens a narrow evidence inspector.

The hierarchy is:

1. Accepted state chain and latest anchored root.
2. Primary and recovery extension relationship.
3. Restore action attached to the latest accepted node.
4. Rejected rollback or fork shown in its exact historical position.
5. Raw node and contract evidence in the inspector.

### Named style mix

Space-tech minimal protocol line-art with monochrome data-grid precision.

### Structured direction

Create a space-tech minimal protocol line-art spatial canvas for rollback-safe FCC state continuity. Use a compact neo-grotesk face, monospace epochs and roots, a full-width state lineage with thin orthogonal connectors, a docked node inspector, deep graphite and cold-gray surfaces, white accepted history, Flare magenta for the active FCC identity, red for rejected branches, and restrained pan, focus, and branch-rejection motion. Avoid sci-fi HUD clutter, neon cyberpunk, glowing nodes, particle effects, force-directed graph movement, generic dashboard cards, gradient backgrounds, rounded soft panels, decorative network globes, numbered timelines, and any branch animation that is not tied to a real result.

### Reference principles

- GitKraken Commit Graph: make ordered history and branching readable without hiding identifiers.
- Temporal's event-history model: treat the ordered history as the source for reconstruction and show branching only where it matters.
- Synergy Codes data lineage: allow relationship-first browsing with details on selection.
- Inngest Traces: keep the selected transition linked to precise evidence.

### Why it can beat the visual bar

It turns rollback and fork prevention into a memorable visual proof instead of a textual claim. None of the inspected past winners used their infrastructure state as the central visual language. It would look more considered than the older bridge frontends and more product-specific than Ignite's conventional lending shell.

### Main risk

The graph can consume implementation time and obscure the one recovery action. It must remain a short, deterministic chain rather than become a general canvas or topology explorer.

## Direction C: Snapshot Bench

### Paradigm and hierarchy

Split-view snapshot master-detail. A narrow left rail lists anchored epochs and rejected restore attempts. The main pane compares the selected snapshot with the current onchain anchor and contains the recovery control. A bottom evidence drawer holds signed results, calldata, events, and storage metadata.

The hierarchy is:

1. Latest anchored snapshot and its compatibility with the recovery extension.
2. One selected snapshot comparison.
3. `Recover this latest snapshot` and its real outcome.
4. State history and rejected attempts in the rail.
5. Raw evidence in the drawer.

This is a developer bench, not an incident-monitoring console. It differs from FAsset Sentry's archived forensic design because the snapshot is the navigation object, state compatibility is the dominant content, and recovery is an explicit write action.

### Named style mix

Editorial brutalist proof-bench with Swiss utility and raw-terminal accents.

### Structured direction

Create an editorial brutalist proof-bench split-view for an FCC encrypted-snapshot recovery tool. Use one neutral grotesk family with compact monospace machine data, a narrow epoch rail, a dominant snapshot compatibility pane, a hard-edged evidence drawer, white and near-black surfaces, cobalt for selection, Flare magenta for verified FCC identity, red for stale or forked state, and immediate selection and disclosure transitions. Avoid the generic compliance dashboard, cream card grids, serif headings, status pills, checklist rows, numbered-circle timelines, rounded cards with soft shadows, purple gradients, glassmorphism, glowing backgrounds, AI illustrations, decorative charts, and a passive read-only dashboard feel.

### Reference principles

- Inngest Traces: connect one selected transition to a contextual detail panel.
- Subtrace: keep payload and machine evidence dense but readable.
- Stripe Workbench: place the operator action beside the exact object and its event history.
- GitKraken: preserve selected-history context while inspecting one record deeply.

### Why it can beat the visual bar

It looks like a usable developer product rather than a hackathon walkthrough. The selected snapshot, compatibility decision, recovery action, and signed evidence can all fit above the fold. It would be more finished than FireLink and the older bridge repositories, while matching the operational clarity of current products such as Offset.

### Main risk

This is the least visually surprising option and can drift toward a standard admin tool. Strong typography, a dominant compatibility comparison, and strict removal of KPI cards are required.

## Recommendation

Direction A, Recovery Runbook, is the best fit for the approved scope. It gives the judge one obvious action, keeps design investment lean, and can still expose the real technical evidence. Direction B has the highest visual wow factor but adds the most frontend complexity. Direction C is the strongest long-term operator interface but has the greatest risk of feeling familiar.
