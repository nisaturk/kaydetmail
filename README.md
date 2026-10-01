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
  moving mail. The detail move sheet shows nested folders only from the mail's account;
  mixed-account selections can move only to shared standard folder types.
- **Reading, threading & actions.** Mail lists and search show each message as an
  independent row; swipes and bulk actions affect only the explicitly selected messages,
  never their unselected thread siblings. Opening a message still shows its conversation:
  the opened message stays first. Expanding quoted history shows older messages
  newest-to-oldest, with a subtle 1 px indent step and progressively smaller text;
  long threads retain readable width and respect accessibility text scaling.
  Reply, reply-all and forward buttons remain below the opened message; older messages
  use the three-dot header menu beside the star. Each action targets its own message.
  Read/unread, star/pin (capped at 3 concurrent pins), trash/restore,
  archive, spam, move, and multi-select bulk actions.
  Mail move and label edits update loaded lists immediately and restore rejected changes
  if the server refuses them. Permanent deletion keeps mail visible in Trash until the
  server confirms removal; partial failures leave rejected messages visible.
- **Compose.** Attachments (files, camera and gallery), drafts,
  reply/reply-all/forward with quoted history, templates, snippets, multiple
  signatures, sender identities and OS share-sheet intake. Draft changes are persisted
  locally first, then synchronized in the background. Failed synchronization warns
  without reopening the editor; **Aç** opens the preserved local draft on request.
  Transient failures retry with one notification per saved version. Permanent
  failures pause until another save or session restore, without blocking other drafts.
  Immediate sends can optionally request read (MDN) and
  delivery (SMTP DSN) receipts; neither is guaranteed by recipients or providers.
  Receipt requests are not supported for scheduled sends.
  Replies start with five editable blank lines above quoted history; the selected
  signature sits after the new reply and before the old conversation. Restoring drafts
  or undoing a send preserves the composed body without adding another signature.
- **Scheduled send.** Queue a message for a future time from Compose; the backend
  delivers it even if the app is closed and retries recoverable pre-delivery failures
  with backoff. Failed/delivery-uncertain sends stay visible in Zamanlanmış
  Gönderimler for manual reschedule or cancel — never resent automatically.
- **Undo send and outbox.** Gönder waits for the configured undo interval;
  the complete message and attachment bytes are persisted locally before compose closes.
  Once delivery is confirmed, an **E-posta gönderildi.** toast replaces the countdown
  or attachment-upload feedback; failed or uncertain sends never show success.
  Definitive pre-delivery failures can be retried or edited from Giden Kutusu.
  If delivery is uncertain, the app does not resend automatically; check
  Gönderilenler before deleting the local copy or composing another message.
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
  Otomatik Yenileme in Settings), configurable left/right swipe actions, and swipe
  sensitivity under Settings → Interaction. Low/Normal/High sensitivity requires
  70%/55%/40% of the mail row's width (Normal by default), in either direction.
  Actions require horizontal displacement at least twice the largest vertical
  excursion; short fast flings cannot bypass the distance requirement.
  Swipe preferences persist across restarts.

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

`Kaydetmail (Linux, Debug)` targets Linux (`-d linux`), connects to
`http://localhost:5071`, and disables mobile push. Open `kaydetmail-frontend/`
as the Android Studio project, select this run profile and the **Linux (desktop)**
device, then use Run or Debug. For the default Compose backend, change the
profile's `API_BASE_URL` port to `8080`.

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

### Linux desktop

Linux x64 supports the desktop app, with tokens and the encrypted cache key stored
in the session's Secret Service keyring. Flutter 3.47.5 / Dart 3.13.2+ and the
Linux desktop toolchain are required.

On Ubuntu 24.04, install build dependencies and a keyring provider:

```bash
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev libsecret-1-dev libstdc++-12-dev gnome-keyring
```

On Arch-based systems:

```bash
sudo pacman -S --needed base-devel clang cmake ninja pkgconf gtk3 libsecret gnome-keyring
```

Run from a graphical desktop session with a session D-Bus and an unlocked
Secret Service provider (for example, GNOME Keyring or a compatible KWallet
configuration). Installing `libsecret` alone does not provide a keyring daemon.
Credentials and cache keys are not downgraded to plaintext if the keyring is
unavailable.

From the project directory:

```bash
flutter pub get
flutter run -d linux --dart-define=API_BASE_URL=http://localhost:5071

# Standalone release; Flutter is not needed on the destination machine.
flutter build linux --release --dart-define=API_BASE_URL=http://localhost:5071
./build/linux/x64/release/bundle/kaydetmail
```

Use the backend's actual address/port (`http://localhost:8080` for the default
Compose stack), or change it from the login screen's server settings.
Distribute the **entire `bundle/` directory**, not just the executable; it includes
Flutter, plugin libraries, PDFium, native SQLite assets and application resources.
The destination still needs GTK 3, libsecret, a working keyring and compatible
system libraries. Build on the oldest Linux distribution you intend to support;
a bundle built on a newer system may require a newer glibc.

Linux does not use mobile Firebase push/monitoring, home-screen widgets, mobile
share-intent intake or biometric app locking. Periodic mailbox refresh runs while
the app is open; closing it stops client-side refresh. The Linux biometric-lock
setting is hidden. An already-enabled lock on a platform without `local_auth`
offers explicit continuation rather than trapping the user in retry attempts.

CI builds both Linux Debug and Release on Ubuntu 24.04 and uploads the complete
release bundle as `kaydetmail-linux-x64`.


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
