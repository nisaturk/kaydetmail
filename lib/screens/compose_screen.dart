import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../config/app_config.dart';
import '../models/email.dart';
import '../repositories/mail_repository.dart';
import '../theme/app_theme.dart';
import '../utils/error_messages.dart';

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
/// carry a ~120 character snippet and no attachment files, so the draft is
/// fetched (and its attachments downloaded) first — saving an editor
/// prefilled from the row would truncate the body and drop attachments.
/// Falls back to the cached copy when the fetch fails (e.g. offline).
Future<void> openDraftEditor(BuildContext context, Email draft) async {
  final repo = AppConfig.mailRepository;
  var full = draft;
  try {
    full = await repo.getEmail(draft.id) ?? draft;
  } catch (_) {}
  final attachments = await Future.wait(
    full.attachments.map((attachment) async {
      if (attachment.bytes != null || attachment.id == null) return attachment;
      try {
        return Attachment(
          id: attachment.id,
          name: attachment.name,
          sizeBytes: attachment.sizeBytes,
          mimeType: attachment.mimeType,
          bytes: await repo.downloadAttachment(full.id, attachment),
        );
      } catch (_) {
        return attachment;
      }
    }),
  );
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
        initialAttachments: attachments,
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
/// open or the screen is narrow. The mic button dictates speech to text via
/// the on-device speech recognizer (Android/iOS).
/// Smart-back saves a draft when content exists.
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
    this.editingDraftId,
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

  /// Id of the draft being edited, or null for a new mail/reply/forward.
  final String? editingDraftId;
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
  final _bodyFocus = FocusNode();

  bool _ccExpanded = false;
  bool _bccExpanded = false;
  bool _recording = false;
  bool _sending = false;
  String? _fromAccount;

  final SpeechToText _speech = SpeechToText();
  bool _speechInitialized = false;

  /// Body text captured at the start of the current dictation session; each
  /// recognized chunk is appended after this so restarting the recognizer
  /// (Android stops listening after a few seconds of silence) never drops
  /// or duplicates already-dictated text.
  String _dictationBase = '';

  final List<Attachment> _attachments = [];

  MailRepository get _repo => AppConfig.mailRepository;

  @override
  void initState() {
    super.initState();
    _toRecipients.addAll(_parseRecipients(widget.initialTo));
    _ccRecipients.addAll(_parseRecipients(widget.initialCc));
    _bccRecipients.addAll(_parseRecipients(widget.initialBcc));
    _subjectController.text = widget.initialSubject;
    _bodyController.text = widget.initialBody;
    // Fields that already carry content start visible so nothing is lost;
    // empty ones stay hidden behind the Cc/Bcc menu.
    _ccExpanded = _ccRecipients.isNotEmpty;
    _bccExpanded = _bccRecipients.isNotEmpty;
    _attachments.addAll(widget.initialAttachments);
    final accounts = _repo.accounts;
    if (widget.initialFrom != null &&
        accounts.any((a) => a.email == widget.initialFrom)) {
      _fromAccount = widget.initialFrom;
    } else {
      _fromAccount = accounts.any((a) => a.email == _repo.currentUser)
          ? _repo.currentUser
          : (accounts.isNotEmpty ? accounts.first.email : null);
    }
  }

  static List<_Recipient> _parseRecipients(String raw) => raw
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .map((e) => _Recipient(e, valid: _emailShapePattern.hasMatch(e)))
      .toList();

  @override
  void dispose() {
    _toInputController.dispose();
    _ccInputController.dispose();
    _bccInputController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    _toFocus.dispose();
    _bodyFocus.dispose();
    if (_speechInitialized) _speech.cancel();
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

  Future<void> _send() async {
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
      return;
    }
    final allRecipients = [..._toRecipients, ..._ccRecipients, ..._bccRecipients];
    if (allRecipients.any((r) => !r.valid)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Geçersiz e-posta adreslerini düzeltip tekrar deneyin.'),
        ),
      );
      _toFocus.requestFocus();
      return;
    }

    setState(() => _sending = true);
    try {
      await _repo.sendEmail(
        from: _fromAccount,
        to: _addressStrings(_toRecipients),
        cc: _addressStrings(_ccRecipients),
        bcc: _addressStrings(_bccRecipients),
        subject: _subjectController.text.trim(),
        body: _bodyController.text,
        attachments: List.unmodifiable(_attachments),
        threadId: widget.initialThreadId,
        inReplyToId: widget.inReplyToId,
      );
      // A sent draft leaves Drafts — the sent copy lives in Sent now.
      final draftId = _draftId;
      if (draftId != null) {
        try {
          await _repo.deleteDraft(draftId);
        } catch (_) {
          // The mail is already sent; a stale draft row is harmless next
          // to that and reconciles on the next refresh.
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('E-posta gönderildi.')));
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gönderilemedi: ${friendlyErrorMessage(e)}')),
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
    setState(() {
      _commitPendingRecipient(_toRecipients, _toInputController);
      _commitPendingRecipient(_ccRecipients, _ccInputController);
      _commitPendingRecipient(_bccRecipients, _bccInputController);
    });
    try {
      final saved = await _repo.saveDraft(
        from: _fromAccount,
        to: _addressStrings(_toRecipients),
        cc: _addressStrings(_ccRecipients),
        bcc: _addressStrings(_bccRecipients),
        subject: _subjectController.text.trim(),
        body: _bodyController.text,
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
    setState(() => _attachments.remove(attachment));
  }

  /// Starts (or restarts) a listen session. Android in particular stops
  /// listening after a few seconds of silence even mid-sentence — see
  /// [_onSpeechStatus], which restarts it automatically until the user taps
  /// the mic again — so this is called more than once per dictation.
  Future<void> _startListening() async {
    try {
      await _speech.listen(
        onResult: _onSpeechResult,
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
          autoPunctuation: true,
          pauseFor: const Duration(seconds: 30),
          listenFor: const Duration(minutes: 5),
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _recording = false);
    }
  }

  /// Appends each recognized chunk after [_dictationBase] (the text typed
  /// or dictated before this listen session) instead of after the current
  /// controller text, so a live partial result never gets appended on top
  /// of itself as it is refined.
  void _onSpeechResult(SpeechRecognitionResult result) {
    final words = result.recognizedWords;
    final needsSpace =
        _dictationBase.isNotEmpty &&
        !_dictationBase.endsWith('\n') &&
        !_dictationBase.endsWith(' ');
    final combined = '$_dictationBase${needsSpace ? ' ' : ''}$words';
    _bodyController.value = TextEditingValue(
      text: combined,
      selection: TextSelection.collapsed(offset: combined.length),
    );
    if (result.finalResult) _dictationBase = combined;
  }

  /// `notListening`/`done` fire both when the user stops dictation and when
  /// the platform times out a pause; `_recording` (cleared *before* calling
  /// [SpeechToText.stop]) tells these two cases apart so a pause never
  /// silently ends dictation early.
  void _onSpeechStatus(String status) {
    if (!mounted || !_recording) return;
    if (status == SpeechToText.notListeningStatus ||
        status == SpeechToText.doneStatus) {
      _startListening();
    }
  }

  void _onSpeechError(SpeechRecognitionError error) {
    if (!error.permanent) {
      return; // Transient — the retry in onStatus covers it.
    }
    if (!mounted) return;
    setState(() => _recording = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sesle yazma kullanılamıyor.')),
    );
  }

  Future<void> _toggleDictation() async {
    if (_recording) {
      setState(() => _recording = false);
      await _speech.stop();
      return;
    }
    if (!_speechInitialized) {
      _speechInitialized = await _speech.initialize(
        onStatus: _onSpeechStatus,
        onError: _onSpeechError,
      );
    }
    if (!_speechInitialized) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sesle yazma için mikrofon iznini vermeniz gerekiyor.'),
        ),
      );
      return;
    }
    _dictationBase = _bodyController.text;
    setState(() => _recording = true);
    await _startListening();
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
            else
              IconButton(
                icon: const Icon(LucideIcons.send),
                tooltip: 'Gönder',
                onPressed: _send,
              ),
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
                        onRemove: (r) => _removeRecipient(_toRecipients, r),
                        onChanged: (v) =>
                            _onRecipientChanged(_toRecipients, _toInputController, v),
                        onSubmitted: () =>
                            _onRecipientSubmitted(_toRecipients, _toInputController),
                        trailing: (!_ccExpanded || !_bccExpanded)
                            ? PopupMenuButton<String>(
                                key: const Key('cc-bcc-menu'),
                                tooltip: 'Cc / Bcc ekle',
                                padding: EdgeInsets.zero,
                                enabled: !_sending,
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
                          fieldKey: const Key('cc-field'),
                          enabled: !_sending,
                          onRemove: (r) => _removeRecipient(_ccRecipients, r),
                          onChanged: (v) =>
                              _onRecipientChanged(_ccRecipients, _ccInputController, v),
                          onSubmitted: () =>
                              _onRecipientSubmitted(_ccRecipients, _ccInputController),
                        ),
                      if (_bccExpanded)
                        _recipientFieldRow(
                          label: 'Bcc',
                          recipients: _bccRecipients,
                          inputController: _bccInputController,
                          fieldKey: const Key('bcc-field'),
                          enabled: !_sending,
                          onRemove: (r) => _removeRecipient(_bccRecipients, r),
                          onChanged: (v) => _onRecipientChanged(
                            _bccRecipients,
                            _bccInputController,
                            v,
                          ),
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
                            enabled: !_sending,
                          ),
                      ],
                      const SizedBox(height: 8),
                      TextField(
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
  /// [_fieldRow] so Kimden/Kime/Cc/Bcc/Konu stay aligned.
  Widget _recipientFieldRow({
    required String label,
    required List<_Recipient> recipients,
    required TextEditingController inputController,
    required void Function(_Recipient) onRemove,
    required void Function(String) onChanged,
    required VoidCallback onSubmitted,
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
                SizedBox(
                  width: 140,
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
              onSelected: (picked) => setState(() => _fromAccount = picked),
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
          IconButton(
            onPressed: _sending ? null : _toggleDictation,
            icon: _recording
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: colors.destructive,
                    ),
                  )
                : const Icon(LucideIcons.mic, size: 22),
            tooltip: _recording ? 'Dinlemeyi durdur' : 'Sesle yaz',
          ),
          if (_recording)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                'Dinleniyor…',
                style: TextStyle(
                  fontSize: 13,
                  color: colors.destructive,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            const Spacer(),
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
    required this.enabled,
    required this.onDeleted,
  });

  final _Recipient recipient;
  final bool enabled;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    if (recipient.valid) {
      return Chip(
        label: Text(recipient.address),
        onDeleted: enabled ? onDeleted : null,
        deleteButtonTooltipMessage: '${recipient.address} kaldır',
        visualDensity: VisualDensity.compact,
      );
    }
    return Semantics(
      label: '${recipient.address}, geçersiz e-posta adresi',
      child: Chip(
        label: Text(recipient.address),
        labelStyle: TextStyle(color: colors.destructive),
        backgroundColor: colors.destructive.withValues(alpha: 0.12),
        side: BorderSide(color: colors.destructive),
        deleteIconColor: colors.destructive,
        onDeleted: enabled ? onDeleted : null,
        deleteButtonTooltipMessage: '${recipient.address} kaldır',
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({
    required this.attachment,
    required this.onRemove,
    this.enabled = true,
  });

  final Attachment attachment;
  final VoidCallback onRemove;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(10),
        color: colors.unreadBackground,
      ),
      child: Row(
        children: [
          Icon(LucideIcons.fileText, size: 20, color: colors.secondaryText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              attachment.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: colors.bodyText),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            attachment.sizeLabel,
            style: TextStyle(fontSize: 13, color: colors.secondaryText),
          ),
          IconButton(
            key: ValueKey('attach-remove-${attachment.name}'),
            onPressed: enabled ? onRemove : null,
            tooltip: '${attachment.name} kaldır',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: Icon(LucideIcons.x, color: colors.secondaryText),
          ),
        ],
      ),
    );
  }
}
