#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

CONTROLLER_ADDRESS="${CONTROLLER_ADDRESS:-}"
EXTENSION_ID="${EXTENSION_ID:-}"
PRIMARY_PROXY_URL="${PRIMARY_PROXY_URL:-}"
RECOVERY_PROXY_URL="${RECOVERY_PROXY_URL:-}"

is_address "$CONTROLLER_ADDRESS" || die "CONTROLLER_ADDRESS must be a deployed address"
[[ "$CONTROLLER_ADDRESS" != "$ZERO_ADDRESS" ]] || die "CONTROLLER_ADDRESS is still zero"
[[ "$EXTENSION_ID" =~ ^[1-9][0-9]*$ ]] || die "EXTENSION_ID must be a positive integer"
[[ "$PRIMARY_PROXY_URL" == https://* ]] || die "PRIMARY_PROXY_URL must use stable HTTPS"
[[ "$RECOVERY_PROXY_URL" == https://* ]] || die "RECOVERY_PROXY_URL must use stable HTTPS"
require_coston2

primary="$(tee_id_from_info "$PRIMARY_PROXY_URL")"
recovery="$(tee_id_from_info "$RECOVERY_PROXY_URL")"
[[ "${primary,,}" != "${recovery,,}" ]] || die "primary and recovery resolve to the same TEE ID"

for item in "$primary" "$recovery"; do
  actual_extension="$(cast call "$FLARE_TEE_MANAGER" 'getExtensionId(address)(uint256)' "$item" --rpc-url "$CHAIN_URL" | awk '{print $1}')"
  status="$(cast call "$FLARE_TEE_MANAGER" 'getTeeMachineStatus(address)(uint8)' "$item" --rpc-url "$CHAIN_URL" | awk '{print $1}')"
  [[ "$actual_extension" == "$EXTENSION_ID" ]] || die "$item belongs to extension $actual_extension"
  [[ "$status" == "1" ]] || die "$item must be INITIALIZED status 1, got $status"
done

printf 'Primary TEE: %s\n' "$primary"
printf 'Recovery TEE: %s\n' "$recovery"
printf 'Both machines are INITIALIZED for extension %s. No transaction was sent.\n' "$EXTENSION_ID"

require_execute "${1:-}"
executor="$(require_funded_executor)"
owner="$(cast call "$CONTROLLER_ADDRESS" 'owner()(address)' --rpc-url "$CHAIN_URL")"
[[ "${owner,,}" == "${executor,,}" ]] || die "executor $executor is not controller owner $owner"

cast send "$CONTROLLER_ADDRESS" 'configureMachines(address,address)' "$primary" "$recovery" \
  --rpc-url "$CHAIN_URL" --private-key "$DEPLOYMENT_PRIVATE_KEY" --confirmations 1 >/dev/null

active="$(cast call "$CONTROLLER_ADDRESS" 'activeTee()(address)' --rpc-url "$CHAIN_URL")"
standby="$(cast call "$CONTROLLER_ADDRESS" 'recoveryTee()(address)' --rpc-url "$CHAIN_URL")"
[[ "${active,,}" == "${primary,,}" ]] || die "primary controller binding verification failed"
[[ "${standby,,}" == "${recovery,,}" ]] || die "recovery controller binding verification failed"
printf 'Machine pair and genesis expectations verified on Coston2.\n'
