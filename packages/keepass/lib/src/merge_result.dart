class MergeResult {
 final int entriesAdded;
 final int entriesUpdated;
 final int entriesDeleted;
 final int entriesRelocated;
 final int groupsAdded;
 final int groupsUpdated;
 final int groupsDeleted;
 final int groupsRelocated;
 final int totalChanges;
 final int conflictsCount;
 final int warningsCount;
 final List<String> warnings;

 MergeResult({
 required this.entriesAdded,
 required this.entriesUpdated,
 required this.entriesDeleted,
 required this.entriesRelocated,
 required this.groupsAdded,
 required this.groupsUpdated,
 required this.groupsDeleted,
 required this.groupsRelocated,
 required this.totalChanges,
 required this.conflictsCount,
 required this.warningsCount,
 required this.warnings,
 });

 factory MergeResult.fromJson(Map<String, dynamic> json) {
 return MergeResult(
 entriesAdded: json['entries_added'] as int? ?? 0,
 entriesUpdated: json['entries_updated'] as int? ?? 0,
 entriesDeleted: json['entries_deleted'] as int? ?? 0,
 entriesRelocated: json['entries_relocated'] as int? ?? 0,
 groupsAdded: json['groups_added'] as int? ?? 0,
 groupsUpdated: json['groups_updated'] as int? ?? 0,
 groupsDeleted: json['groups_deleted'] as int? ?? 0,
 groupsRelocated: json['groups_relocated'] as int? ?? 0,
 totalChanges: json['total_changes'] as int? ?? 0,
 conflictsCount: json['conflicts_count'] as int? ?? 0,
 warningsCount: json['warnings_count'] as int? ?? 0,
 warnings: (json['warnings'] as List<dynamic>?)?.cast<String>() ?? [],
 );
 }

 Map<String, dynamic> toJson() => {
 'entries_added': entriesAdded,
 'entries_updated': entriesUpdated,
 'entries_deleted': entriesDeleted,
 'entries_relocated': entriesRelocated,
 'groups_added': groupsAdded,
 'groups_updated': groupsUpdated,
 'groups_deleted': groupsDeleted,
 'groups_relocated': groupsRelocated,
 'total_changes': totalChanges,
 'conflicts_count': conflictsCount,
 'warnings_count': warningsCount,
 'warnings': warnings,
 };

 @override
 String toString() {
 final lines = <String>[];
 if (entriesAdded > 0) lines.add('Entries added: $entriesAdded');
 if (entriesUpdated > 0) lines.add('Entries updated: $entriesUpdated');
 if (entriesDeleted > 0) lines.add('Entries deleted: $entriesDeleted');
 if (entriesRelocated > 0) {
 lines.add('Entries relocated: $entriesRelocated');
 }
 if (groupsAdded > 0) lines.add('Groups added: $groupsAdded');
 if (groupsUpdated > 0) lines.add('Groups updated: $groupsUpdated');
 if (groupsDeleted > 0) lines.add('Groups deleted: $groupsDeleted');
 if (groupsRelocated > 0) {
 lines.add('Groups relocated: $groupsRelocated');
 }
 lines.add('Total changes: $totalChanges');
 if (conflictsCount > 0) lines.add('Conflicts: $conflictsCount');
 if (warningsCount > 0) {
 lines.add('Warnings: $warningsCount');
 for (final w in warnings) {
 lines.add(' - $w');
 }
 }
 return lines.join('\n');
 }
}
