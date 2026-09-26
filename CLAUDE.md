# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
flutter analyze                    # static analysis (must be clean before committing)
flutter test                       # full suite (~180 tests)
flutter test test/some_file.dart   # single test file
flutter test --plain-name "name"   # single test/group by name, any file
flutter run                        # launch the app against the real backend
flutter pub get                    # after editing pubspec.yaml
```

There is no separate lint/format CI script beyond `flutter_lints` via `analysis_options.yaml` (default Flutter lint set, no custom rules).

## Architecture

Flutter mail client (Turkish UI). The entire app talks to a single abstract
interface, `MailRepository` (`lib/repositories/mail_repository.dart`), which
extends `ChangeNotifier`. Screens/widgets never know or branch on which
implementation is active — they only call `MailRepository` methods and listen
for notifications.

`ApiMailRepository` (`lib/repositories/api_mail_repository.dart`) is the only
implementation; `AppConfig.mailRepository` is the shared singleton the whole app
reads (tests inject fakes via `AppConfig.mailRepositoryForTest`).

When the real backend contract is needed, it's documented in
`docs/flutter-api-integration.md` (gitignored, not committed — endpoints,
error codes, idempotency rules, enum values). Read it before implementing any
`ApiMailRepository` method rather than guessing the shape of a request/response.

**Layering:**
- `lib/models/` — plain data classes (`Email`, `MailAccount`, `MailFolder` enum, `MailLabel`). `MailFolder.pinned` is a virtual folder (grouping pinned mails across real folders), not a server-side one.
- `lib/repositories/` — the `MailRepository` interface and its `ApiMailRepository` implementation.
- `lib/services/` — API plumbing used only by `ApiMailRepository` (`api_client.dart` for HTTP, `api_auth_service.dart` for token/session, `api_mail_service.dart` for mail endpoints, `token_store.dart`/`session_store.dart` for persistence via `flutter_secure_storage`/`shared_preferences`).
- `lib/state/` — cross-widget UI state that isn't mail data itself (`MailSelectionController` for multi-select mode, `AppSettingsController` for sync interval/server address settings).
- `lib/screens/` + `lib/widgets/` — UI. `HomeScreen` hosts the drawer/folder/list/selection-mode shell; other screens (`inbox`, `mail_detail`, `compose`, `search`, `accounts`, `settings`, `login`) are pushed on top.

**Multi-account model:** `activeAccountId == null` means the unified mailbox
(all connected accounts merged); a non-null id scopes every repository read
to that one account. Search and bulk actions can span accounts; folder state,
labels, and archive/trash actions stay account-local — see the doc comments
on `MailRepository` for the exact contract before changing behavior here.

**Pinning:** capped at `MailRepository.maxPinnedMails` (3); pin/star/unread
are independent flags on `Email`, not mutually exclusive — see
`multi_account_mail_test.dart` for the expected independence behavior.

**Feature state ownership:** Cached device state may be shown offline, but
confirmed server state wins after reconnect.

| Feature | Authoritative source |
|---|---|
| Mail read/star/folder state | IMAP server (through the backend) |
| Mail content | IMAP server; backend and device caches are read copies |
| Drafts | IMAP Drafts folder (through backend draft endpoints) |
| Sent mail | SMTP delivery plus backend Sent-folder reconciliation |
| Pin, snooze, labels | KaydetMail backend; device cache/queue while offline |
| Manual contacts, mail rules | KaydetMail backend; contacts can queue offline, legacy rules migrate from device storage |
| Per-account notification preferences | KaydetMail backend; device-wide push enablement is a device preference |
| Undo-send duration, biometric lock timeout | Device preferences |
| Offline mutations | Device SQLite queue until backend confirmation; reconcile from server on reconnect |

## Git history and commit messages

Full branch/commit/PR/merge discipline for this repo lives in
`skill://kaydetmail-git-workflow` (`.claude/skills/kaydetmail-git-workflow/SKILL.md`)
— read it before any git or GitHub operation here. Summary: `main` is
PR-only, branches are `<type>/<kebab-slug>`, commits are `type: summary`
describing *why* (matching the two most recent commits — earlier history is
inconsistent and should not be imitated), `flutter analyze` + full
`flutter test` must pass before every commit, and PRs are merged with a
**merge commit** (`gh pr merge --merge`), never squashed.
