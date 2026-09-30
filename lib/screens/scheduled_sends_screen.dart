import 'dart:async';

import '../utils/insets.dart';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:file_picker/file_picker.dart';

import '../config/app_config.dart';
import '../models/email.dart';
import '../models/scheduled_send.dart';
import '../models/scheduled_send_detail.dart';
import '../repositories/mail_repository.dart';
import '../theme/app_theme.dart';
import '../utils/attachment_mime.dart';
import '../utils/html_to_text.dart';
import '../utils/error_messages.dart';
import '../utils/markdown_lite_to_html.dart';
import '../l10n/l10n.dart';

/// Lists every mail queued via Compose's "Zamanla" (send later): pending
/// ones can be cancelled here, past ones show their outcome. The backend
/// owns the actual send — this screen only reads/cancels
/// `GET`/`DELETE /api/scheduled-sends`.
class ScheduledSendsScreen extends StatefulWidget {
  const ScheduledSendsScreen({super.key});

  @override
  State<ScheduledSendsScreen> createState() => _ScheduledSendsScreenState();
}

class _ScheduledSendsScreenState extends State<ScheduledSendsScreen>
    with WidgetsBindingObserver {
  MailRepository get _repo => AppConfig.mailRepository;

  bool _loading = true;
  Object? _error;
  Timer? _refreshTimer;
  bool _refreshing = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_foreground) unawaited(_load(showLoading: false));
    });
    _load();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(_load(showLoading: false));
  }

  Future<void> _load({bool showLoading = true}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      await _repo.refreshScheduledSends();
      _error = null;
    } catch (e) {
      if (showLoading) _error = e;
    } finally {
      _refreshing = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(ScheduledSend item) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _ScheduledEditSheet(item: item)),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(l10nNow.scheduledSends)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListenableBuilder(
          listenable: _repo,
          builder: (context, _) {
            if (_loading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (_error != null) {
              return _ErrorState(error: _error!, onRetry: _load);
            }
            final items = _repo.getScheduledSends();
            if (items.isEmpty) {
              return _EmptyState(onRetry: _load);
            }
            return ListView.separated(
              padding: withBottomInset(
                context,
                const EdgeInsets.symmetric(vertical: 8),
              ),
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) =>
                  _ScheduledRow(item: items[i], onOpen: () => _open(items[i])),
            );
          },
        ),
      ),
    );
  }
}

class _ScheduledRow extends StatelessWidget {
  const _ScheduledRow({required this.item, required this.onOpen});

  final ScheduledSend item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final status = switch (item.status) {
      ScheduledSendStatus.pending => (
        label: l10nNow.scheduled,
        color: Theme.of(context).colorScheme.primary,
        icon: LucideIcons.clock,
      ),
      ScheduledSendStatus.sent => (
        label: l10nNow.sent2,
        color: colors.secondaryText,
        icon: LucideIcons.check,
      ),
      ScheduledSendStatus.cancelled => (
        label: l10nNow.cancelled,
        color: colors.secondaryText,
        icon: LucideIcons.x,
      ),
      ScheduledSendStatus.failed => (
        label: item.failureReason ?? l10nNow.couldntSend,
        color: colors.destructive,
        icon: LucideIcons.triangleAlert,
      ),
      ScheduledSendStatus.deliveryUnknown => (
        label: l10nNow.resultUnknownCheckSent,
        color: colors.destructive,
        icon: LucideIcons.circleHelp,
      ),
    };
    final tappable =
        item.status == ScheduledSendStatus.pending ||
        item.status == ScheduledSendStatus.failed;
    return ListTile(
      leading: Icon(status.icon, color: status.color, size: 22),
      title: Text(
        item.subject.isEmpty ? l10nNow.noSubject3 : item.subject,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            item.to.join(', '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            '${status.label} · ${_formatDateTime(item.sendAt)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: status.color),
          ),
        ],
      ),
      trailing: tappable
          ? Icon(
              LucideIcons.chevronRight,
              size: 20,
              color: colors.secondaryText,
            )
          : null,
      onTap: tappable ? onOpen : null,
    );
  }
}

class _ScheduledEditSheet extends StatefulWidget {
  const _ScheduledEditSheet({required this.item});

  final ScheduledSend item;

  @override
  State<_ScheduledEditSheet> createState() => _ScheduledEditSheetState();
}

class _ScheduledEditSheetState extends State<_ScheduledEditSheet> {
  MailRepository get _repo => AppConfig.mailRepository;

  bool get _failed => widget.item.status == ScheduledSendStatus.failed;

  bool _loading = true;
  Object? _error;
  ScheduledSendDetail? _detail;

  late final TextEditingController _toController;
  late final TextEditingController _ccController;
  late final TextEditingController _bccController;
  late final TextEditingController _subjectController;
  late final TextEditingController _bodyController;
  late DateTime _sendAt;
  final Set<String> _removedAttachmentIds = {};
  final List<Attachment> _newAttachments = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _toController = TextEditingController(text: widget.item.to.join(', '));
    _ccController = TextEditingController(text: widget.item.cc.join(', '));
    _bccController = TextEditingController(text: widget.item.bcc.join(', '));
    _subjectController = TextEditingController(text: widget.item.subject);
    _bodyController = TextEditingController();
    _sendAt = widget.item.sendAt;
    _load();
  }

  @override
  void dispose() {
    _toController.dispose();
    _ccController.dispose();
    _bccController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await _repo.getScheduledSend(widget.item.id);
      if (!mounted) return;
      _detail = detail;
      final plain =
          detail.bodyText ??
          (detail.bodyHtml == null
              ? null
              : htmlToPlainText(detail.bodyHtml!)) ??
          '';
      _bodyController.text = plain;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  List<String> _parse(String raw) => [
    for (final part in raw.split(RegExp(r'[,;\n]')))
      if (part.trim().isNotEmpty) part.trim(),
  ];

  List<Attachment> get _keptAttachments => [
    for (final info
        in (_detail?.attachments ?? const <ScheduledSendAttachmentInfo>[]))
      if (!_removedAttachmentIds.contains(info.id))
        Attachment(
          id: info.id,
          name: info.name,
          sizeBytes: info.sizeBytes,
          mimeType: info.mimeType,
        ),
  ];

  Future<void> _pickSendAt() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _sendAt.isAfter(now) ? _sendAt : now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_sendAt),
    );
    if (time == null || !mounted) return;
    setState(() {
      _sendAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _pickAttachments() async {
    final files = await FilePicker.pickFiles(type: FileType.any);
    if (files.isEmpty || !mounted) return;
    final attachments = <Attachment>[];
    for (final file in files) {
      if (file.name.isEmpty) continue;
      final bytes = await file.readAsBytes();
      attachments.add(
        Attachment(
          name: file.name,
          sizeBytes: bytes.length,
          mimeType: attachmentContentType(file.name, null),
          bytes: bytes,
        ),
      );
    }
    if (!mounted) return;
    setState(() => _newAttachments.addAll(attachments));
  }

  Future<void> _confirmCancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10nNow.cancelScheduledSend),
        content: Text(
          l10nNow.cancelTheSendOf(
            widget.item.subject.isEmpty
                ? l10nNow.noSubject3
                : widget.item.subject,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10nNow.cancel2),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10nNow.cancelSend),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _repo.cancelScheduledSend(widget.item.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10nNow.sendCancelled)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
    }
  }

  Future<void> _savePending() async {
    final to = _parse(_toController.text);
    if (to.isEmpty || !_sendAt.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10nNow.chooseAtLeastOneRecipient)),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _repo.updateScheduledSend(
        id: widget.item.id,
        to: to,
        cc: _parse(_ccController.text),
        bcc: _parse(_bccController.text),
        subject: _subjectController.text.trim(),
        body: _bodyController.text,
        bodyHtml: _bodyHtmlFor(_bodyController.text),
        sendAt: _sendAt,
        keepAttachmentIds: [
          for (final kept in _keptAttachments)
            if (kept.id != null) kept.id!,
        ],
        attachments: List.unmodifiable(_newAttachments),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10nNow.scheduledSendUpdated)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
    }
  }

  Future<void> _retryFailed() async {
    final to = _parse(_toController.text);
    if (to.isEmpty || !_sendAt.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10nNow.chooseAtLeastOneRecipient)),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _repo.rescheduleFailedSend(
        id: widget.item.id,
        to: to,
        cc: _parse(_ccController.text),
        bcc: _parse(_bccController.text),
        subject: _subjectController.text.trim(),
        body: _bodyController.text,
        bodyHtml: _bodyHtmlFor(_bodyController.text),
        attachmentIds: [
          for (final kept in _keptAttachments)
            if (kept.id != null) kept.id!,
        ],
        sendAt: _sendAt,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10nNow.sendReQueued)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
    }
  }

  String? _bodyHtmlFor(String body) =>
      hasMarkdownLiteMarkup(body) ? markdownLiteToHtml(body) : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_failed ? l10nNow.failedSend : l10nNow.editScheduledSend),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorState(error: _error!, onRetry: _load)
          : ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                if (_failed && widget.item.failureReason != null) ...[
                  Card(
                    child: ListTile(
                      leading: Icon(
                        LucideIcons.triangleAlert,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      title: Text(l10nNow.sendFailed),
                      subtitle: Text(widget.item.failureReason!),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                _FormHeading(l10nNow.recipients),
                const SizedBox(height: 8),
                TextField(
                  controller: _toController,
                  decoration: InputDecoration(
                    labelText: l10nNow.to,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _ccController,
                  decoration: const InputDecoration(
                    labelText: 'Cc',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bccController,
                  decoration: const InputDecoration(
                    labelText: 'Bcc',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                _FormHeading(l10nNow.content),
                const SizedBox(height: 8),
                TextField(
                  controller: _subjectController,
                  decoration: InputDecoration(
                    labelText: l10nNow.subject,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bodyController,
                  maxLines: 8,
                  decoration: InputDecoration(
                    labelText: l10nNow.body,
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(LucideIcons.calendarClock),
                    title: Text(l10nNow.sendTime),
                    subtitle: Text(_formatDateTime(_sendAt)),
                    trailing: TextButton(
                      onPressed: _saving ? null : _pickSendAt,
                      child: Text(l10nNow.replace),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _FormHeading(l10nNow.attachments),
                for (final kept in _keptAttachments)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(LucideIcons.paperclip, size: 18),
                    title: Text(kept.name),
                    trailing: IconButton(
                      icon: const Icon(LucideIcons.x, size: 18),
                      onPressed: _saving
                          ? null
                          : () => setState(
                              () => _removedAttachmentIds.add(kept.id!),
                            ),
                    ),
                  ),
                for (final added in _newAttachments)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(LucideIcons.paperclip, size: 18),
                    title: Text(added.name),
                    trailing: IconButton(
                      icon: const Icon(LucideIcons.x, size: 18),
                      onPressed: _saving
                          ? null
                          : () => setState(() => _newAttachments.remove(added)),
                    ),
                  ),
                if (!_failed)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _saving ? null : _pickAttachments,
                      icon: const Icon(LucideIcons.plus, size: 18),
                      label: Text(l10nNow.addAttachment),
                    ),
                  ),
                const SizedBox(height: 12),
                if (_failed)
                  FilledButton.icon(
                    onPressed: _saving ? null : _retryFailed,
                    icon: const Icon(LucideIcons.refreshCw, size: 18),
                    label: Text(l10nNow.retry),
                  )
                else
                  FilledButton(
                    onPressed: _saving ? null : _savePending,
                    child: Text(l10nNow.save),
                  ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _saving ? null : _confirmCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  child: Text(l10nNow.cancelSend2),
                ),
              ],
            ),
    );
  }
}

String _formatDateTime(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(dt.day)}.${two(dt.month)}.${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
}

class _FormHeading extends StatelessWidget {
  const _FormHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: constraints.maxHeight,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.calendarClock,
                      size: 48,
                      color: colors.secondaryText,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10nNow.noScheduledSends,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10nNow.scheduleASendWithThe,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: constraints.maxHeight,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      friendlyErrorMessage(error),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.secondaryText),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(LucideIcons.refreshCw, size: 18),
                      label: Text(l10nNow.refresh),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
