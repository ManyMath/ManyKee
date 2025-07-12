import 'package:flutter/material.dart';
import 'package:keepass_ui/keepass_ui.dart';

import '../state/native_vault_state.dart';

/// Minimal three-panel vault browser for the native example app.
///
/// Desktop-only layout for Phase 8 scaffold:
/// - Left: GroupTree sidebar (280px)
/// - Center: EntryList (expanded)
/// - Right: EntryDetail or EntryDetailEmpty (expanded)
///
/// No responsive breakpoints, auto-lock, settings, or lock button -- Phase 9.
class NativeVaultScreen extends StatefulWidget {
  final NativeVaultState vaultState;

  const NativeVaultScreen({
    super.key,
    required this.vaultState,
  });

  @override
  State<NativeVaultScreen> createState() => _NativeVaultScreenState();
}

class _NativeVaultScreenState extends State<NativeVaultScreen> {
  late final ClipboardManager _clipboardManager;

  @override
  void initState() {
    super.initState();
    _clipboardManager = ClipboardManager();
  }

  @override
  void dispose() {
    _clipboardManager.dispose();
    super.dispose();
  }

  Future<String> _fetchPassword(String entryUuid) async {
    final fields = await widget.vaultState.readEntryFields(entryUuid);
    return fields['Password'] as String? ?? '';
  }

  void _onGroupSelected(VaultGroup group) {
    widget.vaultState.selectGroup(group);
  }

  void _onEntrySelected(VaultEntry entry) {
    widget.vaultState.selectEntry(entry);
  }

  /// Whether the search query is active (>= 2 chars).
  bool get _isSearchActive =>
      widget.vaultState.searchQuery.length >= 2;

  /// Handle selecting a search result.
  void _onSearchResultSelected(VaultEntry entry) {
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
          ['Root', ...currentPath].join(' > ');
      if (breadcrumb.startsWith(currentBreadcrumb)) {
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

  Widget _buildSearchResults(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final results = widget.vaultState.searchResults;

    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('No matches', style: textTheme.titleMedium),
            const SizedBox(height: Spacing.sm),
            Text(
              "No entries match '${widget.vaultState.searchQuery}'. Try a different search.",
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final vaultState = widget.vaultState;

    return ListenableBuilder(
      listenable: vaultState,
      builder: (context, _) {
        return Scaffold(
          body: Row(
            children: [
              // Left: Group tree sidebar (280px fixed).
              SizedBox(
                width: Spacing.sidebarWidth,
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
                        onUrlTap: null,
                      )
                    : const EntryDetailEmpty(),
              ),
            ],
          ),
        );
      },
    );
  }
}
