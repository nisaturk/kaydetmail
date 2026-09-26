import '../models/mail_signature.dart';
import '../repositories/mail_repository.dart';

enum ComposeSignatureMode { newMail, reply, forward }

Future<String> resolveComposeSignature(
  MailRepository repo, {
  required String accountId,
  required ComposeSignatureMode mode,
  MailIdentity? identity,
  String? legacySignature,
}) async {
  try {
    var signatureId = identity?.signatureId;
    if (signatureId == null) {
      final defaults = await repo.getSignatureDefaults(accountId);
      signatureId = switch (mode) {
        ComposeSignatureMode.newMail => defaults.newMailSignatureId,
        ComposeSignatureMode.reply => defaults.replySignatureId,
        ComposeSignatureMode.forward => defaults.forwardSignatureId,
      };
    }
    if (signatureId == null) return '';
    final signatures = await repo.listSignatures(accountId);
    return signatures
            .where((item) => item.id == signatureId)
            .firstOrNull
            ?.bodyText ??
        '';
  } catch (_) {
    return mode == ComposeSignatureMode.newMail ? legacySignature ?? '' : '';
  }
}
