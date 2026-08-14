# Reproducible Coston2 deployment

This directory is a thin overlay on Flare's official `fce-extension-scaffold` at commit `e3f587949069780084e2ced8a53c9419ed05c250`. It builds the Continuity journal together with `tee-node v0.0.24` at commit `adc67a29eb7162f6f1b5dabcbca320009480695e` and the reviewed extension-state patch.

The image derives its `teeId` from tee-node's fresh in-memory key and passes only that public address into the journal. No TEE private key is exported or configured.

## Safety boundary

Run the read-only preflight first:

```bash
source .env.coston2
./scripts/fcc/preflight.sh
```

For a fresh local setup, copy `fcc/deploy/.env.example` into an ignored file such as `.fcc-work/coston2.env`, fill the public deployment values and local secret variables, then source that file before running the scripts. The example intentionally contains empty secret fields, never real credentials.

The preflight pins chain ID 114 and the live manager at `0x1a9C4A0f9D76c0b1D91d22E24E573a9b377618aE`. It rejects the old manager, missing contract code, a controller bound to another manager, placeholder proxy URLs, and non-HTTPS public proxies. It sends no transaction.

Build the exact Go image with:

```bash
./scripts/fcc/build-image.sh
```

`SOURCE_DATE_EPOCH` defaults to the current Continuity commit time. The build pins the base image, tee-node revision, module graph, target architecture, path trimming, and build ID. The image label permits the Coston2 launch configuration, including `APPLICATION_ID`, but never permits a TEE identity or private key override.

Build the exact official proxy release used by the reviewed scaffold:

```bash
./scripts/fcc/build-proxy.sh
```

The proxy image pins tee-proxy `v0.0.18` and both base image digests. Create `fcc/deploy/proxy-config/primary.toml` and `recovery.toml` from `proxy-config.example.toml`. Those ignored files contain the FCC indexer credentials. Set distinct ignored proxy keys, then start the two isolated stacks:

```bash
./scripts/fcc/start-machines.sh
```

The primary and recovery machines use separate TEE identities, proxy keys, Redis queues, proxy configurations, and local ports. Give each local proxy its own stable named HTTPS tunnel. A quick tunnel is rejected because its hostname changes after restart.

`EXTENSION_ID` remains the decimal public registry ID in the local environment. `start-machines.sh` converts it to the padded 32-byte hex form required by tee-node.

## Required registration order

Continuity can't use the scaffold's one-shot `pre-build.sh` because that sample registers a zero state verifier. Register the deployed `ContinuityController` as both the state verifier and instruction sender:

```text
FlareTeeManager.register(controller, controller)
ContinuityController.configureExtension(extensionId)
```

Start two copies of the same image behind two stable named HTTPS proxy URLs. Use separate Redis, proxy configuration, and generated registration state for each machine.

The first machine-registration pass must stop after upstream `register-tee -command r`. Both machines are then `INITIALIZED`. Call `configureMachines(primaryTee, recoveryTee)` while both remain in that state. Only then run the upstream version, governance, and `register-tee -command Rap` availability and promotion path for each machine.

This staged order lets the controller assign the deterministic genesis root before Flare calls `verifyTeeState` during each promotion. Running the scaffold's default `rRap` before `configureMachines` makes the genesis availability proof fail.

Generated configuration, proxy database credentials, registration state, tunnel tokens, and executor keys belong in ignored local files. Never place them in this directory.

## Guarded transaction sequence

Every state-changing script runs a read-only target check first and refuses to broadcast unless `--execute` is present:

```bash
./scripts/fcc/deploy-controller.sh
./scripts/fcc/deploy-controller.sh --execute

./scripts/fcc/register-extension.sh
./scripts/fcc/register-extension.sh --execute

./scripts/fcc/register-machine.sh primary initialize
./scripts/fcc/register-machine.sh primary initialize --execute
./scripts/fcc/register-machine.sh recovery initialize --execute

./scripts/fcc/configure-machines.sh
./scripts/fcc/configure-machines.sh --execute

./scripts/fcc/register-machine.sh primary promote --execute
./scripts/fcc/register-machine.sh recovery promote --execute
```

The two initialize calls must finish before `configure-machines.sh`. Both promotions must happen afterward. Each script re-reads the expected manager, chain, extension, machine identity, status, controller owner, or accepted state as appropriate.
