import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/utils/attachment_mime.dart';

void main() {
  test('camera captures get a readable timestamped name', () {
    final at = DateTime(2026, 9, 6, 8, 5, 3);
    expect(
      cameraPhotoName(at, '901f9f26-84d6-40be.JPG'),
      'foto-20260906-080503.jpg',
    );
    expect(cameraPhotoName(at, ''), 'foto-20260906-080503.jpg');
  });
}
