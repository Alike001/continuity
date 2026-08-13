#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

ROLE="${1:-}"
PHASE="${2:-}"
EXECUTE="${3:-}"
[[ "$ROLE" == "primary" || "$ROLE" == "recovery" ]] || die "usage: register-machine.sh primary|recovery initialize|promote [--execute]"
[[ "$PHASE" == "initialize" || "$PHASE" == "promote" ]] || die "usage: register-machine.sh primary|recovery initialize|promote [--execute]"

case "$ROLE" in
  primary)
    PROXY_URL="${PRIMARY_PROXY_URL:-}"
    HOST_URL="${PRIMARY_PROXY_HOST_URL:-$PROXY_URL}"
    ;;
  recovery)
    PROXY_URL="${RECOVERY_PROXY_URL:-}"
    HOST_URL="${RECOVERY_PROXY_HOST_URL:-$PROXY_URL}"
    ;;
esac

EXTENSION_ID="${EXTENSION_ID:-}"
NORMAL_PROXY_URL="${NORMAL_PROXY_URL:-https://tee-proxy-coston2-1.flare.rocks}"
TEE_VERSION="${TEE_VERSION:-v0.1.0}"
SCAFFOLD_DIR="${SCAFFOLD_DIR:-$ROOT/.fcc-work/fce-extension-scaffold}"
STATE_DIR="$ROOT/.fcc-work/registration"
STATE_FILE="$STATE_DIR/$ROLE.state"

[[ "$EXTENSION_ID" =~ ^[1-9][0-9]*$ ]] || die "EXTENSION_ID must be a positive integer"
[[ "$PROXY_URL" == https://* ]] || die "$ROLE proxy must use stable HTTPS"
[[ "$HOST_URL" == https://* ]] || die "$ROLE registered host must use stable HTTPS"
[[ "$PROXY_URL" != *example.invalid* && "$HOST_URL" != *example.invalid* ]] || die "$ROLE proxy is still a placeholder"
[[ -d "$SCAFFOLD_DIR/.git" ]] || die "run scripts/fcc/bootstrap-scaffold.sh first"
[[ "$(git -C "$SCAFFOLD_DIR" rev-parse HEAD)" == "e3f587949069780084e2ced8a53c9419ed05c250" ]] || die "scaffold is not at the reviewed revision"
[[ -f "$ADDRESSES_FILE" ]] || die "addresses file missing: $ADDRESSES_FILE"
require_coston2

proxy_extension="$(extension_id_from_info "$PROXY_URL")"
[[ "$proxy_extension" == "$EXTENSION_ID" ]] || die "$ROLE proxy reports extension $proxy_extension"
tee_id="$(tee_id_from_info "$PROXY_URL")"
printf '%s TEE ID: %s\n' "$ROLE" "$tee_id"
printf 'Phase: %s\n' "$PHASE"
printf 'Registered URL: %s\n' "$HOST_URL"
printf 'Dry-run registration target verified. No transaction was sent.\n'

require_execute "$EXECUTE"
require_funded_executor >/dev/null
mkdir -p "$STATE_DIR"
cd "$SCAFFOLD_DIR/tools"
export SIMULATED_TEE="${SIMULATED_TEE:-true}"

if [[ "$PHASE" == "initialize" ]]; then
  go run ./cmd/register-tee \
    -a "$ADDRESSES_FILE" -c "$CHAIN_URL" -p "$PROXY_URL" -h "$HOST_URL" \
    -ep "$NORMAL_PROXY_URL" -state "$STATE_FILE" -command r
  status="$(cast call "$FLARE_TEE_MANAGER" 'getTeeMachineStatus(address)(uint8)' "$tee_id" --rpc-url "$CHAIN_URL")"
  [[ "$status" == "1" ]] || die "$ROLE did not reach INITIALIZED status 1, got $status"
  printf '%s is INITIALIZED. Configure both machines before promotion.\n' "$ROLE"
  exit 0
fi

CONTROLLER_ADDRESS="${CONTROLLER_ADDRESS:-}"
is_address "$CONTROLLER_ADDRESS" || die "CONTROLLER_ADDRESS must be set before promotion"
expected="$(cast call "$CONTROLLER_ADDRESS" 'expectedState(address)((uint64,bytes32,bool))' "$tee_id" --rpc-url "$CHAIN_URL")"
[[ "$expected" == *"true"* ]] || die "$ROLE has no armed genesis expectation in the controller"

go run ./cmd/allow-tee-version -a "$ADDRESSES_FILE" -c "$CHAIN_URL" -p "$PROXY_URL" -version "$TEE_VERSION"
go run ./cmd/set-governance -a "$ADDRESSES_FILE" -c "$CHAIN_URL" -p "$PROXY_URL"
go run ./cmd/register-tee \
  -a "$ADDRESSES_FILE" -c "$CHAIN_URL" -p "$PROXY_URL" -h "$HOST_URL" \
  -ep "$NORMAL_PROXY_URL" -state "$STATE_FILE" -command Rap

status="$(cast call "$FLARE_TEE_MANAGER" 'getTeeMachineStatus(address)(uint8)' "$tee_id" --rpc-url "$CHAIN_URL")"
[[ "$status" == "2" ]] || die "$ROLE did not reach PRODUCTION status 2, got $status"
printf '%s is PRODUCTION with an accepted Continuity genesis state.\n' "$ROLE"
