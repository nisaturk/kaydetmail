import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/services/share_intake.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

void main() {
  Future<Uint8List> read(String path) async {
    if (path.contains('broken')) throw StateError('unreadable');
    return Uint8List.fromList([1, 2, 3]);
  }

  test(
    'keeps every file, text, url and caption; reports unreadable files',
    () async {
      final draft = await buildShareDraft([
        SharedMediaFile(
          path: '/tmp/photo.jpg',
          type: SharedMediaType.image,
          mimeType: 'image/jpeg',
          message: 'Toplantı fotoğrafı',
        ),
        SharedMediaFile(path: '/tmp/report.pdf', type: SharedMediaType.file),
        SharedMediaFile(path: '/tmp/broken.bin', type: SharedMediaType.file),
        SharedMediaFile(path: 'https://ornek.com/a', type: SharedMediaType.url),
        SharedMediaFile(path: 'Seçili metin', type: SharedMediaType.text),
      ], read);

      expect(draft.attachments.map((a) => a.name), ['photo.jpg', 'report.pdf']);
      expect(draft.attachments.first.mimeType, 'image/jpeg');
      expect(draft.failedNames, ['broken.bin']);
      expect(
        draft.body,
        'Toplantı fotoğrafı\nhttps://ornek.com/a\nSeçili metin',
      );
    },
  );

  test(
    'a share where every file fails is empty but still reports them',
    () async {
      final draft = await buildShareDraft([
        SharedMediaFile(path: '/tmp/broken.bin', type: SharedMediaType.file),
      ], read);
      expect(draft.isEmpty, isTrue);
      expect(draft.failedNames, ['broken.bin']);
    },
  );
}
