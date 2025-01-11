/// A credential entry in the KDBX database.
class VaultEntry {
  final String uuid;
  final String title;
  final String username;
  final String url;

  /// Group path for search results (e.g. "Root > Finance > Banking").
  /// Non-null when this entry appears in search results.
  final String? breadcrumb;

  VaultEntry({
    required this.uuid,
    required this.title,
    required this.username,
    required this.url,
    this.breadcrumb,
  });

  /// Parse from the Map returned by [KeePassWebApi.listEntries].
  factory VaultEntry.fromMap(
    Map<String, dynamic> map, {
    String? breadcrumb,
  }) =>
      VaultEntry(
        uuid: map['uuid'] as String? ?? '',
        title: map['title'] as String? ?? '',
        username: map['username'] as String? ?? '',
        url: map['url'] as String? ?? '',
        breadcrumb: breadcrumb,
      );
}
