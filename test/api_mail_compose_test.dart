import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/repositories/api_mail_repository.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/services/api_auth_service.dart';
import 'package:kaydetmail/services/api_client.dart';
import 'package:kaydetmail/services/api_mail_service.dart';
import 'package:kaydetmail/services/device_identifier_provider.dart';
import 'package:kaydetmail/services/token_store.dart';

import 'support/wire_multipart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ApiMailService compose', () {
    test('deleteAccount sends DELETE to /api/account', () async {
      late http.Request sent;
      final service = ApiMailService(
        _client((request) async {
          sent = request;
          return http.Response('', 204);
        }),
      );

      await service.deleteAccount();

      expect(sent.method, 'DELETE');
      expect(sent.url.path, '/api/account');
    });

    test(
      'createDraft posts repeated To/Cc parts and returns the server mailId',
      () async {
        late WireMultipart sent;
        final service = ApiMailService(
          _multipartClient((request) async {
            sent = request;
            return http.Response(
              jsonEncode({
                'created': true,
                'mailId': 'draft-9',
                'warning': null,
              }),
              200,
            );
          }),
        );

        final result = await service.createDraft(
          to: ['a@example.com', 'b@example.com'],
          cc: ['c@example.com'],
          subject: 'Merhaba',
          bodyText: 'Selam',
          replySourceMailId: 'mail-1',
        );

        expect(sent.url.path, '/api/drafts');
        expect(await _partValues(sent, 'To'), [
          'a@example.com',
          'b@example.com',
        ]);
        expect(await _partValues(sent, 'Cc'), ['c@example.com']);
        expect(sent.fields['subject'], 'Merhaba');
        expect(sent.fields['bodyText'], 'Selam');
        expect(sent.fields['replySourceMailId'], 'mail-1');
        expect(result.mailId, 'draft-9');
        expect(result.created, isTrue);
      },
    );

    test(
      'createDraft falls back to a null mailId when reconciliation is pending',
      () async {
        final service = ApiMailService(
          _multipartClient(
            (_) async => http.Response(
              jsonEncode({'created': true, 'mailId': null, 'warning': null}),
              200,
            ),
          ),
        );

        final result = await service.createDraft(
          to: ['a@example.com'],
          subject: 'S',
        );

        expect(result.mailId, isNull);
      },
    );

    test(
      'sendMail sends the Idempotency-Key header and attachment bytes',
      () async {
        late WireMultipart sent;
        final service = ApiMailService(
          _multipartClient((request) async {
            sent = request;
            return http.Response(
              jsonEncode({
                'sent': true,
                'sentCopySaved': true,
                'warning': null,
              }),
              200,
            );
          }),
        );

        final result = await service.sendMail(
          to: ['a@example.com'],
          subject: 'Konu',
          bodyText: 'Gövde',
          attachments: [
            Attachment(
              name: 'file.txt',
              sizeBytes: 3,
              bytes: Uint8List.fromList([1, 2, 3]),
            ),
          ],
          idempotencyKey: 'key-123',
        );

        expect(sent.url.path, '/api/mails/send');
        expect(sent.headers['Idempotency-Key'], 'key-123');
        expect(await _partValues(sent, 'To'), ['a@example.com']);
        final attachmentPart = sent.files.singleWhere(
          (f) => f.filename != null,
        );
        expect(attachmentPart.field, 'attachments');
        expect(attachmentPart.filename, 'file.txt');
        expect(result.sent, isTrue);
        expect(result.sentCopySaved, isTrue);
      },
    );

    test('sendMail includes bodyHtml as a form field when given', () async {
      late WireMultipart sent;
      final service = ApiMailService(
        _multipartClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({'sent': true, 'sentCopySaved': true, 'warning': null}),
            200,
          );
        }),
      );

      await service.sendMail(
        to: ['a@example.com'],
        subject: 'Konu',
        bodyText: '**Gövde**',
        bodyHtml: '<p><b>Gövde</b></p>',
        idempotencyKey: 'key-123',
      );

      expect(sent.fields['bodyHtml'], '<p><b>Gövde</b></p>');
    });

    test('sendMail omits the bodyHtml field entirely when null', () async {
      late WireMultipart sent;
      final service = ApiMailService(
        _multipartClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({'sent': true, 'sentCopySaved': true, 'warning': null}),
            200,
          );
        }),
      );

      await service.sendMail(
        to: ['a@example.com'],
        subject: 'Konu',
        bodyText: 'Gövde',
        idempotencyKey: 'key-123',
      );

      expect(sent.fields.containsKey('bodyHtml'), isFalse);
    });
  });

  group('ApiMailRepository compose', () {
    test(
      'sendEmail echoes into the Sent cache when the server saved a copy',
      () async {
        final mailService = _RecordingMailService();
        final repo = await _loggedInRepository(mailService);

        final email = await repo.sendEmail(
          to: ['a@example.com'],
          subject: 'Konu',
          body: 'Gövde',
        );

        expect(email.folder, MailFolder.sent);
        expect(repo.getEmailsInFolder(MailFolder.sent).single.id, email.id);
        expect(mailService.sendCalls.single.idempotencyKey, isNotEmpty);
      },
    );

    test(
      'sendEmail forwards bodyHtml to the service and echoes it locally',
      () async {
        final mailService = _RecordingMailService();
        final repo = await _loggedInRepository(mailService);

        final email = await repo.sendEmail(
          to: ['a@example.com'],
          subject: 'Konu',
          body: '**Gövde**',
          bodyHtml: '<p><b>Gövde</b></p>',
        );

        expect(mailService.sendCalls.single.bodyHtml, '<p><b>Gövde</b></p>');
        expect(email.bodyHtml, '<p><b>Gövde</b></p>');
      },
    );

    test(
      'sendEmail does not cache locally when the server reports no saved copy',
      () async {
        final mailService = _RecordingMailService()..sentCopySaved = false;
        final repo = await _loggedInRepository(mailService);

        await repo.sendEmail(
          to: ['a@example.com'],
          subject: 'Konu',
          body: 'Gövde',
        );

        expect(repo.getEmailsInFolder(MailFolder.sent), isEmpty);
      },
    );

    test(
      'sendEmail keeps unsuccessful pre-delivery send out of Sent',
      () async {
        final mailService = _RecordingMailService()..sent = false;
        final repo = await _loggedInRepository(mailService);

        await expectLater(
          repo.sendEmail(
            to: ['a@example.com'],
            subject: 'Konu',
            body: 'Gövde',
            idempotencyKey: 'stable-key',
          ),
          throwsA(isA<SendBeforeDeliveryException>()),
        );
        expect(repo.getEmailsInFolder(MailFolder.sent), isEmpty);
        expect(mailService.sendCalls.single.idempotencyKey, 'stable-key');
      },
    );

    test(
      'saveDraft uses the server-assigned mailId and caches it under Drafts',
      () async {
        final mailService = _RecordingMailService()..draftMailId = 'draft-42';
        final repo = await _loggedInRepository(mailService);

        final email = await repo.saveDraft(
          to: ['a@example.com'],
          subject: 'Taslak',
        );

        expect(email.id, 'draft-42');
        expect(email.folder, MailFolder.drafts);
        expect(repo.getEmailsInFolder(MailFolder.drafts).single.id, 'draft-42');
      },
    );

    test(
      'removeAccount deletes the account and logs out only when the id matches',
      () async {
        final mailService = _RecordingMailService();
        final repo = await _loggedInRepository(mailService);

        await repo.removeAccount('not-the-active-account');
        expect(mailService.deleteAccountCalled, isFalse);
        expect(repo.isLoggedIn, isTrue);

        await repo.removeAccount('account-1');
        expect(mailService.deleteAccountCalled, isTrue);
        expect(repo.isLoggedIn, isFalse);
      },
    );
  });
}

Future<ApiMailRepository> _loggedInRepository(
  _RecordingMailService mailService,
) async {
  SharedPreferences.setMockInitialValues({});
  final tokenStore = TokenStore(storage: _MemoryTokenStorage());
  await tokenStore.save(
    accountId: 'account-1',
    accessToken: 'access',
    refreshToken: 'refresh',
  );
  final authService = ApiAuthService(
    client: ApiClient(
      tokenStore: tokenStore,
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    ),
    tokenStore: tokenStore,
    deviceIdentifierProvider: const MemoryDeviceIdentifierProvider('device-1'),
  );
  final repo = ApiMailRepository(
    authService: authService,
    mailService: mailService,
  );
  await repo.restoreSession('person@example.com');
  return repo;
}

class _SendCall {
  _SendCall(this.idempotencyKey, this.bodyHtml);
  final String idempotencyKey;
  final String? bodyHtml;
}

class _RecordingMailService extends ApiMailService {
  _RecordingMailService()
    : super(ApiClient(tokenStore: TokenStore(storage: _MemoryTokenStorage())));

  bool sentCopySaved = true;
  bool sent = true;
  String draftMailId = 'draft-1';
  bool deleteAccountCalled = false;
  final List<_SendCall> sendCalls = [];

  @override
  Future<List<ApiMailFolder>> getFolders() async => const [];

  @override
  Future<void> deleteAccount() async {
    deleteAccountCalled = true;
  }

  @override
  Future<DraftResult> createDraft({
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    String subject = '',
    String bodyText = '',
    String? bodyHtml,
    List<Attachment> attachments = const [],
    String? replySourceMailId,
    String? identityId,
  }) async => DraftResult(created: true, mailId: draftMailId);

  @override
  Future<SendResult> sendMail({
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    required String subject,
    String bodyText = '',
    String? bodyHtml,
    List<Attachment> attachments = const [],
    String? replySourceMailId,
    String? identityId,
    required String idempotencyKey,
    void Function(int, int)? onProgress,
    Future<void>? abortTrigger,
  }) async {
    sendCalls.add(_SendCall(idempotencyKey, bodyHtml));
    return SendResult(sent: sent, sentCopySaved: sentCopySaved);
  }
}

/// Reads every no-filename multipart part named [field], in order — how
/// repeated `To`/`Cc`/`Bcc` values are sent (see `ApiMailService._composeParts`).
Future<List<String>> _partValues(WireMultipart request, String field) async =>
    request.values(field);

ApiClient _client(Future<http.Response> Function(http.Request) handler) =>
    ApiClient(
      tokenStore: TokenStore(storage: _MemoryTokenStorage()),
      accountId: 'account-1',
      httpClient: MockClient(handler),
    );

ApiClient _multipartClient(
  Future<http.Response> Function(WireMultipart) handler,
) => ApiClient(
  tokenStore: TokenStore(storage: _MemoryTokenStorage()),
  accountId: 'account-1',
  httpClient: MockClient.streaming((request, bodyStream) async {
    final response = await handler(
      await WireMultipart.decode(request, bodyStream),
    );
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
    );
  }),
);

class _MemoryTokenStorage implements TokenStorage {
  final Map<String, String> _values = {};

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}
