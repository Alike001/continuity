#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMPOSE_FILE="$ROOT/fcc/deploy/docker-compose.coston2.yaml"
CONFIG_DIR="$ROOT/fcc/deploy/proxy-config"

die() { printf 'start-machines: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 is required"; }
need docker

[[ -f "$CONFIG_DIR/primary.toml" ]] || die "create ignored $CONFIG_DIR/primary.toml from proxy-config.example.toml"
[[ -f "$CONFIG_DIR/recovery.toml" ]] || die "create ignored $CONFIG_DIR/recovery.toml from proxy-config.example.toml"
[[ -n "${INITIAL_OWNER:-}" ]] || die "INITIAL_OWNER is required"
[[ -n "${EXTENSION_ID:-}" && "$EXTENSION_ID" != "0" ]] || die "EXTENSION_ID is required"
[[ -n "${APPLICATION_ID:-}" ]] || die "APPLICATION_ID is required"
[[ -n "${PRIMARY_PROXY_PRIVATE_KEY:-}" ]] || die "PRIMARY_PROXY_PRIVATE_KEY is required"
[[ -n "${RECOVERY_PROXY_PRIVATE_KEY:-}" ]] || die "RECOVERY_PROXY_PRIVATE_KEY is required"
[[ "$PRIMARY_PROXY_PRIVATE_KEY" != "$RECOVERY_PROXY_PRIVATE_KEY" ]] || die "primary and recovery proxies need distinct keys"

[[ "${EXTENSION_ID:-}" =~ ^[1-9][0-9]*$ ]] || die "EXTENSION_ID must be the decimal public extension ID"
EXTENSION_ID_HEX="$(printf '0x%064x' "$EXTENSION_ID")"
export EXTENSION_ID_HEX

docker compose -f "$COMPOSE_FILE" config --quiet
docker compose -f "$COMPOSE_FILE" up -d

printf 'Two isolated Continuity machines started.\n'
printf 'Primary local proxy: http://127.0.0.1:%s/info\n' "${PRIMARY_PROXY_PORT:-6674}"
printf 'Recovery local proxy: http://127.0.0.1:%s/info\n' "${RECOVERY_PROXY_PORT:-6684}"
printf 'Use two stable named HTTPS tunnels for those ports before registration.\n'
