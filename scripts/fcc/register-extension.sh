#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

CONTROLLER_ADDRESS="${CONTROLLER_ADDRESS:-}"
is_address "$CONTROLLER_ADDRESS" || die "CONTROLLER_ADDRESS must be a deployed address"
[[ "$CONTROLLER_ADDRESS" != "$ZERO_ADDRESS" ]] || die "CONTROLLER_ADDRESS is still zero"
require_coston2
[[ "$(cast code "$CONTROLLER_ADDRESS" --rpc-url "$CHAIN_URL")" != "0x" ]] || die "controller has no code"
actual_manager="$(cast call "$CONTROLLER_ADDRESS" 'teeManager()(address)' --rpc-url "$CHAIN_URL")"
[[ "${actual_manager,,}" == "${FLARE_TEE_MANAGER,,}" ]] || die "controller points to $actual_manager"

next_id="$(cast call "$FLARE_TEE_MANAGER" 'nextPublicExtensionId()(uint256)' --rpc-url "$CHAIN_URL" | awk '{print $1}')"
printf 'Extension registration target: %s\n' "$FLARE_TEE_MANAGER"
printf 'State verifier and instruction sender: %s\n' "$CONTROLLER_ADDRESS"
printf 'Expected extension ID: %s\n' "$next_id"
printf 'Dry-run registration target verified. No transaction was sent.\n'

require_execute "${1:-}"
executor="$(require_funded_executor)"
owner="$(cast call "$CONTROLLER_ADDRESS" 'owner()(address)' --rpc-url "$CHAIN_URL")"
[[ "${owner,,}" == "${executor,,}" ]] || die "executor $executor is not controller owner $owner"

cast send "$FLARE_TEE_MANAGER" 'register(address,address)' \
  "$CONTROLLER_ADDRESS" "$CONTROLLER_ADDRESS" \
  --rpc-url "$CHAIN_URL" --private-key "$DEPLOYMENT_PRIVATE_KEY" --confirmations 1 >/dev/null

sender="$(cast call "$FLARE_TEE_MANAGER" 'getTeeExtensionInstructionsSender(uint256)(address)' "$next_id" --rpc-url "$CHAIN_URL")"
verifier="$(cast call "$FLARE_TEE_MANAGER" 'getTeeExtensionStateVerifier(uint256)(address)' "$next_id" --rpc-url "$CHAIN_URL")"
[[ "${sender,,}" == "${CONTROLLER_ADDRESS,,}" ]] || die "instruction sender verification failed"
[[ "${verifier,,}" == "${CONTROLLER_ADDRESS,,}" ]] || die "state verifier verification failed"

cast send "$CONTROLLER_ADDRESS" 'configureExtension(uint256)' "$next_id" \
  --rpc-url "$CHAIN_URL" --private-key "$DEPLOYMENT_PRIVATE_KEY" --confirmations 1 >/dev/null
configured="$(cast call "$CONTROLLER_ADDRESS" 'extensionId()(uint256)' --rpc-url "$CHAIN_URL" | awk '{print $1}')"
[[ "$configured" == "$next_id" ]] || die "controller extension verification failed"

printf 'EXTENSION_ID=%s\n' "$next_id"
printf 'Extension registration and controller binding verified on Coston2.\n'
