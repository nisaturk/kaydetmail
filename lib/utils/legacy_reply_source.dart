final _mailIdPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Migrates the old persisted field that mixed API GUIDs with MIME Message-IDs.
/// A server draft can supply its own saved threading when the old value was MIME.
String? migrateLegacyReplySource(String? value, {String? draftId}) {
  if (value == null || value.isEmpty) return null;
  if (_mailIdPattern.hasMatch(value)) return value;
  return draftId != null && _mailIdPattern.hasMatch(draftId) ? draftId : null;
}
