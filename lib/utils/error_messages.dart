import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../services/api_exception.dart';
import '../repositories/mail_repository.dart';
import '../l10n/l10n.dart';

/// Turns any error caught around a repository/network call into a short,
/// Turkish, user-facing message — never the raw exception text (stack-trace
/// style `ApiException(...)`/`SocketException(...)` strings leaking into a
/// SnackBar or error screen).
String friendlyErrorMessage(Object error) {
  if (error is SendBeforeDeliveryException) {
    return l10nNow.theSendDidntStartYou;
  }
  if (error is ApiException) return error.userMessage;
  if (error is SocketException || error is http.ClientException) {
    return l10nNow.checkYourInternetConnection;
  }
  if (error is TimeoutException) {
    return l10nNow.theServerDidntRespondPlease;
  }
  if (error is FormatException) {
    return l10nNow.theServerReturnedAnUnexpected;
  }
  return l10nNow.anUnexpectedErrorOccurredPlease;
}
