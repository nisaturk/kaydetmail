import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/models/mail_account.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/models/remote_search_result.dart';
import 'package:kaydetmail/models/search_page.dart';
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
      SearchContinuation? continuation;
      Future<SearchPage> page() async {
        final result = await search.searchOnServer(
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
          continuation: continuation,
          pageSize: 1,
        );
        continuation = result.continuation;
        return result;
      }

      final firstPage = await page();
      expect(firstPage.items.map((mail) => mail.id), ['newer']);
      expect(firstPage.total, 2);
      expect(firstPage.hasMore, isTrue);
      expect(firstPage.accountProgress['one']!.offline, isTrue);
      final secondPage = await page();
      expect(secondPage.items.map((mail) => mail.id), ['older']);
      expect(secondPage.hasMore, isFalse);
      expect((await page()).items, isEmpty);
      expect(first.offline, isTrue);
      expect(second.offline, isFalse);
      expect(
        (await search.searchOnServer(
          query: 'domates',
          accountId: 'two',
          labelId: 'one-label',
        )).items,
        isEmpty,
      );
      expect(
        (await search.searchOnServer(
          query: 'domates',
          accountId: 'missing',
        )).items,
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
        )).items.map((mail) => mail.id),
        ['custom-mail'],
      );
      expect(
        (await search.searchOnServer(
          query: 'domates',
          customFolderId: 'foreign',
        )).items,
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
  for (final interleaved in [false, true]) {
    test(
      'all multi-account pages retain global order (interleaved: $interleaved)',
      () async {
        final ctx = _Context();
        List<Email> messages(String account, int count, int start, int step) =>
            [
              for (var i = 0; i < count; i++)
                _message('$account-$i', 1).copyWith(
                  timestamp: DateTime.utc(
                    2026,
                    9,
                    1,
                  ).add(Duration(minutes: start - i * step)),
                  accountId: account,
                ),
            ];
        final first = messages('one', 45, 200, interleaved ? 2 : 1);
        final second = messages(
          'two',
          27,
          interleaved ? 199 : 100,
          interleaved ? 2 : 1,
        );
        ctx.registry.sessions.addAll({
          'one': _session('one', messages: first),
          'two': _session('two', messages: second),
        });
        final search = SearchModule(ctx);
        var page = await search.searchOnServer(query: 'domates');
        expect(page.items.length, 20);
        expect(page.total, 72);
        expect(page.hasMore, isTrue);
        final results = [...page.items];
        while (page.hasMore) {
          page = await search.searchOnServer(
            query: 'domates',
            continuation: page.continuation,
          );
          results.addAll(page.items);
        }
        final expected = [...first, ...second]
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        expect(results.map((mail) => mail.id), expected.map((mail) => mail.id));
        expect(page.total, 72);
        expect(page.accountProgress['one']!.consumed, 45);
        expect(page.accountProgress['two']!.consumed, 27);
      },
    );
  }

  test('initial account requests overlap without changing tie order', () async {
    final ctx = _Context();
    final calls = <String>[];
    final gates = <String, Completer<void>>{};
    for (final id in ['two', 'one']) {
      final session = _session(id, messages: [_message('$id-mail', 1)]);
      ctx.registry.sessions[id] = session;
      gates[id] = Completer<void>();
      (session.mailService as _UnavailableSearch).beforeSearch = (_) {
        calls.add(id);
        return gates[id]!.future;
      };
    }
    final search = SearchModule(ctx);
    final pending = search.searchOnServer(query: 'domates', pageSize: 1);
    final started = [...calls];
    gates['one']!.complete();
    gates['two']!.complete();
    final page = await pending;

    expect(started, ['two', 'one']);
    expect(page.items.map((mail) => mail.id), ['one-mail']);
    expect(page.total, 2);
    expect(page.accountProgress.keys, ['two', 'one']);
    final next = await search.searchOnServer(
      query: 'domates',
      pageSize: 1,
      continuation: page.continuation,
    );
    expect(next.items.map((mail) => mail.id), ['two-mail']);
    expect(next.hasMore, isFalse);
    expect(calls, ['two', 'one']);
  });

  test(
    'exhausted account heads refill together and preserve checkpoints',
    () async {
      final ctx = _Context();
      for (final id in ['one', 'two']) {
        ctx.registry.sessions[id] = _session(
          id,
          messages: [for (var i = 0; i < 4; i++) _message('$id-$i', 4 - i)],
        );
      }
      final search = SearchModule(ctx);
      final initial = await search.searchOnServer(
        query: 'domates',
        pageSize: 2,
      );
      final checkpoint = SearchContinuation(
        scope: initial.continuation.scope,
        accounts: {
          for (final id in ['one', 'two'])
            id: SearchAccountCursor(
              buffered: [],
              nextPage: 2,
              total: 4,
              consumed: 2,
              remoteHasMore: true,
              offline: false,
            ),
        },
      );
      final calls = <(String, int)>[];
      final gates = <String, Completer<void>>{};
      for (final entry in ctx.registry.sessions.entries) {
        gates[entry.key] = Completer<void>();
        (entry.value.mailService as _UnavailableSearch).beforeSearch = (page) {
          calls.add((entry.key, page));
          return gates[entry.key]!.future;
        };
      }
      final pending = search.searchOnServer(
        query: 'domates',
        pageSize: 2,
        continuation: checkpoint,
      );
      final started = [...calls];
      gates['two']!.complete();
      gates['one']!.complete();
      final page = await pending;

      expect(started, [('one', 2), ('two', 2)]);
      expect(page.items.map((mail) => mail.id), ['one-2', 'two-2']);
      expect(page.total, 8);
      expect(page.accountProgress.values.map((state) => state.consumed), [
        3,
        3,
      ]);
      expect(checkpoint.accounts.values.map((state) => state.consumed), [2, 2]);

      for (final session in ctx.registry.sessions.values) {
        (session.mailService as _UnavailableSearch).beforeSearch = null;
      }
      (ctx.registry.sessions['two']!.mailService as _UnavailableSearch)
              .failPageOnce =
          2;
      await expectLater(
        search.searchOnServer(
          query: 'domates',
          pageSize: 2,
          continuation: checkpoint,
        ),
        throwsA(isA<ApiException>()),
      );
      expect(checkpoint.accounts.values.map((state) => state.consumed), [2, 2]);
      final retry = await search.searchOnServer(
        query: 'domates',
        pageSize: 2,
        continuation: checkpoint,
      );
      expect(retry.items.map((mail) => mail.id), ['one-2', 'two-2']);
    },
  );

  test(
    'parallel failures retain account error and offline side-effect order',
    () async {
      final ctx = _Context();
      const firstFailure = ApiException(status: 401);
      final calls = <String>[];
      final gates = <String, Completer<void>>{};
      for (final (id, failure) in [
        ('one', firstFailure),
        ('two', const ApiException(status: 500)),
        ('three', const ApiException(status: 0, code: 'network_unavailable')),
      ]) {
        final session = _session(id, failure: failure);
        ctx.registry.sessions[id] = session;
        gates[id] = Completer<void>();
        (session.mailService as _UnavailableSearch).beforeSearch = (_) {
          calls.add(id);
          return gates[id]!.future;
        };
      }
      final pending = SearchModule(ctx).searchOnServer(query: 'domates');
      final failure = expectLater(pending, throwsA(same(firstFailure)));
      final started = [...calls];
      gates['three']!.complete();
      gates['two']!.complete();
      gates['one']!.complete();
      await failure;

      expect(started, ['one', 'two', 'three']);
      expect(
        ctx.registry.sessions.values.every((session) => !session.offline),
        isTrue,
      );
      expect(ctx.notifications, 0);
    },
  );

  test(
    'remote imports remain sequential and stop after the first failure',
    () async {
      final ctx = _Context();
      final calls = <String>[];
      var firstGate = Completer<RemoteSearchResult>();
      for (final id in ['one', 'two']) {
        final session = _session(id);
        ctx.registry.sessions[id] = session;
        (session.mailService as _UnavailableSearch).remoteSearch = (_) {
          calls.add(id);
          return id == 'one'
              ? firstGate.future
              : Future.value(
                  const RemoteSearchResult(
                    matched: 3,
                    imported: 1,
                    remaining: 2,
                    complete: false,
                  ),
                );
        };
      }
      final search = SearchModule(ctx);
      final pending = search.searchRemote(query: 'domates');
      expect(calls, ['one']);
      firstGate.complete(
        const RemoteSearchResult(
          matched: 2,
          imported: 2,
          remaining: 0,
          complete: true,
        ),
      );
      final result = await pending;
      expect(calls, ['one', 'two']);
      expect(
        [result.matched, result.imported, result.remaining, result.complete],
        [5, 3, 2, false],
      );

      calls.clear();
      firstGate = Completer<RemoteSearchResult>();
      const error = ApiException(status: 500);
      final failed = expectLater(
        search.searchRemote(query: 'domates'),
        throwsA(same(error)),
      );
      firstGate.completeError(error);
      await failed;
      expect(calls, ['one']);
    },
  );

  test(
    'failed continuation leaves progress intact and retries the same results',
    () async {
      final ctx = _Context();
      final matches = [
        for (var i = 0; i < 45; i++)
          _message('mail-$i', 1).copyWith(
            timestamp: DateTime.utc(2026, 9, 1).subtract(Duration(minutes: i)),
          ),
      ];
      final session = _session('one', messages: matches);
      ctx.registry.sessions['one'] = session;
      final search = SearchModule(ctx);
      final first = await search.searchOnServer(query: 'domates');
      (session.mailService as _UnavailableSearch).failPageOnce = 2;
      await expectLater(
        search.searchOnServer(
          query: 'domates',
          continuation: first.continuation,
        ),
        throwsA(isA<ApiException>()),
      );
      expect(first.accountProgress['one']!.consumed, 20);
      final retry = await search.searchOnServer(
        query: 'domates',
        continuation: first.continuation,
      );
      expect(
        retry.items.map((mail) => mail.id),
        matches.skip(20).take(20).map((mail) => mail.id),
      );
      expect(retry.hasMore, isTrue);
      await expectLater(
        search.searchOnServer(
          query: 'changed',
          continuation: retry.continuation,
        ),
        throwsArgumentError,
      );
    },
  );

  test('offline pagination reaches every locally cached match with a truthful local total', () async {
    final ctx = _Context();
    final session = _session('one');
    ctx.registry.sessions['one'] = session;
    final matches = [
      for (var i = 0; i < 43; i++)
        _message('cached-$i', 1).copyWith(
          timestamp: DateTime.utc(2026, 9, 1).subtract(Duration(minutes: i)),
        ),
    ];
    session.emails[MailFolder.inbox] = matches;
    final search = SearchModule(ctx);
    var page = await search.searchOnServer(query: 'domates', accountId: 'one');
    final results = [...page.items];
    expect(page.total, 43);
    expect(page.accountProgress['one']!.offline, isTrue);
    while (page.hasMore) {
      page = await search.searchOnServer(
        query: 'domates',
        accountId: 'one',
        continuation: page.continuation,
      );
      results.addAll(page.items);
    }
    expect(results.map((mail) => mail.id), matches.map((mail) => mail.id));
    expect(page.accountProgress['one']!.consumed, 43);
  });
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

AccountSession _session(
  String id, {
  ApiException? failure,
  List<Email>? messages,
}) {
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
      messages: messages,
    ),
    account: MailAccount(id: id, email: '$id@example.test'),
  )..folderIds[MailFolder.inbox] = '$id-inbox';
}

class _UnavailableSearch extends ApiMailService {
  _UnavailableSearch(super.client, this.failure, {this.messages});
  final ApiException failure;
  final List<Email>? messages;
  int? failPageOnce;
  Future<void> Function(int page)? beforeSearch;
  Future<RemoteSearchResult> Function(String? folderId)? remoteSearch;

  @override
  Future<MailListPage> search({
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
  }) async {
    await beforeSearch?.call(page);
    if (failPageOnce == page) {
      failPageOnce = null;
      throw const ApiException(status: 500);
    }
    final matches = messages;
    if (matches == null) throw failure;
    return MailListPage(
      items: matches.skip((page - 1) * pageSize).take(pageSize).toList(),
      page: page,
      pageSize: pageSize,
      total: matches.length,
    );
  }

  @override
  Future<RemoteSearchResult> searchRemote({
    required String query,
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
  }) async {
    final action = remoteSearch;
    if (action == null) throw failure;
    return action(folderId);
  }
}

class _Context implements RepositoryContext {
  int notifications = 0;
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
  void notify() => notifications++;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
