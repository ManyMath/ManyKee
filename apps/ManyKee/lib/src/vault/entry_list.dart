import 'package:flutter/widgets.dart';
import 'package:keepass_ui/keepass_ui.dart' show VaultEntry;
import 'package:manyui/manyui.dart';

/// Entries of the selected group: title plus muted username.
class EntryList extends StatelessWidget {
  const EntryList({
    required this.entries,
    required this.selectedUuid,
    required this.onSelect,
    super.key,
  });

  final List<VaultEntry> entries;
  final String? selectedUuid;
  final ValueChanged<VaultEntry> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = MTheme.of(context);

    if (entries.isEmpty) {
      return Center(
        child: Text(
          'No entries in this group',
          style: theme.typography.bodySmall
              .copyWith(color: theme.colors.mutedForeground),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final selected = entry.uuid == selectedUuid;
        final foreground =
            selected ? theme.colors.accentForeground : theme.colors.foreground;
        final muted = selected
            ? theme.colors.accentForeground
            : theme.colors.mutedForeground;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onSelect(entry),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? theme.colors.accent : null,
              borderRadius: BorderRadius.circular(theme.radius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  entry.title.isEmpty ? '(untitled)' : entry.title,
                  style: theme.typography.body.copyWith(color: foreground),
                  overflow: TextOverflow.ellipsis,
                ),
                if (entry.username.isNotEmpty)
                  Text(
                    entry.username,
                    style: theme.typography.bodySmall.copyWith(color: muted),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
