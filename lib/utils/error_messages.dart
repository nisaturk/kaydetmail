import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../services/api_exception.dart';
import '../repositories/mail_repository.dart';

/// Turns any error caught around a repository/network call into a short,
/// Turkish, user-facing message — never the raw exception text (stack-trace
/// style `ApiException(...)`/`SocketException(...)` strings leaking into a
/// SnackBar or error screen).
String friendlyErrorMessage(Object error) {
  if (error is SendBeforeDeliveryException) {
    return 'Gönderim başlamadı. Giden Kutusu’ndan yeniden deneyebilirsiniz.';
  }
  if (error is ApiException) return error.userMessage;
  if (error is SocketException || error is http.ClientException) {
    return 'İnternet bağlantınızı kontrol edin.';
  }
  if (error is TimeoutException) {
    return 'Sunucu yanıt vermedi. Lütfen tekrar deneyin.';
  }
  if (error is FormatException) {
    return 'Sunucudan beklenmeyen bir yanıt geldi.';
  }
  return 'Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.';
}
