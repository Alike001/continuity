#!/usr/bin/env bash
set -euo pipefail

# Resumable Coston2 acceptance runner. Dry-run is the default. A broadcast
# requires both --execute and CONFIRM_COSTON2_TX=I_UNDERSTAND.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

COMMAND="${1:-status}"
shift || true
STATE_DIR="${ACCEPTANCE_STATE_DIR:-$ROOT/.fcc-work/acceptance}"
MANIFEST="$STATE_DIR/manifest.json"
SNAPSHOT_DIR="$STATE_DIR/snapshots"
SNAPSHOT_RESULT="$STATE_DIR/snapshot.result.json"
CONTROLLER_ADDRESS="${CONTROLLER_ADDRESS:-}"
EXTENSION_ID="${EXTENSION_ID:-}"
PRIMARY_PROXY_URL="${PRIMARY_PROXY_URL:-}"
RECOVERY_PROXY_URL="${RECOVERY_PROXY_URL:-}"
ACTION_TIMEOUT="${ACTION_TIMEOUT:-900}"
POLL_SECONDS="${POLL_SECONDS:-10}"
ENTRY_TEXT="${ENTRY_TEXT:-continuity-live-acceptance-1}"
INSTRUCTION_FEE_WEI="${INSTRUCTION_FEE_WEI:-1000000}"

need jq
need curl
need cast
mkdir -p "$SNAPSHOT_DIR"

die() { printf 'acceptance: %s\n' "$*" >&2; exit 1; }
is_address "$CONTROLLER_ADDRESS" || die "CONTROLLER_ADDRESS must be set to the deployed controller"
[[ "$EXTENSION_ID" =~ ^[1-9][0-9]*$ ]] || die "EXTENSION_ID must be the decimal extension ID"
[[ "$PRIMARY_PROXY_URL" == https://* ]] || die "PRIMARY_PROXY_URL must be stable HTTPS"
[[ "$RECOVERY_PROXY_URL" == https://* ]] || die "RECOVERY_PROXY_URL must be stable HTTPS"
require_coston2

load_manifest() {
	if [[ ! -f "$MANIFEST" ]]; then
		printf '{"version":1,"chainId":114,"controller":"%s","steps":{}}\n' "${CONTROLLER_ADDRESS,,}" > "$MANIFEST"
	fi
	local actual
	actual="$(jq -r '.controller // empty' "$MANIFEST")"
	[[ "${actual,,}" == "${CONTROLLER_ADDRESS,,}" ]] || die "manifest belongs to controller $actual"
}

record() {
	local key="$1" value="$2"
	local tmp="$MANIFEST.tmp"
	jq --arg key "$key" --arg value "$value" '.steps[$key]=$value' "$MANIFEST" > "$tmp"
	mv "$tmp" "$MANIFEST"
}

step() { jq -r --arg key "$1" '.steps[$key] // empty' "$MANIFEST"; }

require_execute() {
	[[ "${1:-}" == "--execute" ]] || die "dry run only; pass --execute after reviewing the printed target"
	[[ "${CONFIRM_COSTON2_TX:-}" == "I_UNDERSTAND" ]] || die "set CONFIRM_COSTON2_TX=I_UNDERSTAND only after approving Coston2 transactions"
	[[ -n "${DEPLOYMENT_PRIVATE_KEY:-}" ]] || die "DEPLOYMENT_PRIVATE_KEY must come from an ignored environment file"
}

owner_check() {
	local executor owner
	executor="$(executor_address)"
	owner="$(cast call "$CONTROLLER_ADDRESS" 'owner()(address)' --rpc-url "$CHAIN_URL")"
	[[ "${executor,,}" == "${owner,,}" ]] || die "executor $executor is not controller owner $owner"
}

send() {
	local tx
	tx="$(cast send "$@" --rpc-url "$CHAIN_URL" --private-key "$DEPLOYMENT_PRIVATE_KEY" --confirmations 1 --json)"
	jq -r '.transactionHash // .hash // empty' <<<"$tx"
}

wait_result() {
	local proxy="$1" action="$2" started response status
	started="$(date +%s)"
	while :; do
		response="$(curl --silent --show-error --fail --max-time 20 "$proxy/action/result/$action" 2>/dev/null || true)"
		if [[ -n "$response" ]] && jq -e '.result and (.signature | type == "string")' >/dev/null 2>&1 <<<"$response"; then
			status="$(jq -r '.result.status' <<<"$response")"
			case "$status" in
				0|1) printf '%s\n' "$response"; return 0 ;;
			esac
		fi
		(( "$(date +%s)" - started >= ACTION_TIMEOUT )) && die "timed out waiting for signed result $action"
		sleep "$POLL_SECONDS"
	done
}

action_from_receipt() {
	local tx="$1" event="$2" topic
	topic="$(cast keccak "$event")"
	cast receipt "$tx" --rpc-url "$CHAIN_URL" --json | jq -r --arg topic "$topic" '.logs[] | select((.topics[0] // "") == $topic) | .topics[1]' | head -1
}

public_key_from_tuple() {
	local tuple="$1" line
	local -a coordinates=()
	# cast 1.7.1 emits each bytes32 tuple member on its own line. Validate
	# every complete line, preserving the value exactly and rejecting extras.
	while IFS= read -r line; do
		[[ -z "$line" ]] && continue
		is_hash "$line" || return 1
		coordinates+=("$line")
	done <<< "$tuple"
	[[ "${#coordinates[@]}" -eq 2 ]] || return 1
	printf '%s\n%s\n' "${coordinates[0]}" "${coordinates[1]}"
}

save_response() {
	local name="$1" response="$2"
	local result="$STATE_DIR/$name.result.json"
	jq '.' <<<"$response" > "$result"
	printf '%s\n' "$result"
}

request_snapshot() {
	local execute="${1:-}" tx action keyx keyy ciphertext public_key
	local -a key_coordinates=()
	load_manifest
	[[ -z "$(step snapshot_action)" ]] || die "snapshot already recorded; resume with snapshot-commit"
	primary="$(cast call "$CONTROLLER_ADDRESS" 'activeTee()(address)' --rpc-url "$CHAIN_URL")"
	recovery="$(cast call "$CONTROLLER_ADDRESS" 'recoveryTee()(address)' --rpc-url "$CHAIN_URL")"
	state="$(cast call "$CONTROLLER_ADDRESS" 'latestStateRoot()(bytes32)' --rpc-url "$CHAIN_URL")"
	printf 'Snapshot target: active=%s recovery=%s parent=%s\n' "$primary" "$recovery" "$state"
	public_key="$(cast call "$FLARE_TEE_MANAGER" 'getPublicKey(address)(bytes32,bytes32)' "$primary" --rpc-url "$CHAIN_URL")" || die "could not read active TEE public key"
	mapfile -t key_coordinates < <(public_key_from_tuple "$public_key") || die "could not parse active TEE public key tuple: $public_key"
	[[ "${#key_coordinates[@]}" -eq 2 ]] || die "active TEE public key must contain exactly two coordinates"
	keyx="${key_coordinates[0]}"
	keyy="${key_coordinates[1]}"
	is_hash "$keyx" || die "active TEE public key x coordinate is malformed"
	is_hash "$keyy" || die "active TEE public key y coordinate is malformed"
	ciphertext="$(cd "$ROOT/extension" && go run ./cmd/acceptance-crypto -x "$keyx" -y "$keyy" -plaintext "$ENTRY_TEXT")"
	printf '%s\n' "$ciphertext" > "$SNAPSHOT_DIR/entry.ciphertext"
	[[ "$execute" == "--execute" ]] || { printf 'Encrypted entry: %s\nNo transaction was sent.\n' "$SNAPSHOT_DIR/entry.ciphertext"; return 0; }
	require_execute "$execute"; owner_check
	tx="$(send "$CONTROLLER_ADDRESS" 'requestSnapshot(bytes)' "$ciphertext" --value "$INSTRUCTION_FEE_WEI")"
	action="$(action_from_receipt "$tx" 'SnapshotRequested(bytes32,uint64,uint64,address,address,bytes32)')"
	is_hash "$action" || die "SnapshotRequested action ID not found in $tx"
	record snapshot_request_tx "$tx"; record snapshot_action "$action"; record snapshot_ciphertext "$ciphertext"
	printf 'Snapshot requested: tx=%s action=%s\n' "$tx" "$action"
}

commit_snapshot() {
	local execute="${1:-}" action response data status signature tag tx
	load_manifest; action="$(step snapshot_action)"; is_hash "$action" || die "run snapshot-request first"
	response="$(wait_result "$PRIMARY_PROXY_URL" "$action")"; save_response snapshot "$response" >/dev/null
	status="$(jq -r '.result.status' <<<"$response")"; data="$(jq -r '.result.data' <<<"$response")"; signature="$(jq -r '.signature' <<<"$response")"; tag="$(jq -r '.result.submissionTag' <<<"$response")"
	printf 'Signed snapshot result: status=%s data-bytes=%s\n' "$status" "$(( (${#data}-2) / 2 ))"
	[[ "$execute" == "--execute" ]] || { printf 'No transaction was sent.\n'; return 0; }
	require_execute "$execute"; owner_check
	tx="$(send "$CONTROLLER_ADDRESS" 'commitSnapshot(bytes,bytes32,string,uint8,bytes)' "$data" "$action" "$tag" "$status" "$signature")"
	record snapshot_commit_tx "$tx"; printf 'Snapshot committed: tx=%s\n' "$tx"
}

request_recovery() {
	local execute="${1:-}" tx action ciphertext snapshot_data
	load_manifest
	[[ -n "$(step snapshot_commit_tx)" ]] || die "snapshot is not committed"
	[[ -f "$SNAPSHOT_RESULT" ]] || die "snapshot result is missing: $SNAPSHOT_RESULT"
	snapshot_data="$(jq -r '.result.data' "$SNAPSHOT_RESULT")"
	ciphertext="$(cast abi-decode 'decode()(bytes32,address,address,uint64,uint64,bytes32,bytes32,bytes)' "$snapshot_data" | awk 'NF { value=$NF } END { print value }')"
	is_hash "$ciphertext" || [[ "$ciphertext" == 0x* ]] || die "could not decode snapshot ciphertext"
	printf 'Recovery target: %s, ciphertext digest: %s\n' "$(cast call "$CONTROLLER_ADDRESS" 'recoveryTee()(address)' --rpc-url "$CHAIN_URL")" "$(cast keccak "$ciphertext")"
	[[ "$execute" == "--execute" ]] || { printf 'No transaction was sent.\n'; return 0; }
	require_execute "$execute"; owner_check
	tx="$(send "$CONTROLLER_ADDRESS" 'requestRecovery(bytes)' "$ciphertext" --value "$INSTRUCTION_FEE_WEI")"
	action="$(action_from_receipt "$tx" 'RecoveryRequested(bytes32,address,uint64,bytes32,bytes32)')"
	is_hash "$action" || die "RecoveryRequested action ID not found in $tx"
	printf '%s\n' "$ciphertext" > "$SNAPSHOT_DIR/committed.ciphertext"
	record recovery_request_tx "$tx"; record recovery_action "$action"
	printf 'Recovery requested: tx=%s action=%s\n' "$tx" "$action"
}

arm_recovery() {
	local execute="${1:-}" action response data status signature tag tx
	load_manifest; action="$(step recovery_action)"; is_hash "$action" || die "run recovery-request first"
	response="$(wait_result "$RECOVERY_PROXY_URL" "$action")"; save_response recovery "$response" >/dev/null
	status="$(jq -r '.result.status' <<<"$response")"; data="$(jq -r '.result.data' <<<"$response")"; signature="$(jq -r '.signature' <<<"$response")"; tag="$(jq -r '.result.submissionTag' <<<"$response")"
	printf 'Signed recovery result: status=%s\n' "$status"
	[[ "$execute" == "--execute" ]] || { printf 'The recovery TEE must be PAUSED before armRecovery. No transaction was sent.\n'; return 0; }
	require_execute "$execute"; owner_check
	[[ "$(cast call "$FLARE_TEE_MANAGER" 'getTeeMachineStatus(address)(uint8)' "$(cast call "$CONTROLLER_ADDRESS" 'recoveryTee()(address)' --rpc-url "$CHAIN_URL")" --rpc-url "$CHAIN_URL" | awk '{print $1}')" == "4" ]] || die "recovery TEE must be PAUSED before arm"
	tx="$(send "$CONTROLLER_ADDRESS" 'armRecovery(bytes,bytes32,string,uint8,bytes)' "$data" "$action" "$tag" "$status" "$signature")"
	record recovery_arm_tx "$tx"; printf 'Recovery armed: tx=%s\n' "$tx"
}

activate_recovery() {
	local execute="${1:-}" tx
	load_manifest; [[ -n "$(step recovery_arm_tx)" ]] || die "recovery is not armed"
	printf 'Activation target: %s\n' "$(cast call "$CONTROLLER_ADDRESS" 'recoveryTee()(address)' --rpc-url "$CHAIN_URL")"
	[[ "$execute" == "--execute" ]] || { printf 'A fresh production availability proof must already exist. No transaction was sent.\n'; return 0; }
	require_execute "$execute"; owner_check
	tx="$(send "$CONTROLLER_ADDRESS" 'activateRecovery()')"
	record recovery_activation_tx "$tx"; printf 'Recovery activated: tx=%s\n' "$tx"
}

status() {
	load_manifest
	printf 'Controller: %s\n' "$CONTROLLER_ADDRESS"
	printf 'Active TEE: %s\n' "$(cast call "$CONTROLLER_ADDRESS" 'activeTee()(address)' --rpc-url "$CHAIN_URL")"
	printf 'Recovery TEE: %s\n' "$(cast call "$CONTROLLER_ADDRESS" 'recoveryTee()(address)' --rpc-url "$CHAIN_URL")"
	printf 'Epoch: %s\n' "$(cast call "$CONTROLLER_ADDRESS" 'latestEpoch()(uint64)' --rpc-url "$CHAIN_URL")"
	printf 'State root: %s\n' "$(cast call "$CONTROLLER_ADDRESS" 'latestStateRoot()(bytes32)' --rpc-url "$CHAIN_URL")"
	printf 'Manifest: %s\n' "$MANIFEST"
	jq '.steps' "$MANIFEST"
}

case "$COMMAND" in
	status) status ;;
	snapshot-request) request_snapshot "${1:-}" ;;
	snapshot-commit) commit_snapshot "${1:-}" ;;
	recovery-request) request_recovery "${1:-}" ;;
	recovery-arm) arm_recovery "${1:-}" ;;
	recovery-activate) activate_recovery "${1:-}" ;;
	*) die "usage: live-acceptance.sh status|snapshot-request|snapshot-commit|recovery-request|recovery-arm|recovery-activate [--execute]" ;;
esac
