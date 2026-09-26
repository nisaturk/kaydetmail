import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/repositories/api_mail_repository.dart';
import 'package:kaydetmail/services/api_auth_service.dart';
import 'package:kaydetmail/services/api_client.dart';
import 'package:kaydetmail/services/api_exception.dart';
import 'package:kaydetmail/services/api_mail_service.dart';
import 'package:kaydetmail/services/device_identifier_provider.dart';
import 'package:kaydetmail/services/mail_cache.dart';
import 'package:kaydetmail/services/token_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('addManualContact writes through to the backend and survives a fresh '
      'repository instance', () async {
    final mailService = _RecordingMailService();
    final db = MailCache.inMemory();
    final repo1 = await _repositoryWithLoadedInbox(mailService, cache: db);

    final created = await repo1.addManualContact(
      email: 'friend@example.com',
      displayName: 'Arkadaş',
    );

    expect(created.email, 'friend@example.com');
    expect(mailService.contacts, hasLength(1));
    expect(repo1.getManualContacts().map((c) => c.email), [
      'friend@example.com',
    ]);

    // A second repository instance (e.g. after an app restart) reloads
    // from the backend fake, not local state.
    final repo2 = await _repositoryWithLoadedInbox(mailService, cache: db);
    expect(repo2.getManualContacts().map((c) => c.email), [
      'friend@example.com',
    ]);
  });

  test(
    'addManualContact rejects a duplicate email (case-insensitive)',
    () async {
      final mailService = _RecordingMailService();
      final repo = await _repositoryWithLoadedInbox(mailService);
      await repo.addManualContact(email: 'friend@example.com');

      expect(
        () => repo.addManualContact(email: 'FRIEND@example.com'),
        throwsArgumentError,
      );
      expect(mailService.contacts, hasLength(1));
    },
  );

  test(
    'updateManualContact edits email/name; deleteManualContact removes it',
    () async {
      final mailService = _RecordingMailService();
      final repo = await _repositoryWithLoadedInbox(mailService);
      final contact = await repo.addManualContact(
        email: 'old@example.com',
        displayName: 'Eski',
      );

      await repo.updateManualContact(
        id: contact.id,
        email: 'new@example.com',
        displayName: 'Yeni',
      );
      expect(repo.getManualContacts().single.email, 'new@example.com');
      expect(repo.getManualContacts().single.displayName, 'Yeni');

      await repo.deleteManualContact(contact.id);
      expect(repo.getManualContacts(), isEmpty);
      expect(mailService.contacts, isEmpty);
    },
  );

  test('a failed delete never desyncs local state', () async {
    final mailService = _RecordingMailService();
    final repo = await _repositoryWithLoadedInbox(mailService);
    final contact = await repo.addManualContact(email: 'keep@example.com');
    mailService.failNextDelete = true;

    await repo.deleteManualContact(contact.id);

    expect(repo.getManualContacts().single.email, 'keep@example.com');
  });

  group('offline manual contact changes', () {
    test('a contact created offline shows immediately, then replays once '
        'after reconnecting', () async {
      final mailService = _RecordingMailService();
      final repo = await _repositoryWithLoadedInbox(mailService);

      mailService.offline = true;
      final created = await repo.addManualContact(
        email: 'friend@example.com',
        displayName: 'Arkadaş',
      );

      expect(repo.isOffline, isTrue);
      expect(repo.getManualContacts().single.email, 'friend@example.com');
      expect(await repo.queuedOfflineMutationCount('account-1'), 1);
      expect(mailService.contacts, isEmpty);

      mailService.offline = false;
      await repo.refreshEmails(MailFolder.inbox);

      expect(mailService.contacts.single['email'], 'friend@example.com');
      expect(mailService.contacts.single['displayName'], 'Arkadaş');
      final synced = repo.getManualContacts().single;
      expect(synced.id, mailService.contacts.single['id']);
      expect(synced.id, isNot(created.id));
      expect(await repo.queuedOfflineMutationCount('account-1'), 0);
      expect(repo.offlineMutationConflicts, isEmpty);
    });

    test('editing a contact created offline replays a single create with '
        'the edited values', () async {
      final mailService = _RecordingMailService();
      final repo = await _repositoryWithLoadedInbox(mailService);

      mailService.offline = true;
      final created = await repo.addManualContact(email: 'old@example.com');
      await repo.updateManualContact(
        id: created.id,
        email: 'new@example.com',
        displayName: 'Yeni',
      );
      expect(await repo.queuedOfflineMutationCount('account-1'), 1);

      mailService.offline = false;
      await repo.refreshEmails(MailFolder.inbox);

      expect(mailService.contacts.single['email'], 'new@example.com');
      expect(mailService.contacts.single['displayName'], 'Yeni');
      expect(await repo.queuedOfflineMutationCount('account-1'), 0);
    });

    test(
      'a queued create survives a repository restart while offline',
      () async {
        final mailService = _RecordingMailService();
        final cache = MailCache.inMemory();
        final first = await _repositoryWithLoadedInbox(
          mailService,
          cache: cache,
        );

        mailService.offline = true;
        await first.addManualContact(email: 'saved@example.com');
        final restored = await _repositoryWithLoadedInbox(
          mailService,
          cache: cache,
        );
        expect(restored.getManualContacts().single.email, 'saved@example.com');
        expect(await restored.queuedOfflineMutationCount('account-1'), 1);

        mailService.offline = false;
        await restored.refreshEmails(MailFolder.inbox);
        expect(
          restored.getManualContacts().single.id,
          mailService.contacts.single['id'],
        );
        expect(await restored.queuedOfflineMutationCount('account-1'), 0);
      },
    );

    test(
      'deleting a contact created offline cancels its queued create',
      () async {
        final mailService = _RecordingMailService();
        final repo = await _repositoryWithLoadedInbox(mailService);
        mailService.offline = true;
        final created = await repo.addManualContact(
          email: 'cancel@example.com',
        );

        await repo.deleteManualContact(created.id);
        expect(repo.getManualContacts(), isEmpty);
        expect(await repo.queuedOfflineMutationCount('account-1'), 0);

        mailService.offline = false;
        await repo.refreshEmails(MailFolder.inbox);
        expect(mailService.contacts, isEmpty);
      },
    );

    test('a contact deleted offline disappears immediately, then the delete '
        'replays after reconnecting', () async {
      final mailService = _RecordingMailService();
      final repo = await _repositoryWithLoadedInbox(mailService);
      final contact = await repo.addManualContact(email: 'gone@example.com');

      mailService.offline = true;
      await repo.deleteManualContact(contact.id);

      expect(repo.getManualContacts(), isEmpty);
      expect(mailService.contacts, hasLength(1));
      expect(await repo.queuedOfflineMutationCount('account-1'), 1);

      mailService.offline = false;
      await repo.refreshEmails(MailFolder.inbox);

      expect(mailService.contacts, isEmpty);
      expect(repo.getManualContacts(), isEmpty);
      expect(await repo.queuedOfflineMutationCount('account-1'), 0);
    });

    test('an offline edit the server rejects on replay is surfaced and '
        'rolled back to the server state', () async {
      final mailService = _RecordingMailService();
      final repo = await _repositoryWithLoadedInbox(mailService);
      final contact = await repo.addManualContact(email: 'old@example.com');

      mailService.offline = true;
      await repo.updateManualContact(id: contact.id, email: 'new@example.com');
      final editedOffline = repo.getManualContacts().single.email;

      mailService.offline = false;
      mailService.rejectionCode = 'validation_failed';
      await repo.refreshEmails(MailFolder.inbox);

      expect(editedOffline, 'new@example.com');
      expect(repo.offlineMutationConflicts, [contact.id]);
      expect(repo.getManualContacts().single.email, 'old@example.com');
      expect(mailService.contacts.single['email'], 'old@example.com');
      expect(await repo.queuedOfflineMutationCount('account-1'), 0);
    });
  });
}

Future<ApiMailRepository> _repositoryWithLoadedInbox(
  _RecordingMailService mailService, {
  MailCache? cache,
}) async {
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
    openCache: cache == null ? null : () async => cache,
  );
  await repo.restoreSession('person@example.com');
  await repo.loadMoreEmails(MailFolder.inbox);
  return repo;
}

class _RecordingMailService extends ApiMailService {
  _RecordingMailService()
    : super(ApiClient(tokenStore: TokenStore(storage: _MemoryTokenStorage())));

  final List<Map<String, dynamic>> contacts = [];
  bool failNextDelete = false;
  bool offline = false;
  String? rejectionCode;
  int _seq = 0;

  @override
  Future<List<ApiMailFolder>> getFolders() async => [
    ApiMailFolder(
      id: 'folder-inbox',
      mailAccountId: 'account-1',
      name: 'Inbox',
      type: 'Inbox',
    ),
  ];

  @override
  Future<MailListPage> getMails({
    required String folderId,
    required MailFolder Function(String folderId) resolveFolder,
    int page = 1,
    int pageSize = 20,
    bool? isRead,
    bool? hasAttachments,
    String? search,
  }) async =>
      MailListPage(items: const [], page: page, pageSize: pageSize, total: 0);

  @override
  Future<List<Map<String, dynamic>>> getContacts() async {
    if (offline) {
      throw const ApiException(status: 0, code: 'network_unavailable');
    }
    return List.from(contacts);
  }

  @override
  Future<Map<String, dynamic>> createContact(
    String email,
    String? displayName,
  ) async {
    if (offline) {
      throw const ApiException(status: 0, code: 'network_unavailable');
    }
    if (rejectionCode case final code?) {
      throw ApiException(status: 409, code: code);
    }
    final normalized = email.toLowerCase();
    if (contacts.any(
      (c) => (c['email'] as String).toLowerCase() == normalized,
    )) {
      throw const ApiException(status: 409, code: 'contact_already_exists');
    }
    final created = {
      'id': 'contact-${_seq++}',
      'email': email,
      'displayName': displayName,
    };
    contacts.add(created);
    return created;
  }

  @override
  Future<Map<String, dynamic>> updateContact(
    String id,
    String email,
    String? displayName,
  ) async {
    if (offline) {
      throw const ApiException(status: 0, code: 'network_unavailable');
    }
    if (rejectionCode case final code?) {
      throw ApiException(status: 409, code: code);
    }
    final index = contacts.indexWhere((c) => c['id'] == id);
    final updated = {'id': id, 'email': email, 'displayName': displayName};
    if (index >= 0) contacts[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteContact(String id) async {
    if (offline) {
      throw const ApiException(status: 0, code: 'network_unavailable');
    }
    if (rejectionCode case final code?) {
      throw ApiException(status: 409, code: code);
    }
    if (failNextDelete) {
      failNextDelete = false;
      throw const ApiException(status: 500);
    }
    contacts.removeWhere((c) => c['id'] == id);
  }
}

class _MemoryTokenStorage implements TokenStorage {
  final Map<String, String> _values = {};

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}
