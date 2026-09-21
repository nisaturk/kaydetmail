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
    // Error bodies are Problem Details JSON per contract, but a
    // protocol-violating (non-JSON) body must still surface as an
    // ApiException — never as a raw FormatException from the UI's path.
    Map<String, dynamic> details;
    try {
      final decoded = body.isEmpty ? null : jsonDecode(body);
      details = decoded is Map<String, dynamic>
          ? decoded
          : const <String, dynamic>{};
    } catch (_) {
      details = const <String, dynamic>{};
    }
    final fallbackTitle = details.isEmpty && body.isNotEmpty
        ? body.substring(0, body.length > 120 ? 120 : body.length)
        : null;
    return ApiException(
      status: status,
      code: details['code'] as String?,
      title: details['title'] as String? ?? fallbackTitle,
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
    'mail_account_not_found' => 'Bu e-posta için kayıtlı hesap bulunamadı.',
    'mail_discovery_failed' => 'Otomatik sunucu keşfi başarısız oldu.',
    'discovery_expired' => 'Sunucu keşfinin süresi doldu. Tekrar deneyin.',
    'mail_server_unsafe' => 'Sunucu ayarları güvenli değil.',
    'mail_provider_unavailable' ||
    'mail_tls_failed' ||
    'mail_server_unreachable' =>
      'Posta sunucusuna ulaşılamadı. Tekrar deneyin.',
    'mail_not_found' || 'draft_not_found' => 'E-posta bulunamadı.',
    'mail_not_draft' => 'Bu taslak artık geçerli değil.',
    'drafts_folder_unavailable' ||
    'trash_folder_unavailable' ||
    'mail_folder_not_found' => 'Posta klasörü kullanılamıyor.',
    'mail_operation_not_supported' =>
      'Bu işlem bu e-posta için desteklenmiyor.',
    'mail_operation_conflict' ||
    'mailbox_changed' => 'Posta kutusu değişti. Yenileyip tekrar deneyin.',
    'mail_move_failed' => 'E-posta taşınamadı. Tekrar deneyin.',
    'mail_operation_failed' => 'İşlem tamamlanamadı. Tekrar deneyin.',
    'delivery_unknown' =>
      'Gönderim sonucu belirsiz. Gönderilenler\u2019i kontrol edin.',
    'send_in_progress' => 'Gönderim sürüyor. Kısa süre sonra tekrar deneyin.',
    'idempotency_key_required' ||
    'idempotency_key_too_long' ||
    'idempotency_conflict' => 'Gönderim tekrar denensin.',
    'recipient_required' => 'En az bir alıcı yazmalısınız.',
    'invalid_recipient' => 'Alıcı adresi geçersiz.',
    'body_required' => 'E-posta gövdesi boş olamaz.',
    'body_too_large' => 'E-posta gövdesi çok büyük.',
    'attachment_too_large' ||
    'too_many_attachments' => 'Ek dosya sınırı aşıldı.',
    'mail_folder_unavailable' => 'Klasör sunucudan kaldırılmış.',
    'sync_queue_full' => 'Eşitleme kuyruğu dolu. Birazdan tekrar deneyin.',
    'mail_account_needs_reauthentication' ||
    'credential_missing' => 'Hesap yeniden bağlanmayı istiyor.',
    'unexpected_error' => 'Beklenmeyen bir hata oluştu.',
    _ => title ?? 'İstek tamamlanamadı.',
  };

  @override
  String toString() => 'ApiException($status, $code, $correlationId)';
}
