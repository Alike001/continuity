#!/usr/bin/env bash

EXPECTED_MANAGER="0x1a9C4A0f9D76c0b1D91d22E24E573a9b377618aE"
EXPECTED_CHAIN_ID="114"
ZERO_ADDRESS="0x0000000000000000000000000000000000000000"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHAIN_URL="${CHAIN_URL:-https://coston2-api.flare.network/ext/C/rpc}"
FLARE_TEE_MANAGER="${FLARE_TEE_MANAGER:-$EXPECTED_MANAGER}"
ADDRESSES_FILE="${ADDRESSES_FILE:-$ROOT/fcc/deploy/coston2-addresses.json}"

die() { printf 'fcc: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 is required"; }

is_address() {
  [[ "$1" =~ ^0x[0-9a-fA-F]{40}$ ]]
}

is_hash() {
  [[ "$1" =~ ^0x[0-9a-fA-F]{64}$ ]]
}

require_coston2() {
  need cast
  [[ "$FLARE_TEE_MANAGER" == "$EXPECTED_MANAGER" ]] || die "refusing stale FlareTeeManager $FLARE_TEE_MANAGER"
  local chain_id manager_code
  chain_id="$(cast chain-id --rpc-url "$CHAIN_URL")"
  [[ "$chain_id" == "$EXPECTED_CHAIN_ID" ]] || die "expected Coston2 chain ID 114, got $chain_id"
  manager_code="$(cast code "$FLARE_TEE_MANAGER" --rpc-url "$CHAIN_URL")"
  [[ "$manager_code" != "0x" ]] || die "live FlareTeeManager has no code"
}

require_execute() {
  [[ "${1:-}" == "--execute" ]] || die "dry run only. Review the targets, then pass --execute to send transactions"
  [[ -n "${DEPLOYMENT_PRIVATE_KEY:-}" ]] || die "DEPLOYMENT_PRIVATE_KEY must be exported from an ignored local environment file"
}

executor_address() {
  local address
  address="$(cast wallet address --private-key "$DEPLOYMENT_PRIVATE_KEY")"
  is_address "$address" || die "could not derive executor address"
  printf '%s\n' "$address"
}

require_funded_executor() {
  local executor balance
  executor="$(executor_address)"
  balance="$(cast balance "$executor" --rpc-url "$CHAIN_URL")"
  [[ "$balance" =~ ^[0-9]+$ ]] || die "could not read executor balance"
  balance="$(printf '%s' "$balance" | sed 's/^0*//')"
  [[ -n "$balance" ]] || die "executor $executor has no Coston2 balance"
  printf '%s\n' "$executor"
}

tee_id_from_info() {
  local url="$1" info x y digest
  need curl
  need jq
  info="$(curl --fail --silent --show-error --max-time 10 "${url%/}/info")"
  x="$(jq -r '.teeInfo.publicKey.x // empty' <<<"$info")"
  y="$(jq -r '.teeInfo.publicKey.y // empty' <<<"$info")"
  is_hash "$x" || die "$url returned a malformed TEE public key x coordinate"
  is_hash "$y" || die "$url returned a malformed TEE public key y coordinate"
  digest="$(cast keccak "0x${x#0x}${y#0x}")"
  printf '0x%s\n' "${digest: -40}"
}

extension_id_from_info() {
  local url="$1" value
  need curl
  need jq
  value="$(curl --fail --silent --show-error --max-time 10 "${url%/}/info" | jq -r '.machineData.extensionId // empty')"
  is_hash "$value" || die "$url omitted a valid extensionId"
  cast to-dec "$value"
}
