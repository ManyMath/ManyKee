import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:keepass_ui/keepass_ui.dart';
import 'package:web/web.dart' as web;

import 'settings_screen.dart';
import '../state/idle_timer.dart';
import '../state/settings_state.dart';
import '../state/web_vault_state.dart';

@JS('chrome.runtime.id')
external JSString? get _chromeRuntimeId;

/// Whether the app is running inside a Chrome extension context.
bool get _isExtensionContext {
  try {
    return _chromeRuntimeId != null;
  } catch (_) {
    return false;
  }
}

@JS('chrome.runtime.sendMessage')
external JSPromise _chromeSendMessage(JSAny message);

/// Sends openFullPage message to the extension background script.
Future<void> _openFullPage() async {
  final message = {'action': 'openFullPage'}.jsify()!;
  await _chromeSendMessage(message).toDart;
}

/// Three-panel vault browser with responsive layout.
///
/// Desktop (>= 960px): sidebar | entry list | entry detail side-by-side.
/// Mobile (< 960px): stacked full-screen views with Navigator push/pop.
class VaultScreen extends StatefulWidget {
  /// Central vault state for group/entry selection and data access.
  final WebVaultState vaultState;
  final SettingsState settingsState;

  const VaultScreen({
    super.key,
    required this.vaultState,
    required this.settingsState,
  });

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  late final ClipboardManager _clipboardManager;
  late final IdleTimer _idleTimer;

  /// Mobile navigation state.
  _MobileView _mobileView = _MobileView.groups;

  @override
  void initState() {
    super.initState();
    _clipboardManager = ClipboardManager();
    _idleTimer = IdleTimer();
    _idleTimer.updateTimeout(widget.settingsState.autoLockTimeout);
    _idleTimer.start(() => widget.vaultState.lock());
  }

  @override
  void dispose() {
    _idleTimer.dispose();
    _clipboardManager.dispose();
    super.dispose();
  }

  Future<String> _fetchPassword(String entryUuid) async {
    return await widget.vaultState.readEntryField(entryUuid, 'Password') ?? '';
  }

  void _onGroupSelected(VaultGroup group) {
    widget.vaultState.selectGroup(group);
    setState(() => _mobileView = _MobileView.entries);
  }

  void _onEntrySelected(VaultEntry entry) {
    widget.vaultState.selectEntry(entry);
    setState(() => _mobileView = _MobileView.detail);
  }

  Map<String, dynamic> _extractCustomFields(Map<String, dynamic> fields) {
    final customFields = <String, dynamic>{};
    final rawCustomData = fields['custom_data'];
    if (rawCustomData is Map) {
      for (final entry in rawCustomData.entries) {
        customFields[entry.key.toString()] = entry.value;
      }
    }
    for (final entry in fields.entries) {
      if (const {
        'Title',
        'UserName',
        'Password',
        'URL',
        'Notes',
        'Tags',
        'custom_data',
        'protected',
      }.contains(entry.key)) {
        continue;
      }
      customFields[entry.key] = entry.value;
    }
    return customFields;
  }

  Set<String> _extractProtectedCustomFields(Map<String, dynamic> fields) {
    final protected = fields['protected'];
    if (protected is! Map) {
      return const <String>{};
    }
    return protected.entries
        .where((entry) => entry.value == true)
        .map((entry) => entry.key.toString())
        .toSet();
  }

  void _showActionError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not complete entry action: $error')),
    );
  }

  Future<void> _saveVault() async {
    final password = await showPasswordPromptDialog(
      context,
      message: 'Re-enter your master password to save the vault.',
    );
    if (password == null) {
      return;
    }
    try {
      await widget.vaultState.saveDatabase(password: password);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vault saved')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save vault: $error')),
      );
    }
  }

  Future<void> _createEntry() async {
    final result = await showEntryFormDialog(
      context,
      title: 'Create Entry',
      submitLabel: 'Create Entry',
    );
    if (result == null) {
      return;
    }

    try {
      final entryUuid = await widget.vaultState.createEntry(
        widget.vaultState.selectedGroup?.uuid ?? '',
      );
      await widget.vaultState.updateEntry(
        entryUuid,
        result.toFields(),
        protectedFields: result.protectedFields,
      );
      if (mounted) {
        setState(() => _mobileView = _MobileView.detail);
      }
    } catch (error) {
      _showActionError(error);
    }
  }

  Future<void> _editEntry() async {
    final entry = widget.vaultState.selectedEntry;
    if (entry == null) {
      return;
    }

    try {
      final fields = await widget.vaultState.readEntryFields(entry.uuid);
      final result = await showEntryFormDialog(
        context,
        title: 'Edit Entry',
        submitLabel: 'Save Entry',
        initialFields: fields,
        customFields: _extractCustomFields(fields),
        protectedCustomFields: _extractProtectedCustomFields(fields),
        fetchFieldValue: (fieldKey) =>
            widget.vaultState.readEntryField(entry.uuid, fieldKey),
      );
      if (result == null) {
        return;
      }

      await widget.vaultState.updateEntry(
        entry.uuid,
        result.toFields(),
        protectedFields: result.protectedFields,
      );
    } catch (error) {
      _showActionError(error);
    }
  }

  Future<void> _moveEntry() async {
    final entry = widget.vaultState.selectedEntry;
    if (entry == null) {
      return;
    }

    try {
      final targetGroupUuid = await showEntryMoveDialog(
        context,
        groups: widget.vaultState.groups,
        initialGroupUuid: widget.vaultState.selectedGroup?.uuid,
      );
      if (targetGroupUuid == null ||
          targetGroupUuid == widget.vaultState.selectedGroup?.uuid) {
        return;
      }

      await widget.vaultState.moveEntry(entry.uuid, targetGroupUuid);
      if (mounted) {
        setState(() => _mobileView = _MobileView.entries);
      }
    } catch (error) {
      _showActionError(error);
    }
  }

  Future<void> _deleteEntry() async {
    final entry = widget.vaultState.selectedEntry;
    if (entry == null) {
      return;
    }

    final confirmed = await showEntryDeleteConfirmation(context);
    if (!confirmed) {
      return;
    }

    try {
      await widget.vaultState.deleteEntry(entry.uuid);
      if (mounted) {
        setState(() => _mobileView = _MobileView.entries);
      }
    } catch (error) {
      _showActionError(error);
    }
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(settingsState: widget.settingsState),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.vaultState, widget.settingsState]),
      builder: (context, _) {
        _idleTimer.updateTimeout(widget.settingsState.autoLockTimeout);
        return Scaffold(
          appBar: _buildTopBar(context),
          body: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 960) {
                return _buildDesktopLayout(context);
              } else {
                return _buildMobileLayout(context);
              }
            },
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildTopBar(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return PreferredSize(
      preferredSize: const Size.fromHeight(48),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(
            bottom: BorderSide(color: colorScheme.outline),
          ),
        ),
        child: Row(
          children: [
            // Mobile back button.
            if (_mobileView != _MobileView.groups)
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
                onPressed: () {
                  setState(() {
                    if (_mobileView == _MobileView.detail) {
                      _mobileView = _MobileView.entries;
                    } else {
                      _mobileView = _MobileView.groups;
                    }
                  });
                },
              ),
            // Vault filename.
            Expanded(
              child: Text(
                widget.vaultState.lastFilename ?? 'Vault',
                style: textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Settings',
              onPressed: () => _openSettings(context),
            ),
            IconButton(
              icon: const Icon(Icons.save_outlined),
              tooltip: 'Save Vault',
              onPressed: widget.vaultState.isDirty ? _saveVault : null,
            ),
            // Open full page button (extension context only).
            if (_isExtensionContext)
              IconButton(
                icon: const Icon(Icons.open_in_new),
                tooltip: 'Open in full tab',
                onPressed: _openFullPage,
              ),
            // Lock button.
            IconButton(
              icon: const Icon(Icons.lock_outline),
              tooltip: 'Lock Vault',
              onPressed: () => widget.vaultState.lock(),
            ),
          ],
        ),
      ),
    );
  }

  /// Whether the search query is active (>= 2 chars).
  bool get _isSearchActive => widget.vaultState.searchQuery.length >= 2;

  /// Handle selecting a search result: navigate to its group and entry.
  void _onSearchResultSelected(VaultEntry entry) {
    // Find the group containing this entry by matching the breadcrumb.
    final targetGroup = _findGroupByBreadcrumb(
      entry.breadcrumb,
      widget.vaultState.groups,
      <String>[],
    );
    if (targetGroup != null) {
      widget.vaultState.selectGroup(targetGroup);
    }
    widget.vaultState.selectEntry(entry);
    widget.vaultState.clearSearch();
    setState(() => _mobileView = _MobileView.detail);
  }

  /// Recursively find a group whose path matches the breadcrumb string.
  VaultGroup? _findGroupByBreadcrumb(
    String? breadcrumb,
    List<VaultGroup> groups,
    List<String> path,
  ) {
    if (breadcrumb == null) return null;
    for (final group in groups) {
      final currentPath = [...path, group.name];
      final currentBreadcrumb =
          ['Root', ...currentPath.skip(path.isEmpty ? 0 : 0)].join(' > ');
      // Check if this group's breadcrumb matches.
      if (breadcrumb.startsWith(currentBreadcrumb)) {
        // Check children for a more specific match.
        final childMatch = _findGroupByBreadcrumb(
          breadcrumb,
          group.children,
          currentPath,
        );
        return childMatch ?? group;
      }
    }
    return null;
  }

  /// Build the search results panel replacing the entry list.
  Widget _buildSearchResults(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final vaultState = widget.vaultState;
    final results = vaultState.searchResults;

    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No matches',
              style: textTheme.titleMedium,
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              "No entries match '${vaultState.searchQuery}'. Try a different search.",
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final entry = results[index];
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _onSearchResultSelected(entry),
            hoverColor: colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md,
                vertical: Spacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (entry.username.isNotEmpty)
                    Text(
                      entry.username,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (entry.breadcrumb != null)
                    Text(
                      entry.breadcrumb!,
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDesktopLayout(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final vaultState = widget.vaultState;

    return Row(
      children: [
        // Left: Group tree sidebar (280px fixed).
        SizedBox(
          width: 280,
          child: ColoredBox(
            color: colorScheme.surfaceContainerLow,
            child: GroupTree(
              groups: vaultState.groups,
              selectedGroup: vaultState.selectedGroup,
              onGroupSelected: _onGroupSelected,
              vaultState: vaultState,
            ),
          ),
        ),
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: colorScheme.outline,
        ),
        // Center: Entry list or search results.
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: Spacing.entryListMinWidth,
            ),
            child: ColoredBox(
              color: colorScheme.surfaceContainerLow,
              child: _isSearchActive
                  ? _buildSearchResults(context)
                  : EntryList(
                      entries: vaultState.entries,
                      selectedEntry: vaultState.selectedEntry,
                      onEntrySelected: _onEntrySelected,
                      groupName:
                          vaultState.selectedGroup?.name ?? 'All Entries',
                      clipboardManager: _clipboardManager,
                      fetchPassword: _fetchPassword,
                      onCreateEntry: _createEntry,
                    ),
            ),
          ),
        ),
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: colorScheme.outline,
        ),
        // Right: Entry detail (flexible).
        Expanded(
          child: vaultState.selectedEntry != null
              ? EntryDetail(
                  entry: vaultState.selectedEntry!,
                  vaultState: vaultState,
                  clipboardManager: _clipboardManager,
                  onUrlTap: (url) =>
                      web.window.open(url, '_blank', 'noopener,noreferrer'),
                  onEditEntry: _editEntry,
                  onMoveEntry: _moveEntry,
                  onDeleteEntry: _deleteEntry,
                )
              : const EntryDetailEmpty(),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final vaultState = widget.vaultState;

    switch (_mobileView) {
      case _MobileView.groups:
        return ColoredBox(
          color: colorScheme.surfaceContainerLow,
          child: GroupTree(
            groups: vaultState.groups,
            selectedGroup: vaultState.selectedGroup,
            onGroupSelected: _onGroupSelected,
            vaultState: vaultState,
          ),
        );
      case _MobileView.entries:
        return ColoredBox(
          color: colorScheme.surfaceContainerLow,
          child: _isSearchActive
              ? _buildSearchResults(context)
              : EntryList(
                  entries: vaultState.entries,
                  selectedEntry: vaultState.selectedEntry,
                  onEntrySelected: _onEntrySelected,
                  groupName: vaultState.selectedGroup?.name ?? 'All Entries',
                  clipboardManager: _clipboardManager,
                  fetchPassword: _fetchPassword,
                  onCreateEntry: _createEntry,
                ),
        );
      case _MobileView.detail:
        return vaultState.selectedEntry != null
            ? EntryDetail(
                entry: vaultState.selectedEntry!,
                vaultState: vaultState,
                clipboardManager: _clipboardManager,
                onUrlTap: (url) =>
                    web.window.open(url, '_blank', 'noopener,noreferrer'),
                onEditEntry: _editEntry,
                onMoveEntry: _moveEntry,
                onDeleteEntry: _deleteEntry,
              )
            : const EntryDetailEmpty();
    }
  }
}

/// Mobile view states for stacked navigation.
enum _MobileView { groups, entries, detail }
