import 'attachment_download_manager.dart';
import 'contacts_store.dart';
import 'mail_cache.dart';
import 'signature_store.dart';

/// Single place that knows every piece of on-device data tied to a mail
/// account, so logging out, removing an account, and a server-side session
/// expiry all wipe the same things.
///
/// Credentials (tokens) and the persisted session list are cleared by their
/// own stores; this covers everything else: the encrypted mail cache (mails,
/// flags, labels, snoozes, folders, contacts, queues and the send journal),
/// downloaded attachment files, the legacy signature and the derived contact
/// address book.
class AccountDataPurger {
  AccountDataPurger({AttachmentDownloadManager? attachments})
    : _attachments = attachments ?? AttachmentDownloadManager.instance;

  final AttachmentDownloadManager _attachments;

  Future<void> purge({
    required String accountId,
    required String accountEmail,
    MailCache? cache,
  }) async {
    cache?.forgetAccount(accountId);
    // Each step is independent: one failing (e.g. a missing plugin in a
    // test, a locked file) must not leave the remaining data behind.
    for (final step in <Future<void> Function()>[
      () => _attachments.removeAccount(accountId),
      () => SignatureStore.clear(accountEmail),
      ContactsStore.clear,
    ]) {
      try {
        await step();
      } catch (_) {
        // Best-effort by design; see above.
      }
    }
  }
}
