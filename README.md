# kaydetmail

A mail client project.

## Backend

The app talks to the real backend through `ApiMailRepository`. See
`docs/flutter-api-integration.md` for the API contract.

### Attachments

The compose screen can attach local files (paperclip icon, multiple files,
size shown, removable). The file-picker call is injected at
`ComposeScreen.pickAttachments` so tests can substitute a fake picker.
