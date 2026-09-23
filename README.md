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
  mail across real folders, and user-defined colored labels.
- **Reading, threading & actions.** Conversations render as a collapsible card stack
  (oldest first); read/unread, star/pin (capped at 3 concurrent pins), trash/restore,
  archive, spam, move, and multi-select bulk actions.
- **Compose.** Attachments (paperclip, multiple files, size shown, removable), drafts,
  reply/reply-all/forward with quoted history, and OS share-sheet intake (share a file
  or link into the app to open compose pre-filled).
- **Search.** Server-backed, always spans every connected account, with an inline label
  filter row.
- **Offline cache.** An on-device SQLite mirror of loaded mail (metadata only, no
  attachment bytes) paints the last known mailbox instantly on cold start and
  revalidates against the API in the background; falls back to it when the backend is
  unreachable.
- **Push notifications (FCM).** Device registration, foreground/background message
  routing, and tap-to-open — see [Push notifications](#push-notifications) below.
- **Account & session management.** OAuth (Google/Microsoft) or password/manual
  IMAP-SMTP setup with auto-discovery; a "Bağlı cihazlar" view lists every device
  session on the account and can revoke them remotely.
- **Settings.** Configurable server address (with validation), simulated sync interval
  and swipe-to-delete toggle.

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
