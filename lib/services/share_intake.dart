import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'share_intake_io.dart'
    if (dart.library.js_interop) 'share_intake_web.dart'
    as platform;

import '../models/email.dart';
import '../screens/compose_screen.dart';

/// Opens the compose screen for content shared into the app from the OS share
/// sheet (files/images become attachments, text/links become the body).
///
/// Covers both cold start (initial media) and while running (media stream).
/// Best-effort: platforms without the plugin simply never emit. There is no
/// OS share sheet on the web, so [start] no-ops there instead of touching
/// the native-only plugin or `dart:io` (see `share_intake_web.dart`).
class ShareIntake {
  ShareIntake(this._context);

  /// Returns a context under a Navigator, or null once disposed.
  final BuildContext? Function() _context;
  StreamSubscription<List<SharedMediaFile>>? _sub;

  void start() {
    if (kIsWeb) return;
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
        final bytes = await platform.readSharedFileBytes(m.path);
        attachments.add(
          Attachment(
            name: platform.fileNameFromPath(m.path),
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
