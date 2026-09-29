import '../utils/insets.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/compose_prefill.dart';
import '../models/email.dart';
import '../models/mail_folder.dart';
import '../models/mail_label.dart';
import '../repositories/mail_repository.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../utils/error_messages.dart';
import '../utils/mail_pdf_export.dart';
import '../utils/mail_threads.dart';
import '../utils/mail_unsubscribe.dart';
import '../widgets/move_folder_sheet.dart';
import '../widgets/label_picker_sheet.dart';
import '../widgets/mail_avatar.dart';
import '../widgets/mail_authentication_row.dart';
import '../widgets/permanent_delete_dialog.dart';
import '../widgets/snooze_picker.dart';
import 'compose_screen.dart';
import 'mail_inspection_screen.dart';
import 'mail_detail/message_body.dart';
import 'mail_detail/quick_reply.dart';
import 'mail_detail/message_parts.dart';
part 'mail_detail_state/reply.dart';
part 'mail_detail_state/thread_load.dart';
part 'mail_detail_state/mail_actions.dart';
part 'mail_detail_state/menu.dart';
part 'mail_detail_state/base_state.dart';

/// Full view of the opened mail followed by older messages in its conversation.
/// Opening marks the selected mail as read; enrichment appends older history
/// without moving the reader's scroll position.
class MailDetailScreen extends StatefulWidget {
  const MailDetailScreen({
    super.key,
    required this.emailId,
    this.seed,
    this.openReplyOnLoad = false,
    this.currentCustomFolderId,
    this.showAppBar = true,
  });

  final String emailId;

  /// Mail list snapshot shown synchronously while full detail revalidates.
  final Email? seed;
  final bool openReplyOnLoad;

  final String? currentCustomFolderId;

  /// Wide mailbox layouts provide their own app bar.
  final bool showAppBar;

  @override
  State<MailDetailScreen> createState() => _MailDetailScreenState();
}

class _MailDetailScreenState extends _MailDetailStateBase
    with _ReplyMixin, _ThreadLoadMixin, _MailActionsMixin, _MenuMixin {
  @override
  void initState() {
    super.initState();
    final seed = widget.seed;
    if (seed != null && seed.id == widget.emailId) {
      _email = seed;
      _thread = _mergeThread(seed, _repo.getThreadEmails(seed.threadId));
      _loading = false;
    }
    _repo.addListener(_syncCachedMail);
    _reload();
  }

  @override
  void dispose() {
    _repo.removeListener(_syncCachedMail);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.showAppBar ? AppBar(actions: _appBarActions()) : null,
      body: SafeArea(child: _buildBody()),
    );
  }

  /// Reply/Forward stay available regardless of folder, including Trash —
  /// replying to or forwarding a trashed mail is still a meaningful action,
  /// and hiding them would only cost the user a round-trip through Geri
  /// Yükle first.
  List<Widget> _appBarActions() {
    final email = _email;
    if (email == null) return const [];
    final folderAction = _folderAction(email);
    return [
      ?folderAction,
      if (email.folder != MailFolder.archive &&
          email.folder != MailFolder.trash &&
          email.folder != MailFolder.spam)
        IconButton(
          onPressed: () {
            _watchBackgroundMutation(
              _repo.moveToFolder([email.id], MailFolder.archive),
            );
            unawaited(Navigator.of(context).maybePop(true).then<void>((_) {}));
          },
          tooltip: 'Arşivle',
          icon: const Icon(LucideIcons.archive),
        ),
      if (email.folder != MailFolder.trash)
        IconButton(
          onPressed: () {
            _watchBackgroundMutation(_repo.moveToTrash([email.id]));
            unawaited(Navigator.of(context).maybePop(true).then<void>((_) {}));
          },
          tooltip: 'Sil',
          icon: const Icon(LucideIcons.trash2),
        ),
      IconButton(
        onPressed: () => _watchBackgroundMutation(
          email.isRead
              ? _repo.markAsUnread([email.id])
              : _repo.markAsRead([email.id]),
        ),
        tooltip: email.isRead
            ? 'Okunmadı olarak işaretle'
            : 'Okundu olarak işaretle',
        icon: Icon(email.isRead ? LucideIcons.mail : LucideIcons.mailOpen),
      ),
      PopupMenuButton<String>(
        icon: const Icon(LucideIcons.moreHorizontal),
        tooltip: 'Daha fazla',
        onSelected: (action) => _handleMenu(action),
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'reply_all',
            enabled: !_composeActionBusy,
            child: const Text('Tümünü Yanıtla'),
          ),
          PopupMenuItem(
            value: 'reply',
            enabled: !_composeActionBusy,
            child: const Text('Yanıtla'),
          ),
          PopupMenuItem(
            value: 'forward',
            enabled: !_composeActionBusy,
            child: const Text('İlet'),
          ),
          PopupMenuItem(
            value: 'pin',
            child: Text(email.isPinned ? 'Sabitlemeyi kaldır' : 'Sabitle'),
          ),
          PopupMenuItem(
            value: 'star',
            child: Text(email.isStarred ? 'Yıldızı kaldır' : 'Yıldızla'),
          ),
          if (email.isRead)
            const PopupMenuItem(
              value: 'unread',
              child: Text('Okunmadı olarak işaretle'),
            )
          else
            const PopupMenuItem(
              value: 'read',
              child: Text('Okundu olarak işaretle'),
            ),
          PopupMenuItem(
            value: 'snooze',
            child: Text(
              _repo.snoozedUntilOf(email.id) != null
                  ? 'Ertelemeyi kaldır'
                  : 'Ertele',
            ),
          ),
          if (email.folder != MailFolder.drafts)
            const PopupMenuItem(value: 'move', child: Text('Move to')),
          if (email.folder == MailFolder.trash)
            const PopupMenuItem(
              value: 'delete_forever',
              child: Text('Kalıcı olarak sil'),
            ),
          if (anyLabeled(_repo, _conversationIds))
            const PopupMenuItem(value: 'unlabel', child: Text('Etiketi kaldır'))
          else
            const PopupMenuItem(value: 'label', child: Text('Etiketle')),
          const PopupMenuItem(value: 'print', child: Text('Yazdır')),
          const PopupMenuItem(
            value: 'share_pdf',
            child: Text('PDF olarak paylaş'),
          ),
          if (parseUnsubscribeHeaders(email.headers)?.hasAction ?? false)
            const PopupMenuItem(
              value: 'unsubscribe',
              child: Text('Abonelikten Çık'),
            ),
          const PopupMenuItem(
            value: 'all_headers',
            child: Text('Tüm başlıkları göster'),
          ),
          const PopupMenuItem(
            value: 'raw_mime',
            child: Text('Ham MIME göster'),
          ),
        ],
      ),
    ];
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final colors = AppTheme.colors(context);
    final email = _email;
    if (email == null) {
      // The mail genuinely isn't there (null without an error), or the
      // detail request itself failed — the two get different messages and
      // only a failure offers a retry.
      final error = _loadError;
      if (error == null) {
        return Center(
          child: Text(
            'Bu e-posta artık mevcut değil.',
            style: TextStyle(fontSize: 15, color: colors.secondaryText),
          ),
        );
      }
      final message = friendlyErrorMessage(error);
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.cloudOff, size: 40, color: colors.secondaryText),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _retry,
                icon: const Icon(LucideIcons.refreshCw, size: 18),
                label: const Text('Tekrar dene'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scroll,
      padding: withBottomInset(
        context,
        const EdgeInsets.fromLTRB(16, 8, 16, 32),
      ),
      itemCount: _thread.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              email.subject,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
                height: 1.2,
              ),
            ),
          );
        }
        if (index == 2) {
          return email.folder == MailFolder.drafts
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: QuickReply(
                    email: email,
                    from: _originatingFrom(email),
                  ),
                );
        }
        final message = index == 1 ? _thread.first : _thread[index - 2];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (index > 2)
              Divider(height: 24, thickness: 0.5, color: colors.border),
            _SingleMessage(
              email: message,
              ownAddress: _originatingFrom(message),
              labels: _labelsFor(message),
              collapseQuoted: _thread.length > 1,
              onCompose: (mode, title) =>
                  _openComposePrefill(mode, title: title, target: message),
              onStar: () => _watchBackgroundMutation(
                _repo.setStarred([message.id], !message.isStarred),
              ),
            ),
          ],
        );
      },
    );
  }

  List<MailLabel> _labelsFor(Email email) =>
      _repo.getLabels().where((l) => email.labelIds.contains(l.id)).toList();
}

/// Full message, never a collapsible conversation card.
class _SingleMessage extends StatefulWidget {
  const _SingleMessage({
    required this.email,
    required this.ownAddress,
    required this.labels,
    required this.onCompose,
    required this.onStar,
    this.collapseQuoted = false,
  });

  final Email email;
  final String? ownAddress;
  final List<MailLabel> labels;
  final bool collapseQuoted;
  final Future<void> Function(String mode, String title) onCompose;
  final VoidCallback onStar;

  @override
  State<_SingleMessage> createState() => _SingleMessageState();
}

class _SingleMessageState extends State<_SingleMessage> {
  bool _detailsVisible = false;

  @override
  Widget build(BuildContext context) {
    final email = widget.email;
    final labels = widget.labels;
    final collapseQuoted = widget.collapseQuoted;
    final colors = AppTheme.colors(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            MailAvatar(
              identity: email.senderEmail,
              displayName: email.senderName,
              size: 36,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    email.senderName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: onSurface,
                    ),
                  ),
                  TextButton.icon(
                    key: Key('message-recipients-${email.id}'),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 24),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: colors.secondaryText,
                    ),
                    onPressed: () =>
                        setState(() => _detailsVisible = !_detailsVisible),
                    iconAlignment: IconAlignment.end,
                    icon: Icon(
                      _detailsVisible
                          ? LucideIcons.chevronUp
                          : LucideIcons.chevronDown,
                      size: 12,
                    ),
                    label: Text(
                      _recipientSummary(email.recipients, widget.ownAddress),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: Text(
                formatMailTime(email.timestamp),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: colors.secondaryText),
              ),
            ),
            IconButton(
              onPressed: widget.onStar,
              tooltip: email.isStarred ? 'Yıldızı kaldır' : 'Yıldızla',
              visualDensity: VisualDensity.compact,
              iconSize: 20,
              icon: Icon(
                email.isStarred ? Icons.star : Icons.star_outline,
                color: email.isStarred ? Colors.amber : null,
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'İleti işlemleri',
              iconSize: 20,
              icon: const Icon(LucideIcons.moreVertical),
              onSelected: (mode) => widget.onCompose(
                mode,
                mode == 'forward'
                    ? 'İlet'
                    : mode == 'reply-all'
                    ? 'Tümünü Yanıtla'
                    : 'Yanıtla',
              ),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'reply', child: Text('Yanıtla')),
                PopupMenuItem(
                  value: 'reply-all',
                  child: Text('Tümünü Yanıtla'),
                ),
                PopupMenuItem(value: 'forward', child: Text('İlet')),
              ],
            ),
          ],
        ),
        if (_detailsVisible)
          Padding(
            padding: const EdgeInsets.only(left: 46, top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RecipientLine(label: 'Kimden: ', addresses: email.senderEmail),
                if (email.recipients.isNotEmpty)
                  RecipientLine(
                    label: 'Alıcı: ',
                    addresses: email.recipients.join(', '),
                  ),
                if (email.cc.isNotEmpty)
                  RecipientLine(label: 'Cc: ', addresses: email.cc.join(', ')),
                if (email.bcc.isNotEmpty)
                  RecipientLine(
                    label: 'Bcc: ',
                    addresses: email.bcc.join(', '),
                  ),
                RecipientLine(
                  label: 'Tarih: ',
                  addresses: formatMailDateFull(email.timestamp),
                ),
              ],
            ),
          ),
        if (labels.isNotEmpty) ...[
          const SizedBox(height: 12),
          LabelChips(labels: labels),
        ],
        if (email.authentication case final authentication?) ...[
          const SizedBox(height: 8),
          MailAuthenticationRow(authentication: authentication),
        ],
        if (email.security case final security?) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(LucideIcons.lock, size: 20),
            title: Text(
              [
                if (security.signed case final signed?)
                  '${signed == 'SMime' ? 'S/MIME' : 'OpenPGP'} imzalı (doğrulanmadı)',
                if (security.encrypted case final encrypted?)
                  '${encrypted == 'SMime' ? 'S/MIME' : 'OpenPGP'} şifreli (açılamıyor)',
              ].join(' · '),
            ),
            onTap: security.signed == null
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => MailInspectionScreen(
                        mailId: email.id,
                        mode: MailInspectionMode.signature,
                        repository: AppConfig.mailRepository,
                      ),
                    ),
                  ),
          ),
        ],
        const SizedBox(height: 2),
        if (email.trackingPixelHosts.isNotEmpty) ...[
          Row(
            children: [
              const Icon(LucideIcons.eyeOff, size: 18),
              const SizedBox(width: 8),
              const Expanded(child: Text('Takip içeriği engellendi')),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (email.remoteImageHosts.isNotEmpty &&
            !email.remoteImagesAllowed) ...[
          RemoteContentBanner(email: email),
          const SizedBox(height: 12),
        ],
        MessageBody(email: email, collapseQuoted: collapseQuoted),
        if (email.attachments.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Ekler',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: 8),
          AttachmentList(email: email),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 2,
            runSpacing: 0,
            children: [
              TextButton.icon(
                key: Key('message-reply-${email.id}'),
                style: _actionStyle(colors),
                onPressed: () => widget.onCompose('reply', 'Yanıtla'),
                icon: const Icon(LucideIcons.reply, size: 16),
                label: const Text('Yanıtla'),
              ),
              TextButton.icon(
                key: Key('message-reply-all-${email.id}'),
                style: _actionStyle(colors),
                onPressed: () =>
                    widget.onCompose('reply-all', 'Tümünü Yanıtla'),
                icon: const Icon(LucideIcons.replyAll, size: 16),
                label: const Text('Tümünü yanıtla'),
              ),
              TextButton.icon(
                key: Key('message-forward-${email.id}'),
                style: _actionStyle(colors),
                onPressed: () => widget.onCompose('forward', 'İlet'),
                icon: const Icon(LucideIcons.forward, size: 16),
                label: const Text('İlet'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  ButtonStyle _actionStyle(AppColors colors) => TextButton.styleFrom(
    foregroundColor: colors.secondaryText,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    minimumSize: const Size(0, 40),
    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
  );

  String _recipientSummary(List<String> recipients, String? ownAddress) {
    if (recipients.isEmpty) return 'alıcı yok';
    if (ownAddress != null &&
        recipients.any((recipient) {
          final address = recipient.contains('<')
              ? recipient.split('<').last.split('>').first.trim()
              : recipient.trim();
          return address.toLowerCase() == ownAddress.toLowerCase();
        })) {
      return 'bana';
    }
    final first = recipients.first;
    final name = first.contains('<')
        ? first.substring(0, first.indexOf('<')).trim().replaceAll('"', '')
        : first.split('@').first;
    return name.isEmpty ? first : "$name'ye";
  }
}
