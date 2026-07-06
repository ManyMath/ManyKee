import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:keepass_ui/keepass_ui.dart' show VaultGroup;
import 'package:manyui/manyui.dart';

import '../merge/merge_page.dart';
import '../state/manykee_vault_state.dart';
import '../state/vault_state_provider.dart';
import '../theme.dart';
import 'confirm_dialog.dart';
import 'entry_detail.dart';
import 'entry_form_dialog.dart';
import 'entry_list.dart';
import 'group_name_dialog.dart';
import 'group_tree.dart';
import 'move_dialog.dart';

void _showActionError(BuildContext context, Object error) {
  if (!context.mounted) return;
  showMToast(
    context,
    builder: (_) => Text('Could not complete action: $error'),
    duration: const Duration(seconds: 3),
  );
}

/// Bundles the vault-mutation handlers shared by the wide and narrow layouts,
/// so both can wire the same actions into [GroupTree]/[EntryList]/[EntryDetail]
/// without duplicating the dialog-orchestration logic.
class _VaultActions {
  _VaultActions(this.context, this.vault);

  final BuildContext context;
  final ManyKeeVaultState vault;

  Future<void> createEntry() async {
    final groupUuid = vault.selectedGroup?.uuid;
    if (groupUuid == null) return;
    final result = await showEntryFormDialog(
      context,
      title: 'Create Entry',
      submitLabel: 'Create Entry',
    );
    if (result == null) return;
    try {
      final entryUuid = await vault.createEntry(groupUuid);
      await vault.updateEntry(
        entryUuid,
        result.toFields(),
        protectedFields: result.protectedFields,
      );
    } catch (error) {
      if (context.mounted) _showActionError(context, error);
    }
  }

  Future<void> editEntry() async {
    final entry = vault.selectedEntry;
    if (entry == null) return;
    try {
      final fields = await vault.readEntryFields(entry.uuid);
      if (!context.mounted) return;
      final result = await showEntryFormDialog(
        context,
        title: 'Edit Entry',
        submitLabel: 'Save Entry',
        initialFields: fields,
      );
      if (result == null) return;
      await vault.updateEntry(
        entry.uuid,
        result.toFields(),
        protectedFields: result.protectedFields,
      );
    } catch (error) {
      if (context.mounted) _showActionError(context, error);
    }
  }

  Future<void> moveEntry() async {
    final entry = vault.selectedEntry;
    if (entry == null) return;
    final targetGroupUuid = await showMoveDialog(
      context,
      title: 'Move Entry',
      groups: vault.groups,
      initialGroupUuid: vault.selectedGroup?.uuid,
    );
    if (targetGroupUuid == null ||
        targetGroupUuid == vault.selectedGroup?.uuid) {
      return;
    }
    try {
      await vault.moveEntry(entry.uuid, targetGroupUuid);
    } catch (error) {
      if (context.mounted) _showActionError(context, error);
    }
  }

  Future<void> deleteEntry() async {
    final entry = vault.selectedEntry;
    if (entry == null) return;
    final confirmed = await showDeleteConfirmDialog(
      context,
      title: 'Delete entry?',
      message: entry.title.isEmpty ? '(untitled)' : entry.title,
    );
    if (!confirmed) return;
    try {
      await vault.deleteEntry(entry.uuid);
    } catch (error) {
      if (context.mounted) _showActionError(context, error);
    }
  }

  Future<void> createGroup(VaultGroup? parent) async {
    final name = await showGroupNameDialog(
      context,
      title: 'New Group',
      submitLabel: 'Create',
    );
    if (name == null) return;
    try {
      await vault.createGroup(parent?.uuid ?? '', name);
    } catch (error) {
      if (context.mounted) _showActionError(context, error);
    }
  }

  Future<void> renameGroup(VaultGroup group) async {
    final name = await showGroupNameDialog(
      context,
      title: 'Rename Group',
      submitLabel: 'Rename',
      initialValue: group.name,
    );
    if (name == null || name == group.name) return;
    try {
      await vault.renameGroup(group.uuid, name);
    } catch (error) {
      if (context.mounted) _showActionError(context, error);
    }
  }

  Future<void> moveGroup(VaultGroup group) async {
    final targetUuid = await showMoveDialog(
      context,
      title: 'Move Group',
      groups: vault.groups,
      excludeUuid: group.uuid,
    );
    if (targetUuid == null) return;
    try {
      await vault.moveGroup(group.uuid, targetUuid);
    } catch (error) {
      if (context.mounted) _showActionError(context, error);
    }
  }

  Future<void> deleteGroup(VaultGroup group) async {
    final confirmed = await showDeleteConfirmDialog(
      context,
      title: 'Delete group?',
      message:
          '${group.name} and everything inside it will be deleted.',
    );
    if (!confirmed) return;
    try {
      await vault.deleteGroup(group.uuid);
    } catch (error) {
      if (context.mounted) _showActionError(context, error);
    }
  }
}

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
    final currentFilePath = vault.lastFilePath;

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
            onPressed: currentFilePath == null
                ? null
                : () => showMergeDatabasesPage(
                      context,
                      currentFilePath: currentFilePath,
                    ),
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
    final actions = _VaultActions(context, vault);

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
            onAddGroup: actions.createGroup,
            onRenameGroup: actions.renameGroup,
            onMoveGroup: actions.moveGroup,
            onDeleteGroup: actions.deleteGroup,
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
            onCreateEntry:
                vault.selectedGroup == null ? null : actions.createEntry,
          ),
        ),
        const MDivider(orientation: MDividerOrientation.vertical),
        Expanded(
          child: vault.selectedEntry == null
              ? const _EmptyDetail()
              : EntryDetail(
                  entry: vault.selectedEntry!,
                  onEditEntry: actions.editEntry,
                  onMoveEntry: actions.moveEntry,
                  onDeleteEntry: actions.deleteEntry,
                ),
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
    final actions = _VaultActions(context, vault);

    switch (pane.value) {
      case _NarrowPane.groups:
        return GroupTree(
          groups: vault.groups,
          selectedUuid: vault.selectedGroup?.uuid,
          onSelect: (group) {
            vault.selectGroup(group);
            pane.value = _NarrowPane.entries;
          },
          onAddGroup: actions.createGroup,
          onRenameGroup: actions.renameGroup,
          onMoveGroup: actions.moveGroup,
          onDeleteGroup: actions.deleteGroup,
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
                onCreateEntry:
                    vault.selectedGroup == null ? null : actions.createEntry,
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
              child: entry == null
                  ? const _EmptyDetail()
                  : EntryDetail(
                      entry: entry,
                      onEditEntry: actions.editEntry,
                      onMoveEntry: actions.moveEntry,
                      onDeleteEntry: actions.deleteEntry,
                    ),
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
