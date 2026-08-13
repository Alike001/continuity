#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCAFFOLD_REV="e3f587949069780084e2ced8a53c9419ed05c250"
WORK_ROOT="${FCC_WORK_ROOT:-$ROOT/.fcc-work}"
SCAFFOLD_DIR="$WORK_ROOT/fce-extension-scaffold"

need() { command -v "$1" >/dev/null 2>&1 || { printf 'bootstrap: %s is required\n' "$1" >&2; exit 1; }; }
need git

mkdir -p "$WORK_ROOT"
if [[ ! -d "$SCAFFOLD_DIR/.git" ]]; then
  git clone https://github.com/flare-foundation/fce-extension-scaffold.git "$SCAFFOLD_DIR"
fi

git -C "$SCAFFOLD_DIR" fetch origin "$SCAFFOLD_REV"
git -C "$SCAFFOLD_DIR" checkout --detach "$SCAFFOLD_REV"
[[ "$(git -C "$SCAFFOLD_DIR" rev-parse HEAD)" == "$SCAFFOLD_REV" ]] || {
  printf 'bootstrap: scaffold revision verification failed\n' >&2
  exit 1
}

printf 'Pinned scaffold ready: %s\n' "$SCAFFOLD_DIR"
printf 'Revision: %s\n' "$SCAFFOLD_REV"
