#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IMAGE="${CONTINUITY_IMAGE:-continuity-tee:v0.1.0}"
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "$ROOT" log -1 --format=%ct)}"

docker build \
  --file "$ROOT/fcc/deploy/Dockerfile" \
  --build-arg "SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH" \
  --tag "$IMAGE" \
  "$ROOT"

docker inspect "$IMAGE" --format '{{index .Config.Labels "tee.launch_policy.allow_env_override"}}'
printf 'Built %s from SOURCE_DATE_EPOCH=%s\n' "$IMAGE" "$SOURCE_DATE_EPOCH"
