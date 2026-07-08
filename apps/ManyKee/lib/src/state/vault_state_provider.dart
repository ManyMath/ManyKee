import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'manykee_vault_state.dart';
import 'vault_state_factory.dart';
import 'vault_sessions.dart';

/// The app's active vault state.
///
/// In production this is a [VaultSessionsController], which can keep multiple
/// database sessions open and delegates this legacy state contract to the
/// active session. Tests may still override it with a single fake
/// [ManyKeeVaultState].
final vaultStateProvider = ChangeNotifierProvider<ManyKeeVaultState>(
  (ref) => VaultSessionsController(createVaultState),
);

final vaultSessionsControllerProvider = Provider<VaultSessionsController?>((
  ref,
) {
  final vault = ref.watch(vaultStateProvider);
  return vault is VaultSessionsController ? vault : null;
});
