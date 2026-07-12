#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
site_app_dir="$(cd "$script_dir/.." && pwd)"
repo_root="$(cd "$site_app_dir/../.." && pwd)"
site_dir="$site_app_dir/site"
flutter_dir="$repo_root/apps/ManyKee/build/web"
dist_dir="$site_app_dir/build/dist"
staging_dir="$site_app_dir/build/.dist-staging-$$"

cleanup() {
  rm -rf "$staging_dir"
}
trap cleanup EXIT

required_site_assets=(
  index.html
  styles.css
  assets/manykee-mark.svg
  assets/manykee-vault.png
)
for relative_path in "${required_site_assets[@]}"; do
  test -s "$site_dir/$relative_path" || {
    echo "missing ManyKee.com site artifact: $site_dir/$relative_path" >&2
    exit 1
  }
done
if [[ -e "$site_dir/web" ]]; then
  echo "the product site may not contain a web path; /web/ is reserved for Flutter" >&2
  exit 1
fi

required_flutter_assets=(
  index.html
  flutter_bootstrap.js
  main.dart.js
  manifest.json
  keepassxc_worker.js
  pkg/keepassxc_wasm.js
  pkg/keepassxc_wasm_bg.wasm
)
for relative_path in "${required_flutter_assets[@]}"; do
  test -s "$flutter_dir/$relative_path" || {
    echo "missing ManyKee Flutter artifact: $flutter_dir/$relative_path" >&2
    exit 1
  }
done

grep -Fq '<base href="/web/">' "$flutter_dir/index.html" || {
  echo "Flutter output does not have the required /web/ base href" >&2
  exit 1
}
if [[ -s "$flutter_dir/flutter_service_worker.js" ]]; then
  echo "Flutter output unexpectedly contains an active service worker" >&2
  exit 1
fi

wasm_magic="$(od -An -tx1 -N4 "$flutter_dir/pkg/keepassxc_wasm_bg.wasm" | tr -d '[:space:]')"
if [[ "$wasm_magic" != "0061736d" ]]; then
  echo "keepassxc_wasm_bg.wasm is not a valid WebAssembly binary" >&2
  exit 1
fi

rm -rf "$staging_dir"
mkdir -p "$staging_dir/web"
cp -R "$site_dir/." "$staging_dir/"
cp -R "$flutter_dir/." "$staging_dir/web/"

rm -rf "$dist_dir"
mv "$staging_dir" "$dist_dir"
trap - EXIT

echo "Assembled ManyKee.com web distribution at $dist_dir"
