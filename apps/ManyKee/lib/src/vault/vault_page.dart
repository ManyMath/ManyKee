import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:manyui/manyui.dart';

import '../merge/merge_page.dart';
import '../state/vault_state_provider.dart';
import '../theme.dart';
import 'entry_detail.dart';
import 'entry_list.dart';
import 'group_tree.dart';

/// Which pane the stacked (narrow) layout is showing.
enum _NarrowPane { groups, entries, detail }

/// Read-only vault browser: group tree, entry list, entry detail.
///
/// Wide (>= 900px): three panes side by side. Narrow: stacked navigation
/// with back buttons.
class VaultPage extends HookConsumerWidget {
  const VaultPage({super.key});

  static const double _wideBreakpoint = 900;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = MTheme.of(context);
    final vault = ref.watch(vaultStateProvider);
    final narrowPane = useState(_NarrowPane.groups);

    final filename = vault.lastFilename;

    return MScaffold(
      header: Row(
        children: <Widget>[
          Text('ManyKee', style: theme.typography.title),
          if (filename != null) ...[
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                filename,
                style: theme.typography.bodySmall
                    .copyWith(color: theme.colors.mutedForeground),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          const Spacer(),
          MButton(
            variant: MButtonVariant.ghost,
            onPressed: () => showMergeDatabasesPage(context),
            semanticLabel: 'Merge databases',
            child: const Text('Merge databases…'),
          ),
          const SizedBox(width: 8),
          MButton(
            variant: MButtonVariant.ghost,
            onPressed: () {
              final mode = ref.read(themeModeProvider);
              ref.read(themeModeProvider.notifier).state =
                  mode == MThemeMode.dark ? MThemeMode.light : MThemeMode.dark;
            },
            semanticLabel: 'Toggle theme',
            child: MIcon(ref.watch(themeModeProvider) == MThemeMode.dark
                ? MIconData.sun
                : MIconData.moon),
          ),
          const SizedBox(width: 8),
          MButton(
            variant: MButtonVariant.outline,
            onPressed: () => vault.lock(),
            child: const Text('Lock'),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= _wideBreakpoint) {
            return _WideLayout(narrowPane: narrowPane);
          }
          return _NarrowLayout(pane: narrowPane);
        },
      ),
    );
  }
}

class _WideLayout extends ConsumerWidget {
  const _WideLayout({required this.narrowPane});

  /// Kept in sync so shrinking the window lands on a sensible pane.
  final ValueNotifier<_NarrowPane> narrowPane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vault = ref.watch(vaultStateProvider);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          width: 260,
          child: GroupTree(
            groups: vault.groups,
            selectedUuid: vault.selectedGroup?.uuid,
            onSelect: (group) {
              narrowPane.value = _NarrowPane.entries;
              vault.selectGroup(group);
            },
          ),
        ),
        const MDivider(orientation: MDividerOrientation.vertical),
        SizedBox(
          width: 320,
          child: EntryList(
            entries: vault.entries,
            selectedUuid: vault.selectedEntry?.uuid,
            onSelect: (entry) {
              narrowPane.value = _NarrowPane.detail;
              vault.selectEntry(entry);
            },
          ),
        ),
        const MDivider(orientation: MDividerOrientation.vertical),
        Expanded(
          child: vault.selectedEntry == null
              ? const _EmptyDetail()
              : EntryDetail(entry: vault.selectedEntry!),
        ),
      ],
    );
  }
}

class _NarrowLayout extends ConsumerWidget {
  const _NarrowLayout({required this.pane});

  final ValueNotifier<_NarrowPane> pane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vault = ref.watch(vaultStateProvider);

    switch (pane.value) {
      case _NarrowPane.groups:
        return GroupTree(
          groups: vault.groups,
          selectedUuid: vault.selectedGroup?.uuid,
          onSelect: (group) {
            vault.selectGroup(group);
            pane.value = _NarrowPane.entries;
          },
        );
      case _NarrowPane.entries:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _BackBar(
              label: vault.selectedGroup?.name ?? 'Entries',
              onBack: () => pane.value = _NarrowPane.groups,
            ),
            const MDivider(),
            Expanded(
              child: EntryList(
                entries: vault.entries,
                selectedUuid: vault.selectedEntry?.uuid,
                onSelect: (entry) {
                  vault.selectEntry(entry);
                  pane.value = _NarrowPane.detail;
                },
              ),
            ),
          ],
        );
      case _NarrowPane.detail:
        final entry = vault.selectedEntry;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _BackBar(
              label: entry?.title ?? 'Entry',
              onBack: () => pane.value = _NarrowPane.entries,
            ),
            const MDivider(),
            Expanded(
              child:
                  entry == null ? const _EmptyDetail() : EntryDetail(entry: entry),
            ),
          ],
        );
    }
  }
}

class _BackBar extends StatelessWidget {
  const _BackBar({required this.label, required this.onBack});

  final String label;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = MTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: <Widget>[
          MButton(
            variant: MButtonVariant.ghost,
            size: MButtonSize.sm,
            onPressed: onBack,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                MIcon(MIconData.chevronLeft, size: 14),
                const SizedBox(width: 4),
                const Text('Back'),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: theme.typography.body,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail();

  @override
  Widget build(BuildContext context) {
    final theme = MTheme.of(context);
    return Center(
      child: Text(
        'Select an entry',
        style: theme.typography.bodySmall
            .copyWith(color: theme.colors.mutedForeground),
      ),
    );
  }
}
