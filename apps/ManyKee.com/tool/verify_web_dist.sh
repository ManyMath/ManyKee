#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
site_app_dir="$(cd "$script_dir/.." && pwd)"
dist_dir="${1:-$site_app_dir/build/dist}"
server_log="${TMPDIR:-/tmp}/manykee-web-smoke-$$.log"
download_dir="${TMPDIR:-/tmp}/manykee-web-smoke-$$"
server_pid=""

cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -rf "$download_dir" "$server_log"
}
trap cleanup EXIT

for command in curl python3; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "$command is required to verify the ManyKee.com distribution" >&2
    exit 1
  }
done

port="${MANYKEE_SMOKE_PORT:-$(python3 -c '
import socket

with socket.socket() as server:
    server.bind(("127.0.0.1", 0))
    print(server.getsockname()[1])
')}"

required_files=(
  index.html
  styles.css
  assets/manykee-mark.svg
  assets/manykee-vault.png
  web/index.html
  web/flutter_bootstrap.js
  web/main.dart.js
  web/keepassxc_worker.js
  web/pkg/keepassxc_wasm.js
  web/pkg/keepassxc_wasm_bg.wasm
)
for relative_path in "${required_files[@]}"; do
  test -s "$dist_dir/$relative_path" || {
    echo "missing distribution artifact: $dist_dir/$relative_path" >&2
    exit 1
  }
done

grep -Fq '<base href="/web/">' "$dist_dir/web/index.html" || {
  echo "composed ManyKee app does not have the required /web/ base href" >&2
  exit 1
}
if [[ -s "$dist_dir/web/flutter_service_worker.js" ]]; then
  echo "composed ManyKee app unexpectedly contains an active service worker" >&2
  exit 1
fi

for url in \
  'https://manymath.com/' \
  'https://manymatrix.com/' \
  'https://manytype.com/' \
  'https://manytier.com/'; do
  grep -Fq "href=\"$url\"" "$dist_dir/index.html" || {
    echo "landing page is missing ecosystem link: $url" >&2
    exit 1
  }
done

mkdir -p "$download_dir"
python3 -m http.server "$port" \
  --bind 127.0.0.1 \
  --directory "$dist_dir" >"$server_log" 2>&1 &
server_pid=$!

for _ in $(seq 1 50); do
  if curl --fail --silent --show-error "http://127.0.0.1:$port/" \
    --output "$download_dir/site.html" 2>/dev/null; then
    break
  fi
  sleep 0.1
done
if ! kill -0 "$server_pid" 2>/dev/null; then
  cat "$server_log" >&2
  echo "ManyKee.com distribution server failed to start" >&2
  exit 1
fi

curl --fail --silent --show-error "http://127.0.0.1:$port/web/" \
  --output "$download_dir/app.html"
curl --fail --silent --show-error "http://127.0.0.1:$port/styles.css" \
  --output "$download_dir/styles.css"
curl --fail --silent --show-error "http://127.0.0.1:$port/assets/manykee-mark.svg" \
  --output "$download_dir/manykee-mark.svg"
curl --fail --silent --show-error "http://127.0.0.1:$port/assets/manykee-vault.png" \
  --output "$download_dir/manykee-vault.png"
curl --fail --silent --show-error "http://127.0.0.1:$port/web/main.dart.js" \
  --output "$download_dir/main.dart.js"
curl --fail --silent --show-error "http://127.0.0.1:$port/web/keepassxc_worker.js" \
  --output "$download_dir/keepassxc_worker.js"
curl --fail --silent --show-error \
  --dump-header "$download_dir/wasm.headers" \
  "http://127.0.0.1:$port/web/pkg/keepassxc_wasm_bg.wasm" \
  --output "$download_dir/keepassxc_wasm_bg.wasm"

grep -Fq '<base href="/web/">' "$download_dir/app.html"
if grep -Eiq '<!doctype html|<html' "$download_dir/styles.css"; then
  echo "/styles.css returned HTML" >&2
  exit 1
fi
if ! grep -Fq '<svg' "$download_dir/manykee-mark.svg"; then
  echo "/assets/manykee-mark.svg is not an SVG image" >&2
  exit 1
fi
preview_magic="$(od -An -tx1 -N8 "$download_dir/manykee-vault.png" | tr -d '[:space:]')"
if [[ "$preview_magic" != "89504e470d0a1a0a" ]]; then
  echo "served manykee-vault.png is not a valid PNG image" >&2
  exit 1
fi
if grep -Eiq '<!doctype html|<html' "$download_dir/main.dart.js"; then
  echo "/web/main.dart.js returned HTML" >&2
  exit 1
fi
grep -Fq "./pkg/keepassxc_wasm.js" "$download_dir/keepassxc_worker.js" || {
  echo "served worker does not reference its WebAssembly package" >&2
  exit 1
}
wasm_magic="$(od -An -tx1 -N4 "$download_dir/keepassxc_wasm_bg.wasm" | tr -d '[:space:]')"
if [[ "$wasm_magic" != "0061736d" ]]; then
  echo "served keepassxc_wasm_bg.wasm is not a valid WebAssembly binary" >&2
  exit 1
fi
grep -Eiq '^Content-Type: application/wasm([[:space:]]*;|[[:space:]]*$)' \
  "$download_dir/wasm.headers" || {
  echo "served WebAssembly does not use the application/wasm content type" >&2
  exit 1
}

for missing_path in web/missing.js web/missing.wasm; do
  status="$({ curl --silent --show-error \
    --output "$download_dir/missing" \
    --write-out '%{http_code}' \
    "http://127.0.0.1:$port/$missing_path"; } || true)"
  if [[ "$status" != "404" ]]; then
    echo "/$missing_path returned $status instead of 404" >&2
    exit 1
  fi
  if cmp -s "$download_dir/missing" "$download_dir/site.html" || \
    cmp -s "$download_dir/missing" "$download_dir/app.html"; then
    echo "/$missing_path fell back to an application entry point" >&2
    exit 1
  fi
done

echo "Verified ManyKee.com at / and the canonical ManyKee app at /web/."
