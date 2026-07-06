import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:manyui/manyui.dart';

import 'state/recent_database.dart';
import 'state/vault_state_provider.dart';
import 'theme.dart';
import 'unlock/unlock_page.dart';
import 'vault/vault_page.dart';

class ManyKeeApp extends ConsumerWidget {
  const ManyKeeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final vault = ref.watch(vaultStateProvider);
    ref.watch(recentDatabasesLoaderProvider);
    ref.watch(recentDatabasesPersistenceProvider);
    return MWidgetsApp(
      title: 'ManyKee',
      theme: MThemeData.light(),
      darkTheme: MThemeData.dark(),
      themeMode: mode,
      debugShowCheckedModeBanner: false,
      home: vault.isLocked ? const UnlockPage() : const VaultPage(),
    );
  }
}
