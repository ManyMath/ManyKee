#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
EXPECTED_VERSION="2.7.12"

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

resolve_keepassxc() {
  local candidate="${MANYKEE_KEEPASSXC_CLI:-keepassxc-cli}"

  if [[ "$candidate" == */* ]]; then
    if [[ -e "$candidate" ]]; then
      local dir
      dir="$(cd -- "$(dirname -- "$candidate")" && pwd -P)"
      printf '%s/%s\n' "$dir" "$(basename -- "$candidate")"
      return 0
    fi

    printf '%s\n' "$candidate"
    return 1
  fi

  command -v "$candidate"
}

normalize_version() {
  local line
  local token

  while IFS= read -r line; do
    [[ -z "${line//[[:space:]]/}" ]] && continue

    for token in $line; do
      if [[ "$token" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
        printf '%s\n' "$token"
        return 0
      fi
    done

    printf '%s\n' "$line"
    return 0
  done

  return 1
}

attempted_path="${MANYKEE_KEEPASSXC_CLI:-keepassxc-cli}"
if ! resolved_path="$(resolve_keepassxc)"; then
  fail "expected keepassxc-cli ${EXPECTED_VERSION}; attempted path=${attempted_path}; discovered version=unavailable"
fi

version_output=""
if ! version_output="$("$resolved_path" --version 2>&1)"; then
  discovered_version="$(printf '%s\n' "$version_output" | normalize_version || printf 'unavailable')"
  fail "expected keepassxc-cli ${EXPECTED_VERSION}; attempted path=${resolved_path}; discovered version=${discovered_version}"
fi

discovered_version="$(printf '%s\n' "$version_output" | normalize_version || printf 'unavailable')"
if [[ "$discovered_version" != "$EXPECTED_VERSION" ]]; then
  fail "expected keepassxc-cli ${EXPECTED_VERSION}; attempted path=${resolved_path}; discovered version=${discovered_version}"
fi

printf 'Using keepassxc-cli: path=%s version=%s\n' "$resolved_path" "$EXPECTED_VERSION"

export MANYKEE_REQUIRE_OFFICIAL_TOOLS=1
export MANYKEE_KEEPASSXC_CLI="$resolved_path"

cargo test --manifest-path "$ROOT/rust/Cargo.toml" -p keepassxc --test official_tool_harness
cargo test --manifest-path "$ROOT/rust/Cargo.toml" -p keepassxc --test keepassxc_compat
cargo test --manifest-path "$ROOT/rust/Cargo.toml" -p keepassxc --test semantic_snapshot
cargo test --manifest-path "$ROOT/rust/Cargo.toml" -p keepassxc --test compat_matrix
cargo test --manifest-path "$ROOT/rust/Cargo.toml" -p keepassxc --test official_fixture_corpus
cargo run --manifest-path "$ROOT/rust/Cargo.toml" -p keepassxc --bin record_compat_evidence -- --check
cargo run --manifest-path "$ROOT/rust/Cargo.toml" -p keepassxc --bin record_official_fixture_evidence -- --check
"$ROOT/scripts/generate_compat_matrix.sh" --check
