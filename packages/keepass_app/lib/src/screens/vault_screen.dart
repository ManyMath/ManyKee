import 'package:flutter/material.dart';

import '../models/vault_entry.dart';
import '../models/vault_group.dart';
import '../state/clipboard_manager.dart';
import '../state/vault_state.dart';
import '../theme/spacing.dart';
import '../widgets/entry_detail.dart';
import '../widgets/entry_list.dart';
import '../widgets/group_tree.dart';

/// Three-panel vault browser with responsive layout.
///
/// Desktop (>= 960px): sidebar | entry list | entry detail side-by-side.
/// Mobile (< 960px): stacked full-screen views with Navigator push/pop.
class VaultScreen extends StatefulWidget {
  /// Central vault state for group/entry selection and data access.
  final VaultState vaultState;

  const VaultScreen({
    super.key,
    required this.vaultState,
  });

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  late final ClipboardManager _clipboardManager;

  /// Mobile navigation state.
  _MobileView _mobileView = _MobileView.groups;

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
    setState(() => _mobileView = _MobileView.entries);
  }

  void _onEntrySelected(VaultEntry entry) {
    widget.vaultState.selectEntry(entry);
    setState(() => _mobileView = _MobileView.detail);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.vaultState,
      builder: (context, _) {
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
            // Settings placeholder (Plan 04).
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Settings',
              onPressed: () {
                // Placeholder for Plan 04 (timeout config).
              },
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
            ),
          ),
        ),
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: colorScheme.outline,
        ),
        // Center: Entry list (flexible, min 320px).
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: Spacing.entryListMinWidth,
            ),
            child: ColoredBox(
              color: colorScheme.surfaceContainerLow,
              child: EntryList(
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
          ),
        );
      case _MobileView.entries:
        return ColoredBox(
          color: colorScheme.surfaceContainerLow,
          child: EntryList(
            entries: vaultState.entries,
            selectedEntry: vaultState.selectedEntry,
            onEntrySelected: _onEntrySelected,
            groupName:
                vaultState.selectedGroup?.name ?? 'All Entries',
            clipboardManager: _clipboardManager,
            fetchPassword: _fetchPassword,
          ),
        );
      case _MobileView.detail:
        return vaultState.selectedEntry != null
            ? EntryDetail(
                entry: vaultState.selectedEntry!,
                vaultState: vaultState,
                clipboardManager: _clipboardManager,
              )
            : const EntryDetailEmpty();
    }
  }
}

/// Mobile view states for stacked navigation.
enum _MobileView { groups, entries, detail }
