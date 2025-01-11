/// A group in the KDBX database (folder containing entries and sub-groups).
class VaultGroup {
  final String uuid;
  final String name;
  final List<VaultGroup> children;

  VaultGroup({
    required this.uuid,
    required this.name,
    this.children = const [],
  });

  /// Parse from the Map returned by [KeePassWebApi.listGroups].
  factory VaultGroup.fromMap(
    Map<String, dynamic> map, {
    List<VaultGroup> children = const [],
  }) =>
      VaultGroup(
        uuid: map['uuid'] as String? ?? '',
        name: map['name'] as String? ?? '',
        children: children,
      );
}
