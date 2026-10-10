#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$PROJECT_ROOT/apps/ManyKee"
WASM_CRATE_DIR="$PROJECT_ROOT/rust/keepassxc-wasm"
WASM_SOURCE_DIR="$PROJECT_ROOT/packages/keepass_web/web"
WASM_PKG_DIR="$WASM_SOURCE_DIR/pkg"
BUILD_DIR="$APP_DIR/build/web"

if ! command -v flutter &>/dev/null; then
  echo "ERROR: flutter not found" >&2
  exit 1
fi

if ! command -v wasm-pack &>/dev/null; then
  echo "ERROR: wasm-pack not found" >&2
  exit 1
fi

echo "Building keepassxc WASM worker package..."
(cd "$WASM_CRATE_DIR" && wasm-pack build --release --target web --out-dir ../../packages/keepass_web/web/pkg)

echo "Building ManyKee web app..."
# No service worker: it would cache main.dart.js while the worker and wasm
# copied below bypass it, serving stale Dart against new wasm after a
# redeploy.
(cd "$APP_DIR" && flutter build web --pwa-strategy=none "$@")

echo "Copying keepassxc worker assets into ManyKee web build..."
mkdir -p "$BUILD_DIR/pkg"
cp "$WASM_SOURCE_DIR/keepassxc_worker.js" "$BUILD_DIR/"
find "$WASM_PKG_DIR" -maxdepth 1 -type f -name 'keepassxc_wasm*' \
  -exec cp {} "$BUILD_DIR/pkg/" \;

missing=0
for file in \
  "$BUILD_DIR/index.html" \
  "$BUILD_DIR/main.dart.js" \
  "$BUILD_DIR/keepassxc_worker.js" \
  "$BUILD_DIR/pkg/keepassxc_wasm.js" \
  "$BUILD_DIR/pkg/keepassxc_wasm_bg.wasm"; do
  if [[ ! -f "$file" ]]; then
    echo "MISSING: $file" >&2
    missing=1
  fi
done

if [[ "$missing" -ne 0 ]]; then
  echo "ERROR: ManyKee web build is missing required files" >&2
  exit 1
fi

echo "ManyKee web build ready at: $BUILD_DIR"
