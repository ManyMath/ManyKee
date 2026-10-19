#!/usr/bin/env python3
"""Materialize a closed native source bundle only in a disposable payload stage."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

CRATES = ("keepass-rs", "keepassxc", "keepassxc-ffi")


def stage(root, revision):
    # native_payload snapshots into an empty Git repository. Refuse to change
    # a developer checkout with history, including an isolated worktree.
    if subprocess.run(["git", "rev-parse", "--verify", "HEAD"], cwd=root,
                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
        raise ValueError("Native staging requires a disposable snapshot without Git history")
    plugin = root / "packages/keepass_flutter/rust"
    output = plugin / "sources"
    if output.exists() or (plugin / "SOURCE_PROVENANCE.json").exists():
        raise ValueError("Refusing stale or reused native staging output")
    shim = plugin / "Cargo.toml"
    original = shim.read_text()
    before = 'path = "../../../rust/keepassxc-ffi"'
    if original.count(before) != 1:
        raise ValueError("Unexpected canonical native dependency; review source closure")
    output.mkdir()
    inventory = {}
    for name in CRATES:
        source = root / "rust" / name
        for path in sorted(source.rglob("*")):
            relative = path.relative_to(source)
            if any(part == "target" or part.startswith(".") for part in relative.parts):
                continue
            if path.is_symlink():
                raise ValueError(f"Source symlink needs explicit provenance review: {path}")
            if not path.is_file():
                continue
            target = output / name / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)
            inventory[str(target.relative_to(plugin))] = hashlib.sha256(target.read_bytes()).hexdigest()
        if not (output / name / "LICENSE").is_file():
            raise ValueError(f"Missing license for {name}")
    shim.write_text(original.replace(before, 'path = "sources/keepassxc-ffi"'))
    inventory["Cargo.toml"] = hashlib.sha256(shim.read_bytes()).hexdigest()
    # Cargokit hashes src/ and top-level manifests, not nested path dependencies.
    # Bind its cache identity to every copied source/license byte.
    identity = hashlib.sha256(json.dumps(inventory, sort_keys=True).encode()).hexdigest()
    marker = plugin / "src/staged_source_identity.rs"
    marker.parent.mkdir(exist_ok=True)
    marker.write_text("// Generated staged source closure SHA256: " + identity + "\n")
    inventory["src/staged_source_identity.rs"] = hashlib.sha256(marker.read_bytes()).hexdigest()
    (plugin / "SOURCE_PROVENANCE.json").write_text(json.dumps({
        "schema": 1, "canonical_revision": revision,
        "canonical_source": "rust/", "staged_shim_transform": "local path only",
        "upstream": {"keepass-rs": "https://github.com/sseemayer/keepass-rs", "upstream_revision": "unknown; source hashes identify the maintained local snapshot"},
        "files_sha256": inventory,
    }, sort_keys=True, indent=2) + "\n")
    return inventory


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staged-root", type=Path, required=True)
    parser.add_argument("--revision", required=True)
    args = parser.parse_args()
    root = args.staged_root.resolve()
    stage(root, args.revision)
    plugin = root / "packages/keepass_flutter/rust"
    shutil.copyfile(root / "rust/Cargo.lock", plugin / "Cargo.lock")
    # Resolve the shim closure from the canonical lock, retaining existing
    # versions where compatible. Cargo records the standalone shim in its lock.
    metadata = json.loads(subprocess.check_output([
        "cargo", "metadata", "--manifest-path", str(plugin / "Cargo.toml"),
        "--format-version", "1"
    ], cwd=root, text=True))
    dependencies = [{key: package.get(key) for key in ("name", "version", "license", "source")}
                    for package in metadata["packages"]]
    (plugin / "NATIVE_DEPENDENCIES.json").write_text(json.dumps(dependencies, sort_keys=True, indent=2) + "\n")
    provenance = plugin / "SOURCE_PROVENANCE.json"
    document = json.loads(provenance.read_text())
    for name in ["Cargo.lock", "NATIVE_DEPENDENCIES.json"]:
        document["files_sha256"][name] = hashlib.sha256((plugin / name).read_bytes()).hexdigest()
    provenance.write_text(json.dumps(document, sort_keys=True, indent=2) + "\n")
