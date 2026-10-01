import 'dart:convert';

import '../l10n/l10n.dart';

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
    // A non-JSON body (proxy/HTML error page, stack trace, internal host
    // names) is deliberately never copied into the exception: it can reach
    // the UI and crash reports, and tells the user nothing actionable.
    String? text(String key) {
      final value = details[key];
      return value is String ? value : null;
    }

    return ApiException(
      status: status,
      code: text('code'),
      title: text('title'),
      correlationId: text('correlationId'),
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
    'request_timeout' => l10nNow.theServerDidntRespondPlease,
    'network_unavailable' => l10nNow.checkYourInternetConnection,
    'mail_authentication_failed' => l10nNow.wrongPassword,
    'invalid_refresh_token' => l10nNow.yourSessionExpiredPleaseSign,
    'email_not_allowlisted' => l10nNow.accessHasntBeenEnabledFor,
    'mail_account_disabled' => l10nNow.thisMailAccountHasBeen,
    'mail_account_already_exists' => l10nNow.thisAccountIsAlreadyConnected,
    'template_name_taken' => l10nNow.aTemplateWithThisName,
    'mail_account_not_found' => l10nNow.noRegisteredAccountFoundFor,
    'mail_discovery_failed' => l10nNow.automaticServerDiscoveryFailed,
    'discovery_expired' => l10nNow.serverDiscoveryTimedOutTry,
    'mail_server_unsafe' => l10nNow.theServerSettingsArentSecure,
    'mail_provider_unavailable' ||
    'mail_tls_failed' ||
    'mail_server_unreachable' => l10nNow.couldntReachTheMailServer,
    'mail_not_found' || 'draft_not_found' => l10nNow.emailNotFound,
    'mail_not_draft' => l10nNow.thisDraftIsNoLonger,
    'drafts_folder_unavailable' ||
    'trash_folder_unavailable' ||
    'mail_folder_not_found' => l10nNow.theMailFolderIsUnavailable,
    'mail_operation_not_supported' => l10nNow.thisActionIsntSupportedFor,
    'mail_reconciliation_pending' => l10nNow.mailReconciliationRetry,
    'mail_operation_conflict' ||
    'mailbox_changed' => l10nNow.theMailboxChangedRefreshAnd,
    'mail_move_failed' => l10nNow.couldntMoveTheEmailTry,
    'mail_delete_failed' => l10nNow.couldntPermanentlyDeleteTheEmail,
    'mail_operation_failed' => l10nNow.theActionCouldntBeCompleted,
    'pinned_limit_reached' => l10nNow.youCanPinAtMost3EmailsPer,
    'draft_not_reconciled' => l10nNow.theDraftHasntMatchedOn,
    'delivery_unknown' => l10nNow.theSendResultIsUnknown,
    'send_in_progress' => l10nNow.theMessageIsBeingSent,
    'idempotency_key_required' ||
    'idempotency_key_too_long' => l10nNow.theSendRequestIsInvalid,
    'idempotency_conflict' => l10nNow.theSendRequestWasUsed,
    'recipient_required' => l10nNow.youMustEnterAtLeast,
    'invalid_recipient' => l10nNow.theRecipientAddressIsInvalid,
    'invalid_email' => l10nNow.invalidEmailAddress,
    'invalid_mail_header' => l10nNow.theEmailHeadersAreInvalid,
    'message_not_constructible' => l10nNow.theEmailCouldntBeCreated,
    'manual_setup_invalid' => l10nNow.theServerSettingsAreInvalid,
    'oauth_provider_not_configured' => l10nNow.thisSignInMethodIsnt,
    'oauth_redirect_uri_invalid' => l10nNow.theRedirectAddressIsInvalid,
    'oauth_state_invalid' => l10nNow.sessionVerificationIsInvalidTry,
    'oauth_code_exchange_failed' => l10nNow.theProviderRejectedTheSign,
    'oauth_refresh_lock_unavailable' => l10nNow.theServerIsBusyTry,
    'draft_delete_failed' => l10nNow.couldntDeleteTheDraftTry,
    'scheduled_send_in_past' => l10nNow.aSendCantBeScheduled,
    'scheduled_send_not_pending' => l10nNow.thisSendIsNoLonger,
    'scheduled_send_modified' => l10nNow.theSendWasChangedOn,
    'scheduled_send_already_sent' => l10nNow.thisSendCanNoLonger,
    'scheduled_send_not_found' => l10nNow.scheduledSendNotFoundRefresh,
    'scheduled_send_attachment_not_found' =>
      l10nNow.theHeldAttachmentWasntFound,
    'identity_not_found' => l10nNow.theSelectedIdentityWasntFound,
    'signature_not_found' => l10nNow.theSelectedSignatureWasntFound,
    'identity_already_exists' => l10nNow.thisAddressIsAlreadyRegistered,
    'identity_in_use' => l10nNow.thisIdentityIsUsedIn,
    'session_revoked' => l10nNow.theSessionIsAlreadyClosed,
    'body_required' => l10nNow.theEmailBodyCantBe,
    'body_too_large' => l10nNow.theEmailBodyIsToo,
    'attachment_too_large' ||
    'too_many_attachments' => l10nNow.attachmentLimitExceeded,
    'mail_folder_exists' => l10nNow.aFolderWithThisName,
    'mail_folder_not_empty' => l10nNow.theFolderIsntEmptyMove,
    'mail_folder_has_children' => l10nNow.deleteTheSubfoldersFirst,
    'mail_folder_protected' => l10nNow.thisFolderCantBeChanged,
    'invalid_folder_name' => l10nNow.theFolderNameIsInvalid,
    'mail_folder_rejected' => l10nNow.theMailServerDidntAccept,
    'mail_folder_unavailable' => l10nNow.theFolderWasRemovedFrom,
    'sync_queue_full' => l10nNow.theSyncQueueIsFull,
    'sync_retry_deferred' => l10nNow.syncWasPostponedTryAgain,
    'sync_interrupted' => l10nNow.syncWasInterruptedTryAgain,
    'sync_failed' => l10nNow.syncCouldntBeCompletedTry,
    'mail_account_needs_reauthentication' ||
    'credential_missing' => l10nNow.theAccountNeedsToBe,
    'unsupported_authentication_method' =>
      l10nNow.thisSignInMethodIsntSupported,
    'mail_smtp_authentication_failed' => l10nNow.theSmtpPasswordWasRejected,
    'provider_disabled' ||
    'provider_new_accounts_disabled' ||
    'provider_existing_accounts_disabled' ||
    'authentication_method_disabled' => l10nNow.thisSignInIsntSupported,
    'unexpected_error' => l10nNow.anUnexpectedErrorOccurred,
    _ => title ?? l10nNow.theRequestCouldntBeCompleted,
  };

  @override
  String toString() => 'ApiException($status, $code, $correlationId)';
}
