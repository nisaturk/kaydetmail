import 'package:flutter/foundation.dart';

@immutable
class MailAuthentication {
  const MailAuthentication({this.authservId, this.spf, this.dkim, this.dmarc});

  final String? authservId;
  final String? spf;
  final String? dkim;
  final String? dmarc;

  bool get hasResults => spf != null || dkim != null || dmarc != null;
}
