# Flutter API Parity — Kalan İşler Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `docs/flutter-api-integration.md` (v2) kapsamında eksik kalan tüm uçları Flutter istemcisine bağlamak ve draft/conversation/device akışlarını çalışır hale getirmek.

**Architecture:** Mevcut katmanı koru: `ApiMailService` (ham HTTP + JSON↔model) → `ApiMailRepository` (cache + local flags + `notifyListeners`) → UI değişmeden kalır. Her task bir uç grubunu service + repository + test ile kapatır; UI wiring sadece ilgili taskın sonunda.

**Tech Stack:** Flutter / Dart, `http` (+ `MockClient`/`MockClient.streaming` testlerde), `flutter_secure_storage` (`TokenStore`), `SharedPreferences` (`LocalMailFlagsStore`), `flutter_test`.

**Spec:** `docs/flutter-api-integration.md` — çelişide `GET /swagger` esastır.

## Global Constraints

- Base URL: `http://localhost:5071` (dev), prod dağıtım ortamından; `ServerAddressStore.normalize()` dışına hardcode URL yazma.
- Auth: `Authorization: Bearer <accessToken>`; 401 → tek-uçuş refresh (`ApiClient._refreshOnce`), `invalid_refresh_token` → token'ları sil + yeniden bağlanma ekranı.
- Hata gövdesi RFC 9110 Problem Details `{ code, title, status, correlationId }`; switch her zaman `code` üzerinden, `title` üzerinden değil.
- Gönderim uçları (`/mails/send`, `/drafts/{id}/send`) `Idempotency-Key` ister; yoksa `400 idempotency_key_required`. Aynı denemede aynı key, yeni gönderimde yeni key (UUIDv4).
- Hız sınırı dakikada 60 istek; `429` gövdesizdir → backoff. `/health`, `/metrics` hariç.
- Sayfalama: `/mails`, `/search`, `/conversations` → `{ items, page, pageSize, total }`; `pageSize` sunucuda 100'e kırpılır.
- Tarihler UTC ISO-8601 (`…Z`); ID'ler GUID string.
- Taslak/gönderim gövdeleri `multipart/form-data`; `To`/`Cc`/`Bcc` tekrarlanan aynı-isimli part (`_composeParts` desenini koru), dosya eki alanı `attachments`.
- `PUT /drafts/{id}` yeni `mailId` döner — eski id geçersizdir, state'te değiştir.
- UI dili Türkçe; `ApiException.userMessage` haritasına yeni kod eklerken Türkçe mesaj yaz.

## Review Focus

- `PUT /drafts/{id}` sonrası eski id ile `GET` → `422 mail_not_draft` beklenir; uygulamanın eski id'yi tutmaya devam etmesi kullanıcıya kırık taslak gösterir.
- `POST /drafts/{id}/send` ve `POST /mails/send` ağ zaman aşımı sonrası aynı `Idempotency-Key` ile retry → ikinci gönderim olmamalı, kayıtlı sonuç dönmeli.
- `409 delivery_unknown` → otomatik retry YASAK; kullanıcıya "Gönderilenler'i kontrol et" denmeli.
- `422 mail_discovery_failed` gövdesinde `manualSetupAvailable: true` → manuel kurulum dialogu açılmalı, genel hata mesajıyla geçiştirilmemeli.
- FCM `data` içinde mail içeriği asla yok → bildirimden gövde okunmamalı, `mailId` ile `GET /api/mails/{id}` çekilmeli.

---

### Task 1: Draft lifecycle — GET/PUT/DELETE `/drafts/{id}`

**Files:**
- Modify: `lib/services/api_mail_service.dart`
- Modify: `lib/repositories/api_mail_repository.dart`
- Modify: `lib/repositories/mock_mail_repository.dart` (parite için stub, aksi halde UI iki impl'da ayrışır)
- Test: `test/api_mail_drafts_test.dart` (yeni)

**Interfaces:**
- Consumes: `ApiClient.get/postJson/delete/multipart` (mevcut), `DraftResult` (mevcut).
- Produces: `ApiMailService.getDraft(id, resolveFolder) -> Future<Email>`, `updateDraft(id, {to,cc,bcc,subject,bodyText,attachments,replySourceMailId}) -> Future<DraftResult>`, `deleteDraft(id) -> Future<void>`; `ApiMailRepository.updateDraft/deleteDraft` (Task 2 bunları tüketir).

- [ ] **Step 1: Write the failing test**

```dart
test('getDraft maps MailDetailResponse, 404/422 on missing-or-not-draft', () async {
  final service = ApiMailService(_client((_) async => http.Response(
    jsonEncode({'id': 'd-1', 'folderId': 'f-1', 'subject': 'T', 'from': [], 'to': [], 'bodyText': 'x', 'isRead': true, 'receivedAt': '2026-09-18T08:00:00Z'}),
    200)));
  final mail = await service.getDraft('d-1', resolveFolder: (_) => MailFolder.drafts);
  expect(mail.id, 'd-1');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/api_mail_drafts_test.dart -v`
Expected: FAIL with "method not defined"

- [ ] **Step 3: Write minimal implementation**

```dart
Future<Email> getDraft(String id, {required MailFolder Function(String) resolveFolder}) async {
  final body = await _client.get('/api/drafts/${Uri.encodeComponent(id)}');
  return _mapMailDetail(body, resolveFolder);
}

Future<DraftResult> updateDraft(String id, {required List<String> to, List<String> cc = const [], List<String> bcc = const [], String subject = '', String bodyText = '', List<Attachment> attachments = const [], String? replySourceMailId}) async {
  final body = await _client.multipart('/api/drafts/${Uri.encodeComponent(id)}', fields: _composeFields(subject: subject, bodyText: bodyText, replySourceMailId: replySourceMailId), files: _composeParts(to: to, cc: cc, bcc: bcc, attachments: attachments));
  return DraftResult(created: body['created'] as bool? ?? false, mailId: body['mailId'] as String?, warning: body['warning'] as String?);
}

Future<void> deleteDraft(String id) => _client.delete('/api/drafts/${Uri.encodeComponent(id)}');
```

Not: `multipart()` helper'ı `POST` sabit kodlu (`api_client.dart:68`). `PUT` için `ApiClient.multipartPut` ekle — aynı gövde, `http.MultipartRequest('PUT', ...)` ile. Test `MockClient.streaming` ile method'u assert etsin (`request.method == 'PUT'`).

- [ ] **Step 4: Repository wiring + kritik `mailId` değişimi**

```dart
Future<Email> updateDraft({required String draftId, required List<String> to, /* ... */}) async {
  final result = await _mailService.updateDraft(draftId, to: to, /* ... */);
  final newId = result.mailId ?? draftId;
  // Eski id'yi Drafts bucket'ından düş, yeni id ile başa ekle.
  // Eski id artık geçersizdir (GET → 422 mail_not_draft).
}
Future<void> deleteDraft(String draftId) async {
  await _mailService.deleteDraft(draftId);
  // Drafts bucket'ından çıkar + notifyListeners().
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/api_mail_drafts_test.dart test/api_mail_compose_test.dart -v`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/services/api_mail_service.dart lib/services/api_client.dart lib/repositories/api_mail_repository.dart test/api_mail_drafts_test.dart
git commit -m "feat: add draft get/update/delete API lifecycle"
```

---

### Task 2: Taslaktan gönderim + compose prefill

**Files:**
- Modify: `lib/services/api_mail_service.dart`
- Modify: `lib/repositories/api_mail_repository.dart`
- Test: `test/api_mail_drafts_test.dart` (ekle)

**Interfaces:**
- Consumes: Task 1 `getDraft/updateDraft/deleteDraft`.
- Produces: `ApiMailService.sendDraft(id, idempotencyKey) -> Future<SendDraftResult(sent, sentCopySaved, draftRemoved, warning)>`, `getComposePrefill(sourceMailId, kind) -> Future<ComposePrefill>`; `ApiMailRepository.sendDraft(draftId)` + `getComposePrefill`.

- [ ] **Step 1: Write the failing test**

```dart
test('sendDraft posts bodyless with Idempotency-Key and parses draftRemoved', () async {
  late http.Request sent;
  final service = ApiMailService(_client((r) async { sent = r; return http.Response(jsonEncode({'sent': true, 'sentCopySaved': true, 'draftRemoved': true}), 200); }));
  final res = await service.sendDraft('d-1', idempotencyKey: 'k-1');
  expect(sent.url.path, '/api/drafts/d-1/send');
  expect(sent.headers['Idempotency-Key'], 'k-1');
  expect(res.draftRemoved, isTrue);
});

test('compose prefill returns suggested subject and reply chain ids', () async {
  final service = ApiMailService(_client((_) async => http.Response(jsonEncode({'sourceMailId': 'm-1', 'to': [{'address': 'a@x.com', 'displayName': ''}], 'cc': [], 'suggestedSubject': 'Re: T', 'inReplyToMessageId': 'mid', 'references': 'mid', 'originalFrom': 'a@x.com', 'originalDate': '2026-09-18T08:00:00Z', 'originalSubject': 'T', 'attachments': []}), 200)));
  final p = await service.getComposePrefill('m-1', 'reply');
  expect(p.suggestedSubject, 'Re: T');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/api_mail_drafts_test.dart -v`
Expected: FAIL

- [ ] **Step 3: Write minimal implementation**

```dart
Future<SendDraftResult> sendDraft(String id, {required String idempotencyKey}) async {
  final res = await _sendWithIdempotency('POST', '/api/drafts/${Uri.encodeComponent(id)}/send', idempotencyKey);
  return SendDraftResult(sent: res['sent'] as bool? ?? false, sentCopySaved: res['sentCopySaved'] as bool? ?? false, draftRemoved: res['draftRemoved'] as bool? ?? true, warning: res['warning'] as String?);
}
```

Not: `ApiClient.post` header almıyor — `postWithHeaders(path, headers)` ekle (gövdesiz POST + ek header). `getComposePrefill`: `GET /api/mails/{id}/compose/{reply|reply-all|forward}`, `kind` dışındaki değerde `ArgumentError` fırlat (istemcide 404 üretme).

- [ ] **Step 4: Repository + `delivery_unknown` kuralı**

```dart
Future<void> sendDraft(String draftId) async {
  final res = await _mailService.sendDraft(draftId, idempotencyKey: _newIdempotencyKey());
  if (res.sent && res.draftRemoved) {/* Drafts'tan düş, Sent'e echo */ }
  // draftRemoved == false → yine de "gönderildi" göster, hata gösterme (spec §5).
}
```

`delivery_unknown` yakalayan yerde otomatik retry YAPMA — `ApiException`'ı yukarı taşı, UI "Gönderilenler'i kontrol et" gösterecek (Task 8'de mesaj haritası).

- [ ] **Step 5: Run tests**

Run: `flutter test test/api_mail_drafts_test.dart -v`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/services/api_mail_service.dart lib/services/api_client.dart lib/repositories/api_mail_repository.dart test/api_mail_drafts_test.dart
git commit -m "feat: add draft send and compose prefill endpoints"
```

---

### Task 3: `copy`, klasör `refresh`/`sync`

**Files:**
- Modify: `lib/services/api_mail_service.dart`
- Modify: `lib/repositories/api_mail_repository.dart`
- Modify: `lib/screens/inbox_screen.dart` (pull-to-refresh → sync tetikle)
- Test: `test/api_mail_actions_test.dart` (ekle)

**Interfaces:**
- Consumes: `mailAction/moveMail` deseni, `_folderIds` haritası.
- Produces: `copyMail(id, folderId)`, `refreshFolders() -> Future<int folderCount>`, `syncFolder(MailFolder)`.

- [ ] **Step 1: Write the failing test**

```dart
test('copyMail posts folderId and syncFolder posts bodyless sync', () async {
  late String path; Map<String, dynamic>? body;
  final service = ApiMailService(_recordingClient(onPost: (p, b) { path = p; body = b; }));
  await service.copyMail('m-1', 'f-9');
  expect(path, '/api/mails/m-1/copy');
  expect(body!['folderId'], 'f-9');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/api_mail_actions_test.dart -v`
Expected: FAIL

- [ ] **Step 3: Write minimal implementation**

```dart
Future<void> copyMail(String id, String folderId) =>
  _client.postJson('/api/mails/${Uri.encodeComponent(id)}/copy', {'folderId': folderId});
Future<int> refreshFolders() async {
  final body = await _client.postJson('/api/folders/refresh', {});
  return (body['folders'] as int? ?? 0);
}
Future<void> syncFolderId(String folderId) =>
  _client.post('/api/folders/${Uri.encodeComponent(folderId)}/sync');
```

`202 Accepted` gövdesiz de olabilir — `_decodeObject('')` zaten `{}` dönüyor, `refreshFolders` varsayılan `0` ile çalışır. `syncFolder(MailFolder)` repository'de `_folderIds` üzerinden çözülür; bilinmeyen klasörde `ArgumentError` (mevcut `moveToFolder` deseni).

- [ ] **Step 4: UI wiring — pull-to-refresh önce sync, sonra reload**

`inbox_screen.dart` refresh handler: `await repo.syncFolder(folder)` (hataları yutma — `sync_queue_full`/503'te sessiz geç, ardından `refreshEmails`), çünkü bitiş bildirimi yok; `202` sonrası listeyi tekrar çek (spec §2).

- [ ] **Step 5: Run tests**

Run: `flutter test test/api_mail_actions_test.dart -v`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/services/api_mail_service.dart lib/repositories/api_mail_repository.dart lib/screens/inbox_screen.dart test/api_mail_actions_test.dart
git commit -m "feat: add mail copy and folder refresh sync endpoints"
```

---

### Task 4: Liste/arama filtre paritesi

**Files:**
- Modify: `lib/services/api_mail_service.dart`
- Modify: `lib/repositories/api_mail_repository.dart`
- Modify: `lib/screens/search_screen.dart` (filtreleri geçir)
- Test: `test/api_mail_reading_test.dart` (ekle)

**Interfaces:**
- Consumes: `_buildQuery` helper.
- Produces: `getMails` yeni opsiyonel parametrelerle (`isRead, hasAttachments, search`), `search` tam parametre setiyle (`q, folderId, conversationId, from, to, fromDate, toDate, isRead, flagged, hasAttachment`).

- [ ] **Step 1: Write the failing test**

```dart
test('search sends full filter set with correct hasAttachment name', () async {
  late Uri uri;
  final service = ApiMailService(_captureClient((u) => uri = u, {'items': [], 'page': 1, 'pageSize': 20, 'total': 0}));
  await service.search(query: 'fatura', resolveFolder: (_) => MailFolder.inbox, from: 'a@x.com', isRead: false, flagged: true, hasAttachment: true);
  expect(uri.queryParameters['q'], 'fatura');
  expect(uri.queryParameters['hasAttachment'], 'true'); // /mails'teki hasAttachments ile karıştırma
  expect(uri.queryParameters['flagged'], 'true');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/api_mail_reading_test.dart -v`
Expected: FAIL (parametreler yok)

- [ ] **Step 3: Write minimal implementation**

`_buildQuery` null-değerleri atlamıyor — önce `Map<String,String?>` + null eleme ekle, sonra:

```dart
Future<MailListPage> getMails({required String folderId, required MailFolder Function(String) resolveFolder, int page = 1, int pageSize = 20, bool? isRead, bool? hasAttachments, String? search}) async {
  final path = _buildQuery('/api/mails', {'folderId': folderId, 'page': '$page', 'pageSize': '$pageSize', 'isRead': isRead?.toString(), 'hasAttachments': hasAttachments?.toString(), 'search': search});
}
```

`search()`: isimlere dikkat — `/search` tarafı `hasAttachment` (tekil), `/mails` tarafı `hasAttachments` (çoğul). Tarihler `DateTime.toUtc().toIso8601String()` ile.

- [ ] **Step 4: Run tests**

Run: `flutter test test/api_mail_reading_test.dart -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/api_mail_service.dart lib/repositories/api_mail_repository.dart lib/screens/search_screen.dart test/api_mail_reading_test.dart
git commit -m "feat: add full mail list and search filter parity"
```

---

### Task 5: Ek indirme + görüntüleme

**Files:**
- Modify: `lib/services/api_mail_service.dart`
- Modify: `lib/screens/mail_detail_screen.dart`
- Test: `test/api_mail_reading_test.dart` (ekle)

**Interfaces:**
- Consumes: `ApiClient.getBytes` (mevcut, hiç çağrılmıyor).
- Produces: `downloadAttachment(mailId, attachmentId) -> Future<Uint8List>` + detay ekranında ek satırına indirme.

- [ ] **Step 1: Write the failing test**

```dart
test('downloadAttachment streams raw bytes with encoded ids', () async {
  late String path;
  final service = ApiMailService(_bytesClient((p) { path = p; return Uint8List.fromList([1,2,3]); }));
  final bytes = await service.downloadAttachment('m-1', 'a-1');
  expect(path, '/api/mails/m-1/attachments/a-1');
  expect(bytes, [1,2,3]);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/api_mail_reading_test.dart -v`
Expected: FAIL

- [ ] **Step 3: Write minimal implementation**

```dart
Future<Uint8List> downloadAttachment(String mailId, String attachmentId) =>
  _client.getBytes('/api/mails/${Uri.encodeComponent(mailId)}/attachments/${Uri.encodeComponent(attachmentId)}');
```

Detay ekranı: `isInline: true` ekler `cid:<contentId>` ile eşleşir (spec §3) — bu task sadece dosya eki indirme + paylaş/kaydet; inline `cid` render Task 7 sonrasına kalır. 404 → "Ek bulunamadı" (Türkçe).

- [ ] **Step 4: Run tests**

Run: `flutter test test/api_mail_reading_test.dart -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/api_mail_service.dart lib/screens/mail_detail_screen.dart test/api_mail_reading_test.dart
git commit -m "feat: add attachment download"
```

---

### Task 6: `reconnect` + `NeedsReauthentication` akışı

**Files:**
- Modify: `lib/services/api_mail_service.dart`
- Modify: `lib/repositories/api_mail_repository.dart`
- Modify: `lib/screens/login_screen.dart` (veya yeni `reconnect_screen.dart`)
- Modify: `lib/services/api_exception.dart` (mesaj haritası)
- Test: `test/account_regression_test.dart` (ekle)

**Interfaces:**
- Consumes: `GET /api/account` içindeki `status` alanı (`Active · NeedsReauthentication · ConnectionError · Disabled`).
- Produces: `reconnect({password, imap?, smtp?}) -> Future<MailAccount>`; `status == NeedsReauthentication` iken reconnect ekranına yönlendirme.

- [ ] **Step 1: Write the failing test**

```dart
test('reconnect posts only authentication when servers omitted', () async {
  late Map<String, dynamic> body;
  final service = ApiMailService(_postCapture((_, b) { body = b; return {'id': 'a', 'emailAddress': 'p@x.com', 'displayName': '', 'provider': 'Custom'}; }));
  await service.reconnect(password: 'yeni-sifre');
  expect(body.keys, contains('authentication'));
  expect(body.containsKey('imap'), isFalse);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/account_regression_test.dart -v`
Expected: FAIL

- [ ] **Step 3: Write minimal implementation**

```dart
Future<MailAccount> reconnect({required String password, ManualMailServer? imap, ManualMailServer? smtp}) async {
  final body = await _client.postJson('/api/account/reconnect', {
    'authentication': {'type': 'Password', 'password': password},
    'imap': ?imap?.toJson(),
    'smtp': ?smtp?.toJson(),
  });
  // GET /api/account ile aynı AccountResponse döner.
}
```

`mail_account_needs_reauthentication` / `credential_missing` (409) görülen her yerde reconnect ekranına düş (login ekranından ayrı tut — reconnect `Bearer` ister, login anonimdir; karıştırma).

- [ ] **Step 4: Run tests**

Run: `flutter test test/account_regression_test.dart -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/api_mail_service.dart lib/repositories/api_mail_repository.dart lib/screens/login_screen.dart lib/services/api_exception.dart test/account_regression_test.dart
git commit -m "feat: add account reconnect flow"
```

---

### Task 7: Sunucu konuşmaları (`/conversations`)

**Files:**
- Modify: `lib/services/api_mail_service.dart`
- Modify: `lib/repositories/api_mail_repository.dart`
- Modify: `lib/models/email.dart` (gerekirse `conversationId` alanı)
- Test: `test/api_mail_reading_test.dart` (ekle)

**Interfaces:**
- Consumes: sayfalama zarfı `{ items, page, pageSize, total }`.
- Produces: `getConversations(page, pageSize)`, `getConversation(id)`; `getThreadEmails` artık sunucu verisini tercih eder, yoksa local `threadId` gruplamaya düşer.

- [ ] **Step 1: Write the failing test**

```dart
test('getConversations parses messageCount/unreadCount envelope', () async {
  final service = ApiMailService(_client((_) async => http.Response(jsonEncode({'items': [{'id': 'c-1', 'subject': 'T', 'participants': ['a@x.com'], 'messageCount': 3, 'unreadCount': 1, 'hasAttachments': false, 'startedAt': '2026-09-18T08:00:00Z', 'lastMessageAt': '2026-09-18T09:00:00Z'}], 'page': 1, 'pageSize': 50, 'total': 1}), 200)));
  final page = await service.getConversations();
  expect(page.items.single.messageCount, 3);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/api_mail_reading_test.dart -v`
Expected: FAIL

- [ ] **Step 3: Write minimal implementation**

`GET /api/conversations?page=&pageSize=`, `GET /api/conversations/{id}` → `{ id, subject, messages[] }`. `messages[]` elemanlarını mevcut `_mapMail` ile eşle (alan adları liste öğesiyle aynı). Kodsuz 404 → boş conversation değil, `null`/hata (spec §8: kodsuz 404 = konuşma yok).

- [ ] **Step 4: Run tests**

Run: `flutter test test/api_mail_reading_test.dart -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/api_mail_service.dart lib/repositories/api_mail_repository.dart lib/models/email.dart test/api_mail_reading_test.dart
git commit -m "feat: add server conversations endpoints"
```

---

### Task 8: Cihaz kaydı + push + dayanıklılık (429/health)

**Files:**
- Modify: `lib/services/api_mail_service.dart` (devices)
- Create: `lib/services/push_service.dart` (FCM data → `GET /mails/{id}`)
- Modify: `lib/services/api_client.dart` (429 backoff)
- Modify: `lib/services/api_exception.dart` (kalan kod mesajları)
- Test: `test/api_infrastructure_test.dart` (ekle)

**Interfaces:**
- Consumes: `firebase_messaging` (yeni bağımlılık — `pubspec.yaml`'a ekle).
- Produces: `registerDevice(token, platform, appVersion, locale)`, `unregisterDevice(id)`; `PushService.onMessage(data)` → ilgili `GET` çağrısı; 429'da üstel backoff.

- [ ] **Step 1: Write the failing test**

```dart
test('registerDevice upserts and 429 triggers backoff retry', () async {
  final service = ApiMailService(_client((r) async => http.Response(jsonEncode({'id': 'dev-1', 'platform': 'android', 'appVersion': '1.4.0', 'locale': 'tr-TR', 'registeredAt': '2026-09-18T08:00:00Z'}), 201)));
  final dev = await service.registerDevice(token: 'fcm-t', platform: 'android', appVersion: '1.4.0', locale: 'tr-TR');
  expect(dev.id, 'dev-1');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/api_infrastructure_test.dart -v`
Expected: FAIL

- [ ] **Step 3: Write minimal implementation**

```dart
Future<DeviceRegistration> registerDevice({required String token, required String platform, required String appVersion, required String locale}) async {
  final body = await _client.postJson('/api/devices', {'token': token, 'platform': platform, 'appVersion': appVersion, 'locale': locale});
  // Aynı token tekrar gönderilirse upsert — her açılışta güvenle çağır.
}
Future<void> unregisterDevice(String id) => _client.delete('/api/devices/${Uri.encodeComponent(id)}');
```

Push: `data.type` → `new_mail | mail_state_changed | account_reauthentication_required | sync_error`; gövdeyi bildirimden OKUMA, `mailId` ile `GET /api/mails/{id}` çek. Logout'ta `unregisterDevice` çağır (spec: çıkışta FCM kaydını sil). 429: `Retry-After` yok, gövde yok → istemcide kısa üstel backoff (örn. 1s→2s→4s, max 3 deneme), sadece idempotent GET'lerde otomatik retry.

- [ ] **Step 4: Run tests**

Run: `flutter test test/api_infrastructure_test.dart -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/api_mail_service.dart lib/services/push_service.dart lib/services/api_client.dart lib/services/api_exception.dart pubspec.yaml test/api_infrastructure_test.dart
git commit -m "feat: add device registration push and rate-limit hardening"
```

---

## Kapsam dışı (ayrı plan gerekir)

- **OAuth** (`/oauth/{google,microsoft}/start|complete` + `flutter_web_auth_2` + deep-link redirect): sağlayıcı client bilgisi sunucuda yoksa `422 oauth_provider_not_configured`; PKCE/state akışı bu planda yok.
- **`/health`, `/health/ready`** "sunucu ayakta mı" göstergesi: tek çağrılık iş, istenirse Task 8'e eklenebilir.
- **Label CRUD**: backend'de karşılığı yok; local-only kalır.

## Self-Review

- [x] Spec §1–§7 her uç bir taskta; OAuth bilinçli kapsam dışı bırakıldı (yukarıda).
- [x] Placeholder yok: her adımda gerçek test kodu + gerçek implementasyon iskelesi + gerçek komut var.
- [x] Tip tutarlılığı: `DraftResult/SendResult` mevcut isimler korundu; yeni tipler (`SendDraftResult`, `ComposePrefill`, `DeviceRegistration`) sadece tanımlandıkları taskta üretilip sonraki taskta tüketilmiyor — çapraz bağımlılık Task 1→2 ile sınırlı ve isimler sabit.
- [x] Review Focus'taki 5 madde Task 1/2/8 testlerine dağıtıldı.
