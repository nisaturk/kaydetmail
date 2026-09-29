import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/widgets/color_picker_dialog.dart';

void main() {
  group('hex helpers', () {
    test('parse accepts #RRGGBB, RRGGBB and shorthand RGB', () {
      expect(parseHexColor('#3E7CB1'), const Color(0xFF3E7CB1));
      expect(parseHexColor('3e7cb1'), const Color(0xFF3E7CB1));
      expect(parseHexColor('#f0a'), const Color(0xFFFF00AA));
    });

    test('parse rejects malformed input', () {
      expect(parseHexColor(''), isNull);
      expect(parseHexColor('#12345'), isNull);
      expect(parseHexColor('#GGGGGG'), isNull);
      expect(parseHexColor('#1234567'), isNull);
    });

    test('format is uppercase #RRGGBB and ignores alpha', () {
      expect(colorToHex(const Color(0x803E7CB1)), '#3E7CB1');
      expect(colorToHex(const Color(0xFF00000A)), '#00000A');
    });
  });

  Future<void> open(WidgetTester tester, void Function(Color?) onResult) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => onResult(
                await showColorPickerDialog(
                  context,
                  initial: const Color(0xFF3E7CB1),
                ),
              ),
              child: const Text('aç'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle();
  }

  testWidgets('starts on the initial colour and confirms it unchanged', (
    tester,
  ) async {
    Color? result;
    await open(tester, (c) => result = c);

    expect(find.text('#3E7CB1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('color-picker-confirm')));
    await tester.pumpAndSettle();

    expect(result?.toARGB32(), 0xFF3E7CB1);
  });

  testWidgets('typing a hex code changes the returned colour', (tester) async {
    Color? result;
    await open(tester, (c) => result = c);

    await tester.enterText(find.byKey(const Key('color-picker-hex')), '#FF8800');
    await tester.pump();
    await tester.tap(find.byKey(const Key('color-picker-confirm')));
    await tester.pumpAndSettle();

    expect(result!.toARGB32() & 0xFFFFFF, closeTo(0xFF8800, 0x0300));
    expect(result!.a, 1.0);
  });

  testWidgets('an invalid hex disables confirm and shows an error', (
    tester,
  ) async {
    await open(tester, (_) {});

    await tester.enterText(find.byKey(const Key('color-picker-hex')), '#12');
    await tester.pump();

    expect(find.text('Geçersiz renk'), findsOneWidget);
    final confirm = tester.widget<FilledButton>(
      find.byKey(const Key('color-picker-confirm')),
    );
    expect(confirm.onPressed, isNull);
  });

  testWidgets('dragging the pad and hue bar updates the hex field', (
    tester,
  ) async {
    Color? result;
    await open(tester, (c) => result = c);

    final pad = find.byKey(const Key('color-picker-pad'));
    final padRect = tester.getRect(pad);
    // Top-right corner of the pad = fully saturated, full brightness.
    await tester.tapAt(padRect.topRight - const Offset(1, -1));
    await tester.pump();
    final hue = find.byKey(const Key('color-picker-hue'));
    final hueRect = tester.getRect(hue);
    // Centre of the hue bar = green-cyan region (hue ≈ 180°).
    await tester.tapAt(hueRect.center);
    await tester.pump();

    await tester.tap(find.byKey(const Key('color-picker-confirm')));
    await tester.pumpAndSettle();

    final hsv = HSVColor.fromColor(result!);
    expect(hsv.saturation, greaterThan(0.95));
    expect(hsv.value, greaterThan(0.95));
    expect(hsv.hue, closeTo(180, 5));
  });

  testWidgets('cancel returns null', (tester) async {
    Color? result = const Color(0xFF000000);
    await open(tester, (c) => result = c);

    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });
}
