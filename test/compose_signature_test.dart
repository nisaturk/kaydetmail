import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/models/mail_signature.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/utils/compose_signature.dart';

class _Repo extends MailRepository {
  _Repo({this.fail = false});

  final bool fail;

  MailSignature _sig(String id, String text) => MailSignature(
    id: id,
    name: id,
    bodyText: text,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );

  @override
  Future<List<MailSignature>> listSignatures(
    String accountId, {
    bool refresh = false,
  }) async {
    if (fail) throw StateError('offline');
    return [
      _sig('new', 'Yeni imza'),
      _sig('reply', 'Yanıt imzası'),
      _sig('alias', 'Kimlik imzası'),
    ];
  }

  @override
  Future<SignatureDefaults> getSignatureDefaults(String accountId) async {
    if (fail) throw StateError('offline');
    return const SignatureDefaults(
      newMailSignatureId: 'new',
      replySignatureId: 'reply',
    );
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  Future<String> resolve(
    ComposeSignatureMode mode, {
    MailRepository? repo,
    MailIdentity? identity,
  }) => resolveComposeSignature(
    repo ?? _Repo(),
    accountId: 'a',
    mode: mode,
    identity: identity,
    legacySignature: 'Eski imza',
  );

  test('each compose mode uses its own default signature', () async {
    expect(await resolve(ComposeSignatureMode.newMail), 'Yeni imza');
    expect(await resolve(ComposeSignatureMode.reply), 'Yanıt imzası');
    expect(await resolve(ComposeSignatureMode.forward), '');
  });

  test('an identity signature wins over the mode default', () async {
    const identity = MailIdentity(
      id: 'i',
      emailAddress: 'alias@example.com',
      signatureId: 'alias',
    );
    expect(
      await resolve(ComposeSignatureMode.reply, identity: identity),
      'Kimlik imzası',
    );
  });

  test(
    'unreachable signatures fall back to the legacy one for new mail only',
    () async {
      final offline = _Repo(fail: true);
      expect(
        await resolve(ComposeSignatureMode.newMail, repo: offline),
        'Eski imza',
      );
      expect(await resolve(ComposeSignatureMode.reply, repo: offline), '');
    },
  );
}
