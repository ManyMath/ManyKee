import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:keepass_ui/keepass_ui.dart' show VaultGroup;
import 'package:manyui/manyui.dart';
import 'package:manyui_riverpod/manyui_riverpod.dart';

import '../merge/merge_page.dart';
import '../settings/settings_page.dart';
import '../state/manykee_vault_state.dart';
import '../state/settings_state.dart';
import '../state/vault_state_provider.dart';
import '../theme.dart';
import 'confirm_dialog.dart';
import 'entry_detail.dart';
import 'entry_form_dialog.dart';
import 'entry_list.dart';
import 'group_name_dialog.dart';
import 'group_tree.dart';
import 'move_dialog.dart';
import 'save_password_dialog.dart';
import 'unsaved_changes_dialog.dart';
import 'vault_sessions_dialog.dart';

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

  Future<bool> saveChanges() async {
    final password = await showSavePasswordDialog(context);
    if (password == null) return false;
    try {
      await vault.saveDatabase(password: password);
      if (context.mounted) {
        showMToast(
          context,
          builder: (_) => const Text('Changes saved.'),
          duration: const Duration(seconds: 2),
        );
      }
      return true;
    } catch (error) {
      if (context.mounted) _showActionError(context, error);
      return false;
    }
  }

  Future<void> saveCopyAs() async {
    if (kIsWeb) {
      final password = await showSavePasswordDialog(
        context,
        title: 'Save a copy',
        message: 'Enter the master password for the downloaded database.',
      );
      if (password == null) return;
      try {
        await vault.saveCopyAs(
          filePath: _copyFileName(vault.lastFilename),
          password: password,
        );
        if (context.mounted) {
          showMToast(
            context,
            builder: (_) => const Text('Database copy downloaded.'),
            duration: const Duration(seconds: 2),
          );
        }
      } catch (error) {
        if (context.mounted) _showActionError(context, error);
      }
      return;
    }

    final String? selectedPath;
    try {
      selectedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save a copy as...',
        fileName: _copyFileName(vault.lastFilename),
        type: FileType.custom,
        allowedExtensions: const <String>['kdbx'],
      );
    } catch (error) {
      if (context.mounted) _showActionError(context, error);
      return;
    }
    if (selectedPath == null) return;
    if (!context.mounted) return;

    final password = await showSavePasswordDialog(
      context,
      title: 'Save a copy',
      message: 'Enter the master password for the copied database.',
    );
    if (password == null) return;

    try {
      await vault.saveCopyAs(
        filePath: _ensureKdbxExtension(selectedPath),
        password: password,
      );
      if (context.mounted) {
        showMToast(
          context,
          builder: (_) => const Text('Database copy saved.'),
          duration: const Duration(seconds: 2),
        );
      }
    } catch (error) {
      if (context.mounted) _showActionError(context, error);
    }
  }

  Future<void> discardAndLock() async {
    final confirmed = await showDeleteConfirmDialog(
      context,
      title: 'Discard changes?',
      message: 'Unsaved changes will be lost and the vault will lock.',
      submitLabel: 'Discard',
    );
    if (!confirmed) return;
    await vault.lock();
  }

  Future<void> lock() async {
    if (!vault.isDirty) {
      await vault.lock();
      return;
    }

    final action = await showUnsavedChangesDialog(context);
    if (action == null) return;
    switch (action) {
      case UnsavedChangesAction.save:
        if (await saveChanges()) {
          await vault.lock();
        }
        break;
      case UnsavedChangesAction.discard:
        await vault.lock();
        break;
    }
  }

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
      message: '${group.name} and everything inside it will be deleted.',
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
    final sessions = ref.watch(vaultSessionsControllerProvider);
    final narrowPane = useState(_NarrowPane.groups);
    final actions = _VaultActions(context, vault);

    final filename = vault.lastFilename;
    final currentFilePath = vault.lastFilePath;

    return MScaffold(
      header: MAppHeader(
        title: 'ManyKee',
        subtitle: filename,
        actions: _vaultHeaderActions(
          theme: theme,
          isDirty: vault.isDirty,
          canMerge: currentFilePath != null,
          isDark: ref.watchMThemeMode(themeModeProvider) == MThemeMode.dark,
          onSave: actions.saveChanges,
          onSaveCopy: actions.saveCopyAs,
          onDiscard: actions.discardAndLock,
          onMerge: currentFilePath == null
              ? null
              : () => showMergeDatabasesPage(
                  context,
                  currentFilePath: currentFilePath,
                ),
          onDatabases: sessions == null
              ? null
              : () => showVaultSessionsDialog(context, sessions),
          databaseCount: sessions?.sessionCount ?? 1,
          onToggleTheme: () {
            ref.read(manyKeeSettingsControllerProvider).toggleLightDarkTheme();
          },
          onSettings: () => showSettingsPage(context),
          onLock: actions.lock,
        ),
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

List<Widget> _vaultHeaderActions({
  required MThemeData theme,
  required bool isDirty,
  required bool canMerge,
  required bool isDark,
  required VoidCallback onSave,
  required VoidCallback onSaveCopy,
  required VoidCallback onDiscard,
  required VoidCallback? onMerge,
  required VoidCallback? onDatabases,
  required int databaseCount,
  required VoidCallback onToggleTheme,
  required VoidCallback onSettings,
  required VoidCallback onLock,
}) {
  return <Widget>[
    if (isDirty)
      Text(
        'Unsaved changes',
        style: theme.typography.caption.copyWith(
          color: theme.colors.mutedForeground,
        ),
      ),
    if (isDirty)
      MButton(
        size: MButtonSize.sm,
        onPressed: onSave,
        child: const Text('Save changes'),
      ),
    MButton(
      variant: MButtonVariant.ghost,
      onPressed: onSaveCopy,
      child: const Text('Save a copy...'),
    ),
    if (isDirty)
      MButton(
        variant: MButtonVariant.destructive,
        size: MButtonSize.sm,
        onPressed: onDiscard,
        child: const Text('Discard'),
      ),
    MButton(
      variant: MButtonVariant.ghost,
      onPressed: canMerge ? onMerge : null,
      semanticLabel: 'Merge databases',
      child: const Text('Merge databases…'),
    ),
    MButton(
      variant: MButtonVariant.ghost,
      onPressed: onDatabases,
      child: Text(
        databaseCount > 1 ? 'Databases ($databaseCount)' : 'Databases',
      ),
    ),
    MButton(
      variant: MButtonVariant.ghost,
      onPressed: onToggleTheme,
      semanticLabel: 'Toggle theme',
      child: MIcon(isDark ? MIconData.sun : MIconData.moon),
    ),
    MButton(
      variant: MButtonVariant.ghost,
      onPressed: onSettings,
      child: const Text('Settings'),
    ),
    MButton(
      variant: MButtonVariant.outline,
      onPressed: onLock,
      child: const Text('Lock'),
    ),
  ];
}

String _ensureKdbxExtension(String path) =>
    path.toLowerCase().endsWith('.kdbx') ? path : '$path.kdbx';

String _copyFileName(String? filename) {
  final value = filename == null || filename.trim().isEmpty
      ? 'vault.kdbx'
      : filename.split(RegExp(r'[/\\]')).last;
  if (value.toLowerCase().endsWith('.kdbx')) {
    return '${value.substring(0, value.length - 5)} copy.kdbx';
  }
  return '$value copy.kdbx';
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
            onCreateEntry: vault.selectedGroup == null
                ? null
                : actions.createEntry,
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
                onCreateEntry: vault.selectedGroup == null
                    ? null
                    : actions.createEntry,
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
        style: theme.typography.bodySmall.copyWith(
          color: theme.colors.mutedForeground,
        ),
      ),
    );
  }
}
