import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../../config/app_config.dart';
import '../../models/email.dart';
import '../../theme/app_theme.dart';
import '../../utils/conversation_text.dart';
import '../../utils/error_messages.dart';
import '../../widgets/mail_link_handler.dart';

class MessageBody extends StatefulWidget {
  const MessageBody({
    super.key,
    required this.email,
    this.collapseQuoted = false,
  });

  final Email email;
  final bool collapseQuoted;

  @override
  State<MessageBody> createState() => _MessageBodyState();
}

class _MessageBodyState extends State<MessageBody> {
  bool _showQuoted = false;

  @override
  Widget build(BuildContext context) {
    final email = widget.email;
    final colors = AppTheme.colors(context);
    final style = TextStyle(fontSize: 15, height: 1.6, color: colors.bodyText);
    final html = email.bodyHtml;
    final hideQuoted = widget.collapseQuoted && !_showQuoted;
    final Widget body;
    final bool hasQuoted;
    if (html == null || html.trim().isEmpty) {
      final collapsed = collapseQuotedText(email.bodyText);
      hasQuoted = widget.collapseQuoted && collapsed.collapsed;
      body = SelectableText(
        hideQuoted ? collapsed.visible : email.bodyText,
        style: style,
      );
    } else {
      hasQuoted = widget.collapseQuoted && htmlHasQuotedContent(html);
      body = SelectionArea(
        child: HtmlWidget(
          html,
          textStyle: style,
          factoryBuilder: () => MailLinkWidgetFactory(
            onLinkTap: (href, text) => unawaited(
              MailLinkOpener.open(context, href, displayText: text),
            ),
          ),
          customStylesBuilder: (element) {
            if (element.localName == 'img' || element.localName == 'table') {
              return {'max-width': '100%'};
            }
            return null;
          },
          customWidgetBuilder: (element) {
            if (hideQuoted &&
                isQuotedHtmlElement(
                  element.localName,
                  element.classes,
                  element.id,
                )) {
              return const SizedBox.shrink();
            }
            if (element.localName != 'img') return null;
            final src = element.attributes['src'] ?? '';
            if (src.startsWith('data:')) return null;
            // Plain-http images would leak the read receipt (and the
            // reader's network position) in clear text even after the user
            // opted in to remote content, so only https is ever fetched.
            if (email.remoteImagesAllowed && src.startsWith('https://')) {
              return null;
            }
            return const SizedBox.shrink();
          },
        ),
      );
    }
    final fullWidthBody = SizedBox(
      key: Key('message-body-${email.id}'),
      width: double.infinity,
      child: body,
    );
    if (!hasQuoted) return fullWidthBody;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fullWidthBody,
        TextButton(
          key: Key('toggle-quoted-${email.id}'),
          onPressed: () => setState(() => _showQuoted = !_showQuoted),
          child: Text(
            _showQuoted ? 'Alıntıyı gizle' : 'Alıntı ve imzayı göster',
          ),
        ),
      ],
    );
  }
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
          const Text(
            'Bu mesajda uzak görseller güvenlik nedeniyle durduruldu.',
          ),
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
                    : Text(_error == null ? 'Görselleri yükle' : 'Tekrar dene'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
