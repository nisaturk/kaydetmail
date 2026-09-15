import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/email.dart';
import '../repositories/mail_repository.dart';
import '../theme/app_theme.dart';

/// Compose a new mail (or reply/forward — same screen).
///
/// Supports To, CC, BCC (expandable), Subject, Body and local file
/// attachments. Inside a scrolled column so nothing overflows when the
/// keyboard is open or the screen is narrow. The mic button appends simulated
/// voice text. Smart-back saves a draft when content exists.
class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key, this.pickAttachments});

  /// Lets tests substitute the real OS file picker.
  final Future<List<Attachment>?> Function()? pickAttachments;

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

  final List<Attachment> _attachments = [];

  MailRepository get _repo => AppConfig.mailRepository;

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
            content: const Text('Taslak olarak kaydedebilir veya silebilirsiniz.'),
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
                child: const Text(
                  'Sil',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

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
        to: to.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        cc: _ccController.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        bcc: _bccController.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        subject: _subjectController.text.trim(),
        body: _bodyController.text,
        attachments: List.unmodifiable(_attachments),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('E-posta gönderildi.')),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gönderilemedi: $e')),
        );
      }
    }
  }

  Future<void> _saveDraft() async {
    final to = _toController.text.trim();
    final hasAny = to.isNotEmpty ||
        _subjectController.text.trim().isNotEmpty ||
        _bodyController.text.trim().isNotEmpty ||
        _attachments.isNotEmpty;
    if (!hasAny) return;
    try {
      await _repo.saveDraft(
        to: to.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        cc: _ccController.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        bcc: _bccController.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        subject: _subjectController.text.trim(),
        body: _bodyController.text,
        attachments: List.unmodifiable(_attachments),
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
          title: const Text('Yeni E-posta'),
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
                      _fieldRow(
                        label: 'Alıcı',
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
                      if (!_ccExpanded || !_bccExpanded)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!_ccExpanded)
                                _expandChip(
                                  label: 'Cc',
                                  onTap: () =>
                                      setState(() => _ccExpanded = true),
                                ),
                              if (!_ccExpanded && !_bccExpanded)
                                const SizedBox(width: 8),
                              if (!_bccExpanded)
                                _expandChip(
                                  label: 'Bcc',
                                  onTap: () =>
                                      setState(() => _bccExpanded = true),
                                ),
                            ],
                          ),
                        ),
                      const Divider(indent: 0, endIndent: 0),
                      _fieldRow(
                        label: 'Konu',
                        controller: _subjectController,
                        fieldKey: const Key('subject-field'),
                      ),
                      if (_attachments.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        for (final attachment in _attachments)
                          _AttachmentRow(
                            attachment: attachment,
                            onRemove: () => _removeAttachment(attachment),
                          ),
                      ],
                      const SizedBox(height: 4),
                      TextField(
                        controller: _bodyController,
                        focusNode: _bodyFocus,
                        minLines: 12,
                        maxLines: null,
                        textAlignVertical: TextAlignVertical.top,
                        decoration: const InputDecoration(
                          hintText: 'E-postanızı yazın…',
                          border: InputBorder.none,
                          filled: false,
                          hintStyle: TextStyle(
                            color: AppTheme.tertiaryText,
                          ),
                        ),
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

  Widget _fieldRow({
    required String label,
    required TextEditingController controller,
    FocusNode? focusNode,
    Key? fieldKey,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Natural-width label; a fixed width is what previously made
        // "Subject" wrap mid-word on narrow screens.
        Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppTheme.secondaryText,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            key: fieldKey,
            controller: controller,
            focusNode: focusNode,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              hintText: '',
              border: InputBorder.none,
              filled: false,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 12),
            ),
            style: const TextStyle(fontSize: 15, color: Colors.black),
          ),
        ),
      ],
    );
  }

  Widget _expandChip({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(
          '+ $label',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.secondaryText,
          ),
        ),
      ),
    );
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
          const Icon(LucideIcons.fileText,
              size: 20, color: AppTheme.secondaryText),
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
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.secondaryText,
            ),
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