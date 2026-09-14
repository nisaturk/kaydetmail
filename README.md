# kaydetmail

A mail client project.

## Mock mode

The app runs against an in-memory mock backend by default so every feature can
be exercised without a real account or network calls.

### Enabling mock mode

Mock mode is controlled by `AppConfig.useMockApi` in
`lib/config/app_config.dart` (currently `true`). Setting it to `false` switches
the app to the not-yet-implemented `ApiMailRepository`.

### Mock login account

Any well-formed email + password is accepted by the simulated login, but the
documented mock account is:

- **Email:** `nisa@kaydet.com`
- **Password:** `kaydet123`

Mock-only: no real account exists, nothing is sent anywhere. These constants
live on `MockMailRepository` as `demoEmail` / `demoPassword`.

### Attachments

The compose screen can attach local files (paperclip icon, multiple files,
size shown, removable). In mock mode only the attachment metadata
(name/size) is stored on the composed message — nothing is uploaded,
downloaded or persisted. The file-picker call is the only platform plugin
involved; it is injected at `ComposeScreen.pickAttachments` so tests can
substitute a fake picker.

### Test messages

The seed dataset (`lib/data/mock/mock_emails.dart`) includes:

- Inbox: read and unread messages, one long subject and a long body, a pinned
  message, one with attachments
- Sent, Draft, Trash and Spam messages
- Multiple senders and several distinct dates
- Messages with labels (Work, Personal, Finance, Travel, Important)
- Messages searchable by sender, subject and body
- Infinite scrolling: `MockEmailGenerator` appends 20 more messages per page

### Resetting mock state

Mock data lives in memory only — a full app restart returns the original clean
dataset. For tests and development you can also call
`MockMailRepository.resetMockData()` or `AppConfig.resetForTest()` to restore
the seed within the current session. No database or preferences are involved.

### Switching mock mode off later

Set `AppConfig.useMockApi` to `false`. The app keeps talking to the
`MailRepository` interface either way; only `MockMailRepository` is swapped for
`ApiMailRepository`.