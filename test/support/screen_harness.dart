import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/theme/app_theme.dart';

/// One Android phone configuration a screen is rendered under.
///
/// Insets are the values Android 15+ edge-to-edge reports: the status bar
/// (and cutout) on top, the gesture/3-button navigation bar at the bottom.
class AndroidDevice {
  const AndroidDevice(
    this.name, {
    required this.width,
    required this.height,
    this.top = 32,
    this.bottom = 24,
    this.textScale = 1.0,
    this.keyboard = 0,
    this.dark = false,
  });

  final String name;
  final double width;
  final double height;
  final double top;
  final double bottom;
  final double textScale;

  /// Soft keyboard height in dp (0 = closed).
  final double keyboard;
  final bool dark;

  static const double dpr = 2.75;

  AndroidDevice copyWith({
    String? name,
    double? textScale,
    double? keyboard,
    bool? dark,
  }) => AndroidDevice(
    name ?? this.name,
    width: width,
    height: height,
    top: top,
    bottom: bottom,
    textScale: textScale ?? this.textScale,
    keyboard: keyboard ?? this.keyboard,
    dark: dark ?? this.dark,
  );

  /// Old/small phone (Galaxy A01 class), 3-button navigation.
  static const compact = AndroidDevice(
    'compact-320x568',
    width: 320,
    height: 568,
    top: 24,
    bottom: 48,
  );

  /// Common mid-range phone, gesture navigation.
  static const phone = AndroidDevice('phone-360x780', width: 360, height: 780);

  /// Pixel-class phone.
  static const large = AndroidDevice(
    'large-412x915',
    width: 412,
    height: 915,
    top: 40,
  );

  static const all = [compact, phone, large];
}

/// Errors that were reported to the framework while a screen was built,
/// laid out or painted (RenderFlex overflow, exceptions, ...).
class CapturedErrors {
  final List<FlutterErrorDetails> details = [];

  List<String> get messages => [
    for (final d in details) d.exceptionAsString().split('\n').first,
  ];

  bool get isEmpty => details.isEmpty;
}

CapturedErrors captureFlutterErrors() {
  final captured = CapturedErrors();
  final previous = FlutterError.onError;
  FlutterError.onError = captured.details.add;
  addTearDown(() => FlutterError.onError = previous);
  return captured;
}

bool _fontsLoaded = false;

/// Loads Roboto (Android's default UI font) so text metrics match a real
/// device instead of the test-only Ahem font, which is far wider.
Future<void> loadAndroidFonts() async {
  if (_fontsLoaded) return;
  _fontsLoaded = true;
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final dir = '$root/bin/cache/artifacts/material_fonts';
  Future<ByteData> read(String file) async {
    final bytes = await File('$dir/$file').readAsBytes();
    return ByteData.sublistView(bytes);
  }

  try {
    final loader = FontLoader('Roboto')
      ..addFont(read('Roboto-Regular.ttf'))
      ..addFont(read('Roboto-Medium.ttf'))
      ..addFont(read('Roboto-Bold.ttf'))
      ..addFont(read('Roboto-Italic.ttf'));
    await loader.load();
  } on FileSystemException {
    // Fonts unavailable: fall back to Ahem (wider text, still a valid check).
  }
}

void _applyDevice(WidgetTester tester, AndroidDevice device) {
  const dpr = AndroidDevice.dpr;
  tester.view
    ..devicePixelRatio = dpr
    ..physicalSize = Size(device.width * dpr, device.height * dpr)
    ..viewPadding = FakeViewPadding(
      top: device.top * dpr,
      bottom: device.bottom * dpr,
    )
    ..padding = FakeViewPadding(
      top: device.top * dpr,
      // While the keyboard is up Android reports the nav bar as covered.
      bottom: device.keyboard > 0 ? 0 : device.bottom * dpr,
    )
    ..viewInsets = FakeViewPadding(bottom: device.keyboard * dpr);
  tester.platformDispatcher.textScaleFactorTestValue = device.textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
  });
}

final GlobalKey screenshotKey = GlobalKey();

/// Pumps [screen] pushed on top of a base route (like the real app, where
/// most screens are pushed from Home) under [device].
Future<void> pumpOnDevice(
  WidgetTester tester,
  AndroidDevice device,
  WidgetBuilder screen, {
  bool settle = true,
}) async {
  await loadAndroidFonts();
  _applyDevice(tester, device);
  await tester.pumpWidget(
    RepaintBoundary(
      key: screenshotKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: device.dark ? ThemeMode.dark : ThemeMode.light,
        locale: const Locale('tr'),
        supportedLocales: const [Locale('tr')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    ),
  );
  final navigator = tester.state<NavigatorState>(find.byType(Navigator));
  navigator.push(MaterialPageRoute<void>(builder: screen));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
}

/// Writes a PNG of the current frame when `SCREENSHOT_DIR` is set.
Future<void> maybeScreenshot(WidgetTester tester, String name) async {
  final dir = Platform.environment['SCREENSHOT_DIR'];
  if (dir == null || dir.isEmpty) return;
  await tester.runAsync(() async {
    final boundary =
        screenshotKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$dir/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
  });
}
