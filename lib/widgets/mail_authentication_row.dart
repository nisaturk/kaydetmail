import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/mail_authentication.dart';

class MailAuthenticationRow extends StatelessWidget {
  const MailAuthenticationRow({super.key, required this.authentication});

  final MailAuthentication authentication;

  @override
  Widget build(BuildContext context) {
    final results = <String>[
      if (authentication.spf case final result?) 'SPF ${_label(result)}',
      if (authentication.dkim case final result?) 'DKIM ${_label(result)}',
      if (authentication.dmarc case final result?) 'DMARC ${_label(result)}',
    ];
    if (results.isEmpty) return const SizedBox.shrink();
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return ExpansionTile(
      key: const Key('mail-authentication-row'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 12),
      leading: Icon(LucideIcons.shieldCheck, size: 20, color: secondary),
      title: Text(results.join(' · '), style: const TextStyle(fontSize: 13)),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            authentication.authservId?.trim().isNotEmpty == true
                ? 'Bu sonuçlar ${authentication.authservId} tarafından eklenen posta başlığından alınmıştır. Yalnızca bilgi amaçlıdır.'
                : 'Bu sonuçlar posta başlığından alınmıştır. Yalnızca bilgi amaçlıdır.',
            style: TextStyle(fontSize: 12, color: secondary),
          ),
        ),
      ],
    );
  }

  static String _label(String result) => switch (result) {
    'pass' => 'geçti',
    'fail' => 'başarısız',
    'softfail' => 'kısmen başarısız',
    'neutral' => 'nötr',
    'none' => 'yok',
    'temperror' => 'geçici hata',
    'permerror' => 'kalıcı hata',
    'policy' => 'politika',
    _ => result,
  };
}
