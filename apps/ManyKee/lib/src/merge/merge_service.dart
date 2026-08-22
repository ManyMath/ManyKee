/// Platform adapter for the merge-databases flow, mirroring
/// `state/vault_state_factory.dart`: the native implementation opens
/// databases through `package:keepass`'s direct FFI `Database` bindings
/// (`dart:ffi`), so it must never be pulled into the web build.
library;

export 'merge_service_web.dart'
    if (dart.library.ffi) 'merge_service_native.dart'
    show MergeResult, MergeService, MergeServiceResult, createMergeService;
