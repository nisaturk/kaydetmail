import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill_delta_from_html/flutter_quill_delta_from_html.dart';
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';

import '../config/app_config.dart';
import '../models/email.dart';
import '../models/compose_limits.dart';
import '../models/mail_template.dart';
import '../repositories/mail_repository.dart';
import '../services/contacts_store.dart';
import '../services/device_contacts.dart';
import '../state/app_settings_controller.dart';
import '../state/pending_send_queue.dart';
import '../models/mail_signature.dart';
import '../theme/app_theme.dart';
import '../utils/compose_signature.dart';
import '../utils/date_format.dart';
import '../utils/error_messages.dart';
import '../utils/html_to_text.dart';
import '../utils/attachment_mime.dart';
import '../utils/image_resize.dart';
import 'compose/compose_models.dart';
import 'compose/compose_widgets.dart';
import '../l10n/l10n.dart';
part 'compose_state/recipients.dart';
part 'compose_state/attachments.dart';
part 'compose_state/signature.dart';
part 'compose_state/draft.dart';
part 'compose_state/send.dart';
part 'compose_state/base_state.dart';

/// Opens [draft] in the editor with its complete content. List rows only
/// carry a ~120 character snippet, so the full draft (body + attachment
/// metadata) is fetched first — saving an editor prefilled from the row
/// would truncate the body. Falls back to the cached copy when the fetch
/// fails (e.g. offline).
///
/// Attachment *content* is not downloaded here: `ComposeScreen` downloads
/// each remote attachment itself (tracked as ready/downloading/failed) and
/// blocks Send/save while any isn't ready — a silent download failure must
/// never drop an attachment from the saved draft (docs-dev spec §6).
Future<void> openDraftEditor(BuildContext context, Email draft) async {
  final repo = AppConfig.mailRepository;
  var full = draft;
  try {
    full = await repo.getEmail(draft.id) ?? draft;
  } catch (_) {}
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ComposeScreen(
        composeTitle: l10nNow.editDraft,
        editingDraftId: full.id,
        initialFrom: full.senderEmail,
        initialFromAccountId: full.accountId,
        initialTo: full.recipients.join(', '),
        initialCc: full.cc.join(', '),
        initialBcc: full.bcc.join(', '),
        initialSubject: full.subject,
        initialBody: full.bodyText,
        initialBodyHtml: full.bodyHtml,
        initialAttachments: full.attachments,
        attachmentSourceMailId: full.id,
        initialThreadId: full.threadId.isEmpty ? null : full.threadId,
        inReplyToId: full.inReplyToId,
      ),
    ),
  );
}

/// Compose a new mail (or reply/forward/edit-draft — same screen).
///
/// Cc/Bcc stay hidden behind a compact menu until requested. When
/// [editingDraftId] is set the screen edits that draft: fields are prefilled,
/// saving updates it in place (no duplicate) and sending removes it from
/// Drafts. Inside a scrolled column so nothing overflows when the keyboard is
/// open or the screen is narrow.
/// Smart-back saves a draft when content exists.
///
/// Three more behaviors live here:
/// - **Signature**: genuinely new messages receive the selected sender's
///   signature, before quoted history in replies. Restored drafts and undone
///   sends keep their existing body. Sender changes update the signature only
///   while the editor still matches the last automatic insertion, so typing
///   and formatting are never clobbered. See `_syncSignature`.
/// - **Undo send**: "Gönder" doesn't call `MailRepository.sendEmail`
///   directly — it hands the fields to [PendingSendQueue], which holds them
///   for a few seconds (with a "Geri Al" SnackBar) before the real send
///   fires, and pops this screen immediately. See `_send`, which closes the
///   captured `SnackBar` controller itself once the window elapses (the
///   SnackBar's own passive `duration` dismissal doesn't reliably survive
///   the route changes this app does mid-countdown) — closing that specific
///   controller rather than "whatever's current" so a same-instant
///   `PendingSendQueue` failure SnackBar is never wrongly dismissed with it.
/// - **Overflow menu** (⋮ next to "Gönder"): Zamanla (`_scheduleSend`),
///   Kişilerden ekle (`_pickFromContacts`), Taslağı kaydet (disabled while
///   there is no content), Sil (`_discard`), and the opt-in read receipt
///   toggle (`_toggleReadReceipt`).
class ComposeScreen extends StatefulWidget {
  const ComposeScreen({
    super.key,
    this.pickAttachments,
    this.initialFrom,
    this.initialFromAccountId,
    this.initialTo = '',
    this.initialCc = '',
    this.initialBcc = '',
    this.initialSubject = '',
    this.initialBody = '',
    this.initialBodyHtml,
    this.initialReplyWritingLines = 0,
    this.insertSignature = true,
    this.initialAttachments = const [],
    this.attachmentSourceMailId,
    this.editingDraftId,
    this.replacesOutboxId,
    this.composeTitle,
    this.initialThreadId,
    this.inReplyToId,
    this.initialIdentityId,
    this.initialRequestReadReceipt = false,
  });

  /// Lets tests substitute the real OS file picker.
  final Future<List<Attachment>?> Function()? pickAttachments;

  final String? initialFrom;
  final String? initialFromAccountId;
  final String initialTo;
  final String initialCc;
  final String initialBcc;
  final String initialSubject;
  final String initialBody;
  final String? initialBodyHtml;

  /// Blank authored lines before [initialBody]/[initialBodyHtml], which contain
  /// the attribution and quoted history of a new reply. Restored bodies already
  /// contain this space and must leave this at zero.
  final int initialReplyWritingLines;

  /// False when reopening an already composed body (for example Undo send).
  final bool insertSignature;
  final List<Attachment> initialAttachments;

  /// The mail [initialAttachments] with a null `bytes` belong to (the
  /// source mail of a forward, or the draft being edited) — used to
  /// download/re-download their content. Null when every initial
  /// attachment already carries its bytes (locally picked files) or there
  /// are none.
  final String? attachmentSourceMailId;

  /// Id of the draft being edited, or null for a new mail/reply/forward.
  final String? editingDraftId;
  final String? replacesOutboxId;
  final String? composeTitle;

  /// When replying: the conversation this message continues. Null/empty means
  /// a new conversation; the repository generates a fresh thread id.
  final String? initialThreadId;
  final String? inReplyToId;
  final String? initialIdentityId;

  /// Restores the read receipt opt-in when reopening an unsent message
  /// (Giden Kutusu, undo send).
  final bool initialRequestReadReceipt;

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends _ComposeStateBase
    with
        _RecipientsMixin,
        _AttachmentsMixin,
        _SignatureMixin,
        _DraftMixin,
        _SendMixin {
  @override
  void initState() {
    super.initState();
    _toRecipients.addAll(_parseRecipients(widget.initialTo));
    _ccRecipients.addAll(_parseRecipients(widget.initialCc));
    _bccRecipients.addAll(_parseRecipients(widget.initialBcc));
    _subjectController.text = widget.initialSubject;
    final initialDocument = _initialBodyDocument();
    _bodyController = quill.QuillController(
      document: initialDocument,
      selection: const TextSelection.collapsed(offset: 0),
    );
    _initialBodyDelta = jsonEncode(initialDocument.toDelta().toJson());
    _bodyBeforeSignature = _bodyText;
    _signatureInsertionOffset = widget.initialReplyWritingLines > 0
        ? widget.initialReplyWritingLines
        : _bodyBeforeSignature.length;
    _managedSignatureDelta = _initialBodyDelta;
    // Fields that already carry content start visible so nothing is lost;
    // empty ones stay hidden behind the Cc/Bcc menu.
    _ccExpanded = _ccRecipients.isNotEmpty;
    _bccExpanded = _bccRecipients.isNotEmpty;
    for (final attachment in widget.initialAttachments) {
      _attachments.add(attachment);
      if (attachment.bytes == null && attachment.id != null) {
        _attachmentIssues[attachment] = (
          status: AttachmentIssue.downloading,
          error: null,
        );
        unawaited(_downloadRemoteAttachment(attachment));
      }
    }
    final accounts = _repo.accounts;
    final initialAccount = widget.initialFromAccountId == null
        ? null
        : _repo.getAccount(widget.initialFromAccountId!);
    if (initialAccount != null) {
      _fromAccount = initialAccount.email;
    } else if (widget.initialFrom != null &&
        accounts.any((a) => a.email == widget.initialFrom)) {
      _fromAccount = widget.initialFrom;
    } else {
      _fromAccount = accounts.any((a) => a.email == _repo.currentUser)
          ? _repo.currentUser
          : (accounts.isNotEmpty ? accounts.first.email : null);
    }
    unawaited(_loadComposeLimits());
    unawaited(_loadIdentities());
    ContactsStore.startListening(_repo);
    _refreshContacts();
    unawaited(
      DeviceContacts.refresh(
        enabled: AppSettingsController.instance.deviceContactsEnabled,
      ).then((_) {
        if (mounted) _refreshContacts();
      }),
    );
    _repo.addListener(_refreshContacts);
    _toFocus.addListener(() => _handleFieldFocusChange(_toFocus));
    _ccFocus.addListener(() => _handleFieldFocusChange(_ccFocus));
    _bccFocus.addListener(() => _handleFieldFocusChange(_bccFocus));
    if (_signatureEligible) _syncSignature();
  }

  @override
  void dispose() {
    if (_draftId case final draftId?) {
      _repo.detachDraftSyncFailureHandler(draftId);
    }
    _repo.removeListener(_refreshContacts);
    _removeSuggestionOverlay();
    _toInputController.dispose();
    _ccInputController.dispose();
    _bccInputController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    _toFocus.dispose();
    _ccFocus.dispose();
    _bccFocus.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    _bodyController.readOnly = _sending;
    return PopScope(
      // Always intercept: content typed after the last build must still be
      // caught, or back silently discards it.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // Mid-send: navigating away is blocked outright, not just guarded
        // by the draft-save dialog — the send must finish or fail first.
        if (_sending) return;
        if (!_hasContent) return Navigator.of(context).pop();
        final nav = Navigator.of(context);
        final shouldPop = await _onWillPop();
        if (shouldPop && mounted) nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(LucideIcons.x),
            tooltip: l10nNow.close,
            onPressed: _sending
                ? null
                : () async {
                    final nav = Navigator.of(context);
                    final shouldPop = await _onWillPop();
                    if (shouldPop && mounted) nav.pop();
                  },
          ),
          title: Text(
            widget.composeTitle ??
                (widget.editingDraftId != null
                    ? l10nNow.editDraft
                    : l10nNow.newEmail),
          ),
          actions: [
            if (_sending)
              const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              )
            else ...[
              IconButton(
                key: const Key('send-button'),
                icon: const Icon(LucideIcons.send),
                tooltip: l10nNow.sendNow,
                onPressed: _send,
              ),
              PopupMenuButton<ComposeMenuAction>(
                key: const Key('send-options-menu'),
                tooltip: l10nNow.moreOptions,
                position: PopupMenuPosition.under,
                icon: const Icon(LucideIcons.ellipsisVertical),
                onSelected: (action) {
                  switch (action) {
                    case ComposeMenuAction.schedule:
                      _scheduleSend();
                    case ComposeMenuAction.contacts:
                      _pickFromContacts();
                    case ComposeMenuAction.saveDraft:
                      _saveDraftFromMenu();
                    case ComposeMenuAction.discard:
                      _discard();
                    case ComposeMenuAction.readReceipt:
                      _toggleReadReceipt();
                  }
                },
                itemBuilder: (context) {
                  final hasContent = _hasContent;
                  PopupMenuItem<ComposeMenuAction> item(
                    ComposeMenuAction action,
                    IconData icon,
                    String label, {
                    bool enabled = true,
                    Color? color,
                    Widget? trailing,
                  }) => PopupMenuItem(
                    key: Key('compose-menu-${action.name}'),
                    value: action,
                    enabled: enabled,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      enabled: enabled,
                      iconColor: color,
                      textColor: color,
                      leading: Icon(icon, size: 20),
                      title: Text(label),
                      trailing: trailing,
                    ),
                  );
                  return [
                    item(
                      ComposeMenuAction.schedule,
                      LucideIcons.calendarClock,
                      l10nNow.schedule,
                    ),
                    item(
                      ComposeMenuAction.contacts,
                      LucideIcons.bookUser,
                      l10nNow.addFromContacts,
                    ),
                    item(
                      ComposeMenuAction.saveDraft,
                      LucideIcons.save,
                      l10nNow.saveDraft,
                      enabled: hasContent,
                    ),
                    item(
                      ComposeMenuAction.discard,
                      LucideIcons.trash2,
                      l10nNow.delete,
                      color: colors.destructive,
                    ),
                    item(
                      ComposeMenuAction.readReceipt,
                      LucideIcons.mailCheck,
                      l10nNow.requestReadReceipt,
                      trailing: _requestReadReceipt
                          ? const Icon(
                              LucideIcons.check,
                              key: Key('read-receipt-on'),
                              size: 18,
                            )
                          : null,
                    ),
                  ];
                },
              ),
            ],
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _fromRow(),
                      const Divider(indent: 0, endIndent: 0, height: 1),
                      // Gmail-style disclosure: hidden Cc/Bcc are revealed
                      // through the small chevron at the far right of the
                      // Kime row. Entered values live in the chip lists, so
                      // revealing a field never erases its content. Once
                      // both are visible the chevron disappears.
                      _recipientFieldRow(
                        label: l10nNow.to,
                        recipients: _toRecipients,
                        inputController: _toInputController,
                        focusNode: _toFocus,
                        fieldKey: const Key('to-field'),
                        enabled: !_sending,
                        suggestionLink: _toLink,
                        onRemove: (r) => _removeRecipient(_toRecipients, r),
                        onChanged: (v) {
                          _onRecipientChanged(
                            _toRecipients,
                            _toInputController,
                            v,
                          );
                          _updateSuggestions(
                            _toLink,
                            v,
                            _toRecipients,
                            (c) => _commitSuggestion(
                              _toRecipients,
                              _toInputController,
                              c,
                            ),
                          );
                        },
                        onSubmitted: () => _onRecipientSubmitted(
                          _toRecipients,
                          _toInputController,
                        ),
                        trailing: (!_ccExpanded || !_bccExpanded)
                            ? PopupMenuButton<String>(
                                key: const Key('cc-bcc-menu'),
                                tooltip: l10nNow.addCcBcc,
                                padding: EdgeInsets.zero,
                                enabled: !_sending,
                                style: IconButton.styleFrom(
                                  minimumSize: const Size(32, 32),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                icon: Icon(
                                  LucideIcons.chevronDown,
                                  size: 18,
                                  color: colors.secondaryText,
                                ),
                                onSelected: (value) => setState(() {
                                  if (value == 'Cc') {
                                    _ccExpanded = true;
                                  } else {
                                    _bccExpanded = true;
                                  }
                                }),
                                itemBuilder: (context) => [
                                  if (!_ccExpanded)
                                    const PopupMenuItem(
                                      value: 'Cc',
                                      child: Text('Cc'),
                                    ),
                                  if (!_bccExpanded)
                                    const PopupMenuItem(
                                      value: 'Bcc',
                                      child: Text('Bcc'),
                                    ),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                      if (_ccExpanded)
                        _recipientFieldRow(
                          label: 'Cc',
                          recipients: _ccRecipients,
                          inputController: _ccInputController,
                          focusNode: _ccFocus,
                          fieldKey: const Key('cc-field'),
                          enabled: !_sending,
                          suggestionLink: _ccLink,
                          onRemove: (r) => _removeRecipient(_ccRecipients, r),
                          onChanged: (v) {
                            _onRecipientChanged(
                              _ccRecipients,
                              _ccInputController,
                              v,
                            );
                            _updateSuggestions(
                              _ccLink,
                              v,
                              _ccRecipients,
                              (c) => _commitSuggestion(
                                _ccRecipients,
                                _ccInputController,
                                c,
                              ),
                            );
                          },
                          onSubmitted: () => _onRecipientSubmitted(
                            _ccRecipients,
                            _ccInputController,
                          ),
                        ),
                      if (_bccExpanded)
                        _recipientFieldRow(
                          label: 'Bcc',
                          recipients: _bccRecipients,
                          inputController: _bccInputController,
                          focusNode: _bccFocus,
                          fieldKey: const Key('bcc-field'),
                          enabled: !_sending,
                          suggestionLink: _bccLink,
                          onRemove: (r) => _removeRecipient(_bccRecipients, r),
                          onChanged: (v) {
                            _onRecipientChanged(
                              _bccRecipients,
                              _bccInputController,
                              v,
                            );
                            _updateSuggestions(
                              _bccLink,
                              v,
                              _bccRecipients,
                              (c) => _commitSuggestion(
                                _bccRecipients,
                                _bccInputController,
                                c,
                              ),
                            );
                          },
                          onSubmitted: () => _onRecipientSubmitted(
                            _bccRecipients,
                            _bccInputController,
                          ),
                        ),
                      const Divider(indent: 0, endIndent: 0),
                      _fieldRow(
                        label: l10nNow.subject,
                        controller: _subjectController,
                        fieldKey: const Key('subject-field'),
                        enabled: !_sending,
                      ),
                      const Divider(indent: 0, endIndent: 0, height: 1),
                      if (_resizingImages) const LinearProgressIndicator(),
                      if (_attachmentLimitError(_attachments) case final error?)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            error,
                            style: TextStyle(color: colors.destructive),
                          ),
                        ),
                      if (_attachments.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        for (final attachment in _attachments)
                          AttachmentRow(
                            attachment: attachment,
                            onRemove: () => _removeAttachment(attachment),
                            onRetry: () => _retryAttachment(attachment),
                            enabled: !_sending,
                            issue: _attachmentIssues[attachment]?.status,
                            error: _attachmentIssues[attachment]?.error,
                          ),
                      ],
                      const SizedBox(height: 8),
                      Localizations.override(
                        context: context,
                        delegates: const [
                          quill.FlutterQuillLocalizations.delegate,
                        ],
                        child: Column(
                          children: [
                            _formattingToolbar(colors),
                            quill.QuillEditor.basic(
                              key: const Key('body-field'),
                              controller: _bodyController,
                              focusNode: _bodyFocus,
                              config: quill.QuillEditorConfig(
                                unknownEmbedBuilder: EmbedPlaceholder(),
                                scrollable: false,
                                minHeight: 180,
                                padding: EdgeInsets.symmetric(vertical: 10),
                                placeholder: l10nNow.writeYourMessage,
                                textCapitalization:
                                    TextCapitalization.sentences,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _formattingToolbar(AppColors colors) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: const Key('format-toolbar'),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: quill.QuillSimpleToolbar(
        controller: _bodyController,
        config: quill.QuillSimpleToolbarConfig(
          // The default selected state fills with primary but keeps the
          // app-wide onSurface icon color, invisible on this black theme.
          buttonOptions: quill.QuillSimpleToolbarButtonOptions(
            base: quill.QuillToolbarBaseButtonOptions(
              iconTheme: quill.QuillIconTheme(
                iconButtonSelectedData: quill.IconButtonData(
                  style: IconButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                  ),
                ),
              ),
            ),
          ),
          multiRowsDisplay: false,
          showDividers: false,
          showFontFamily: false,
          showFontSize: false,
          showStrikeThrough: false,
          showInlineCode: false,
          showColorButton: false,
          showBackgroundColorButton: false,
          showHeaderStyle: false,
          showCodeBlock: false,
          showListCheck: false,
          showSearchButton: false,
          showSubscript: false,
          showSuperscript: false,
        ),
      ),
    );
  }

  /// Single-line label with a fixed width shared by Kimden/Kime/Konu/Cc/Bcc,
  /// so every value starts at the same x offset and labels never wrap.
  static const _labelWidth = 64.0;

  static TextStyle _labelStyle(AppColors colors) => TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: colors.secondaryText,
  );

  Widget _fieldRow({
    required String label,
    required TextEditingController controller,
    FocusNode? focusNode,
    Key? fieldKey,
    Widget trailing = const SizedBox.shrink(),
    bool enabled = true,
  }) {
    final colors = AppTheme.colors(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: _labelWidth,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: _labelStyle(colors),
          ),
        ),
        Expanded(
          child: TextField(
            key: fieldKey,
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            textInputAction: TextInputAction.next,
            decoration: flatFieldDecoration,
            style: TextStyle(fontSize: 15, color: colors.bodyText),
          ),
        ),
        trailing,
      ],
    );
  }

  /// Chip-based recipient field. Confirmed addresses render as removable
  /// chips (an invalid-looking one — no `@`/domain — still renders, in the
  /// destructive palette, so it's visible and fixable instead of silently
  /// dropped or silently sent); typed text turns into a chip on comma,
  /// space, or Enter/submit. Keeps the same label-column layout as
  /// [_fieldRow] so Kimden/Kime/Cc/Bcc/Konu stay aligned. [suggestionLink]
  /// anchors the contact-autocomplete overlay (see `_updateSuggestions`)
  /// under this field's value area.
  Widget _recipientFieldRow({
    required String label,
    required List<Recipient> recipients,
    required TextEditingController inputController,
    required void Function(Recipient) onRemove,
    required void Function(String) onChanged,
    required VoidCallback onSubmitted,
    required LayerLink suggestionLink,
    FocusNode? focusNode,
    Key? fieldKey,
    Widget trailing = const SizedBox.shrink(),
    bool enabled = true,
  }) {
    final colors = AppTheme.colors(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: SizedBox(
            width: _labelWidth,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: _labelStyle(colors),
            ),
          ),
        ),
        Expanded(
          child: CompositedTransformTarget(
            link: suggestionLink,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppTheme.space2,
                runSpacing: AppTheme.space1,
                children: [
                  for (final recipient in recipients)
                    RecipientChip(
                      key: ObjectKey(recipient),
                      recipient: recipient,
                      enabled: enabled,
                      onDeleted: () => onRemove(recipient),
                    ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 120),
                    child: TextField(
                      key: fieldKey,
                      controller: inputController,
                      focusNode: focusNode,
                      enabled: enabled,
                      textInputAction: TextInputAction.done,
                      decoration: flatFieldDecoration,
                      style: TextStyle(fontSize: 15, color: colors.bodyText),
                      onChanged: onChanged,
                      onSubmitted: (_) => onSubmitted(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        trailing,
      ],
    );
  }

  /// Gmail-style sender row: the account is shown plainly, and only the
  /// small chevron at the far right opens a compact anchored popup — never
  /// a bottom sheet. With a single account there is nothing to choose, so
  /// the chevron is hidden.
  Widget _fromRow() {
    final accounts = _repo.accounts;
    final colors = AppTheme.colors(context);
    final selected =
        _fromAccount ?? (accounts.isNotEmpty ? accounts.first.email : '');
    return Padding(
      key: const Key('from-field'),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: _labelWidth,
            child: Text(
              l10nNow.from,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: _labelStyle(colors),
            ),
          ),
          Expanded(
            child: Text(
              _fromIdentity == null
                  ? selected
                  : '${_fromIdentity!.displayName.isEmpty ? _fromIdentity!.emailAddress : _fromIdentity!.displayName} <${_fromIdentity!.emailAddress}>',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15, color: colors.bodyText),
            ),
          ),
          if (_identities.isNotEmpty)
            PopupMenuButton<String>(
              key: const Key('from-identity-menu'),
              tooltip: l10nNow.chooseIdentity,
              padding: EdgeInsets.zero,
              enabled: !_sending,
              icon: Icon(
                LucideIcons.userRoundPen,
                size: 18,
                color: colors.secondaryText,
              ),
              onSelected: (picked) async {
                final identity = _identities
                    .where((i) => i.id == picked)
                    .firstOrNull;
                if (identity == null) return;
                await _pickIdentity(identity);
              },
              itemBuilder: (context) => [
                for (final identity in _identities)
                  PopupMenuItem(
                    key: ValueKey('identity-${identity.id}'),
                    value: identity.id,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Expanded(
                          child: Text(
                            identity.emailAddress,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15),
                          ),
                        ),
                        if (identity.id == _fromIdentity?.id)
                          Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: Icon(
                              LucideIcons.check,
                              size: 18,
                              color: colors.bodyText,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          if (accounts.length > 1)
            PopupMenuButton<String>(
              key: const Key('from-account-menu'),
              tooltip: l10nNow.chooseAccount,
              padding: EdgeInsets.zero,
              enabled: !_sending,
              icon: Icon(
                LucideIcons.chevronDown,
                size: 18,
                color: colors.secondaryText,
              ),
              onSelected: (picked) {
                setState(() {
                  _fromAccount = picked;
                  _fromIdentity = null;
                  _identities = const [];
                });
                _syncSignature();
                _limits = null;
                unawaited(_loadComposeLimits());
                unawaited(_loadIdentities());
              },
              itemBuilder: (context) => [
                for (final account in accounts)
                  PopupMenuItem(
                    key: ValueKey('from-${account.email}'),
                    value: account.email,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Expanded(
                          child: Text(
                            account.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15),
                          ),
                        ),
                        if (account.email == _fromAccount)
                          Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: Icon(
                              LucideIcons.check,
                              size: 18,
                              color: colors.bodyText,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final colors = AppTheme.colors(context);
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            key: const Key('attach-button'),
            onPressed: _sending || _resizingImages ? null : _attach,
            icon: const Icon(LucideIcons.paperclip, size: 22),
            tooltip: l10nNow.attachFile,
          ),
          TextButton.icon(
            key: const Key('template-button'),
            onPressed: _sending ? null : _pickTemplate,
            icon: const Icon(LucideIcons.layoutTemplate, size: 20),
            label: Text(l10nNow.savedTexts),
          ),
        ],
      ),
    );
  }
}
