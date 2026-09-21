import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/email.dart';
import '../repositories/mail_repository.dart';
import '../theme/app_theme.dart';

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

const _flatBodyDecoration = InputDecoration(
  hintText: 'E-postanızı yazın…',
  border: InputBorder.none,
  enabledBorder: InputBorder.none,
  focusedBorder: InputBorder.none,
  errorBorder: InputBorder.none,
  focusedErrorBorder: InputBorder.none,
  disabledBorder: InputBorder.none,
  filled: false,
  hintStyle: TextStyle(color: AppTheme.tertiaryText),
);

/// Compose a new mail (or reply/forward/edit-draft — same screen).
///
/// Cc/Bcc stay hidden behind a compact menu until requested. When
/// [editingDraftId] is set the screen edits that draft: fields are prefilled,
/// saving updates it in place (no duplicate) and sending removes it from
/// Drafts. Inside a scrolled column so nothing overflows when the keyboard is
/// open or the screen is narrow. The mic button appends simulated voice text.
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
  final _toController = TextEditingController();
  final _ccController = TextEditingController();
  final _bccController = TextEditingController();
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();

  final _toFocus = FocusNode();
  final _bodyFocus = FocusNode();

  bool _ccExpanded = false;
  bool _bccExpanded = false;
  bool _recording = false;
  bool _sending = false;
  String? _fromAccount;

  final List<Attachment> _attachments = [];

  MailRepository get _repo => AppConfig.mailRepository;

  @override
  void initState() {
    super.initState();
    _toController.text = widget.initialTo;
    _ccController.text = widget.initialCc;
    _bccController.text = widget.initialBcc;
    _subjectController.text = widget.initialSubject;
    _bodyController.text = widget.initialBody;
    // Fields that already carry content start visible so nothing is lost;
    // empty ones stay hidden behind the Cc/Bcc menu.
    _ccExpanded = widget.initialCc.trim().isNotEmpty;
    _bccExpanded = widget.initialBcc.trim().isNotEmpty;
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

  @override
  void dispose() {
    _toController.dispose();
    _ccController.dispose();
    _bccController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    _toFocus.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  bool get _hasContent =>
      _toController.text.trim().isNotEmpty ||
      _subjectController.text.trim().isNotEmpty ||
      _bodyController.text.trim().isNotEmpty ||
      _attachments.isNotEmpty;

  Future<bool> _onWillPop() async {
    if (!_hasContent) return true;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Bu e-posta silinsin mi?'),
            content: const Text(
              'Taslak olarak kaydedebilir veya silebilirsiniz.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Vazgeç'),
              ),
              TextButton(
                onPressed: () async {
                  await _saveDraft();
                  if (mounted && ctx.mounted) {
                    Navigator.of(ctx).pop(true);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Taslak kaydedildi.')),
                    );
                  }
                },
                child: const Text('Taslağı Kaydet'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Sil', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ) ??
        false;
  }

  List<String> _splitAddresses(TextEditingController controller) => controller
      .text
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  Future<void> _send() async {
    final to = _toController.text.trim();
    if (to.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('En az bir alıcı yazmalısınız.')),
      );
      _toFocus.requestFocus();
      return;
    }

    setState(() => _sending = true);
    try {
      await _repo.sendEmail(
        from: _fromAccount,
        to: _splitAddresses(_toController),
        cc: _splitAddresses(_ccController),
        bcc: _splitAddresses(_bccController),
        subject: _subjectController.text.trim(),
        body: _bodyController.text,
        attachments: List.unmodifiable(_attachments),
        threadId: widget.initialThreadId,
        inReplyToId: widget.inReplyToId,
      );
      // A sent draft leaves Drafts — the sent copy lives in Sent now.
      final draftId = widget.editingDraftId;
      if (draftId != null) {
        try {
          await _repo.deleteDraft(draftId);
        } catch (_) {
          // The mail is already sent; a stale draft row is harmless next
          // to that and reconciles on the next refresh.
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('E-posta gönderildi.')));
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gönderilemedi: $e')));
      }
    }
  }

  Future<void> _saveDraft() async {
    final to = _toController.text.trim();
    final hasAny =
        to.isNotEmpty ||
        _subjectController.text.trim().isNotEmpty ||
        _bodyController.text.trim().isNotEmpty ||
        _attachments.isNotEmpty;
    if (!hasAny) return;
    try {
      await _repo.saveDraft(
        from: _fromAccount,
        to: _splitAddresses(_toController),
        cc: _splitAddresses(_ccController),
        bcc: _splitAddresses(_bccController),
        subject: _subjectController.text.trim(),
        body: _bodyController.text,
        attachments: List.unmodifiable(_attachments),
        threadId: widget.initialThreadId,
        inReplyToId: widget.inReplyToId,
        // Editing a draft updates it in place — never a duplicate.
        draftId: widget.editingDraftId,
      );
    } catch (_) {
      // Silently fail — mock never throws.
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
    final picked = await (widget.pickAttachments ?? _osPickAttachments)();
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() => _attachments.addAll(picked));
  }

  void _removeAttachment(Attachment attachment) {
    setState(() => _attachments.remove(attachment));
  }

  Future<void> _simulateVoice() async {
    setState(() => _recording = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() => _recording = false);

    final insertion = _bodyController.text.isEmpty ? '' : '\n';
    final text =
        '${insertion}Bu, simüle edilmiş bir sesli diktedir. '
        'Gerçek uygulama cihaz mikrofonunu kullanacaktır.';
    _bodyController.text += text;
    _bodyController.selection = TextSelection.fromPosition(
      TextPosition(offset: _bodyController.text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasContent,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          final nav = Navigator.of(context);
          final shouldPop = await _onWillPop();
          if (shouldPop && mounted) nav.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(LucideIcons.x),
            tooltip: 'Kapat',
            onPressed: () async {
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
                      _fieldRow(
                        label: 'Kime',
                        controller: _toController,
                        focusNode: _toFocus,
                        fieldKey: const Key('to-field'),
                      ),
                      if (_ccExpanded)
                        _fieldRow(
                          label: 'Cc',
                          controller: _ccController,
                          fieldKey: const Key('cc-field'),
                        ),
                      if (_bccExpanded)
                        _fieldRow(
                          label: 'Bcc',
                          controller: _bccController,
                          fieldKey: const Key('bcc-field'),
                        ),
                      // Compact overflow: hidden Cc/Bcc are revealed through
                      // this menu. Entered values live in the controllers, so
                      // revealing a field never erases its content.
                      if (!_ccExpanded || !_bccExpanded)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: PopupMenuButton<String>(
                              key: const Key('cc-bcc-menu'),
                              tooltip: 'Cc / Bcc ekle',
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
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: Text(
                                  '+ Cc / Bcc',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.secondaryText,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      const Divider(indent: 0, endIndent: 0),
                      _fieldRow(
                        label: 'Konu',
                        controller: _subjectController,
                        fieldKey: const Key('subject-field'),
                      ),
                      const Divider(indent: 0, endIndent: 0, height: 1),
                      if (_attachments.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        for (final attachment in _attachments)
                          _AttachmentRow(
                            attachment: attachment,
                            onRemove: () => _removeAttachment(attachment),
                          ),
                      ],
                      const SizedBox(height: 8),
                      TextField(
                        controller: _bodyController,
                        focusNode: _bodyFocus,
                        maxLines: null,
                        textAlignVertical: TextAlignVertical.top,
                        decoration: _flatBodyDecoration,
                        style: const TextStyle(
                          fontSize: 15,
                          color: AppTheme.bodyText,
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

  static const _labelStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppTheme.secondaryText,
  );

  Widget _fieldRow({
    required String label,
    required TextEditingController controller,
    FocusNode? focusNode,
    Key? fieldKey,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: _labelWidth,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: _labelStyle,
          ),
        ),
        Expanded(
          child: TextField(
            key: fieldKey,
            controller: controller,
            focusNode: focusNode,
            textInputAction: TextInputAction.next,
            decoration: _flatFieldDecoration,
            style: const TextStyle(fontSize: 15, color: Colors.black),
          ),
        ),
      ],
    );
  }

  Widget _fromRow() {
    final accounts = _repo.accounts;
    final selected =
        _fromAccount ?? (accounts.isNotEmpty ? accounts.first.email : '');
    return InkWell(
      key: const Key('from-field'),
      onTap: accounts.length < 2 ? null : _pickFromAccount,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(
              width: _labelWidth,
              child: Text(
                'Kimden',
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: _labelStyle,
              ),
            ),
            Expanded(
              child: Text(
                selected,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, color: Colors.black),
              ),
            ),
            if (accounts.length > 1)
              const Icon(
                LucideIcons.chevronDown,
                size: 18,
                color: AppTheme.secondaryText,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFromAccount() async {
    final accounts = _repo.accounts;
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Kimden',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            for (final account in accounts)
              ListTile(
                key: ValueKey('from-${account.email}'),
                leading: Icon(
                  account.email == _fromAccount
                      ? LucideIcons.circleCheckBig
                      : LucideIcons.circle,
                  size: 20,
                  color: account.email == _fromAccount
                      ? Colors.black
                      : AppTheme.tertiaryText,
                ),
                title: Text(
                  account.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15),
                ),
                subtitle: account.displayName == null
                    ? null
                    : Text(
                        account.displayName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                onTap: () => Navigator.of(ctx).pop(account.email),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _fromAccount = picked);
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            key: const Key('attach-button'),
            onPressed: _attach,
            icon: const Icon(LucideIcons.paperclip, size: 22),
            tooltip: 'Dosya ekle',
          ),
          IconButton(
            onPressed: _recording ? null : _simulateVoice,
            icon: _recording
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.red,
                    ),
                  )
                : const Icon(LucideIcons.mic, size: 22),
            tooltip: _recording ? 'Dinleniyor…' : 'Sesle yaz (simülasyon)',
          ),
          if (_recording)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Text(
                'Dinleniyor…',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.red,
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

class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({required this.attachment, required this.onRemove});

  final Attachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(10),
        color: const Color(0xFFF9FAFB),
      ),
      child: Row(
        children: [
          const Icon(
            LucideIcons.fileText,
            size: 20,
            color: AppTheme.secondaryText,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              attachment.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, color: Colors.black),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            attachment.sizeLabel,
            style: const TextStyle(fontSize: 13, color: AppTheme.secondaryText),
          ),
          IconButton(
            key: ValueKey('attach-remove-${attachment.name}'),
            onPressed: onRemove,
            tooltip: '${attachment.name} kaldır',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: const Icon(LucideIcons.x, color: AppTheme.secondaryText),
          ),
        ],
      ),
    );
  }
}
