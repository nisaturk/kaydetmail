import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/email.dart';
import '../repositories/mail_repository.dart';
import '../services/contacts_store.dart';
import '../state/pending_send_queue.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../utils/error_messages.dart';
import '../utils/markdown_lite_to_html.dart';

/// Non-ready states for a remote attachment awaiting/needing its content —
/// see `_ComposeScreenState._attachmentIssues`.
enum _AttachmentIssue { downloading, failed }

/// Borderless field decoration shared by every compose input.
///
/// Every border state is explicitly [InputBorder.none]: the global theme
/// draws rounded boxes (including on focus) and compose must stay one flat
/// writing surface with only a cursor for feedback.
const _flatFieldDecoration = InputDecoration(
  hintText: '',
  border: InputBorder.none,
  enabledBorder: InputBorder.none,
  focusedBorder: InputBorder.none,
  errorBorder: InputBorder.none,
  focusedErrorBorder: InputBorder.none,
  disabledBorder: InputBorder.none,
  filled: false,
  isDense: true,
  contentPadding: EdgeInsets.symmetric(vertical: 12),
);

// Hint color is intentionally left unset here: it falls back to the
// brightness-aware `InputDecorationTheme.hintStyle` (see AppTheme) instead
// of a hardcoded light-only color.
const _flatBodyDecoration = InputDecoration(
  hintText: 'E-postanızı yazın…',
  border: InputBorder.none,
  enabledBorder: InputBorder.none,
  focusedBorder: InputBorder.none,
  errorBorder: InputBorder.none,
  focusedErrorBorder: InputBorder.none,
  disabledBorder: InputBorder.none,
  filled: false,
);

/// Light shape check for a recipient chip: `name@domain.tld`. Not a full
/// RFC 5322 validator — just enough to flag an obviously broken address
/// (missing `@`, missing domain) before it reaches the backend.
final RegExp _emailShapePattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// One recipient chip. [valid] is false for anything that fails
/// [_emailShapePattern] — the chip still renders (never silently dropped)
/// but in the destructive palette so the user notices and fixes it.
@immutable
class _Recipient {
  const _Recipient(this.address, {required this.valid});

  final String address;
  final bool valid;
}

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
        composeTitle: 'Taslağı Düzenle',
        editingDraftId: full.id,
        initialFrom: repo.getAccount(full.accountId)?.email,
        initialTo: full.recipients.join(', '),
        initialCc: full.cc.join(', '),
        initialBcc: full.bcc.join(', '),
        initialSubject: full.subject,
        initialBody: full.bodyText,
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
/// - **Signature**: when [editingDraftId] is null (a genuinely new send, not
///   restoring a stored draft), the signature saved for the selected Kimden
///   account ([MailAccount.signature]) is appended to the body automatically, and
///   re-applied if Kimden changes — but only while the body still matches
///   exactly what auto-insertion put there, so real typing is never
///   clobbered. See `_syncSignature`.
/// - **Undo send**: "Gönder" doesn't call `MailRepository.sendEmail`
///   directly — it hands the fields to [PendingSendQueue], which holds them
///   for a few seconds (with a "Geri Al" SnackBar) before the real send
///   fires, and pops this screen immediately. See `_send`, which closes the
///   captured `SnackBar` controller itself once the window elapses (the
///   SnackBar's own passive `duration` dismissal doesn't reliably survive
///   the route changes this app does mid-countdown) — closing that specific
///   controller rather than "whatever's current" so a same-instant
///   `PendingSendQueue` failure SnackBar is never wrongly dismissed with it.
/// - **Zamanla**: the small chevron next to "Gönder" offers scheduling
///   through `MailRepository.scheduleSend` with a date/time picker instead.
///   See `_scheduleSend`.
class ComposeScreen extends StatefulWidget {
  const ComposeScreen({
    super.key,
    this.pickAttachments,
    this.initialFrom,
    this.initialTo = '',
    this.initialCc = '',
    this.initialBcc = '',
    this.initialSubject = '',
    this.initialBody = '',
    this.initialAttachments = const [],
    this.attachmentSourceMailId,
    this.editingDraftId,
    this.replacesOutboxId,
    this.composeTitle,
    this.initialThreadId,
    this.inReplyToId,
  });

  /// Lets tests substitute the real OS file picker.
  final Future<List<Attachment>?> Function()? pickAttachments;

  final String? initialFrom;
  final String initialTo;
  final String initialCc;
  final String initialBcc;
  final String initialSubject;
  final String initialBody;
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

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  final List<_Recipient> _toRecipients = [];
  final List<_Recipient> _ccRecipients = [];
  final List<_Recipient> _bccRecipients = [];

  // Holds whatever the user has typed but not yet turned into a chip
  // (no comma/space/Enter yet). Read alongside the chip lists so in-flight
  // text is never silently lost from `_hasContent`, send, or save-draft.
  final _toInputController = TextEditingController();
  final _ccInputController = TextEditingController();
  final _bccInputController = TextEditingController();
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();

  final _toFocus = FocusNode();
  final _ccFocus = FocusNode();
  final _bccFocus = FocusNode();
  final _bodyFocus = FocusNode();

  bool _ccExpanded = false;
  bool _bccExpanded = false;
  bool _sending = false;
  String? _fromAccount;

  final List<Attachment> _attachments = [];

  /// Non-ready attachments only — an attachment absent from this map is
  /// implicitly "ready" (either picked locally with bytes already in hand,
  /// or a remote attachment whose download already succeeded). Keyed by
  /// the [Attachment] currently held in [_attachments] (equality is
  /// name+size, matching [_removeAttachment]/`indexOf` elsewhere in this
  /// file). Send/save/schedule must all block while this is non-empty —
  /// a still-downloading or failed remote attachment (forward, or a
  /// draft's remote attachment) must never be silently dropped from the
  /// request. See docs-dev spec §5/§6.
  final Map<Attachment, ({_AttachmentIssue status, String? error})>
  _attachmentIssues = {};

  bool get _attachmentsReady => _attachmentIssues.isEmpty;

  // --- Contact autocomplete (Kime/Cc/Bcc) --------------------------------
  final _toLink = LayerLink();
  final _ccLink = LayerLink();
  final _bccLink = LayerLink();
  OverlayEntry? _suggestionOverlay;
  List<Contact> _contacts = const [];

  // --- Signature -----------------------------------------------------
  /// Body content as it was right before [_insertedSignature] was last
  /// appended — the baseline [_syncSignature] compares against to detect
  /// whether the user has typed anything else since.
  String _bodyBeforeSignature = '';
  String _insertedSignature = '';

  /// Only a genuinely new send auto-gets a signature — restoring a stored
  /// draft must never inject one that was never part of it.
  bool get _signatureEligible => widget.editingDraftId == null;

  MailRepository get _repo => AppConfig.mailRepository;

  @override
  void initState() {
    super.initState();
    _toRecipients.addAll(_parseRecipients(widget.initialTo));
    _ccRecipients.addAll(_parseRecipients(widget.initialCc));
    _bccRecipients.addAll(_parseRecipients(widget.initialBcc));
    _subjectController.text = widget.initialSubject;
    _bodyController.text = widget.initialBody;
    _bodyBeforeSignature = widget.initialBody;
    // Fields that already carry content start visible so nothing is lost;
    // empty ones stay hidden behind the Cc/Bcc menu.
    _ccExpanded = _ccRecipients.isNotEmpty;
    _bccExpanded = _bccRecipients.isNotEmpty;
    for (final attachment in widget.initialAttachments) {
      _attachments.add(attachment);
      if (attachment.bytes == null && attachment.id != null) {
        _attachmentIssues[attachment] = (
          status: _AttachmentIssue.downloading,
          error: null,
        );
        unawaited(_downloadRemoteAttachment(attachment));
      }
    }
    final accounts = _repo.accounts;
    if (widget.initialFrom != null &&
        accounts.any((a) => a.email == widget.initialFrom)) {
      _fromAccount = widget.initialFrom;
    } else {
      _fromAccount = accounts.any((a) => a.email == _repo.currentUser)
          ? _repo.currentUser
          : (accounts.isNotEmpty ? accounts.first.email : null);
    }
    ContactsStore.startListening(_repo);
    _refreshContacts();
    _repo.addListener(_refreshContacts);
    _toFocus.addListener(() => _handleFieldFocusChange(_toFocus));
    _ccFocus.addListener(() => _handleFieldFocusChange(_ccFocus));
    _bccFocus.addListener(() => _handleFieldFocusChange(_bccFocus));
    if (_signatureEligible) _syncSignature();
  }

  static List<_Recipient> _parseRecipients(String raw) => raw
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .map((e) => _Recipient(e, valid: _emailShapePattern.hasMatch(e)))
      .toList();

  /// Recomputes [_contacts] from the persisted address book, manually-added
  /// contacts and whatever mail is currently in memory — re-run every time
  /// [_repo] notifies (registered in [initState]) so a contact from mail
  /// synced after this screen opened still shows up in the suggestion
  /// overlay, without needing to reopen compose. Deliberately not wrapped
  /// in `setState`: [_contacts] never drives `build()` directly, only the
  /// imperative overlay in [_updateSuggestions].
  ///
  /// Manually-added contacts get a synthetic far-future [Contact.lastSeen]
  /// so they always win [ContactsStore.merge] over a same-address mail
  /// sighting — a manually curated display name should never be silently
  /// overridden by a sender-name heuristic.
  static final DateTime _manualContactRank = DateTime.utc(9999);

  void _refreshContacts() {
    final manual = [
      for (final c in _repo.getManualContacts())
        Contact(
          email: c.email,
          displayName: c.label,
          lastSeen: _manualContactRank,
        ),
    ];
    _contacts = ContactsStore.merge(
      ContactsStore.merge(ContactsStore.cachedPersisted, manual),
      ContactsStore.fromEmails(_repo.getAllEmails()),
    );
  }

  @override
  void dispose() {
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

  bool get _hasContent =>
      _toRecipients.isNotEmpty ||
      _ccRecipients.isNotEmpty ||
      _bccRecipients.isNotEmpty ||
      _toInputController.text.trim().isNotEmpty ||
      _ccInputController.text.trim().isNotEmpty ||
      _bccInputController.text.trim().isNotEmpty ||
      _subjectController.text.trim().isNotEmpty ||
      _bodyController.text.trim().isNotEmpty ||
      _attachments.isNotEmpty;

  Future<bool> _onWillPop() async {
    if (!_hasContent) return true;
    final editingDraft = widget.editingDraftId != null;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(
              editingDraft
                  ? 'Değişiklikler kaydedilsin mi?'
                  : 'Bu e-posta silinsin mi?',
            ),
            content: Text(
              editingDraft
                  ? 'Taslağın mevcut hali korunabilir veya değişiklikler kaydedilebilir.'
                  : 'E-postayı taslak olarak kaydedebilir veya içeriği silebilirsiniz.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Vazgeç'),
              ),
              TextButton(
                onPressed: () async {
                  final saved = await _saveDraft();
                  if (!mounted || !ctx.mounted) return;
                  if (!saved) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Taslak kaydedilemedi. İçeriğiniz ekranda tutuluyor.',
                        ),
                      ),
                    );
                    return;
                  }
                  Navigator.of(ctx).pop(true);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Taslak kaydedildi.')),
                  );
                },
                child: const Text('Taslağı Kaydet'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(
                  editingDraft ? 'Değişiklikleri At' : 'İçeriği Sil',
                  style: TextStyle(color: AppTheme.colors(ctx).destructive),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  List<String> _addressStrings(List<_Recipient> recipients) =>
      [for (final recipient in recipients) recipient.address];

  /// Turns whatever is left in [input] into a chip in [recipients] (used on
  /// submit/Enter and right before send/save so an address the user typed
  /// but never delimited isn't silently lost). Caller wraps this in
  /// `setState` when a rebuild is needed.
  void _commitPendingRecipient(
    List<_Recipient> recipients,
    TextEditingController input,
  ) {
    final address = input.text.trim();
    if (address.isEmpty) return;
    recipients.add(_Recipient(address, valid: _emailShapePattern.hasMatch(address)));
    input.clear();
  }

  /// Splits typed text on comma/whitespace, turning every completed token
  /// into a chip and leaving the trailing partial token as pending text —
  /// so a comma or space commits a chip without waiting for submit.
  void _onRecipientChanged(
    List<_Recipient> recipients,
    TextEditingController input,
    String value,
  ) {
    if (!value.contains(',') && !value.contains(' ')) return;
    final parts = value.split(RegExp(r'[,\s]+'));
    final pending = parts.removeLast();
    if (parts.every((p) => p.isEmpty)) {
      input.value = TextEditingValue(
        text: pending,
        selection: TextSelection.collapsed(offset: pending.length),
      );
      return;
    }
    setState(() {
      for (final part in parts) {
        if (part.isEmpty) continue;
        recipients.add(_Recipient(part, valid: _emailShapePattern.hasMatch(part)));
      }
      input.value = TextEditingValue(
        text: pending,
        selection: TextSelection.collapsed(offset: pending.length),
      );
    });
  }

  void _onRecipientSubmitted(
    List<_Recipient> recipients,
    TextEditingController input,
  ) {
    setState(() => _commitPendingRecipient(recipients, input));
  }

  void _removeRecipient(List<_Recipient> recipients, _Recipient recipient) {
    setState(() => recipients.remove(recipient));
  }

  // --- Contact autocomplete ------------------------------------------

  void _handleFieldFocusChange(FocusNode node) {
    if (node.hasFocus) return;
    // A tap on a suggestion briefly steals focus before committing it —
    // give that tap a chance to land before tearing the overlay down.
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted && !node.hasFocus) _removeSuggestionOverlay();
    });
  }

  void _removeSuggestionOverlay() {
    _suggestionOverlay?.remove();
    _suggestionOverlay = null;
  }

  /// Shows/updates the suggestion overlay anchored to [link] for the
  /// current [query], excluding addresses already chipped in
  /// [currentRecipients]. [onSelected] adds the tapped contact as a chip.
  void _updateSuggestions(
    LayerLink link,
    String query,
    List<_Recipient> currentRecipients,
    void Function(Contact) onSelected,
  ) {
    _removeSuggestionOverlay();
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final existing = {
      for (final r in currentRecipients) r.address.toLowerCase(),
    };
    final matches = ContactsStore.search(_contacts, trimmed)
        .where((c) => !existing.contains(c.email.toLowerCase()))
        .take(5)
        .toList();
    if (matches.isEmpty) return;
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        width: 280,
        child: CompositedTransformFollower(
          link: link,
          showWhenUnlinked: false,
          offset: const Offset(0, 4),
          child: _ContactSuggestionList(contacts: matches, onSelected: onSelected),
        ),
      ),
    );
    _suggestionOverlay = entry;
    Overlay.of(context).insert(entry);
  }

  void _commitSuggestion(
    List<_Recipient> recipients,
    TextEditingController input,
    Contact contact,
  ) {
    setState(() {
      recipients.add(
        _Recipient(contact.email, valid: _emailShapePattern.hasMatch(contact.email)),
      );
      input.clear();
    });
    _removeSuggestionOverlay();
  }

  // --- Signature -------------------------------------------------------

  String _signatureSuffix(String signature) =>
      signature.trim().isEmpty ? '' : '\n\n--\n$signature';

  /// Applies the signature for the current Kimden account, but only while
  /// the body still exactly matches [_bodyBeforeSignature] plus whatever
  /// signature was last inserted — i.e. the user hasn't typed anything else
  /// since. Called once on open and again every time Kimden changes, so a
  /// switch re-applies the new account's signature without ever clobbering
  /// real typing.
  Future<void> _syncSignature() async {
    if (!_signatureEligible) return;
    final expected = _bodyBeforeSignature + _signatureSuffix(_insertedSignature);
    if (_bodyController.text != expected) return;
    final account = _fromAccount;
    if (account == null) return;
    final match = _repo.accounts.where((a) => a.email == account);
    final signature = match.isEmpty ? '' : (match.first.signature ?? '');
    if (!mounted || _fromAccount != account) return;
    if (_bodyController.text != expected) return;
    setState(() {
      _insertedSignature = signature;
      _bodyController.text = _bodyBeforeSignature + _signatureSuffix(signature);
      _bodyController.selection = const TextSelection.collapsed(offset: 0);
    });
  }

  // --- Formatting toolbar ----------------------------------------------

  /// Wraps the current body selection in [prefix]/[suffix] (bold/italic/
  /// underline). With no selection, wraps an empty span at the cursor (or
  /// at the end of the text when the field was never focused) so typing
  /// continues right inside the markers.
  void _wrapSelection(String prefix, String suffix) {
    final text = _bodyController.text;
    final selection = _bodyController.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final selected = text.substring(start, end);
    final replacement = '$prefix$selected$suffix';
    final newText = text.replaceRange(start, end, replacement);
    final cursorOffset = selected.isEmpty
        ? start + prefix.length
        : start + replacement.length;
    setState(() {
      _bodyController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: cursorOffset),
      );
    });
  }

  /// Prefixes every line touched by the current selection (or just the
  /// line under the cursor) with `- `, skipping lines already prefixed.
  void _toggleBulletList() {
    final text = _bodyController.text;
    final selection = _bodyController.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final newlineBefore = start == 0 ? -1 : text.lastIndexOf('\n', start - 1);
    final lineStart = newlineBefore + 1;
    final nextNewline = text.indexOf('\n', end);
    final lineEnd = nextNewline == -1 ? text.length : nextNewline;
    final block = text.substring(lineStart, lineEnd);
    final prefixed = block
        .split('\n')
        .map((line) => line.startsWith('- ') ? line : '- $line')
        .join('\n');
    final newText = text.replaceRange(lineStart, lineEnd, prefixed);
    final delta = prefixed.length - block.length;
    setState(() {
      _bodyController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: end + delta),
      );
    });
  }

  /// Prompts for a URL, then inserts `[selected text](url)` — the selected
  /// text becomes the link label, or a generic placeholder when nothing was
  /// selected.
  Future<void> _insertLink() async {
    final text = _bodyController.text;
    final selection = _bodyController.selection;
    final hasSelection = selection.isValid && selection.start != selection.end;
    final insertStart = selection.isValid ? selection.start : text.length;
    final insertEnd = selection.isValid ? selection.end : text.length;
    final label = hasSelection ? text.substring(insertStart, insertEnd) : 'bağlantı';

    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => const _LinkUrlDialog(),
    );
    if (url == null || url.isEmpty || !mounted) return;

    final markup = '[$label]($url)';
    final newText = text.replaceRange(insertStart, insertEnd, markup);
    setState(() {
      _bodyController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: insertStart + markup.length),
      );
    });
  }

  // --- Send / schedule -------------------------------------------------

  /// Resolves [_fromAccount]'s connected-account id, captured once at
  /// send/save time so a later-removed account fails the send explicitly
  /// instead of silently landing on whichever account happens to be
  /// primary by then (see `PendingSend.fromAccountId`).
  String? get _resolvedFromAccountId {
    final email = _fromAccount;
    if (email == null) return null;
    for (final account in _repo.accounts) {
      if (account.email == email) return account.id;
    }
    return null;
  }

  /// The HTML alternative to send/save alongside the plain-text [body], or
  /// null when [body] uses none of the formatting-toolbar markup — so a
  /// plain unformatted mail never carries a redundant html alternative.
  /// Reply/forward flows through this the same as any other compose: the
  /// final typed body (toolbar-added markup, or markup already present in
  /// a quoted/forwarded/draft body) is detected here, at send/save time —
  /// not tracked separately per compose-open kind.
  String? _bodyHtmlFor(String body) =>
      hasMarkdownLiteMarkup(body) ? markdownLiteToHtml(body) : null;

  /// Commits pending recipient text into chips, then validates there is at
  /// least one To recipient and every chip looks like a real address.
  /// Shared by [_send] and [_scheduleSend].
  bool _validateRecipients() {
    setState(() {
      _commitPendingRecipient(_toRecipients, _toInputController);
      _commitPendingRecipient(_ccRecipients, _ccInputController);
      _commitPendingRecipient(_bccRecipients, _bccInputController);
    });
    if (_toRecipients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('En az bir alıcı yazmalısınız.')),
      );
      _toFocus.requestFocus();
      return false;
    }
    final allRecipients = [..._toRecipients, ..._ccRecipients, ..._bccRecipients];
    if (allRecipients.any((r) => !r.valid)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Geçersiz e-posta adreslerini düzeltip tekrar deneyin.'),
        ),
      );
      _toFocus.requestFocus();
      return false;
    }
    return true;
  }

  /// Blocks send/schedule/save-draft while any attachment is still
  /// downloading or failed to download — an attachment must never be
  /// silently dropped from the request (docs-dev spec §5/§6, Kural 4).
  bool _validateAttachmentsReady() {
    if (_attachmentsReady) return true;
    final failed = _attachmentIssues.values.any(
      (issue) => issue.status == _AttachmentIssue.failed,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed
              ? 'Bir ek indirilemedi. Tekrar deneyin veya kaldırın.'
              : 'Ekler hazırlanıyor, lütfen bekleyin.',
        ),
      ),
    );
    return false;
  }

  /// Persist the full message before leaving compose and starting undo.
  /// A storage failure leaves the editor open.
  Future<void> _send() async {
    if (_sending) return;
    if (!_validateRecipients()) return;
    if (!_validateAttachmentsReady()) return;

    final to = _addressStrings(_toRecipients);
    final cc = _addressStrings(_ccRecipients);
    final bcc = _addressStrings(_bccRecipients);
    final subject = _subjectController.text.trim();
    final body = _bodyController.text;
    final bodyHtml = _bodyHtmlFor(body);
    final attachments = List<Attachment>.unmodifiable(_attachments);
    final from = _fromAccount;
    final fromAccountId = _resolvedFromAccountId;
    final threadId = widget.initialThreadId;
    final inReplyToId = widget.inReplyToId;
    final draftId = _draftId;
    final composeTitle = widget.composeTitle;

    final pending = PendingSend(
      id: PendingSendQueue.instance.nextId(),
      to: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      body: body,
      bodyHtml: bodyHtml,
      attachments: attachments,
      from: from,
      fromAccountId: fromAccountId,
      threadId: threadId,
      inReplyToId: inReplyToId,
      draftId: draftId,
    );

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    try {
      await PendingSendQueue.instance.enqueue(
        pending,
        messenger: messenger,
        replacesId: widget.replacesOutboxId,
      );
    } catch (error) {
      if (mounted) {
        setState(() => _sending = false);
        messenger.showSnackBar(SnackBar(
          content: Text('Gönderi kaydedilemedi: ${friendlyErrorMessage(error)}'),
        ));
      }
      return;
    }
    if (!mounted) return;

    final controller = messenger.showSnackBar(
      SnackBar(
        key: const Key('undo-send-snackbar'),
        duration: PendingSendQueue.undoWindow,
        content: _UndoSendSnackContent(duration: PendingSendQueue.undoWindow),
        action: SnackBarAction(
          label: 'Geri Al',
          onPressed: () {
            if (!PendingSendQueue.instance.cancel(pending.id)) return;
            navigator.push(
              MaterialPageRoute(
                builder: (_) => ComposeScreen(
                  composeTitle: composeTitle,
                  editingDraftId: draftId,
                  initialFrom: from,
                  initialTo: to.join(', '),
                  initialCc: cc.join(', '),
                  initialBcc: bcc.join(', '),
                  initialSubject: subject,
                  initialBody: body,
                  initialAttachments: attachments,
                  initialThreadId: threadId,
                  inReplyToId: inReplyToId,
                ),
              ),
            );
          },
        ),
      ),
    );
    unawaited(
      Future<void>.delayed(PendingSendQueue.undoWindow, () {
        try {
          controller.close();
        } catch (_) {
          // Already gone.
        }
      }),
    );

    navigator.pop(true);
  }

  /// Offered from the chevron next to "Gönder": picks a future date/time
  /// through the standard pickers, then queues the mail with
  /// `MailRepository.scheduleSend` instead of sending it now.
  Future<void> _scheduleSend() async {
    if (!_validateRecipients()) return;
    if (!_validateAttachmentsReady()) return;

    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null || !mounted) return;
    final sendAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (!sendAt.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen ileri bir tarih ve saat seçin.')),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      await _repo.scheduleSend(
        to: _addressStrings(_toRecipients),
        cc: _addressStrings(_ccRecipients),
        bcc: _addressStrings(_bccRecipients),
        subject: _subjectController.text.trim(),
        body: _bodyController.text,
        bodyHtml: _bodyHtmlFor(_bodyController.text),
        attachments: List.unmodifiable(_attachments),
        from: _fromAccount,
        fromAccountId: _resolvedFromAccountId,
        inReplyToId: widget.inReplyToId,
        sendAt: sendAt,
      );
      final draftId = _draftId;
      if (draftId != null) {
        try {
          await _repo.deleteDraft(draftId);
        } catch (_) {
          // Scheduled already; a stale draft row reconciles on next refresh.
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'E-posta ${formatMailDateFull(sendAt)} tarihinde gönderilmek üzere zamanlandı.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Zamanlanamadı: ${friendlyErrorMessage(e)}')),
        );
      }
    }
  }

  /// The draft this screen edits: starts as [ComposeScreen.editingDraftId]
  /// and follows the id each save returns (an update re-creates the draft
  /// under a new id).
  late String? _draftId = widget.editingDraftId;

  /// In-flight save shared by every caller, so a double-tapped "Taslağı
  /// Kaydet" writes the draft once instead of cloning it.
  Future<bool>? _pendingSave;

  Future<bool> _saveDraft() =>
      _pendingSave ??= _writeDraft().whenComplete(() => _pendingSave = null);

  Future<bool> _writeDraft() async {
    if (!_hasContent) return true;
    if (!_attachmentsReady) return false;
    setState(() {
      _commitPendingRecipient(_toRecipients, _toInputController);
      _commitPendingRecipient(_ccRecipients, _ccInputController);
      _commitPendingRecipient(_bccRecipients, _bccInputController);
    });
    try {
      final saved = await _repo.saveDraft(
        from: _fromAccount,
        fromAccountId: _resolvedFromAccountId,
        to: _addressStrings(_toRecipients),
        cc: _addressStrings(_ccRecipients),
        bcc: _addressStrings(_bccRecipients),
        subject: _subjectController.text.trim(),
        body: _bodyController.text,
        bodyHtml: _bodyHtmlFor(_bodyController.text),
        attachments: List.unmodifiable(_attachments),
        threadId: widget.initialThreadId,
        inReplyToId: widget.inReplyToId,
        // Editing a draft updates it in place — never a duplicate.
        draftId: _draftId,
      );
      _draftId = saved.id;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<Attachment>?> _osPickAttachments() async {
    final files = await FilePicker.pickFiles(type: FileType.any);
    if (files.isEmpty) return null;
    return [
      for (final file in files)
        if (file.name.isNotEmpty)
          Attachment(
            name: file.name,
            sizeBytes: file.lengthSync() ?? 0,
            mimeType: file.extension,
            bytes: await file.readAsBytes(),
          ),
    ];
  }

  Future<void> _attach() async {
    if (_sending) return;
    final picked = await (widget.pickAttachments ?? _osPickAttachments)();
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() => _attachments.addAll(picked));
  }

  void _removeAttachment(Attachment attachment) {
    setState(() {
      _attachments.remove(attachment);
      _attachmentIssues.remove(attachment);
    });
  }

  /// Downloads (or re-downloads) [attachment]'s content from
  /// [ComposeScreen.attachmentSourceMailId]. Success replaces the
  /// placeholder in [_attachments] with a byte-carrying copy and clears
  /// its entry from [_attachmentIssues]; failure records the reason so the
  /// row can offer retry/remove instead of silently dropping it.
  Future<void> _downloadRemoteAttachment(Attachment attachment) async {
    final sourceMailId = widget.attachmentSourceMailId;
    if (sourceMailId == null) {
      if (mounted) {
        setState(() {
          _attachmentIssues[attachment] = (
            status: _AttachmentIssue.failed,
            error: 'Ek indirilemedi.',
          );
        });
      }
      return;
    }
    try {
      final bytes = await _repo.downloadAttachment(sourceMailId, attachment);
      if (!mounted) return;
      final index = _attachments.indexOf(attachment);
      if (index == -1) return; // Removed while the download was in flight.
      setState(() {
        _attachments[index] = Attachment(
          id: attachment.id,
          name: attachment.name,
          sizeBytes: attachment.sizeBytes,
          mimeType: attachment.mimeType,
          bytes: bytes,
        );
        _attachmentIssues.remove(attachment);
      });
    } catch (error) {
      if (!mounted) return;
      if (!_attachments.contains(attachment)) return;
      setState(() {
        _attachmentIssues[attachment] = (
          status: _AttachmentIssue.failed,
          error: friendlyErrorMessage(error),
        );
      });
    }
  }

  void _retryAttachment(Attachment attachment) {
    setState(() {
      _attachmentIssues[attachment] = (
        status: _AttachmentIssue.downloading,
        error: null,
      );
    });
    unawaited(_downloadRemoteAttachment(attachment));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
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
            tooltip: 'Kapat',
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
                    ? 'Taslağı Düzenle'
                    : 'Yeni E-posta'),
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
                tooltip: 'Şimdi Gönder',
                onPressed: _send,
              ),
              PopupMenuButton<String>(
                key: const Key('send-options-menu'),
                tooltip: 'Gönderme seçenekleri',
                padding: EdgeInsets.zero,
                icon: Icon(
                  LucideIcons.chevronDown,
                  size: 18,
                  color: colors.secondaryText,
                ),
                onSelected: (value) {
                  if (value == 'now') {
                    _send();
                  } else if (value == 'schedule') {
                    _scheduleSend();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'now', child: Text('Şimdi Gönder')),
                  PopupMenuItem(value: 'schedule', child: Text('Zamanla')),
                ],
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
                        label: 'Kime',
                        recipients: _toRecipients,
                        inputController: _toInputController,
                        focusNode: _toFocus,
                        fieldKey: const Key('to-field'),
                        enabled: !_sending,
                        suggestionLink: _toLink,
                        onRemove: (r) => _removeRecipient(_toRecipients, r),
                        onChanged: (v) {
                          _onRecipientChanged(_toRecipients, _toInputController, v);
                          _updateSuggestions(
                            _toLink,
                            v,
                            _toRecipients,
                            (c) => _commitSuggestion(_toRecipients, _toInputController, c),
                          );
                        },
                        onSubmitted: () =>
                            _onRecipientSubmitted(_toRecipients, _toInputController),
                        trailing: (!_ccExpanded || !_bccExpanded)
                            ? PopupMenuButton<String>(
                                key: const Key('cc-bcc-menu'),
                                tooltip: 'Cc / Bcc ekle',
                                padding: EdgeInsets.zero,
                                enabled: !_sending,
                                style: IconButton.styleFrom(
                                  minimumSize: const Size(32, 32),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                            _onRecipientChanged(_ccRecipients, _ccInputController, v);
                            _updateSuggestions(
                              _ccLink,
                              v,
                              _ccRecipients,
                              (c) => _commitSuggestion(_ccRecipients, _ccInputController, c),
                            );
                          },
                          onSubmitted: () =>
                              _onRecipientSubmitted(_ccRecipients, _ccInputController),
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
                            _onRecipientChanged(_bccRecipients, _bccInputController, v);
                            _updateSuggestions(
                              _bccLink,
                              v,
                              _bccRecipients,
                              (c) => _commitSuggestion(_bccRecipients, _bccInputController, c),
                            );
                          },
                          onSubmitted: () => _onRecipientSubmitted(
                            _bccRecipients,
                            _bccInputController,
                          ),
                        ),
                      const Divider(indent: 0, endIndent: 0),
                      _fieldRow(
                        label: 'Konu',
                        controller: _subjectController,
                        fieldKey: const Key('subject-field'),
                        enabled: !_sending,
                      ),
                      const Divider(indent: 0, endIndent: 0, height: 1),
                      if (_attachments.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        for (final attachment in _attachments)
                          _AttachmentRow(
                            attachment: attachment,
                            onRemove: () => _removeAttachment(attachment),
                            onRetry: () => _retryAttachment(attachment),
                            enabled: !_sending,
                            issue: _attachmentIssues[attachment]?.status,
                            error: _attachmentIssues[attachment]?.error,
                          ),
                      ],
                      const SizedBox(height: 8),
                      _formattingToolbar(colors),
                      TextField(
                        key: const Key('body-field'),
                        controller: _bodyController,
                        focusNode: _bodyFocus,
                        enabled: !_sending,
                        maxLines: null,
                        textAlignVertical: TextAlignVertical.top,
                        decoration: _flatBodyDecoration,
                        style: TextStyle(
                          fontSize: 15,
                          color: colors.bodyText,
                          height: 1.55,
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

  /// Small toolbar of markdown-lite formatting shortcuts above the body:
  /// bold/italic/underline wrap the current selection, the list button
  /// bullet-prefixes the current line(s), and the link button prompts for a
  /// URL. See `_wrapSelection`/`_toggleBulletList`/`_insertLink`.
  Widget _formattingToolbar(AppColors colors) {
    Widget button(Key key, IconData icon, String tooltip, VoidCallback onPressed) {
      return IconButton(
        key: key,
        icon: Icon(icon, size: AppTheme.iconSizeMedium),
        tooltip: tooltip,
        color: colors.secondaryText,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        onPressed: _sending ? null : onPressed,
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        button(
          const Key('format-bold'),
          LucideIcons.bold,
          'Kalın',
          () => _wrapSelection('**', '**'),
        ),
        button(
          const Key('format-italic'),
          LucideIcons.italic,
          'İtalik',
          () => _wrapSelection('*', '*'),
        ),
        button(
          const Key('format-underline'),
          LucideIcons.underline,
          'Altı çizili',
          () => _wrapSelection('__', '__'),
        ),
        button(
          const Key('format-list'),
          LucideIcons.list,
          'Madde işaretli liste',
          _toggleBulletList,
        ),
        button(
          const Key('format-link'),
          LucideIcons.link,
          'Bağlantı ekle',
          _insertLink,
        ),
      ],
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
            decoration: _flatFieldDecoration,
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
    required List<_Recipient> recipients,
    required TextEditingController inputController,
    required void Function(_Recipient) onRemove,
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
                    _RecipientChip(
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
                      decoration: _flatFieldDecoration,
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
              'Kimden',
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: _labelStyle(colors),
            ),
          ),
          Expanded(
            child: Text(
              selected,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15, color: colors.bodyText),
            ),
          ),
          if (accounts.length > 1)
            PopupMenuButton<String>(
              key: const Key('from-account-menu'),
              tooltip: 'Hesap seç',
              padding: EdgeInsets.zero,
              enabled: !_sending,
              icon: Icon(
                LucideIcons.chevronDown,
                size: 18,
                color: colors.secondaryText,
              ),
              onSelected: (picked) {
                setState(() => _fromAccount = picked);
                _syncSignature();
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
            onPressed: _sending ? null : _attach,
            icon: const Icon(LucideIcons.paperclip, size: 22),
            tooltip: 'Dosya ekle',
          ),
        ],
      ),
    );
  }
}

/// A single recipient chip. [recipient.valid] false renders it in the
/// destructive palette instead of silently dropping or silently sending a
/// broken address — the user has to see and fix it.
class _RecipientChip extends StatelessWidget {
  const _RecipientChip({
    super.key,
    required this.recipient,
    required this.onDeleted,
    this.enabled = true,
  });

  final _Recipient recipient;
  final VoidCallback onDeleted;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final destructive = !recipient.valid;
    return Chip(
      label: Text(recipient.address, style: const TextStyle(fontSize: 13)),
      backgroundColor: destructive
          ? colors.destructive.withValues(alpha: 0.12)
          : colors.surfaceAlt,
      labelStyle: TextStyle(color: destructive ? colors.destructive : colors.bodyText),
      deleteIcon: Icon(
        LucideIcons.x,
        size: 14,
        color: destructive ? colors.destructive : colors.secondaryText,
      ),
      onDeleted: enabled ? onDeleted : null,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      side: BorderSide(color: destructive ? colors.destructive : colors.border),
    );
  }
}

class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({
    required this.attachment,
    required this.onRemove,
    this.onRetry,
    this.enabled = true,
    this.issue,
    this.error,
  });

  final Attachment attachment;
  final VoidCallback onRemove;
  final VoidCallback? onRetry;
  final bool enabled;

  /// Null means ready (bytes in hand); non-null gates Send/save-draft/
  /// schedule until it's resolved — see `_ComposeScreenState._attachmentIssues`.
  final _AttachmentIssue? issue;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final downloading = issue == _AttachmentIssue.downloading;
    final failed = issue == _AttachmentIssue.failed;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        ),
        child: Row(
          children: [
            Icon(
              failed ? LucideIcons.fileWarning : LucideIcons.paperclip,
              size: 16,
              color: failed ? colors.destructive : colors.secondaryText,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    attachment.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: colors.bodyText),
                  ),
                  if (failed)
                    Text(
                      error ?? 'Ek indirilemedi.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: colors.destructive),
                    )
                  else if (downloading)
                    Text(
                      'İndiriliyor…',
                      style: TextStyle(fontSize: 11, color: colors.secondaryText),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (downloading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (!failed)
              Text(
                attachment.sizeLabel,
                style: TextStyle(fontSize: 12, color: colors.secondaryText),
              ),
            if (failed)
              IconButton(
                onPressed: enabled ? onRetry : null,
                icon: const Icon(LucideIcons.refreshCw, size: 16),
                tooltip: 'Tekrar indir',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            IconButton(
              onPressed: enabled ? onRemove : null,
              icon: const Icon(LucideIcons.x, size: 16),
              tooltip: 'Kaldır',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live "N sn içinde gönderilecek" countdown shown inside the undo-send
/// SnackBar. Purely cosmetic — the actual send fires from
/// [PendingSendQueue]'s own timer, and the SnackBar itself is dismissed by
/// the controller `_ComposeScreenState._send` captured from `showSnackBar`,
/// both on [PendingSendQueue.undoWindow]; this only mirrors it visually.
class _UndoSendSnackContent extends StatefulWidget {
  const _UndoSendSnackContent({required this.duration});

  final Duration duration;

  @override
  State<_UndoSendSnackContent> createState() => _UndoSendSnackContentState();
}

class _UndoSendSnackContentState extends State<_UndoSendSnackContent> {
  late int _secondsLeft = widget.duration.inSeconds;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsLeft <= 1) {
        _ticker?.cancel();
        setState(() => _secondsLeft = 0);
        return;
      }
      setState(() => _secondsLeft -= 1);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text('E-posta $_secondsLeft sn içinde gönderilecek');
  }
}

/// Tappable contact suggestion dropdown, anchored under a recipient field
/// via [CompositedTransformFollower]/[CompositedTransformTarget] (see
/// `_ComposeScreenState._updateSuggestions`).
class _ContactSuggestionList extends StatelessWidget {
  const _ContactSuggestionList({required this.contacts, required this.onSelected});

  final List<Contact> contacts;
  final void Function(Contact) onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      color: Theme.of(context).colorScheme.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        child: ListView(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          children: [
            for (final contact in contacts)
              ListTile(
                key: ValueKey('contact-suggestion-${contact.email}'),
                dense: true,
                title: Text(
                  contact.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: contact.displayName == contact.email
                    ? null
                    : Text(
                        contact.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.secondaryText),
                      ),
                onTap: () => onSelected(contact),
              ),
          ],
        ),
      ),
    );
  }
}

/// Prompts for a URL to insert as a link. A [StatefulWidget] (not a bare
/// controller disposed right after the dialog closes) so the framework
/// disposes [_controller] only once the widget is truly unmounted — the
/// dialog's own exit transition keeps it mounted for a few more frames
/// after `Navigator.pop`, and disposing any earlier crashes that
/// animation (same convention as `_LabelEditorDialogState`).
class _LinkUrlDialog extends StatefulWidget {
  const _LinkUrlDialog();

  @override
  State<_LinkUrlDialog> createState() => _LinkUrlDialogState();
}

class _LinkUrlDialogState extends State<_LinkUrlDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Bağlantı Ekle'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(hintText: 'https://ornek.com'),
        onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Ekle'),
        ),
      ],
    );
  }
}
