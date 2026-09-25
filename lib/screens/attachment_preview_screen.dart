import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';

import '../config/app_config.dart';
import '../models/email.dart';
import '../models/attachment_download_state.dart';
import '../services/api_exception.dart';
import '../theme/app_theme.dart';
import '../utils/attachment_preview.dart';

/// In-app preview of one attachment: images (pinch-zoom), PDFs, .docx text and
/// plain text. Any other type shows a fallback with the share sheet, which is
/// also available from the app bar for every type.
class AttachmentPreviewScreen extends StatefulWidget {
  const AttachmentPreviewScreen({
    super.key,
    required this.mailId,
    required this.attachment,
  });

  final String mailId;
  final Attachment attachment;

  @override
  State<AttachmentPreviewScreen> createState() =>
      _AttachmentPreviewScreenState();
}

class _AttachmentPreviewScreenState extends State<AttachmentPreviewScreen> {
  File? _file;
  Uint8List? _bytes;
  String? _error;
  ValueListenable<AttachmentDownloadState>? _stateListenable;
  Attachment get _attachment => widget.attachment;
  AttachmentKind get _kind => attachmentKindOf(_attachment);

  @override
  void initState() {
    super.initState();
    try {
      _stateListenable = AppConfig.mailRepository.attachmentDownloadState(
        widget.mailId,
        widget.attachment,
      );
    } on UnimplementedError {
      _stateListenable = null;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _bytes = null;
      _file = null;
    });
    try {
      if (_attachment.id != null) {
        final file = await AppConfig.mailRepository.ensureAttachmentFile(
          widget.mailId,
          _attachment,
        );
        final bytes = await file.readAsBytes();
        if (!mounted) return;
        if (bytes.isEmpty) return setState(() => _error = 'Ek indirilemedi.');
        setState(() {
          _file = file;
          _bytes = bytes;
        });
      } else {
        final bytes = await AppConfig.mailRepository.downloadAttachment(
          widget.mailId,
          _attachment,
        );
        if (!mounted) return;
        if (bytes.isEmpty) return setState(() => _error = 'Ek indirilemedi.');
        setState(() => _bytes = bytes);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _error = e.status == 404 ? 'Ek bulunamadı.' : e.userMessage,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        final state = _downloadState;
        _error = state is AttachmentFailed
            ? state.message
            : state is AttachmentCancelled
            ? 'İndirme iptal edildi.'
            : 'Ek indirilemedi.';
      });
    }
  }

  AttachmentDownloadState get _downloadState {
    if (_attachment.id == null) return const AttachmentIdle();
    try {
      return AppConfig.mailRepository
          .attachmentDownloadState(widget.mailId, _attachment)
          .value;
    } on UnimplementedError {
      return const AttachmentIdle();
    }
  }

  Future<void> _cancel() => AppConfig.mailRepository.cancelAttachmentDownload(
    widget.mailId,
    _attachment,
  );

  Future<void> _share() {
    final file = _file;
    return SharePlus.instance.share(
      ShareParams(
        files: [
          if (file != null)
            XFile(file.path, mimeType: _attachment.mimeType)
          else
            XFile.fromData(
              _bytes!,
              name: _attachment.name,
              mimeType: _attachment.mimeType,
            ),
        ],
        text: _attachment.name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_attachment.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Paylaş',
            icon: const Icon(LucideIcons.share),
            onPressed: _bytes == null ? null : _share,
          ),
        ],
      ),
      body: _stateListenable == null
          ? _buildBody()
          : ValueListenableBuilder<AttachmentDownloadState>(
              valueListenable: _stateListenable!,
              builder: (context, state, _) => _buildBody(state),
            ),
    );
  }

  Widget _buildBody([AttachmentDownloadState? state]) {
    final bytes = _bytes;
    if (_error != null) {
      return _Message(
        icon: LucideIcons.cloudOff,
        text: _error!,
        actionLabel: 'Tekrar dene',
        onAction: _load,
      );
    }
    state ??= _downloadState;
    if (bytes == null && state is AttachmentDownloading) {
      final progress = state.progress;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 12),
              Text(
                progress == null
                    ? 'İndiriliyor…'
                    : '%${(progress * 100).round()}',
              ),
              TextButton.icon(
                onPressed: _cancel,
                icon: const Icon(LucideIcons.x),
                label: const Text('İptal'),
              ),
            ],
          ),
        ),
      );
    }
    if (bytes == null && state is AttachmentCancelled) {
      return _Message(
        icon: LucideIcons.cloudOff,
        text: 'İndirme iptal edildi.',
        actionLabel: 'Tekrar dene',
        onAction: _load,
      );
    }
    if (bytes == null) return const Center(child: CircularProgressIndicator());
    switch (_kind) {
      case AttachmentKind.image:
        return InteractiveViewer(
          maxScale: 5,
          child: Center(
            child: Image.memory(
              bytes,
              errorBuilder: (_, _, _) => _cannotOpen(),
            ),
          ),
        );
      case AttachmentKind.pdf:
        return PdfViewer.data(bytes, sourceName: _attachment.name);
      case AttachmentKind.docx:
        try {
          return _TextBody(docxToText(bytes));
        } on FormatException {
          return _cannotOpen();
        }
      case AttachmentKind.text:
        return _TextBody(utf8.decode(bytes, allowMalformed: true));
      case AttachmentKind.other:
        return _cannotOpen(unsupported: true);
    }
  }

  Widget _cannotOpen({bool unsupported = false}) => _Message(
    icon: LucideIcons.fileQuestionMark,
    text: unsupported
        ? 'Bu dosya türü uygulama içinde açılamıyor.'
        : 'Dosya önizlenemedi.',
    actionLabel: 'Başka uygulamada aç',
    onAction: _share,
  );
}

class _TextBody extends StatelessWidget {
  const _TextBody(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        text.isEmpty ? '(Boş belge)' : text,
        style: TextStyle(
          fontSize: 15,
          height: 1.6,
          color: AppTheme.colors(context).bodyText,
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppTheme.colors(context).secondaryText),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
