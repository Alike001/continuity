# tee-node extension-state adapter

Continuity needs the application state reported by a custom FCC extension to reach the existing `TeeState` availability-proof fields. The current Go extension startup path in `tee-node v0.0.24` initializes `ZeroState`, so the application cannot use the live `verifyTeeState(address,bytes32,bytes)` hook without a narrow adapter.

This directory contains a reproducible patch against:

- repository: `https://github.com/flare-foundation/tee-node.git`
- tag: `v0.0.24`
- commit: `adc67a29eb7162f6f1b5dabcbca320009480695e`

## Extension contract

The custom extension must serve `GET /state` on its enclave-local extension port and return one strict JSON object:

```json
{
  "stateVersion": "0x434f4e54494e554954595f53544154455f563100000000000000000000000000",
  "state": "0x1234"
}
```

`stateVersion` must be exactly 32 bytes. `state` is a hex-encoded byte string with a maximum decoded HTTP response size of 1 MiB. The all-zero version is reserved for empty state.

The provider uses a fixed loopback URL, a two-second timeout, no redirects, strict fields, one JSON value, and an exact HTTP 200 response. A read or validation failure makes state collection fail instead of silently attesting empty state.

## Apply and verify

From a clean working directory:

```bash
git clone https://github.com/flare-foundation/tee-node.git
cd tee-node
git checkout adc67a29eb7162f6f1b5dabcbca320009480695e
git apply --unidiff-zero /path/to/continuity/fcc/tee-node/0001-attest-extension-state.patch
go test ./internal/extensionstate ./pkg/server ./internal/attestation ./internal/node
go vet ./internal/extensionstate ./pkg/server ./internal/attestation ./internal/node
```

The PMW startup path keeps `ZeroState`. The adapter is limited to the Go custom-extension path used by the first Continuity reference extension.
