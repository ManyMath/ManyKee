/// Flattens the shared Rust entry payload into the app-facing API shape.
Map<String, dynamic> normalizeEntryFieldsPayload(
  Map<String, dynamic> payload,
) {
  final fields = (payload['fields'] as Map?)?.cast<String, dynamic>();
  if (fields == null) {
    return payload;
  }

  return <String, dynamic>{
    ...fields,
    'custom_data': _safeCustomData(payload['custom_data']),
    'protected': (payload['protected'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{},
    'Tags': _normalizeTags(payload['tags']),
  };
}

Map<String, dynamic> _safeCustomData(dynamic raw) {
  final customData = Map<String, dynamic>.from(
    (raw as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{},
  );
  customData.remove('otp');
  return customData;
}

List<String> _normalizeTags(dynamic raw) {
  final values = raw is List ? raw : <dynamic>[if (raw != null) raw];
  return values
      .expand((value) => value.toString().split(RegExp(r'[,;]')))
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toList(growable: false);
}
