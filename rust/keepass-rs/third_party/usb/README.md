# macOS USB dependency notices

The macOS challenge-response backend uses `rusb 0.9.4` with its `vendored`
feature, which builds the libusb 1.0.27 source included by `libusb1-sys 0.7.0`.
The Rust wrappers use MIT; the embedded libusb source uses LGPL-2.1-or-later.
The full, unmodified notices are included here. `PROVENANCE.json` records the
locked registry archive checksums, source archive URLs, and notice hashes.
The payload staging step includes these files and the archive gate verifies them.
Linux and other existing targets retain the `nusb` feature selection.

No libusb source is patched here. The complete corresponding library source is
inside the pinned libusb1-sys crate archive, including its build scripts.
Binary redistribution needs more than these notices: preserve corresponding
source and the relinkable application/object material required by the chosen
LGPL distribution path, including any modifications and build instructions.
A public precompiled macOS package or application is not release-ready solely
because the native build and runtime tests pass. This maintenance change does
not publish binaries or claim that an application's redistribution requirements
have been satisfied.

See [libusb's license](https://github.com/libusb/libusb/blob/v1.0.27/COPYING),
particularly sections 4 and 6, for the actual redistribution terms.
