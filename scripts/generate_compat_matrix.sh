#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

usage() {
  printf 'usage: scripts/generate_compat_matrix.sh (--write|--check)\n' >&2
}

case "${1:-}" in
  --write|--check)
    mode="$1"
    ;;
  "")
    usage
    exit 2
    ;;
  *)
    usage
    printf 'unknown mode: %s\n' "$1" >&2
    exit 2
    ;;
esac

if [[ "$#" -ne 1 ]]; then
  usage
  exit 2
fi

cargo run --manifest-path "$ROOT/rust/Cargo.toml" -p keepassxc --bin generate_compat_matrix -- "$mode"
