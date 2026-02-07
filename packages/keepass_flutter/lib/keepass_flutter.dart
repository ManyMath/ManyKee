/// Flutter plugin for KeePass -- re-exports package:keepass.
///
/// In Flutter apps, depend on keepass_flutter (not keepass directly)
/// so cargokit builds the native library automatically.
library keepass_flutter;

export 'package:keepass/keepass.dart';
export 'src/state/local_file_storage_provider.dart';
export 'src/state/native_vault_state.dart';
