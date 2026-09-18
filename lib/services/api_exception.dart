import 'dart:convert';

class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    this.code,
    this.title,
    this.correlationId,
    this.details = const {},
  });

  final int statusCode;
  final String? code;
  final String? title;
  final String? correlationId;
  final Map<String, dynamic> details;

  factory ApiException.fromResponse(int statusCode, String body) {
    if (body.trim().isEmpty) return ApiException(statusCode: statusCode);
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return ApiException(
          statusCode: statusCode,
          code: decoded['code']?.toString(),
          title: decoded['title']?.toString(),
          correlationId: decoded['correlationId']?.toString(),
          details: decoded,
        );
      }
    } catch (_) {}
    return ApiException(statusCode: statusCode, title: body.trim());
  }

  String get userMessage {
    switch (code) {
      case 'mail_authentication_failed':
        return 'E-posta şifresi reddedildi.';
      case 'invalid_refresh_token':
        return 'Oturumun süresi doldu. Lütfen yeniden bağlanın.';
      case 'email_not_allowlisted':
        return 'Bu hesap henüz erişime açılmadı.';
      case 'mail_account_disabled':
        return 'Bu posta hesabı devre dışı bırakıldı.';
      case 'mail_account_already_exists':
        return 'Bu e-posta hesabı zaten bağlı.';
      case 'mail_discovery_failed':
        return 'Posta sunucusu otomatik olarak bulunamadı.';
      case 'discovery_expired':
        return 'Sunucu keşfinin süresi doldu. Lütfen tekrar deneyin.';
      case 'mailbox_changed':
        return 'Posta kutusu değişti. Lütfen tekrar senkronize edin.';
      case 'mail_provider_unavailable':
      case 'mail_tls_failed':
      case 'mail_server_unreachable':
        return 'Posta sunucusuna ulaşılamadı. Lütfen tekrar deneyin.';
      case 'recipient_required':
        return 'En az bir alıcı yazmalısınız.';
      case 'invalid_recipient':
        return 'Alıcılardan biri geçersiz.';
      case 'attachment_too_large':
        return 'Bir ek izin verilen boyutu aşıyor.';
      case 'too_many_attachments':
        return 'Çok fazla ek var.';
      case 'mail_not_found':
        return 'E-posta bulunamadı.';
      case 'folder_not_found':
        return 'Klasör bulunamadı.';
      case 'invalid_email':
        return 'Geçerli bir e-posta adresi girin.';
      case 'unexpected_error':
        return 'Sunucuda beklenmeyen bir hata oluştu.';
      default:
        if (statusCode == 429) return 'Çok fazla istek gönderildi. Biraz sonra tekrar deneyin.';
        if (title != null && title!.trim().isNotEmpty) return title!;
        return 'Sunucu isteği başarısız oldu ($statusCode).';
    }
  }

  @override
  String toString() => 'ApiException($statusCode, $code)';
}
