import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/services/home_widget_compose_router.dart';
import 'package:kaydetmail/services/home_widget_service.dart';

/// Fake [HomeWidgetLaunchSource] — no platform channel involved. [initial]
/// is what a cold start from the widget would return via
/// `HomeWidget.initiallyLaunchedFromHomeWidget()`; [emit] simulates a warm
/// app receiving a tap through `HomeWidget.widgetClicked`.
class _FakeLaunchSource implements HomeWidgetLaunchSource {
  _FakeLaunchSource({this.initial});

  final Uri? initial;
  final _controller = StreamController<Uri?>.broadcast();

  @override
  Future<Uri?> initiallyLaunchedUri() async => initial;

  @override
  Stream<Uri?> get clicked => _controller.stream;

  void emit(Uri? uri) => _controller.add(uri);

  void dispose() => _controller.close();
}

/// Marker widget standing in for `ComposeScreen` — proves navigation
/// happened without needing the real screen's repository dependencies.
class _FakeComposeScreen extends StatelessWidget {
  const _FakeComposeScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('Compose'));
}

void main() {
  final composeUri = Uri.parse('kaydetmail://compose');
  late GlobalKey<NavigatorState> navigatorKey;

  setUp(() {
    navigatorKey = GlobalKey<NavigatorState>();
  });

  tearDown(() {
    HomeWidgetService.launchSourceForTest(null);
  });

  Future<void> pumpHarness(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      home: const Scaffold(body: Text('Home')),
    ),
  );

  HomeWidgetComposeRouter buildRouter() => HomeWidgetComposeRouter(
    onComposeRequested: () => navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => const _FakeComposeScreen()),
    ),
  );

  testWidgets(
    'a cold start carrying the compose URI navigates once login resolves true',
    (tester) async {
      final fake = _FakeLaunchSource(initial: composeUri);
      HomeWidgetService.launchSourceForTest(fake);
      addTearDown(fake.dispose);

      await pumpHarness(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      router.start();

      // The cold-start URI resolves asynchronously; login state isn't known
      // yet, so nothing should navigate before `resolveAuth` runs.
      await tester.pumpAndSettle();
      expect(find.byType(_FakeComposeScreen), findsNothing);

      router.resolveAuth(true);
      await tester.pumpAndSettle();

      expect(find.byType(_FakeComposeScreen), findsOneWidget);
    },
  );

  testWidgets(
    'drops the pending compose launch when the session never authenticates',
    (tester) async {
      final fake = _FakeLaunchSource(initial: composeUri);
      HomeWidgetService.launchSourceForTest(fake);
      addTearDown(fake.dispose);

      await pumpHarness(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      router.start();
      await tester.pumpAndSettle();

      router.resolveAuth(false);
      await tester.pumpAndSettle();

      expect(find.byType(_FakeComposeScreen), findsNothing);
    },
  );

  testWidgets(
    'a warm-start widget click navigates immediately when already logged in',
    (tester) async {
      final fake = _FakeLaunchSource();
      HomeWidgetService.launchSourceForTest(fake);
      addTearDown(fake.dispose);

      await pumpHarness(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      router.start();
      router.resolveAuth(true);
      await tester.pumpAndSettle();

      fake.emit(composeUri);
      await tester.pumpAndSettle();

      expect(find.byType(_FakeComposeScreen), findsOneWidget);
    },
  );

  testWidgets('a non-compose launch URI is ignored', (tester) async {
    final fake = _FakeLaunchSource(initial: Uri.parse('kaydetmail://other'));
    HomeWidgetService.launchSourceForTest(fake);
    addTearDown(fake.dispose);

    await pumpHarness(tester);
    final router = buildRouter();
    addTearDown(router.dispose);
    router.start();
    await tester.pumpAndSettle();

    router.resolveAuth(true);
    await tester.pumpAndSettle();

    expect(find.byType(_FakeComposeScreen), findsNothing);
  });

  test('HomeWidgetService.isComposeUri matches only the compose host', () {
    expect(HomeWidgetService.isComposeUri(composeUri), isTrue);
    expect(
      HomeWidgetService.isComposeUri(Uri.parse('kaydetmail://other')),
      isFalse,
    );
    expect(HomeWidgetService.isComposeUri(null), isFalse);
  });
}
