/// Flutter plugin for KeePass: re-exports package:keepass and ships the
/// Rust native library built and bundled via cargokit.
///
/// In Flutter apps, depend on keepass_flutter (not keepass directly) so
/// cargokit builds and bundles the native library automatically across
/// Android, iOS, Linux, macOS, and Windows.
library keepass_flutter;

export 'package:keepass/keepass.dart';
