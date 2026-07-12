class VaultEntry {
  final String uuid;
  final String title;
  final String username;
  final String url;
  final String? groupUuid;
  final String? breadcrumb;
  final Set<String> protectedFields;

  VaultEntry({
    required this.uuid,
    required this.title,
    required this.username,
    required this.url,
    this.groupUuid,
    this.breadcrumb,
    this.protectedFields = const <String>{},
  });

  bool get titleProtected => protectedFields.contains('Title');
  bool get usernameProtected => protectedFields.contains('UserName');
  bool get urlProtected => protectedFields.contains('URL');

  factory VaultEntry.fromMap(
    Map<String, dynamic> map, {
    String? groupUuid,
    String? breadcrumb,
  }) {
    final rawProtected = map['protected'];
    final protectedFields = rawProtected is Map
        ? rawProtected.entries
            .where((entry) => entry.value == true)
            .map((entry) => entry.key.toString())
            .toSet()
        : const <String>{};
    return VaultEntry(
      uuid: map['uuid'] as String? ?? '',
      title: map['title'] as String? ?? '',
      username: map['username'] as String? ?? '',
      url: map['url'] as String? ?? '',
      groupUuid: groupUuid,
      breadcrumb: breadcrumb,
      protectedFields: protectedFields,
    );
  }
}
