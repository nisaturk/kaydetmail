import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../../config/app_config.dart';
import '../../models/email.dart';
import '../../theme/app_theme.dart';
import '../../utils/conversation_text.dart';
import '../../utils/date_format.dart';
import 'message_parts.dart';
import '../../utils/error_messages.dart';
import '../../widgets/mail_link_handler.dart';
import '../../l10n/l10n.dart';

class MessageBody extends StatefulWidget {
  const MessageBody({super.key, required this.email, this.history = const []});

  final Email email;
  final List<Email> history;

  @override
  State<MessageBody> createState() => _MessageBodyState();
}

final _bodyCache = Expando<ConversationBody>('conversation-body');

ConversationBody _sections(Email email) =>
    _bodyCache[email] ??= email.bodyHtml?.trim().isNotEmpty == true
    ? ConversationBody.html(email.bodyHtml!)
    : ConversationBody.text(email.bodyText);

class _MessageBodyState extends State<MessageBody> {
  bool _showQuoted = false;
  bool _showSignature = false;

  @override
  void didUpdateWidget(MessageBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.email.id != widget.email.id) {
      _showQuoted = false;
      _showSignature = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.email;
    final history = widget.history;
    final sections = _sections(email);
    final hasQuoted = sections.hasQuotes || history.isNotEmpty;
    final hasSignature =
        sections.hasSignatures ||
        history.any((message) => _sections(message).hasSignatures);
    final orderedHistory = _showQuoted
        ? (List<Email>.of(history)
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp)))
        : const <Email>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _renderBody(context, email, history, earlier: history),
        if (hasQuoted || hasSignature)
          Wrap(
            spacing: 4,
            children: [
              if (hasQuoted)
                TextButton(
                  key: Key('toggle-quoted-${email.id}'),
                  onPressed: () => setState(() => _showQuoted = !_showQuoted),
                  child: Text(
                    _showQuoted ? l10nNow.hideQuote : l10nNow.showQuote,
                  ),
                ),
              if (hasSignature)
                TextButton(
                  key: Key('toggle-signature-${email.id}'),
                  onPressed: () =>
                      setState(() => _showSignature = !_showSignature),
                  child: Text(
                    _showSignature
                        ? l10nNow.hideSignature
                        : l10nNow.showSignature,
                  ),
                ),
            ],
          ),
        if (_showQuoted && history.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              l10nNow.earlierMessages,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.colors(context).secondaryText,
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              // Use subtle 1 px steps, bounded for very long threads.
              final indentStep =
                  (constraints.maxWidth * 0.25 / orderedHistory.length).clamp(
                    0.0,
                    1.0,
                  );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < orderedHistory.length; index++)
                    _historyMessage(
                      context,
                      orderedHistory[index],
                      history,
                      indent: 8 + indentStep * (index + 1),
                      depth: index + 1,
                    ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _historyMessage(
    BuildContext context,
    Email message,
    List<Email> history, {
    required double indent,
    required int depth,
  }) {
    final colors = AppTheme.colors(context);
    final accent = _historyAccent(message.id, Theme.of(context).brightness);
    final content = Container(
      key: Key('message-history-${message.id}'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: accent, width: 3)),
        color: accent.withValues(alpha: 0.045),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.senderName.trim().isEmpty
                ? message.senderEmail
                : '${message.senderName} <${message.senderEmail}>',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.bodyText,
            ),
          ),
          Text(
            formatMailDateFull(message.timestamp),
            style: TextStyle(fontSize: 11, color: colors.secondaryText),
          ),
          const SizedBox(height: 6),
          if (message.remoteImageHosts.isNotEmpty &&
              !message.remoteImagesAllowed)
            RemoteContentBanner(email: message),
          _renderBody(
            context,
            message,
            history.where((mail) => mail.id != message.id),
            earlier: history.where(
              (mail) => mail.timestamp.isBefore(message.timestamp),
            ),
          ),
          if (message.attachments.isNotEmpty) ...[
            const SizedBox(height: 8),
            AttachmentList(email: message),
          ],
        ],
      ),
    );
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: _HistoryTextScaler(
            MediaQuery.textScalerOf(context),
            1 - 0.2 * depth / (depth + 4),
          ),
        ),
        child: content,
      ),
    );
  }

  Widget _renderBody(
    BuildContext context,
    Email email,
    Iterable<Email> represented, {
    required Iterable<Email> earlier,
  }) {
    final style = TextStyle(
      fontSize: 15,
      height: 1.6,
      color: AppTheme.colors(context).bodyText,
    );
    final body = _sections(email).render(
      showQuotes: _showQuoted,
      showSignatures: _showSignature,
      representedBodies: represented.map(
        (mail) => _sections(mail).unquotedText,
      ),
      earlier: earlier.map(_sections),
    );
    return SizedBox(
      key: Key('message-body-${email.id}'),
      width: double.infinity,
      child: email.bodyHtml?.trim().isNotEmpty != true
          ? SelectableText(body, style: style)
          : SelectionArea(
              child: HtmlWidget(
                body,
                textStyle: style,
                factoryBuilder: () => MailLinkWidgetFactory(
                  onLinkTap: (href, text) => unawaited(
                    MailLinkOpener.open(context, href, displayText: text),
                  ),
                ),
                customStylesBuilder: (element) {
                  if (element.localName == 'img' ||
                      element.localName == 'table') {
                    return {'max-width': '100%'};
                  }
                  return null;
                },
                customWidgetBuilder: (element) {
                  if (element.localName != 'img') return null;
                  final src = element.attributes['src'] ?? '';
                  if (src.startsWith('data:')) return null;
                  // Loading remote content never permits clear-text receipts.
                  if (email.remoteImagesAllowed && src.startsWith('https://')) {
                    return null;
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
    );
  }
}

/// Preserve the user's nonlinear accessibility scaling for older messages.
class _HistoryTextScaler extends TextScaler {
  const _HistoryTextScaler(this.parent, this.factor);

  final TextScaler parent;
  final double factor;

  @override
  double scale(double fontSize) => parent.scale(fontSize) * factor;

  @override
  double get textScaleFactor => scale(14) / 14;
}

Color _historyAccent(String id, Brightness brightness) {
  var hash = 2166136261;
  for (final code in id.codeUnits) {
    hash = ((hash ^ code) * 16777619) & 0xffffffff;
  }
  return HSLColor.fromAHSL(
    1,
    (hash % 360).toDouble(),
    0.62,
    brightness == Brightness.dark ? 0.68 : 0.38,
  ).toColor();
}

class RemoteContentBanner extends StatefulWidget {
  const RemoteContentBanner({super.key, required this.email});

  final Email email;

  @override
  State<RemoteContentBanner> createState() => _RemoteContentBannerState();
}

class _RemoteContentBannerState extends State<RemoteContentBanner> {
  bool _loading = false;
  Object? _error;

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AppConfig.mailRepository.loadRemoteImages(widget.email.id);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Container(
      key: Key('remote-content-${widget.email.id}'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10nNow.remoteImagesWereBlockedIn),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(
              friendlyErrorMessage(_error!),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            children: [
              TextButton(
                key: Key('load-remote-content-${widget.email.id}'),
                onPressed: _loading ? null : () => _load(),
                child: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _error == null ? l10nNow.loadImages : l10nNow.tryAgain,
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
