import 'dart:convert';

class ApiException implements Exception {
  const ApiException({
    required this.status,
    this.code,
    this.title,
    this.correlationId,
    this.details = const {},
  });

  factory ApiException.fromResponse(int status, String body) {
    final decoded = body.isEmpty ? null : jsonDecode(body);
    final details = decoded is Map<String, dynamic>
        ? decoded
        : const <String, dynamic>{};
    return ApiException(
      status: status,
      code: details['code'] as String?,
      title: details['title'] as String?,
      correlationId: details['correlationId'] as String?,
      details: details,
    );
  }

  final int status;
  final String? code;
  final String? title;
  final String? correlationId;
  final Map<String, dynamic> details;

  String get userMessage => switch (code) {
    'mail_authentication_failed' => 'E-posta şifresi reddedildi.',
    'invalid_refresh_token' =>
      'Oturum süresi doldu. Lütfen yeniden giriş yapın.',
    'email_not_allowlisted' => 'Bu e-posta adresi için erişim henüz açılmadı.',
    'mail_account_disabled' => 'Bu posta hesabı devre dışı bırakıldı.',
    'mail_account_already_exists' => 'Bu hesap zaten bağlı.',
    'mail_discovery_failed' => 'Otomatik sunucu keşfi başarısız oldu.',
    'discovery_expired' => 'Sunucu keşfinin süresi doldu. Tekrar deneyin.',
    'mail_server_unsafe' => 'Sunucu ayarları güvenli değil.',
    'mail_provider_unavailable' ||
    'mail_tls_failed' ||
    'mail_server_unreachable' =>
      'Posta sunucusuna ulaşılamadı. Tekrar deneyin.',
    _ => title ?? 'İstek tamamlanamadı.',
  };

  @override
  String toString() => 'ApiException($status, $code, $correlationId)';
}
