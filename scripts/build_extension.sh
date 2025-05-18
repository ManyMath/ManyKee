#!/usr/bin/env bash
set -euo pipefail

# Build Chrome MV3 extension from Flutter Web output
#
# Usage: ./scripts/build_extension.sh
# Or:    melos run build:extension

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$PROJECT_ROOT/packages/keepass_web/example"
BUILD_DIR="$APP_DIR/build"
EXT_OUTPUT="$BUILD_DIR/extension"
EXT_SOURCE="$APP_DIR/extension"

# --- Prerequisites ---
echo "Checking prerequisites..."

if ! command -v flutter &>/dev/null; then
  echo "ERROR: flutter not found in PATH"
  exit 1
fi

if ! command -v wasm-pack &>/dev/null; then
  echo "WARNING: wasm-pack not found — WASM assets may be missing"
fi

# --- Build Flutter Web ---
echo "Building Flutter Web (CSP mode, no CDN)..."
cd "$APP_DIR"
flutter build web --csp --no-web-resources-cdn --release

# --- Create extension directory ---
echo "Creating extension output directory..."
rm -rf "$EXT_OUTPUT"
cp -r "$BUILD_DIR/web" "$EXT_OUTPUT"

# --- Overlay extension files ---
echo "Overlaying extension source files..."
cp "$EXT_SOURCE/manifest.json" "$EXT_OUTPUT/"
cp "$EXT_SOURCE/background.js" "$EXT_OUTPUT/"
cp "$EXT_SOURCE/disable_service_worker.js" "$EXT_OUTPUT/"

# --- Patch index.html ---
echo "Patching index.html..."

# Fix base href for extension-relative paths
sed -i 's|<base href="/">|<base href="./">|' "$EXT_OUTPUT/index.html"

# Inject disable_service_worker.js before flutter_bootstrap.js
sed -i 's|<script src="flutter_bootstrap.js"|<script src="disable_service_worker.js"></script>\n  <script src="flutter_bootstrap.js"|' "$EXT_OUTPUT/index.html"

# --- Patch flutter_bootstrap.js ---
echo "Patching flutter_bootstrap.js..."
sed -i 's/,\?[[:space:]]*serviceWorkerSettings:[[:space:]]*{[^}]*}//g' "$EXT_OUTPUT/flutter_bootstrap.js"

# --- Remove service worker ---
echo "Removing Flutter service worker..."
rm -f "$EXT_OUTPUT/flutter_service_worker.js"

# --- Verify output ---
echo "Verifying extension output..."

REQUIRED_FILES=(
  "manifest.json"
  "index.html"
  "flutter.js"
  "main.dart.js"
  "background.js"
  "disable_service_worker.js"
)

MISSING=0
for file in "${REQUIRED_FILES[@]}"; do
  if [ ! -f "$EXT_OUTPUT/$file" ]; then
    echo "MISSING: $file"
    MISSING=1
  fi
done

# Check for WASM assets (may be in pkg/ subdirectory)
for wasm_file in "pkg/keepassxc_wasm_bg.wasm" "pkg/keepassxc_wasm.js" "keepassxc_worker.js"; do
  if [ ! -f "$EXT_OUTPUT/$wasm_file" ]; then
    echo "WARNING: $wasm_file not found (expected if WASM not yet built)"
  fi
done

if [ "$MISSING" -eq 1 ]; then
  echo "ERROR: Extension build verification failed — required files missing"
  exit 1
fi

echo ""
echo "Extension built successfully at: $EXT_OUTPUT"
echo ""
echo "To install in Chrome:"
echo "  1. Open chrome://extensions"
echo "  2. Enable 'Developer mode'"
echo "  3. Click 'Load unpacked'"
echo "  4. Select: $EXT_OUTPUT"
