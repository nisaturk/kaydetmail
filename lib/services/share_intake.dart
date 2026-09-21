import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../models/email.dart';
import '../screens/compose_screen.dart';

/// Opens the compose screen for content shared into the app from the OS share
/// sheet (files/images become attachments, text/links become the body).
///
/// Covers both cold start (initial media) and while running (media stream).
/// Best-effort: platforms without the plugin simply never emit.
class ShareIntake {
  ShareIntake(this._context);

  /// Returns a context under a Navigator, or null once disposed.
  final BuildContext? Function() _context;
  StreamSubscription<List<SharedMediaFile>>? _sub;

  void start() {
    try {
      final rsi = ReceiveSharingIntent.instance;
      rsi.getInitialMedia().then(_handle).catchError((_) {});
      _sub = rsi.getMediaStream().listen(_handle, onError: (_) {});
    } catch (_) {}
  }

  void dispose() => _sub?.cancel();

  Future<void> _handle(List<SharedMediaFile> media) async {
    if (media.isEmpty) return;
    final attachments = <Attachment>[];
    final text = StringBuffer();
    for (final m in media) {
      if (m.type == SharedMediaType.text || m.type == SharedMediaType.url) {
        if (text.isNotEmpty) text.writeln();
        text.write(m.path);
        continue;
      }
      try {
        final bytes = await File(m.path).readAsBytes();
        attachments.add(
          Attachment(
            name: m.path.split(Platform.pathSeparator).last,
            sizeBytes: bytes.length,
            mimeType: m.mimeType,
            bytes: bytes,
          ),
        );
      } catch (_) {}
    }
    final ctx = _context();
    if (ctx == null || !ctx.mounted) return;
    ReceiveSharingIntent.instance.reset();
    if (attachments.isEmpty && text.isEmpty) return;
    Navigator.of(ctx).push(
      MaterialPageRoute(
        builder: (_) => ComposeScreen(
          initialAttachments: attachments,
          initialBody: text.toString(),
        ),
      ),
    );
  }
}
