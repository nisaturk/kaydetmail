import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../config/app_config.dart';
import '../../models/email.dart';
import '../../models/mail_label.dart';
import '../../models/attachment_download_state.dart';
import '../../services/attachment_auto_download_policy.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_messages.dart';
import '../attachment_preview_screen.dart';
import '../../l10n/l10n.dart';

class RecipientLine extends StatelessWidget {
  const RecipientLine({
    super.key,
    required this.label,
    required this.addresses,
  });

  final String label;
  final String addresses;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Text.rich(
      TextSpan(
        style: TextStyle(fontSize: 13, color: colors.secondaryText),
        children: [
          TextSpan(
            text: label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(text: addresses),
        ],
      ),
    );
  }
}

class LabelChips extends StatelessWidget {
  const LabelChips({super.key, required this.labels});

  final List<MailLabel> labels;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final label in labels)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: label.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              label.name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: label.color,
              ),
            ),
          ),
      ],
    );
  }
}

class AttachmentList extends StatefulWidget {
  const AttachmentList({super.key, required this.email});

  final Email email;

  @override
  State<AttachmentList> createState() => _AttachmentListState();
}

class _AttachmentListState extends State<AttachmentList> {
  @override
  void initState() {
    super.initState();
    _autoDownload();
  }

  @override
  void didUpdateWidget(covariant AttachmentList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.email.id != widget.email.id ||
        oldWidget.email.attachments != widget.email.attachments) {
      _autoDownload();
    }
  }

  void _autoDownload() {
    unawaited(
      AttachmentAutoDownloader().onMailOpened(
        AppConfig.mailRepository,
        widget.email,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final attachment in widget.email.attachments)
        AttachmentTile(mailId: widget.email.id, attachment: attachment),
    ],
  );
}

class AttachmentTile extends StatelessWidget {
  const AttachmentTile({
    super.key,
    required this.mailId,
    required this.attachment,
  });

  final String mailId;
  final Attachment attachment;

  Future<void> _download(BuildContext context) async {
    try {
      await AppConfig.mailRepository.ensureAttachmentFile(mailId, attachment);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final repository = AppConfig.mailRepository;
    final content = Row(
      children: [
        Icon(LucideIcons.fileText, size: 20, color: colors.secondaryText),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                attachment.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${attachment.typeLabel} · ${attachment.sizeLabel}',
                style: TextStyle(fontSize: 12, color: colors.secondaryText),
              ),
            ],
          ),
        ),
      ],
    );
    Widget tile(AttachmentDownloadState state) {
      Widget status = const SizedBox.shrink();
      Widget? action;
      if (state is AttachmentDownloading) {
        final percent = state.progress;
        status = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: percent),
            const SizedBox(height: 4),
            Text(
              percent == null
                  ? l10nNow.downloading
                  : '%${(percent * 100).round()}',
            ),
          ],
        );
        action = IconButton(
          tooltip: l10nNow.cancelDownload,
          onPressed: () =>
              repository.cancelAttachmentDownload(mailId, attachment),
          icon: const Icon(LucideIcons.x, size: 18),
        );
      } else if (state is AttachmentCompleted) {
        status = Text(l10nNow.ready);
      } else if (state is AttachmentFailed) {
        status = Text(
          state.message,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        );
        if (state.retryable) {
          action = IconButton(
            tooltip: l10nNow.tryAgain,
            onPressed: () => _download(context),
            icon: const Icon(LucideIcons.rotateCw, size: 18),
          );
        }
      } else if (state is AttachmentCancelled) {
        status = Text(l10nNow.downloadCancelled);
        action = IconButton(
          tooltip: l10nNow.tryAgain,
          onPressed: () => _download(context),
          icon: const Icon(LucideIcons.download, size: 18),
        );
      } else {
        action = IconButton(
          tooltip: l10nNow.downloadAttachment,
          onPressed: () => _download(context),
          icon: const Icon(LucideIcons.download, size: 18),
        );
      }
      return InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                AttachmentPreviewScreen(mailId: mailId, attachment: attachment),
          ),
        ),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: content),
                  ?action,
                ],
              ),
              if (state is AttachmentDownloading ||
                  state is AttachmentFailed ||
                  state is AttachmentCancelled ||
                  state is AttachmentCompleted)
                Align(alignment: Alignment.centerLeft, child: status),
            ],
          ),
        ),
      );
    }

    if (attachment.id == null) return tile(const AttachmentIdle());
    try {
      return ValueListenableBuilder<AttachmentDownloadState>(
        valueListenable: repository.attachmentDownloadState(mailId, attachment),
        builder: (context, state, _) => tile(state),
      );
    } on UnimplementedError {
      return tile(const AttachmentIdle());
    }
  }
}
