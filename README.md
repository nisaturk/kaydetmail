# kaydetmail

A Flutter IMAP/SMTP mail client (Turkish UI) for a custom mail backend. Multi-account,
offline-first, push-driven — connect any mailbox that speaks IMAP/SMTP (or OAuth to
Google/Microsoft) and read, search, and act on mail across every connected account from
one unified inbox.

## Features

- **Multi-account, unified inbox.** Connect several mailboxes; browse them individually
  or as one merged "Tüm Gelen Kutuları" view. Search and bulk actions span every account;
  folder/label state stays account-local.
- **Folders + labels.** Standard folders (Gelen Kutusu, Gönderilenler, Taslaklar, Çöp
  Kutusu, Spam, Arşiv) plus a virtual **Yıldızlılar** (pinned) folder that groups pinned
  mail across real folders, user-defined colored labels, and a **Diğer Klasörler**
  screen for custom IMAP folders, including nested browsing, create/rename/delete and
  move.
- **Reading, threading & actions.** Conversations render as collapsible cards;
  read/unread, star/pin (capped at 3 concurrent pins), trash/restore,
  archive, spam, move, and multi-select bulk actions.
- **Compose.** Attachments (files, camera and gallery), drafts,
  reply/reply-all/forward with quoted history, templates, snippets, multiple
  signatures, sender identities and OS share-sheet intake. Immediate sends can
  optionally request read (MDN) and delivery (SMTP DSN) receipts; neither is
  guaranteed by recipients or providers. Receipt requests are not supported
  for scheduled sends.
- **Scheduled send.** Queue a message for a future time from Compose; the backend
  delivers it even if the app is closed and retries recoverable pre-delivery failures
  with backoff. Failed/delivery-uncertain sends stay visible in Zamanlanmış
  Gönderimler for manual reschedule or cancel — never resent automatically.
- **Undo send and outbox.** Gönder waits for the configured undo interval;
  the complete message and attachment bytes are persisted locally before compose closes.
  Definitive pre-delivery failures can be retried or edited from Giden Kutusu.
  If delivery is uncertain, the app does not resend automatically; check
  Gönderilenler before deleting the local copy or composing another message.
- **Rules.** Account-scoped rules are evaluated server-side after mail sync,
  including priority, conditions, actions and stop-processing.
- **Search.** Server-backed account/folder/label filters and IMAP fallback for
  mail outside the local index.
- **Offline cache.** An on-device SQLite mirror of loaded mail — including full message
  bodies, but not attachment bytes — paints the last known mailbox instantly on cold
  start and revalidates against the API in the background; falls back to it when the
  backend is unreachable. Pull-to-refresh requests a server sync and waits for it to
  actually finish (not just be queued) before reloading the list.
  Pin, snooze, label and manual-contact changes queue locally while offline and
  reconcile with the backend after reconnecting.
- **Privacy and inspection.** Images in ordinary messages load automatically.
  For Junk or mail with a failed DMARC check, use the per-message action to
  load them. Tiny or hidden tracking pixels stay blocked. Other remote images
  can reveal when and from where you opened a message. Mail detail also shows
  the original IMAP headers and raw MIME on demand, plus SPF/DKIM/DMARC
  results and signed or encrypted format indicators. S/MIME signatures can be
  verified against the original MIME; OpenPGP verification, key management
  and decryption are not supported. Older indexed mail may need re-import
  before indicators appear. Inspecting original source requires a live IMAP
  connection.
- **Push notifications (FCM).** Device registration, foreground/background message
  routing, and tap-to-open — see [Push notifications](#push-notifications) below.
- **Account & session management.** OAuth (Google/Microsoft) or password/manual
  IMAP-SMTP setup with auto-discovery; a "Bağlı cihazlar" view lists every device
  session on the account and can revoke them remotely.
- **Settings.** Configurable server address (with validation), an in-app-open list
  refresh interval (independent of the backend's own background IMAP sync — see
  Otomatik Yenileme in Settings), and a swipe-to-delete toggle.

## Architecture

The entire app talks to a single abstract interface, `MailRepository`
(`lib/repositories/mail_repository.dart`), which extends `ChangeNotifier`. Screens and
widgets never know or branch on which implementation is active — they only call
`MailRepository` methods and listen for notifications. `ApiMailRepository`
(`lib/repositories/api_mail_repository.dart`) is the only implementation;
`AppConfig.mailRepository` is the shared singleton the whole app reads.

```
lib/
├── models/        Plain data classes (Email, MailAccount, MailFolder, MailLabel)
├── repositories/   MailRepository interface + ApiMailRepository
├── services/       API plumbing: HTTP client, auth/session/token stores, offline
│                   cache, push, device identifier, share intake
├── state/          Cross-widget UI state (multi-select mode, app settings)
├── screens/        Inbox, mail detail, compose, search, accounts, settings, login
└── widgets/        Drawer, mail list item, avatar, label picker, dialogs
```

See `CLAUDE.md` for the full layering contract and multi-account/pinning semantics.

## Backend

The app talks to the real backend through `ApiMailRepository`. See
[`docs/flutter-api-integration.md`](docs/flutter-api-integration.md) for the full API
contract (auth flows, error codes, pagination, device/push schema).

Configure which backend to hit via the in-app Settings screen, or at launch:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5071   # Android emulator
flutter run --dart-define=API_BASE_URL=http://192.168.1.23:5071  # physical device on the same LAN
```

Android Studio has shared Flutter run configurations in
`.idea/runConfigurations/`. `Kaydetmail (Emulator, Debug)` connects to
`http://10.0.2.2:5071`; `Kaydetmail (Cihaz, Debug)` and
`Kaydetmail (Cihaz, Release)` connect to `http://192.168.1.25:5071`.
The device needs access to that address on your LAN. Update the device
profiles if your backend runs at a different address. All three enable push;
the release profile also passes `--release`.

## Push notifications

FCM is on by default on Android/iOS (`AppConfig.pushEnabled`; web and desktop skip it).
Pushes that arrive while the app is open are shown through `flutter_local_notifications`.
Disable with:

```bash
flutter run --dart-define=PUSH_ENABLED=false
```

See [`docs/push-notifications.md`](docs/push-notifications.md) for the Firebase project,
Android Gradle wiring, the background message handler, notification-tap navigation, and
what's still missing (iOS APNs setup).

## Crash and performance monitoring

On configured Android devices, Firebase Crashlytics records uncaught Flutter and
asynchronous errors, while Firebase Performance collects app lifecycle data and
an aggregate `api_http` duration trace for API requests. The trace never includes
mail content, URLs, headers, tokens, or account identifiers. Monitoring does not
depend on the push-notification toggle. Web/desktop builds skip monitoring;
without a Firebase configuration the app continues without it.

Use the existing Firebase Android app's `android/app/google-services.json` (ignored
by Git). Enable Crashlytics and Performance Monitoring in the Firebase console.
To verify delivery, run an Android build on a test device, trigger a non-sensitive
test exception, restart the app, and check the Crashlytics dashboard; exercise an
API request and check the Performance dashboard for `api_http`. Do not place real
mail or credentials in a test exception. iOS monitoring requires registering the
iOS app with Firebase and adding its `GoogleService-Info.plist` first; iOS push
also requires the separate APNs setup described above. No backend changes or
service-account credentials in the client are needed.

## Getting started

```bash
flutter pub get
flutter run                        # against the configured backend
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5071   # Android emulator, override
```

## Testing

```bash
flutter analyze                    # static analysis — must be clean before committing
flutter test                       # full suite
flutter test test/some_file.dart   # single file
flutter test --plain-name "name"   # single test/group by name, any file
```

## Documentation

| Doc | Covers |
|---|---|
| [`docs/flutter-api-integration.md`](docs/flutter-api-integration.md) | Full backend API contract for the Flutter client |
| [`docs/push-notifications.md`](docs/push-notifications.md) | FCM setup, Gradle wiring, background handling, tap navigation |
| `CLAUDE.md` | Repository conventions, layering, commit style |
