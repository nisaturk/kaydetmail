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
    final draft = await buildShareDraft(media, platform.readSharedFileBytes);
    final ctx = _context();
    if (ctx == null || !ctx.mounted) return;
    ReceiveSharingIntent.instance.reset();
    final messenger = ScaffoldMessenger.maybeOf(ctx);
    if (draft.isEmpty) {
      if (draft.failedNames.isNotEmpty) {
        messenger?.showSnackBar(
          SnackBar(content: Text(_failureMessage(draft.failedNames))),
        );
      }
      return;
    }
    Navigator.of(ctx).push(
      MaterialPageRoute(
        builder: (_) => ComposeScreen(
          initialAttachments: draft.attachments,
          initialBody: draft.body,
        ),
      ),
    );
    if (draft.failedNames.isNotEmpty) {
      messenger?.showSnackBar(
        SnackBar(content: Text(_failureMessage(draft.failedNames))),
      );
    }
  }

  static String _failureMessage(List<String> names) =>
      'Paylaşılan ${names.length == 1 ? 'dosya' : '${names.length} dosya'} '
      'okunamadı: ${names.join(', ')}';
}

typedef ShareDraft = ({
  List<Attachment> attachments,
  String body,
  List<String> failedNames,
});

extension ShareDraftX on ShareDraft {
  bool get isEmpty => attachments.isEmpty && body.isEmpty;
}

Future<ShareDraft> buildShareDraft(
  List<SharedMediaFile> media,
  Future<Uint8List> Function(String path) readBytes,
) async {
  final attachments = <Attachment>[];
  final failedNames = <String>[];
  final lines = <String>[];
  void addLine(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty || lines.contains(trimmed)) return;
    lines.add(trimmed);
  }

  for (final m in media) {
    if (m.type == SharedMediaType.text || m.type == SharedMediaType.url) {
      addLine(m.path);
      addLine(m.message);
      continue;
    }
    addLine(m.message);
    final name = platform.fileNameFromPath(m.path);
    try {
      final bytes = await readBytes(m.path);
      attachments.add(
        Attachment(
          name: name,
          sizeBytes: bytes.length,
          mimeType: m.mimeType,
          bytes: bytes,
        ),
      );
    } catch (_) {
      failedNames.add(name);
    }
  }
  return (
    attachments: attachments,
    body: lines.join('\n'),
    failedNames: failedNames,
  );
}
