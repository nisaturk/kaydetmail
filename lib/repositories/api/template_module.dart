import 'package:flutter/foundation.dart';

import '../../models/mail_template.dart';
import 'session_registry.dart';

/// Reusable texts ("hazır metinler"): backend-owned, cached per session.
class TemplateModule {
  TemplateModule(this._registry, this._notify);

  final SessionRegistry _registry;

  // ignore: unused_field
  final VoidCallback _notify;

  Future<List<MailTemplate>> listTemplates(
    String accountId, {
    bool refresh = false,
  }) async {
    final session = _registry.forAccount(accountId);
    if (!refresh && session.templates != null) return session.templates!;
    final templates = await session.mailService.getTemplates();
    session.templates = [
      for (final template in templates) template.copyWith(accountId: accountId),
    ];
    return session.templates!;
  }

  Future<MailTemplate> createTemplate(
    String accountId,
    MailTemplate template,
  ) async {
    final session = _registry.forAccount(accountId);
    final created = (await session.mailService.createTemplate(template))
        .copyWith(accountId: accountId);
    final items = session.templates ?? <MailTemplate>[];
    session.templates = [...items, created]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return created;
  }

  Future<MailTemplate> updateTemplate(
    String accountId,
    MailTemplate template,
  ) async {
    final session = _registry.forAccount(accountId);
    final updated = (await session.mailService.updateTemplate(template))
        .copyWith(accountId: accountId);
    if (session.templates != null) {
      session.templates = [
        for (final item in session.templates!)
          if (item.id == updated.id) updated else item,
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return updated;
  }

  Future<void> deleteTemplate(String accountId, String templateId) async {
    final session = _registry.forAccount(accountId);
    await session.mailService.deleteTemplate(templateId);
    session.templates?.removeWhere((item) => item.id == templateId);
  }
}
