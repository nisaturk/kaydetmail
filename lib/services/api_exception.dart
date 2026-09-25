import 'dart:convert';

enum ApiErrorCategory {
  authentication,
  request,
  network,
  timeout,
  server,
  unknown,
}

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
  ApiErrorCategory get category => switch (code) {
    'request_timeout' => ApiErrorCategory.timeout,
    'network_unavailable' => ApiErrorCategory.network,
    _ when status == 401 || status == 403 => ApiErrorCategory.authentication,
    _ when status >= 400 && status < 500 => ApiErrorCategory.request,
    _ when status >= 500 => ApiErrorCategory.server,
    _ => ApiErrorCategory.unknown,
  };

  bool get isTransient =>
      category == ApiErrorCategory.network ||
      category == ApiErrorCategory.timeout ||
      status == 429 ||
      category == ApiErrorCategory.server;

  String get userMessage => switch (code) {
    'request_timeout' => 'Sunucu yanıt vermedi. Lütfen tekrar deneyin.',
    'network_unavailable' => 'İnternet bağlantınızı kontrol edin.',
    'mail_authentication_failed' => 'E-posta şifresi reddedildi.',
    'invalid_refresh_token' =>
      'Oturum süresi doldu. Lütfen yeniden giriş yapın.',
    'email_not_allowlisted' => 'Bu e-posta adresi için erişim henüz açılmadı.',
    'mail_account_disabled' => 'Bu posta hesabı devre dışı bırakıldı.',
    'mail_account_already_exists' => 'Bu hesap zaten bağlı.',
    'template_name_taken' => 'Bu adla bir şablon zaten var.',
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
    'mail_delete_failed' => 'E-posta kalıcı olarak silinemedi. Tekrar deneyin.',
    'mail_operation_failed' => 'İşlem tamamlanamadı. Tekrar deneyin.',
    'delivery_unknown' =>
      'Gönderim sonucu belirsiz. Gönderilenler\u2019i kontrol edin.',
    'send_in_progress' => 'Gönderim sürüyor. Kısa süre sonra tekrar deneyin.',
    'idempotency_key_required' ||
    'idempotency_key_too_long' ||
    'idempotency_conflict' => 'Gönderim tekrar denensin.',
    'recipient_required' => 'En az bir alıcı yazmalısınız.',
    'invalid_recipient' => 'Alıcı adresi geçersiz.',
    'invalid_email' => 'Geçersiz e-posta adresi.',
    'invalid_mail_header' => 'E-posta başlıkları geçersiz.',
    'message_not_constructible' => 'E-posta oluşturulamadı.',
    'manual_setup_invalid' => 'Sunucu ayarları geçersiz.',
    'oauth_provider_not_configured' =>
      'Bu giriş yöntemi sunucuda ayarlı değil.',
    'oauth_redirect_uri_invalid' => 'Yönlendirme adresi geçersiz.',
    'oauth_state_invalid' => 'Oturum doğrulaması geçersiz. Tekrar deneyin.',
    'oauth_code_exchange_failed' => 'Sağlayıcı girişi reddetti.',
    'oauth_refresh_lock_unavailable' =>
      'Sunucu meşgul. Birazdan tekrar deneyin.',
    'draft_delete_failed' => 'Taslak silinemedi. Tekrar deneyin.',
    'session_revoked' => 'Oturum zaten kapatılmış.',
    'body_required' => 'E-posta gövdesi boş olamaz.',
    'body_too_large' => 'E-posta gövdesi çok büyük.',
    'attachment_too_large' ||
    'too_many_attachments' => 'Ek dosya sınırı aşıldı.',
    'mail_folder_unavailable' => 'Klasör sunucudan kaldırılmış.',
    'sync_queue_full' => 'Eşitleme kuyruğu dolu. Birazdan tekrar deneyin.',
    'sync_retry_deferred' => 'Eşitleme ertelendi. Birazdan tekrar deneyin.',
    'sync_interrupted' => 'Eşitleme yarıda kesildi. Tekrar deneyin.',
    'sync_failed' => 'Eşitleme tamamlanamadı. Tekrar deneyin.',
    'mail_account_needs_reauthentication' ||
    'credential_missing' => 'Hesap yeniden bağlanmayı istiyor.',
    'unsupported_authentication_method' => 'Bu giriş yöntemi desteklenmiyor.',
    'mail_smtp_authentication_failed' => 'SMTP şifresi reddedildi.',
    'provider_disabled' ||
    'provider_new_accounts_disabled' ||
    'provider_existing_accounts_disabled' ||
    'authentication_method_disabled' => 'Bu giriş şu an desteklenmiyor.',
    'unexpected_error' => 'Beklenmeyen bir hata oluştu.',
    _ => title ?? 'İstek tamamlanamadı.',
  };

  @override
  String toString() => 'ApiException($status, $code, $correlationId)';
}
