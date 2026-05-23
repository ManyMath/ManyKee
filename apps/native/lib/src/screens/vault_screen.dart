import 'package:flutter/material.dart';
import 'package:keepass_ui/keepass_ui.dart';
import 'package:url_launcher/url_launcher.dart';

class NativeVaultScreen extends StatefulWidget {
  final VaultState vaultState;

  final VoidCallback? onLockPressed;
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
    final fields = await widget.vaultState.readEntryFields(entryUuid);
    return fields['Password'] as String? ?? '';
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
      }.contains(entry.key)) {
        continue;
      }
      customFields[entry.key] = entry.value;
    }
    return customFields;
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
          icon: const Icon(Icons.save_outlined),
          tooltip: 'Save Vault',
          onPressed: widget.vaultState.isDirty ? _saveVault : null,
        ),
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
            icon: const Icon(Icons.save_outlined),
            tooltip: 'Save Vault',
            onPressed: widget.vaultState.isDirty ? _saveVault : null,
          ),
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
