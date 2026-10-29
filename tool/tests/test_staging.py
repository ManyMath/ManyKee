import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('stage_native', Path(__file__).parents[1] / 'stage_native.py')
staging = importlib.util.module_from_spec(spec)
spec.loader.exec_module(staging)

class StagingTests(unittest.TestCase):
    def make_source(self, root):
        subprocess.run(['git', 'init', '-q', str(root)], check=True)
        plugin = root / 'packages/keepass_flutter/rust'
        plugin.mkdir(parents=True)
        (plugin / 'Cargo.toml').write_text('[dependencies]\nkeepassxc-ffi = { path = "../../../rust/keepassxc-ffi" }\n')
        for name in staging.CRATES:
            crate = root / 'rust' / name
            crate.mkdir(parents=True)
            (crate / 'LICENSE').write_text('MIT fixture')
            (crate / 'Cargo.toml').write_text('[package]\nname="fixture"\nversion="0.1.0"\n')
            (crate / 'source.rs').write_text('// fixed bytes\n')

    def test_staging_is_deterministic_and_rejects_stale_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            outputs = []
            for name in ['one','two']:
                destination = root / name
                self.make_source(destination)
                staging.stage(destination, 'a' * 40)
                outputs.append((destination / 'packages/keepass_flutter/rust/SOURCE_PROVENANCE.json').read_bytes())
                with self.assertRaisesRegex(ValueError, 'stale'):
                    staging.stage(destination, 'a' * 40)
            self.assertEqual(*outputs)

    def test_source_only_change_invalidates_actual_cargokit_hash(self):
        import shutil
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            hashes = []
            tool = Path(__file__).parents[2] / 'packages/keepass_flutter/cargokit/build_tool'
            runner = root / 'build_tool'
            shutil.copytree(tool, runner, ignore=shutil.ignore_patterns('.dart_tool', 'build'))
            # CreateProcess does not apply PATHEXT; Flutter's SDK ships dart.bat.
            dart = shutil.which('dart')
            self.assertIsNotNone(dart, 'dart must be on PATH')
            subprocess.run([dart, 'pub', 'get'], cwd=runner, check=True, capture_output=True)
            (runner / 'hash_probe.dart').write_text("import 'lib/src/crate_hash.dart';\nvoid main(List<String> args) { print(CrateHash.compute(args.single)); }\n")
            for index in range(2):
                source = root / str(index)
                self.make_source(source)
                (source / 'rust/keepassxc/source.rs').write_text(f'// changed native implementation {index}\n')
                staging.stage(source, 'a' * 40)
                hashes.append(subprocess.check_output([dart, 'run', 'hash_probe.dart', str(source / 'packages/keepass_flutter/rust')], cwd=runner, text=True).strip())
            self.assertNotEqual(*hashes)

    def test_pinned_notices_survive_autocrlf_checkout(self):
        import hashlib
        import json
        import os
        repo = Path(__file__).parents[2]
        relative = Path('rust/keepass-rs/third_party/usb')
        expected = json.loads((repo / relative / 'PROVENANCE.json').read_text())['files_sha256']
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            # Use committed notice blobs, then reproduce a CRLF-converting
            # checkout. No user Git configuration or existing checkout changes.
            git = ['git', '-c', 'core.autocrlf=true', '-c', 'core.eol=crlf',
                   '-c', 'core.safecrlf=false', '-c', 'core.attributesFile=' + os.devnull]
            subprocess.run([*git, 'init', '-q', str(root)], check=True)
            (root / '.gitattributes').write_bytes((repo / '.gitattributes').read_bytes())
            (root / relative).mkdir(parents=True)
            for name in expected:
                data = subprocess.check_output(['git', 'show', 'HEAD:' + (relative / name).as_posix()], cwd=repo)
                (root / relative / name).write_bytes(data)
            subprocess.run([*git, 'add', '.'], cwd=root, check=True, capture_output=True)
            for name in expected:
                (root / relative / name).unlink()
            subprocess.run([*git, 'checkout-index', '--force', '--all'], cwd=root, check=True, capture_output=True)
            for name, digest in expected.items():
                self.assertEqual(hashlib.sha256((root / relative / name).read_bytes()).hexdigest(), digest, name)

    def test_staging_refuses_a_developer_checkout(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as tmp:
            with patch.object(staging.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)):
                with self.assertRaisesRegex(ValueError, 'disposable'):
                    staging.stage(Path(tmp), 'a' * 40)

    def test_missing_license_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.make_source(root)
            (root / 'rust/keepassxc/LICENSE').unlink()
            with self.assertRaisesRegex(ValueError, 'Missing license'):
                staging.stage(root, 'a' * 40)
