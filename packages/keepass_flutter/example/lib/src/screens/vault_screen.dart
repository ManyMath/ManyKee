import 'package:flutter/material.dart';
import 'package:keepass_ui/keepass_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Responsive three-panel vault browser for the native example app.
class NativeVaultScreen extends StatefulWidget {
  final VaultState vaultState;

  /// Callback when the lock button is pressed.
  /// When null, defaults to calling `vaultState.lock()`.
  final VoidCallback? onLockPressed;

  /// Callback when the settings button is pressed.
  /// When null, the button is shown but performs no action.
  final VoidCallback? onSettingsPressed;

  const NativeVaultScreen({
    super.key,
    required this.vaultState,
    this.onLockPressed,
    this.onSettingsPressed,
  });

  @override
  State<NativeVaultScreen> createState() => _NativeVaultScreenState();
}

class _NativeVaultScreenState extends State<NativeVaultScreen> {
  late final ClipboardManager _clipboardManager;

  int _mobileNavIndex = 0;

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

  bool _isMobile(BuildContext context) {
    return MediaQuery.sizeOf(context).width < 600;
  }

  bool get _isSearchActive => widget.vaultState.searchQuery.length >= 2;

  Future<String> _fetchPassword(String entryUuid) async {
    return await widget.vaultState.readEntryField(entryUuid, 'Password') ?? '';
  }

  void _onGroupSelected(VaultGroup group) {
    widget.vaultState.selectGroup(group);
    if (_isMobile(context)) {
      setState(() => _mobileNavIndex = 1);
    }
  }

  void _onEntrySelected(VaultEntry entry) {
    widget.vaultState.selectEntry(entry);
    if (_isMobile(context)) {
      setState(() => _mobileNavIndex = 2);
    }
  }

  /// Handle selecting a search result: navigate to the matching group/entry.
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
    if (_isMobile(context)) {
      setState(() => _mobileNavIndex = 2);
    }
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
      final currentBreadcrumb = ['Root', ...currentPath].join(' > ');
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

  /// Open a URL via url_launcher.
  void _onUrlTap(String url) {
    launchUrl(Uri.parse(url));
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
      if (_isMobile(context) && mounted) {
        setState(() => _mobileNavIndex = 2);
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
      if (_isMobile(context) && mounted) {
        setState(() => _mobileNavIndex = 1);
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
      if (_isMobile(context) && mounted) {
        setState(() => _mobileNavIndex = 1);
      }
    } catch (error) {
      _showActionError(error);
    }
  }

  /// AppBar shared across desktop and tablet layouts.
  AppBar _buildAppBar(BuildContext context, {bool showDrawerButton = false}) {
    return AppBar(
      leading: showDrawerButton
          ? Builder(
              builder: (scaffoldContext) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(scaffoldContext).openDrawer(),
              ),
            )
          : null,
      title: SizedBox(
        width: 300,
        child: VaultSearchBar(vaultState: widget.vaultState),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.lock_outline),
          tooltip: 'Lock Vault',
          onPressed: widget.onLockPressed ?? () => widget.vaultState.lock(),
        ),
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: 'Settings',
          onPressed: widget.onSettingsPressed,
        ),
      ],
    );
  }

  /// Group tree sidebar panel.
  Widget _buildGroupSidebar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colorScheme.surfaceContainerLow,
      child: GroupTree(
        groups: widget.vaultState.groups,
        selectedGroup: widget.vaultState.selectedGroup,
        onGroupSelected: _onGroupSelected,
        vaultState: widget.vaultState,
      ),
    );
  }

  /// Entry list panel (or search results when search is active).
  Widget _buildEntryListPanel(BuildContext context) {
    if (_isSearchActive) {
      return _buildSearchResults(context);
    }
    return EntryList(
      entries: widget.vaultState.entries,
      selectedEntry: widget.vaultState.selectedEntry,
      onEntrySelected: _onEntrySelected,
      groupName: widget.vaultState.selectedGroup?.name ?? 'All Entries',
      clipboardManager: _clipboardManager,
      fetchPassword: _fetchPassword,
      onCreateEntry: _createEntry,
    );
  }

  /// Detail panel (entry detail or empty state).
  Widget _buildDetailPanel(BuildContext context) {
    if (widget.vaultState.selectedEntry != null) {
      return EntryDetail(
        entry: widget.vaultState.selectedEntry!,
        vaultState: widget.vaultState,
        clipboardManager: _clipboardManager,
        onUrlTap: _onUrlTap,
        onEditEntry: _editEntry,
        onMoveEntry: _moveEntry,
        onDeleteEntry: _deleteEntry,
      );
    }
    return const EntryDetailEmpty();
  }

  /// Search results list with breadcrumbs.
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

  /// Desktop layout: three panels side-by-side.
  Widget _buildDesktopLayout(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: _buildAppBar(context),
      body: Row(
        children: [
          SizedBox(
            width: Spacing.sidebarWidth,
            child: _buildGroupSidebar(context),
          ),
          VerticalDivider(width: 1, thickness: 1, color: colorScheme.outline),
          Expanded(
            child: ColoredBox(
              color: colorScheme.surfaceContainerLow,
              child: _buildEntryListPanel(context),
            ),
          ),
          VerticalDivider(width: 1, thickness: 1, color: colorScheme.outline),
          Expanded(child: _buildDetailPanel(context)),
        ],
      ),
    );
  }

  /// Tablet layout: two panels with groups in a Drawer.
  Widget _buildTabletLayout(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: _buildAppBar(context, showDrawerButton: true),
      drawer: Drawer(
        child: SafeArea(child: _buildGroupSidebar(context)),
      ),
      body: Row(
        children: [
          Expanded(
            child: ColoredBox(
              color: colorScheme.surfaceContainerLow,
              child: _buildEntryListPanel(context),
            ),
          ),
          VerticalDivider(width: 1, thickness: 1, color: colorScheme.outline),
          Expanded(child: _buildDetailPanel(context)),
        ],
      ),
    );
  }

  /// Mobile layout: navigation stack using state index.
  Widget _buildMobileLayout(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _mobileNavIndex > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () =>
                    setState(() => _mobileNavIndex = _mobileNavIndex - 1),
              )
            : null,
        title: _mobileNavIndex == 0
            ? const Text('ManyKee')
            : SizedBox(
                width: double.infinity,
                child: VaultSearchBar(vaultState: widget.vaultState),
              ),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: 'Lock Vault',
            onPressed: widget.onLockPressed ?? () => widget.vaultState.lock(),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: widget.onSettingsPressed,
          ),
        ],
      ),
      body: _buildMobileBody(context),
    );
  }

  /// Mobile body content based on navigation index.
  Widget _buildMobileBody(BuildContext context) {
    switch (_mobileNavIndex) {
      case 0:
        return _buildGroupSidebar(context);
      case 1:
        return _buildEntryListPanel(context);
      case 2:
        return _buildDetailPanel(context);
      default:
        return _buildGroupSidebar(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.vaultState,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            if (width > 900) {
              return _buildDesktopLayout(context);
            } else if (width >= 600) {
              return _buildTabletLayout(context);
            } else {
              return _buildMobileLayout(context);
            }
          },
        );
      },
    );
  }
}
