import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:keepass_ui/keepass_ui.dart' show VaultEntry, VaultGroup;
import 'package:manyui/manyui.dart';
import 'package:manyui_riverpod/manyui_riverpod.dart';

import '../merge/merge_page.dart';
import '../settings/settings_page.dart';
import '../state/manykee_vault_state.dart';
import '../state/settings_state.dart';
import '../state/vault_state_provider.dart';
import '../state/vault_sessions.dart';
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
    final groupUuid = vault.selectedGroup?.uuid ?? '';
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
        loadProtectedField: (fieldName) =>
            vault.readEntryField(entry.uuid, fieldName),
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
    final currentGroupUuid = vault.selectedGroup?.uuid ?? '';
    final targetGroupUuid = await showMoveDialog(
      context,
      title: 'Move Entry',
      groups: vault.groups,
      initialGroupUuid: currentGroupUuid,
    );
    if (targetGroupUuid == null || targetGroupUuid == currentGroupUuid) {
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
/// Adapts from a resizable three-pane desktop workbench to a two-pane tablet
/// layout and stacked navigation on phones.
class VaultPage extends HookConsumerWidget {
  const VaultPage({super.key});

  static const double _wideBreakpoint = 1100;
  static const double _mediumBreakpoint = 680;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vault = ref.watch(vaultStateProvider);
    final sessions = ref.watch(vaultSessionsControllerProvider);
    final narrowPane = useState(
      vault.groups.isEmpty ? _NarrowPane.entries : _NarrowPane.groups,
    );
    final mediumShowsGroups = useState(vault.groups.isNotEmpty);
    final actions = _VaultActions(context, vault);

    final filename = vault.lastFilename;
    final currentFilePath = vault.lastFilePath;

    return MScaffold(
      header: MAppHeader(
        title: 'ManyKee',
        subtitle: filename,
        actions: _vaultHeaderActions(
          isDirty: vault.isDirty,
          canMerge: vault.supportsDatabaseMerge && currentFilePath != null,
          isDark: ref.watchMThemeMode(themeModeProvider) == MThemeMode.dark,
          onSave: actions.saveChanges,
          onSaveCopy: actions.saveCopyAs,
          onDiscard: actions.discardAndLock,
          onMerge: !vault.supportsDatabaseMerge || currentFilePath == null
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
          if (constraints.maxWidth >= _mediumBreakpoint) {
            return _MediumLayout(
              narrowPane: narrowPane,
              showsGroups: mediumShowsGroups,
            );
          }
          return _NarrowLayout(pane: narrowPane);
        },
      ),
    );
  }
}

List<Widget> _vaultHeaderActions({
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
      const MBadge(
        variant: MBadgeVariant.secondary,
        child: Text('Unsaved · auto-lock paused'),
      ),
    if (isDirty)
      MButton(
        size: MButtonSize.sm,
        onPressed: onSave,
        child: const Text('Save changes'),
      ),
    _VaultHeaderMenu(
      isDirty: isDirty,
      canMerge: canMerge,
      databaseCount: databaseCount,
      onSaveCopy: onSaveCopy,
      onDiscard: onDiscard,
      onMerge: onMerge,
      onDatabases: onDatabases,
    ),
    MIconButton(
      icon: isDark ? MIconData.sun : MIconData.moon,
      label: 'Toggle theme',
      onPressed: onToggleTheme,
    ),
    MIconButton(
      icon: MIconData.settings,
      label: 'Settings',
      onPressed: onSettings,
    ),
    MButton(
      variant: MButtonVariant.outline,
      onPressed: onLock,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          MIcon(MIconData.lock, size: 15),
          SizedBox(width: 7),
          Text('Lock'),
        ],
      ),
    ),
  ];
}

class _VaultHeaderMenu extends HookWidget {
  const _VaultHeaderMenu({
    required this.isDirty,
    required this.canMerge,
    required this.databaseCount,
    required this.onSaveCopy,
    required this.onDiscard,
    required this.onMerge,
    required this.onDatabases,
  });

  final bool isDirty;
  final bool canMerge;
  final int databaseCount;
  final VoidCallback onSaveCopy;
  final VoidCallback onDiscard;
  final VoidCallback? onMerge;
  final VoidCallback? onDatabases;

  @override
  Widget build(BuildContext context) {
    final controller = useMemoized(MPopoverController.new);
    useEffect(() => controller.dispose, const <Object?>[]);

    void run(VoidCallback callback) {
      controller.close();
      callback();
    }

    return MPopover(
      controller: controller,
      semanticLabel: 'Vault actions',
      popoverBuilder: (context, close) => SizedBox(
        width: 220,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _HeaderMenuAction(
              icon: MIconData.copy,
              label: 'Save a copy…',
              onPressed: () => run(onSaveCopy),
            ),
            if (canMerge && onMerge != null)
              _HeaderMenuAction(
                icon: MIconData.network,
                label: 'Merge databases…',
                onPressed: () => run(onMerge!),
              ),
            if (onDatabases != null)
              _HeaderMenuAction(
                icon: MIconData.folder,
                label: databaseCount > 1
                    ? 'Databases ($databaseCount)'
                    : 'Databases',
                onPressed: () => run(onDatabases!),
              ),
            if (isDirty)
              _HeaderMenuAction(
                icon: MIconData.trash,
                label: 'Discard changes',
                destructive: true,
                onPressed: () => run(onDiscard),
              ),
          ],
        ),
      ),
      child: MIconButton(
        icon: MIconData.moreHorizontal,
        label: 'Vault actions',
        onPressed: controller.toggle,
      ),
    );
  }
}

class _HeaderMenuAction extends StatelessWidget {
  const _HeaderMenuAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final MIconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return MButton(
      variant: destructive ? MButtonVariant.destructive : MButtonVariant.ghost,
      onPressed: onPressed,
      child: Row(
        children: <Widget>[
          MIcon(icon, size: 15),
          const SizedBox(width: 8),
          Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
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

List<VaultEntry> _visibleEntries(ManyKeeVaultState vault) =>
    vault.searchQuery.trim().isEmpty ? vault.entries : vault.searchResults;

final Expando<int> _entryNavigationGenerations = Expando<int>(
  'entry navigation generation',
);

Future<void> _selectEntryInOwningGroup(
  ManyKeeVaultState vault,
  VaultEntry entry,
) async {
  final generation = (_entryNavigationGenerations[vault] ?? 0) + 1;
  _entryNavigationGenerations[vault] = generation;
  vault.cancelPendingGroupSelection();
  final targetGroupUuid = entry.groupUuid;
  final currentGroupUuid = vault.selectedGroup?.uuid ?? '';
  if (targetGroupUuid != null && targetGroupUuid != currentGroupUuid) {
    if (targetGroupUuid.isEmpty) {
      await vault.selectRoot();
    } else {
      final group = _findGroup(vault.groups, targetGroupUuid);
      if (group == null) return;
      await vault.selectGroup(group);
    }
  }
  if (_entryNavigationGenerations[vault] != generation) return;
  vault.selectEntry(entry);
}

VaultGroup? _findGroup(List<VaultGroup> groups, String uuid) {
  for (final group in groups) {
    if (group.uuid == uuid) return group;
    final child = _findGroup(group.children, uuid);
    if (child != null) return child;
  }
  return null;
}

String _entryPaneTitle(ManyKeeVaultState vault) {
  if (vault.searchQuery.trim().isNotEmpty) return 'Search results';
  return vault.selectedGroup?.name ?? 'Vault root';
}

Object _sessionIdentity(ManyKeeVaultState vault) =>
    vault is VaultSessionsController ? vault.activeVault : vault;

class _WideLayout extends ConsumerWidget {
  const _WideLayout({required this.narrowPane});

  /// Kept in sync so shrinking the window lands on a sensible pane.
  final ValueNotifier<_NarrowPane> narrowPane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vault = ref.watch(vaultStateProvider);
    final actions = _VaultActions(context, vault);

    return MResizable(
      semanticLabel: 'Vault workspace panes',
      initialSizes: const <double>[0.22, 0.3, 0.48],
      children: <MResizableChild>[
        MResizableChild(
          id: 'groups',
          minSize: 0.16,
          maxSize: 0.36,
          child: GroupTree(
            groups: vault.groups,
            selectedUuid: vault.selectedGroup?.uuid,
            rootSelected: vault.selectedGroup == null,
            onSelectRoot: () {
              vault.clearSearch();
              narrowPane.value = _NarrowPane.entries;
              vault.selectRoot();
            },
            onSelect: (group) {
              vault.clearSearch();
              narrowPane.value = _NarrowPane.entries;
              vault.selectGroup(group);
            },
            onAddGroup: actions.createGroup,
            onRenameGroup: actions.renameGroup,
            onMoveGroup: actions.moveGroup,
            onDeleteGroup: actions.deleteGroup,
          ),
        ),
        MResizableChild(
          id: 'entries',
          minSize: 0.22,
          maxSize: 0.5,
          child: EntryList(
            entries: _visibleEntries(vault),
            selectedUuid: vault.selectedEntry?.uuid,
            title: _entryPaneTitle(vault),
            searchQuery: vault.searchQuery,
            searchIndexReady: vault.allEntriesCached,
            onSearchChanged: vault.search,
            onSelect: (entry) async {
              narrowPane.value = _NarrowPane.detail;
              await _selectEntryInOwningGroup(vault, entry);
            },
            onCreateEntry: actions.createEntry,
          ),
        ),
        MResizableChild(
          id: 'detail',
          minSize: 0.28,
          child: vault.selectedEntry == null
              ? const _EmptyDetail()
              : EntryDetail(
                  key: ValueKey<(Object, String)>((
                    _sessionIdentity(vault),
                    vault.selectedEntry!.uuid,
                  )),
                  entry: vault.selectedEntry!,
                  sessionIdentity: _sessionIdentity(vault),
                  onEditEntry: actions.editEntry,
                  onMoveEntry: actions.moveEntry,
                  onDeleteEntry: actions.deleteEntry,
                ),
        ),
      ],
    );
  }
}

class _MediumLayout extends ConsumerWidget {
  const _MediumLayout({required this.narrowPane, required this.showsGroups});

  final ValueNotifier<_NarrowPane> narrowPane;
  final ValueNotifier<bool> showsGroups;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vault = ref.watch(vaultStateProvider);
    final actions = _VaultActions(context, vault);

    final entryList = EntryList(
      entries: _visibleEntries(vault),
      selectedUuid: vault.selectedEntry?.uuid,
      title: _entryPaneTitle(vault),
      searchQuery: vault.searchQuery,
      searchIndexReady: vault.allEntriesCached,
      onSearchChanged: vault.search,
      onShowGroups: showsGroups.value ? null : () => showsGroups.value = true,
      onSelect: (entry) async {
        narrowPane.value = _NarrowPane.detail;
        await _selectEntryInOwningGroup(vault, entry);
        showsGroups.value = false;
      },
      onCreateEntry: actions.createEntry,
    );

    if (showsGroups.value) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            width: 280,
            child: GroupTree(
              groups: vault.groups,
              selectedUuid: vault.selectedGroup?.uuid,
              rootSelected: vault.selectedGroup == null,
              onSelectRoot: () {
                vault.clearSearch();
                vault.selectRoot();
              },
              onSelect: (group) {
                vault.clearSearch();
                vault.selectGroup(group);
              },
              onAddGroup: actions.createGroup,
              onRenameGroup: actions.renameGroup,
              onMoveGroup: actions.moveGroup,
              onDeleteGroup: actions.deleteGroup,
            ),
          ),
          const MDivider(orientation: MDividerOrientation.vertical),
          Expanded(child: entryList),
        ],
      );
    }

    return MResizable(
      semanticLabel: 'Entries and entry detail panes',
      initialSizes: const <double>[0.4, 0.6],
      children: <MResizableChild>[
        MResizableChild(
          id: 'entries',
          minSize: 0.32,
          maxSize: 0.58,
          child: entryList,
        ),
        MResizableChild(
          id: 'detail',
          minSize: 0.42,
          child: vault.selectedEntry == null
              ? const _EmptyDetail()
              : EntryDetail(
                  key: ValueKey<(Object, String)>((
                    _sessionIdentity(vault),
                    vault.selectedEntry!.uuid,
                  )),
                  entry: vault.selectedEntry!,
                  sessionIdentity: _sessionIdentity(vault),
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
          rootSelected: vault.selectedGroup == null,
          onSelectRoot: () {
            vault.clearSearch();
            vault.selectRoot();
            pane.value = _NarrowPane.entries;
          },
          onSelect: (group) {
            vault.clearSearch();
            vault.selectGroup(group);
            pane.value = _NarrowPane.entries;
          },
          onAddGroup: actions.createGroup,
          onRenameGroup: actions.renameGroup,
          onMoveGroup: actions.moveGroup,
          onDeleteGroup: actions.deleteGroup,
        );
      case _NarrowPane.entries:
        return EntryList(
          entries: _visibleEntries(vault),
          selectedUuid: vault.selectedEntry?.uuid,
          title: _entryPaneTitle(vault),
          searchQuery: vault.searchQuery,
          searchIndexReady: vault.allEntriesCached,
          onSearchChanged: vault.search,
          onShowGroups: () => pane.value = _NarrowPane.groups,
          onSelect: (entry) async {
            await _selectEntryInOwningGroup(vault, entry);
            pane.value = _NarrowPane.detail;
          },
          onCreateEntry: actions.createEntry,
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
                      key: ValueKey<(Object, String)>((
                        _sessionIdentity(vault),
                        entry.uuid,
                      )),
                      entry: entry,
                      sessionIdentity: _sessionIdentity(vault),
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
          MIconButton(
            icon: MIconData.chevronLeft,
            label: 'Back',
            size: MButtonSize.sm,
            onPressed: onBack,
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
    return const Center(child: MEmptyState(title: 'Select an entry'));
  }
}
