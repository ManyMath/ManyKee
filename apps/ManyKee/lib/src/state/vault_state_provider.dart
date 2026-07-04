import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'manykee_vault_state.dart';
import 'vault_state_factory.dart';

/// The app's single vault state instance.
final vaultStateProvider = ChangeNotifierProvider<ManyKeeVaultState>(
  (ref) => createVaultState(),
);
