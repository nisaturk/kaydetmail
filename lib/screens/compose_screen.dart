import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../repositories/mail_repository.dart';
import '../theme/app_theme.dart';

/// Compose a new mail (or reply/forward — same screen).
///
/// Supports To, CC, BCC (expandable), Subject and Body. The mic button
/// appends simulated voice text. Smart-back saves a draft when content exists.
class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key});

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
      _bodyController.text.trim().isNotEmpty;

  Future<bool> _onWillPop() async {
    if (!_hasContent) return true;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Discard this mail?'),
            content: const Text('You can save it as a draft or discard.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.of(ctx).pop(false);
                  await _saveDraft();
                },
                child: const Text('Save draft'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text(
                  'Discard',
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
        const SnackBar(content: Text('At least one recipient is required.')),
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
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email sent.')),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
      }
    }
  }

  Future<void> _saveDraft() async {
    final to = _toController.text.trim();
    if (to.isEmpty && _bodyController.text.trim().isEmpty) return;
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
      );
    } catch (_) {
      // Silently fail — mock never throws.
    }
  }

  Future<void> _simulateVoice() async {
    setState(() => _recording = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() => _recording = false);

    final insertion = _bodyController.text.isEmpty ? '' : '\n';
    final text =
        '${insertion}This is a simulated voice transcription. '
        'The real implementation will use the device microphone.';
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
            tooltip: 'Close',
            onPressed: () async {
              final nav = Navigator.of(context);
              final shouldPop = await _onWillPop();
              if (shouldPop && mounted) nav.pop();
            },
          ),
          title: const Text('New mail'),
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
                tooltip: 'Send',
                onPressed: _send,
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: [
                            _fieldRow(
                              label: 'To',
                              controller: _toController,
                              focusNode: _toFocus,
                            ),
                            if (_ccExpanded)
                              _fieldRow(
                                label: 'Cc',
                                controller: _ccController,
                              ),
                            if (_bccExpanded)
                              _fieldRow(
                                label: 'Bcc',
                                controller: _bccController,
                              ),
                            if (!_ccExpanded || !_bccExpanded)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Row(
                                  children: [
                                    if (!_ccExpanded)
                                      _expandChip(
                                        label: 'Cc',
                                        onTap: () => setState(
                                            () => _ccExpanded = true),
                                      ),
                                    if (!_ccExpanded && !_bccExpanded)
                                      const SizedBox(width: 8),
                                    if (!_bccExpanded)
                                      _expandChip(
                                        label: 'Bcc',
                                        onTap: () => setState(
                                            () => _bccExpanded = true),
                                      ),
                                  ],
                                ),
                              ),
                            const Divider(indent: 0, endIndent: 0),
                            _fieldRow(
                              label: 'Subject',
                              controller: _subjectController,
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: TextField(
                          controller: _bodyController,
                          focusNode: _bodyFocus,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          decoration: const InputDecoration(
                            hintText: 'Write your mail…',
                            border: InputBorder.none,
                            filled: false,
                            hintStyle: TextStyle(
                              color: AppTheme.tertiaryText,
                            ),
                          ),
                          style: const TextStyle(
                            fontSize: 15,
                            color: Color(0xFF1F2937),
                            height: 1.55,
                          ),
                        ),
                      ),
                    ),
                  ],
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
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.secondaryText,
            ),
          ),
        ),
        Expanded(
          child: TextField(
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
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
            tooltip: _recording ? 'Listening…' : 'Voice input (simulated)',
          ),
          if (_recording)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Text(
                'Listening…',
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