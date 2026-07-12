#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
site_app_dir="$(cd "$script_dir/.." && pwd)"
repo_root="$(cd "$site_app_dir/../.." && pwd)"
app_dir="$repo_root/apps/ManyKee"
manyui_dir="$repo_root/../ManyUI/manyui"
wasm_crate_dir="$repo_root/rust/keepassxc-wasm"
wasm_source_dir="$repo_root/packages/keepass_web/web"
wasm_pkg_dir="$site_app_dir/build/.wasm-pkg-$$"
flutter_dir="$app_dir/build/web"

cleanup() {
  rm -rf "$wasm_pkg_dir"
}
trap cleanup EXIT

for command in flutter wasm-pack; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "$command is required to build ManyKee.com" >&2
    exit 1
  }
done

test -s "$manyui_dir/pubspec.yaml" || {
  echo "missing sibling ManyUI package: $manyui_dir" >&2
  echo "check out ManyUI beside ManyKee before building the web distribution" >&2
  exit 1
}

rm -rf "$wasm_pkg_dir" "$flutter_dir"
mkdir -p "$wasm_pkg_dir"

echo "Building the KeePassXC WebAssembly worker package..."
(
  cd "$wasm_crate_dir"
  wasm-pack build \
    --release \
    --target web \
    --out-dir "$wasm_pkg_dir"
)

echo "Building the canonical ManyKee app for /web/..."
(
  cd "$app_dir"
  flutter build web \
    --release \
    --base-href=/web/ \
    --pwa-strategy=none \
    --no-web-resources-cdn \
    --no-wasm-dry-run
)

echo "Adding the KeePassXC worker assets..."
mkdir -p "$flutter_dir/pkg"
cp "$wasm_source_dir/keepassxc_worker.js" "$flutter_dir/"
find "$wasm_pkg_dir" -maxdepth 1 -type f -name 'keepassxc_wasm*' \
  -exec cp {} "$flutter_dir/pkg/" \;

"$script_dir/assemble_web_dist.sh"
