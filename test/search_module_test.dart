import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/models/mail_account.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/repositories/api/account_session.dart';
import 'package:kaydetmail/repositories/api/repository_context.dart';
import 'package:kaydetmail/repositories/api/search_module.dart';
import 'package:kaydetmail/repositories/api/session_registry.dart';
import 'package:kaydetmail/services/api_auth_service.dart';
import 'package:kaydetmail/services/api_client.dart';
import 'package:kaydetmail/services/api_exception.dart';
import 'package:kaydetmail/services/api_mail_service.dart';
import 'package:kaydetmail/services/device_identifier_provider.dart';
import 'package:kaydetmail/services/mail_cache.dart';
import 'package:kaydetmail/services/token_store.dart';

void main() {
  test(
    'literal terms match suffixes across cached fields and require every term',
    () {
      final email = _message('match', 1).copyWith(
        subject: 'Domatesli nefis',
        bodyText: 'çorba 50%_indirim',
        cc: ['chef@example.test'],
        attachments: [const Attachment(name: 'tarif.pdf', sizeBytes: 20)],
      );
      expect(email.matchesQuery(' DOMATES\tÇORBA '), isTrue);
      expect(email.matchesQuery('domates tarif chef'), isTrue);
      expect(email.matchesQuery('domates missing'), isFalse);
      expect(email.matchesQuery('50%_indirim'), isTrue);
      expect(email.matchesQuery('50%_missing'), isFalse);
      expect(email.matchesQuery(''), isTrue);
    },
  );

  test(
    'offline search applies all filters before paging and isolates accounts',
    () async {
      final ctx = _Context();
      final first = _session('one');
      final second = _session('two');
      ctx.registry.sessions.addAll({'one': first, 'two': second});
      final cache = MailCache.inMemory();
      addTearDown(cache.db.close);
      cache.apply('one', [
        _message('older', 1),
        _message('newer', 2),
        _message('read', 3).copyWith(isRead: true),
        _message('different-thread', 4).copyWith(threadId: 'other'),
        _message('other-folder', 5).copyWith(folder: MailFolder.sent),
      ], const []);
      cache.apply('two', [_message('foreign', 6)], const []);
      first.emails[MailFolder.inbox] = cache
          .load('one')
          .where((mail) => mail.folder == MailFolder.inbox)
          .toList();
      first.emails[MailFolder.sent] = cache
          .load('one')
          .where((mail) => mail.folder == MailFolder.sent)
          .toList();
      first.labelMap.addAll({
        'older': ['one-label'],
        'newer': ['one-label'],
        'read': ['one-label'],
        'different-thread': ['one-label'],
      });
      second.emails[MailFolder.inbox] = cache.load('two');
      final search = SearchModule(ctx);
      Future<List<Email>> page(int number) => search.searchOnServer(
        query: 'DOMATES çorba',
        accountId: 'one',
        folder: MailFolder.inbox,
        conversationId: 'thread',
        from: 'CHE',
        to: 'COOK',
        fromDate: DateTime.utc(2026, 9, 1),
        toDate: DateTime.utc(2026, 9, 3),
        isRead: false,
        flagged: true,
        hasAttachment: true,
        labelId: 'one-label',
        page: number,
        pageSize: 1,
      );
      expect((await page(1)).map((mail) => mail.id), ['newer']);
      expect((await page(2)).map((mail) => mail.id), ['older']);
      expect(await page(3), isEmpty);
      expect(first.offline, isTrue);
      expect(second.offline, isFalse);
      expect(
        await search.searchOnServer(
          query: 'domates',
          accountId: 'two',
          labelId: 'one-label',
        ),
        isEmpty,
      );
      expect(
        await search.searchOnServer(query: 'domates', accountId: 'missing'),
        isEmpty,
      );
    },
  );

  test(
    'custom-folder fallback never searches another bucket or account',
    () async {
      final ctx = _Context();
      final session = _session('one');
      ctx.registry.sessions['one'] = session;
      session.customFolders = [
        ApiMailFolder(
          id: 'custom',
          mailAccountId: 'one',
          name: 'Recipes',
          type: 'Custom',
        ),
      ];
      session.emails[MailFolder.inbox] = [_message('inbox', 3)];
      session.customFolderEmails['custom'] = [_message('custom-mail', 2)];
      final search = SearchModule(ctx);
      expect(
        (await search.searchOnServer(
          query: 'domates çorba',
          customFolderId: 'custom',
        )).map((mail) => mail.id),
        ['custom-mail'],
      );
      expect(
        await search.searchOnServer(
          query: 'domates',
          customFolderId: 'foreign',
        ),
        isEmpty,
      );
    },
  );

  test(
    'authentication and server failures are not hidden by cached matches',
    () async {
      for (final status in [401, 500]) {
        final ctx = _Context();
        final session = _session('one', failure: ApiException(status: status));
        ctx.registry.sessions['one'] = session;
        session.emails[MailFolder.inbox] = [_message('cached', 1)];
        await expectLater(
          SearchModule(ctx).searchOnServer(query: 'domates'),
          throwsA(isA<ApiException>()),
        );
        expect(session.offline, isFalse);
      }
    },
  );
}

Email _message(String id, int day) => Email(
  id: id,
  senderName: 'Chef',
  senderEmail: 'chef@example.test',
  recipients: const ['cook@example.test'],
  subject: 'Domatesli nefis çorba',
  bodyText: '',
  timestamp: DateTime.utc(2026, 9, day),
  isStarred: true,
  hasAttachments: true,
  threadId: 'thread',
);

AccountSession _session(String id, {ApiException? failure}) {
  final tokens = TokenStore();
  final client = ApiClient(tokenStore: tokens);
  addTearDown(client.close);
  return AccountSession(
    authService: ApiAuthService(
      client: client,
      tokenStore: tokens,
      deviceIdentifierProvider: const MemoryDeviceIdentifierProvider(
        'search-test',
      ),
    ),
    mailService: _UnavailableSearch(
      client,
      failure ?? const ApiException(status: 0, code: 'network_unavailable'),
    ),
    account: MailAccount(id: id, email: '$id@example.test'),
  )..folderIds[MailFolder.inbox] = '$id-inbox';
}

class _UnavailableSearch extends ApiMailService {
  _UnavailableSearch(super.client, this.failure);
  final ApiException failure;

  @override
  Future<List<Email>> search({
    required String query,
    required MailFolder Function(String) resolveFolder,
    String? folderId,
    String? conversationId,
    String? from,
    String? to,
    DateTime? fromDate,
    DateTime? toDate,
    bool? isRead,
    bool? flagged,
    bool? hasAttachment,
    String? labelId,
    int page = 1,
    int pageSize = 20,
  }) async => throw failure;
}

class _Context implements RepositoryContext {
  @override
  final registry = SessionRegistry();
  @override
  bool isOfflineFailure(Object error) =>
      error is ApiException &&
      (error.category == ApiErrorCategory.network ||
          error.category == ApiErrorCategory.timeout);
  @override
  void markOffline(AccountSession session) => session.offline = true;
  @override
  void notify() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
