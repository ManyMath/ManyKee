class VaultEntry {
 final String uuid;
 final String title;
 final String username;
 final String url;
 final String? breadcrumb;

 VaultEntry({
 required this.uuid,
 required this.title,
 required this.username,
 required this.url,
 this.breadcrumb,
 });

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
