#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/continuity-fcc-scripts.XXXXXX)"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin"

cat >"$TEST_ROOT/bin/cast" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  chain-id) printf '114\n' ;;
  code) printf '0x6000\n' ;;
  keccak) printf '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n' ;;
  to-dec) printf '42\n' ;;
  call)
    case "$3" in
      'nextPublicExtensionId()(uint256)') printf '42 [4.2e1]\n' ;;
      'teeManager()(address)') printf '0x1a9C4A0f9D76c0b1D91d22E24E573a9b377618aE\n' ;;
      *) printf '0\n' ;;
    esac
    ;;
  *) printf 'unsupported mock cast call: %s\n' "$*" >&2; exit 90 ;;
esac
MOCK

cat >"$TEST_ROOT/bin/curl" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' '{"teeInfo":{"publicKey":{"x":"0x1111111111111111111111111111111111111111111111111111111111111111","y":"0x2222222222222222222222222222222222222222222222222222222222222222"}},"machineData":{"extensionId":"0x000000000000000000000000000000000000000000000000000000000000002a"}}'
MOCK
chmod +x "$TEST_ROOT/bin/cast" "$TEST_ROOT/bin/curl"

export PATH="$TEST_ROOT/bin:$PATH"
export CONTROLLER_ADDRESS=0x3333333333333333333333333333333333333333
export PRIMARY_PROXY_URL=https://primary.example.test
export RECOVERY_PROXY_URL=https://recovery.example.test
export EXTENSION_ID=42

"$ROOT/scripts/fcc/preflight.sh" >"$TEST_ROOT/preflight.log"
grep -q 'Read-only preflight passed' "$TEST_ROOT/preflight.log"

if "$ROOT/scripts/fcc/register-extension.sh" >"$TEST_ROOT/register.log" 2>"$TEST_ROOT/register.error"; then
  printf 'register-extension dry run unexpectedly succeeded\n' >&2
  exit 1
fi
grep -q 'dry run only' "$TEST_ROOT/register.error"

if FLARE_TEE_MANAGER=0x4444444444444444444444444444444444444444 "$ROOT/scripts/fcc/preflight.sh" >"$TEST_ROOT/stale.log" 2>"$TEST_ROOT/stale.error"; then
  printf 'stale manager unexpectedly passed\n' >&2
  exit 1
fi
grep -q 'refusing stale FlareTeeManager' "$TEST_ROOT/stale.error"

if PRIMARY_PROXY_URL=https://quick.trycloudflare.com "$ROOT/scripts/fcc/preflight.sh" >"$TEST_ROOT/quick.log" 2>"$TEST_ROOT/quick.error"; then
  printf 'quick tunnel unexpectedly passed\n' >&2
  exit 1
fi
grep -q 'quick Cloudflare tunnel' "$TEST_ROOT/quick.error"

printf 'FCC script tests passed.\n'
