import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:keepass_ui/keepass_ui.dart' show VaultEntry;
import 'package:manyui/manyui.dart';

/// Entries of the selected group: title plus muted username.
class EntryList extends HookWidget {
  const EntryList({
    required this.entries,
    required this.selectedUuid,
    required this.onSelect,
    this.title = 'Entries',
    this.searchQuery = '',
    this.searchIndexReady = true,
    this.onSearchChanged,
    this.onShowGroups,
    this.onCreateEntry,
    super.key,
  });

  final List<VaultEntry> entries;
  final String? selectedUuid;
  final ValueChanged<VaultEntry> onSelect;
  final String title;
  final String searchQuery;
  final bool searchIndexReady;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback? onShowGroups;
  final VoidCallback? onCreateEntry;

  @override
  Widget build(BuildContext context) {
    final theme = MTheme.of(context);
    final searchController = useMemoized(
      () => MController<String>(searchQuery),
    );
    useEffect(() => searchController.dispose, const <Object?>[]);
    useEffect(() {
      if (searchController.value != searchQuery) {
        searchController.value = searchQuery;
      }
      return null;
    }, <Object?>[searchQuery]);

    final searching = searchQuery.trim().isNotEmpty;

    final Widget list = entries.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: MEmptyState(
                title: searching
                    ? searchIndexReady
                          ? 'No matching entries'
                          : 'Indexing vault'
                    : 'No entries here yet',
                description: searching
                    ? searchIndexReady
                          ? 'Try a different title, username, or URL.'
                          : 'Search results will appear when indexing finishes.'
                    : 'Create an entry to store a login or secure note.',
              ),
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              final selected = entry.uuid == selectedUuid;
              final title = entry.titleProtected
                  ? 'Protected entry'
                  : entry.title.isEmpty
                  ? '(untitled)'
                  : entry.title;

              return MListTile(
                title: Text(title, overflow: TextOverflow.ellipsis),
                subtitle: _entrySubtitle(entry, searching).isNotEmpty
                    ? Text(
                        _entrySubtitle(entry, searching),
                        overflow: TextOverflow.ellipsis,
                      )
                    : null,
                selected: selected,
                onTap: () => onSelect(entry),
                semanticLabel: title,
              );
            },
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
          child: Row(
            children: <Widget>[
              if (onShowGroups != null) ...<Widget>[
                MIconButton(
                  icon: MIconData.menu,
                  label: 'Show groups',
                  size: MButtonSize.sm,
                  onPressed: onShowGroups,
                ),
                const SizedBox(width: 6),
              ],
              Expanded(child: Text(title, style: theme.typography.title)),
              Text(
                '${entries.length}',
                style: theme.typography.caption.copyWith(
                  color: theme.colors.mutedForeground,
                ),
              ),
              if (onCreateEntry != null) ...<Widget>[
                const SizedBox(width: 8),
                MIconButton(
                  icon: MIconData.plus,
                  label: 'New entry',
                  size: MButtonSize.sm,
                  onPressed: onCreateEntry,
                ),
              ],
            ],
          ),
        ),
        if (onSearchChanged != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: MTextField(
              controller: searchController,
              placeholder: 'Search vault',
              semanticLabel: 'Search vault',
              leading: const MIcon(MIconData.search, size: 16),
              trailing: searchQuery.isEmpty
                  ? null
                  : MIconButton(
                      icon: MIconData.close,
                      label: 'Clear search',
                      size: MButtonSize.xs,
                      onPressed: () {
                        searchController.value = '';
                        onSearchChanged!('');
                      },
                    ),
              onChanged: onSearchChanged,
            ),
          ),
        const MDivider(),
        Expanded(child: list),
      ],
    );
  }

  String _entrySubtitle(VaultEntry entry, bool searching) {
    final username = entry.usernameProtected ? '' : entry.username;
    if (searching && entry.breadcrumb?.isNotEmpty == true) {
      return username.isEmpty
          ? entry.breadcrumb!
          : '$username · ${entry.breadcrumb}';
    }
    return username;
  }
}
