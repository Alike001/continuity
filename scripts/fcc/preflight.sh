#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_coston2

next_id="$(cast call "$FLARE_TEE_MANAGER" 'nextPublicExtensionId()(uint256)' --rpc-url "$CHAIN_URL")"
printf 'Coston2 manager: %s\n' "$FLARE_TEE_MANAGER"
printf 'Next public extension ID: %s\n' "$next_id"

if [[ -n "${CONTROLLER_ADDRESS:-}" ]]; then
  [[ "$CONTROLLER_ADDRESS" =~ ^0x[0-9a-fA-F]{40}$ ]] || die "CONTROLLER_ADDRESS is malformed"
  [[ "$(cast code "$CONTROLLER_ADDRESS" --rpc-url "$CHAIN_URL")" != "0x" ]] || die "controller has no code"
  actual_manager="$(cast call "$CONTROLLER_ADDRESS" 'teeManager()(address)' --rpc-url "$CHAIN_URL")"
  [[ "${actual_manager,,}" == "${EXPECTED_MANAGER,,}" ]] || die "controller points to $actual_manager"
fi

check_proxy() {
  local label="$1" url="$2"
  [[ "$url" == https://* ]] || die "$label proxy must use stable HTTPS"
  [[ "$url" != *example.invalid* ]] || die "$label proxy is still a placeholder"
  local info
  info="$(curl --fail --silent --show-error --max-time 10 "$url/info")"
  local extension_id tee_id
  extension_id="$(jq -r '.machineData.extensionId // empty' <<<"$info")"
  is_hash "$extension_id" || die "$label proxy omitted a valid extensionId"
  tee_id="$(tee_id_from_info "$url")"
  printf '%s proxy extension ID: %s\n' "$label" "$extension_id"
  printf '%s TEE ID: %s\n' "$label" "$tee_id"

  if [[ -n "${EXTENSION_ID:-}" && "$EXTENSION_ID" != "0" ]]; then
    [[ "$(cast to-dec "$extension_id")" == "$EXTENSION_ID" ]] || die "$label proxy belongs to another extension"
  fi
}

[[ -z "${PRIMARY_PROXY_URL:-}" ]] || check_proxy primary "$PRIMARY_PROXY_URL"
[[ -z "${RECOVERY_PROXY_URL:-}" ]] || check_proxy recovery "$RECOVERY_PROXY_URL"

printf 'Read-only preflight passed. No transaction was sent.\n'
