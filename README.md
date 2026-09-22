# kaydetmail

A mail client project.

## Backend

The app talks to the real backend through `ApiMailRepository`. See
`docs/flutter-api-integration.md` for the API contract.

### Attachments

The compose screen can attach local files (paperclip icon, multiple files,
size shown, removable). The file-picker call is injected at
`ComposeScreen.pickAttachments` so tests can substitute a fake picker.

## Push notifications

FCM is wired end to end but off by default (`AppConfig.pushEnabled`). Enable with
`flutter run --dart-define=PUSH_ENABLED=true`, or use the Android Studio "Kaydetmail
(Profile + FCM)" run configuration. See `docs/push-notifications.md` for the Firebase
project, Gradle wiring, and what's still missing (iOS APNs setup, local notifications
for data-only messages).
