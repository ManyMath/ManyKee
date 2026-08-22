/// Platform adapter: picks the vault state implementation at compile time so
/// `flutter build web` never sees dart:ffi (and native never sees js).
library;

export 'web_vault_state.dart'
    if (dart.library.ffi) 'native_vault_state.dart'
    show createVaultState;
