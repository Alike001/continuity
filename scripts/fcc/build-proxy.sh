#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IMAGE="${TEE_PROXY_IMAGE:-local/tee-proxy:v0.0.18}"

docker build \
  --file "$ROOT/fcc/deploy/Proxy.Dockerfile" \
  --build-arg TEE_PROXY_REF=v0.0.18 \
  --tag "$IMAGE" \
  "$ROOT"

printf 'Built pinned proxy image %s from tee-proxy v0.0.18.\n' "$IMAGE"
