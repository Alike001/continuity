#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

APPLICATION_ID="${APPLICATION_ID:-0x569f078a46d54c8228d4a986d2c421f1504a6456bb83d125982b0bfeb5d90b8c}"
need forge
need jq
is_hash "$APPLICATION_ID" || die "APPLICATION_ID must be a 32-byte 0x hash"
require_coston2

printf 'Controller manager: %s\n' "$FLARE_TEE_MANAGER"
printf 'Application ID: %s\n' "$APPLICATION_ID"
printf 'Dry-run deployment target verified. No transaction was sent.\n'

require_execute "${1:-}"
executor="$(require_funded_executor)"
printf 'Executor: %s\n' "$executor"

result="$(forge create \
  --root "$ROOT" \
  --broadcast \
  --json \
  --rpc-url "$CHAIN_URL" \
  --private-key "$DEPLOYMENT_PRIVATE_KEY" \
  --constructor-args "$FLARE_TEE_MANAGER" "$APPLICATION_ID" \
  contracts/src/ContinuityController.sol:ContinuityController)"

controller="$(jq -r '.deployedTo // empty' <<<"$result")"
is_address "$controller" || die "forge did not report the deployed controller address"
[[ "$(cast code "$controller" --rpc-url "$CHAIN_URL")" != "0x" ]] || die "deployed controller has no code"
actual_manager="$(cast call "$controller" 'teeManager()(address)' --rpc-url "$CHAIN_URL")"
actual_owner="$(cast call "$controller" 'owner()(address)' --rpc-url "$CHAIN_URL")"
[[ "${actual_manager,,}" == "${FLARE_TEE_MANAGER,,}" ]] || die "controller manager verification failed"
[[ "${actual_owner,,}" == "${executor,,}" ]] || die "controller owner verification failed"

printf 'CONTROLLER_ADDRESS=%s\n' "$controller"
printf 'Controller deployment verified on Coston2.\n'
