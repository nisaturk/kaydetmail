part of '../api_mail_service.dart';

mixin _OrganizeApi on _ApiMailServiceBase {
  /// Every label defined for the current mailbox, in display order.
  Future<List<Map<String, dynamic>>> getLabels() async {
    final body = await _client.get('/api/labels');
    return (body['items'] as List).cast<Map<String, dynamic>>();
  }

  /// Creates a label. Throws [ApiException] with code `label_name_taken`
  /// when another label in this account already has that name
  /// (case-insensitive).
  Future<Map<String, dynamic>> createLabel(String name, int color) =>
      _client.postJson('/api/labels', {'name': name, 'color': color});

  /// Renames/recolors a label. Same `label_name_taken` conflict as
  /// [createLabel].
  Future<Map<String, dynamic>> updateLabel(String id, String name, int color) =>
      _client.putJson('/api/labels/${Uri.encodeComponent(id)}', {
        'name': name,
        'color': color,
      });

  /// Deletes a label; also strips it from every mail it was assigned to.
  Future<void> deleteLabel(String id) =>
      _client.delete('/api/labels/${Uri.encodeComponent(id)}');

  Future<List<MailTemplate>> getTemplates() async {
    final items = await _client.getList('/api/templates');
    return items
        .map(
          (item) =>
              MailTemplate.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<MailTemplate> createTemplate(MailTemplate template) async =>
      MailTemplate.fromJson(
        await _client.postJson('/api/templates', template.toJson()),
      );

  Future<MailTemplate> updateTemplate(MailTemplate template) async =>
      MailTemplate.fromJson(
        await _client.putJson(
          '/api/templates/${Uri.encodeComponent(template.id)}',
          template.toJson(),
        ),
      );

  Future<void> deleteTemplate(String id) =>
      _client.delete('/api/templates/${Uri.encodeComponent(id)}');

  /// Full mail id -> assigned label ids map for the current mailbox.
  Future<Map<String, List<String>>> getLabelAssignments() async {
    final body = await _client.get('/api/labels/assignments');
    final assignments = body['assignments'] as Map<String, dynamic>;
    return assignments.map(
      (mailId, labelIds) => MapEntry(mailId, (labelIds as List).cast<String>()),
    );
  }

  /// Assigns [labelIds] to [mailIds]. Pairs outside this account, or
  /// already-assigned pairs, are silently skipped.
  Future<void> assignLabels(List<String> mailIds, List<String> labelIds) =>
      _client.postJson('/api/labels/assignments', {
        'mailIds': mailIds,
        'labelIds': labelIds,
      });

  /// Removes [labelIds] from [mailIds].
  Future<void> unassignLabels(List<String> mailIds, List<String> labelIds) =>
      _client.postJson('/api/labels/assignments/remove', {
        'mailIds': mailIds,
        'labelIds': labelIds,
      });

  /// Every manually-added contact for the current mailbox (see
  /// [ManualContact]).
  Future<List<Map<String, dynamic>>> getContacts() async {
    final body = await _client.get('/api/contacts');
    return (body['items'] as List).cast<Map<String, dynamic>>();
  }

  /// Adds a contact. Throws [ApiException] with code
  /// `contact_already_exists` when this mailbox already has a contact with
  /// that email (case-insensitive).
  Future<Map<String, dynamic>> createContact(
    String email,
    String? displayName,
  ) => _client.postJson('/api/contacts', {
    'email': email,
    'displayName': displayName,
  });

  /// Edits a contact. Same `contact_already_exists` conflict as
  /// [createContact].
  Future<Map<String, dynamic>> updateContact(
    String id,
    String email,
    String? displayName,
  ) => _client.putJson('/api/contacts/${Uri.encodeComponent(id)}', {
    'email': email,
    'displayName': displayName,
  });

  /// Removes a contact.
  Future<void> deleteContact(String id) =>
      _client.delete('/api/contacts/${Uri.encodeComponent(id)}');

  Future<({List<MailSignature> items, SignatureDefaults defaults})>
  getSignatures() async {
    final body = await _client.get('/api/signatures');
    final items = body['items'] as List? ?? const [];
    return (
      items: [
        for (final item in items)
          MailSignature.fromJson(Map<String, dynamic>.from(item as Map)),
      ],
      defaults: SignatureDefaults.fromJson(
        Map<String, dynamic>.from(body['defaults'] as Map? ?? const {}),
      ),
    );
  }

  Future<MailSignature> createSignature(MailSignature signature) async =>
      MailSignature.fromJson(
        await _client.postJson('/api/signatures', signature.toJson()),
      );

  Future<MailSignature> updateSignatureItem(MailSignature signature) async =>
      MailSignature.fromJson(
        await _client.putJson(
          '/api/signatures/${Uri.encodeComponent(signature.id)}',
          signature.toJson(),
        ),
      );

  Future<void> deleteSignature(String id) =>
      _client.delete('/api/signatures/${Uri.encodeComponent(id)}');

  Future<SignatureDefaults> updateSignatureDefaults(
    SignatureDefaults defaults,
  ) async => SignatureDefaults.fromJson(
    await _client.putJson('/api/signatures/defaults', defaults.toJson()),
  );

  Future<List<MailIdentity>> getIdentities() async {
    final items = await _client.getList('/api/identities');
    return items
        .map(
          (item) =>
              MailIdentity.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<MailIdentity> createIdentity(MailIdentity identity) async =>
      MailIdentity.fromJson(
        await _client.postJson('/api/identities', identity.toJson()),
      );

  Future<MailIdentity> updateIdentity(MailIdentity identity) async =>
      MailIdentity.fromJson(
        await _client.putJson(
          '/api/identities/${Uri.encodeComponent(identity.id)}',
          identity.toJson(),
        ),
      );

  Future<void> deleteIdentity(String id) =>
      _client.delete('/api/identities/${Uri.encodeComponent(id)}');
}
