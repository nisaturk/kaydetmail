part of '../compose_screen.dart';

/// Fields shared by the logic mixins of [_ComposeScreenState].
abstract class _ComposeStateBase extends State<ComposeScreen> {
  final List<Recipient> _toRecipients = [];

  final List<Recipient> _ccRecipients = [];

  final List<Recipient> _bccRecipients = [];

  // Holds whatever the user has typed but not yet turned into a chip
  // (no comma/space/Enter yet). Read alongside the chip lists so in-flight
  // text is never silently lost from `_hasContent`, send, or save-draft.
  final _toInputController = TextEditingController();

  final _ccInputController = TextEditingController();

  final _bccInputController = TextEditingController();

  final _subjectController = TextEditingController();

  late final quill.QuillController _bodyController;

  final _toFocus = FocusNode();

  final _ccFocus = FocusNode();

  final _bccFocus = FocusNode();

  final _bodyFocus = FocusNode();

  bool _ccExpanded = false;

  bool _bccExpanded = false;

  bool _sending = false;

  late bool _requestReadReceipt = widget.initialRequestReadReceipt;

  String? _fromAccount;

  MailIdentity? _fromIdentity;

  List<MailIdentity> _identities = const [];

  bool _identitiesLoaded = false;

  ComposeLimits? _limits;

  bool _resizingImages = false;

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
  final Map<Attachment, ({AttachmentIssue status, String? error})>
  _attachmentIssues = {};

  bool get _attachmentsReady => _attachmentIssues.isEmpty && !_resizingImages;

  // --- Contact autocomplete (Kime/Cc/Bcc) --------------------------------
  final _toLink = LayerLink();

  final _ccLink = LayerLink();

  final _bccLink = LayerLink();

  OverlayEntry? _suggestionOverlay;

  List<Contact> _contacts = const [];

  // --- Signature -----------------------------------------------------
  /// Body without the managed signature, including any quoted history.
  String _bodyBeforeSignature = '';

  int _signatureInsertionOffset = 0;

  String _managedSignatureDelta = '';

  int _signatureRequest = 0;

  String _insertedSignature = '';

  late final String _initialBodyDelta;

  /// Restored bodies already contain their signature and writing space.
  bool get _signatureEligible =>
      widget.editingDraftId == null && widget.insertSignature;

  MailRepository get _repo => AppConfig.mailRepository;

  quill.Document _initialBodyDocument() {
    final html = widget.initialBodyHtml;
    if (html != null && html.trim().isNotEmpty) {
      try {
        final document = quill.Document.fromDelta(HtmlToDelta().convert(html));
        return _withReplyWritingSpace(document);
      } catch (_) {
        // Keep backend plain text when rich conversion rejects malformed HTML.
      }
    }
    final document = quill.Document();
    final fallback = widget.initialBody.isNotEmpty
        ? widget.initialBody
        : html == null
        ? ''
        : htmlToPlainText(html);
    if (fallback.isNotEmpty) {
      document.insert(0, fallback);
    }
    return _withReplyWritingSpace(document);
  }

  quill.Document _withReplyWritingSpace(quill.Document document) {
    if (widget.initialReplyWritingLines > 0) {
      document.insert(0, '\n' * widget.initialReplyWritingLines);
    }
    return document;
  }

  String get _bodyText {
    final text = _bodyController.document.toPlainText();
    return text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
  }

  /// The plain-text alternative: embeds (quoted images) have no text form.
  String get _outgoingBodyText =>
      _bodyText.replaceAll(quill.Embed.kObjectReplacementCharacter, '');

  TextSelection get _bodySelection => _bodyController.selection;

  bool get _hasContent =>
      _toRecipients.isNotEmpty ||
      _ccRecipients.isNotEmpty ||
      _bccRecipients.isNotEmpty ||
      _toInputController.text.trim().isNotEmpty ||
      _ccInputController.text.trim().isNotEmpty ||
      _bccInputController.text.trim().isNotEmpty ||
      _subjectController.text.trim().isNotEmpty ||
      _bodyText.trim().isNotEmpty ||
      _attachments.isNotEmpty;

  String _recipientDraftValue(
    List<Recipient> recipients,
    TextEditingController input,
  ) => [
    ...recipients.map((recipient) => recipient.address.trim()),
    if (input.text.trim().isNotEmpty) input.text.trim(),
  ].join(',');

  String _initialRecipientDraftValue(String value) =>
      _parseRecipients(value).map((recipient) => recipient.address).join(',');

  bool get _editingDraftChanged {
    if (widget.editingDraftId == null) return false;
    if (_recipientDraftValue(_toRecipients, _toInputController) !=
            _initialRecipientDraftValue(widget.initialTo) ||
        _recipientDraftValue(_ccRecipients, _ccInputController) !=
            _initialRecipientDraftValue(widget.initialCc) ||
        _recipientDraftValue(_bccRecipients, _bccInputController) !=
            _initialRecipientDraftValue(widget.initialBcc) ||
        _subjectController.text != widget.initialSubject ||
        jsonEncode(_bodyController.document.toDelta().toJson()) !=
            _initialBodyDelta) {
      return true;
    }
    if (_attachments.length != widget.initialAttachments.length) return true;
    for (var index = 0; index < _attachments.length; index++) {
      final current = _attachments[index];
      final initial = widget.initialAttachments[index];
      if (current.id != initial.id ||
          current.name != initial.name ||
          current.sizeBytes != initial.sizeBytes ||
          current.mimeType != initial.mimeType) {
        return true;
      }
    }
    if (_identitiesLoaded && widget.initialFrom != null) {
      final currentFrom = _fromIdentity?.emailAddress ?? _fromAccount;
      if (currentFrom != widget.initialFrom) return true;
    }
    return false;
  }

  /// Everything a draft save persists, for telling whether the editor
  /// changed since the last save from this screen.
  String get _draftFingerprint => jsonEncode([
    _recipientDraftValue(_toRecipients, _toInputController),
    _recipientDraftValue(_ccRecipients, _ccInputController),
    _recipientDraftValue(_bccRecipients, _bccInputController),
    _subjectController.text,
    _bodyController.document.toDelta().toJson(),
    [for (final a in _attachments) '${a.id}|${a.name}|${a.sizeBytes}'],
    _fromIdentity?.emailAddress ?? _fromAccount,
  ]);

  /// [_draftFingerprint] at the last successful save; null until this
  /// screen saves once (then [_editingDraftChanged] no longer applies).
  String? _savedDraftFingerprint;

  bool get _draftChanged => _savedDraftFingerprint == null
      ? _editingDraftChanged
      : _draftFingerprint != _savedDraftFingerprint;

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

  /// Serializes the editor delta to the HTML alternative sent alongside the
  /// plain-text body, or null when nothing is styled or embedded so an
  /// unformatted mail never carries a redundant HTML part.
  String? get _bodyHtml {
    if (_bodyText.trim().isEmpty) return null;
    final operations = _bodyController.document
        .toDelta()
        .toJson()
        .cast<Map<String, dynamic>>();
    if (!operations.any(
      (op) => op['attributes'] != null || op['insert'] is! String,
    )) {
      return null;
    }
    return QuillDeltaToHtmlConverter(
      operations,
      ConverterOptions.forEmail(),
    ).convert();
  }

  /// The draft this screen edits: starts as [ComposeScreen.editingDraftId]
  /// and follows the id each save returns (an update re-creates the draft
  /// under a new id).
  late String? _draftId = widget.editingDraftId;

  /// In-flight save shared by every caller, so a double-tapped "Taslağı
  /// Kaydet" writes the draft once instead of cloning it.
  Future<bool>? _pendingSave;
}

List<Recipient> _parseRecipients(String raw) => raw
    .split(',')
    .map((e) => e.trim())
    .where((e) => e.isNotEmpty)
    .map((e) => Recipient(e, valid: emailShapePattern.hasMatch(e)))
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
final DateTime _manualContactRank = DateTime.utc(9999);
