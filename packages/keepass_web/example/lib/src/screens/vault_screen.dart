import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:keepass_ui/keepass_ui.dart';
import 'package:web/web.dart' as web;

import '../state/idle_timer.dart';
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

enum _MobileView { groups, entries, detail }

/// Three-panel vault browser with responsive layout.
class VaultScreen extends StatefulWidget {
 /// Central vault state for group/entry selection and data access.
 final WebVaultState vaultState;

 const VaultScreen({
 super.key,
 required this.vaultState,
 });

 @override
 State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
 late final ClipboardManager _clipboardManager;
 late final IdleTimer _idleTimer;

int? _selectedTimeoutMinutes = 5;

 _MobileView _mobileView = _MobileView.groups;

 /// Timeout options for the settings dropdown.
 static const List<({String label, int? minutes})> _timeoutOptions = [
 (label: '1 min', minutes: 1),
 (label: '5 min', minutes: 5),
 (label: '15 min', minutes: 15),
 (label: '30 min', minutes: 30),
 (label: 'Never', minutes: null),
 ];

@override
 void initState() {
 super.initState();
 _clipboardManager = ClipboardManager();
 _idleTimer = IdleTimer();

 final stored =
 web.window.localStorage.getItem('manykee_idle_timeout');
 if (stored != null) {
 if (stored == 'never') {
 _selectedTimeoutMinutes = null;
 _idleTimer.updateTimeout(const Duration(days: 365));
 } else {
 final minutes = int.tryParse(stored);
 if (minutes != null) {
 _selectedTimeoutMinutes = minutes;
 _idleTimer.updateTimeout(Duration(minutes: minutes));
 }
 }
 }

 _idleTimer.start(() => widget.vaultState.lock());
 }

 @override
 void dispose() {
 _idleTimer.dispose();
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
 Expanded(
 child: Text(
 widget.vaultState.lastFilename ?? 'Vault',
 style: textTheme.titleMedium,
 overflow: TextOverflow.ellipsis,
 ),
 ),
 PopupMenuButton<int?>(
 icon: const Icon(Icons.settings),
 tooltip: 'Settings',
onSelected: (minutes) {
 setState(() => _selectedTimeoutMinutes = minutes);
 if (minutes == null) {
 _idleTimer.updateTimeout(const Duration(days: 365));
 web.window.localStorage
 .setItem('manykee_idle_timeout', 'never');
 } else {
 _idleTimer.updateTimeout(Duration(minutes: minutes));
 web.window.localStorage
 .setItem('manykee_idle_timeout', minutes.toString());
 }
 },
 itemBuilder: (context) => [
 PopupMenuItem<int?>(
 enabled: false,
 child: Text(
 'Auto-lock after',
 style: Theme.of(context).textTheme.labelSmall?.copyWith(
 color: Theme.of(context).colorScheme.onSurface,
 fontWeight: FontWeight.w600,
 ),
 ),
 ),
 const PopupMenuDivider(),
 for (final option in _timeoutOptions)
 CheckedPopupMenuItem<int?>(
 value: option.minutes,
 checked: _selectedTimeoutMinutes == option.minutes,
 child: Text(option.label),
 ),
],
 ),
 if (_isExtensionContext)
 IconButton(
 icon: const Icon(Icons.open_in_new),
 tooltip: 'Open in full tab',
onPressed: _openFullPage,
 ),
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

bool get _isSearchActive =>
 widget.vaultState.searchQuery.length >= 2;

 /// Handle selecting a search result: navigate to its group and entry.
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
 final currentBreadcrumb = ['Root', ...currentPath.skip(path.isEmpty ? 0 : 0)].join(' > ');
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
 ),
 ),
 ),
 ),
 VerticalDivider(
width: 1,
 thickness: 1,
 color: colorScheme.outline,
 ),
 Expanded(
 child: vaultState.selectedEntry != null
 ? EntryDetail(
 entry: vaultState.selectedEntry!,
 vaultState: vaultState,
 clipboardManager: _clipboardManager,
 onUrlTap: (url) => web.window.open(url, '_blank'),
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
 onUrlTap: (url) => web.window.open(url, '_blank'),
 )
 : const EntryDetailEmpty();
 }
 }
}
