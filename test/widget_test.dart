import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kaydetmail/app.dart';
import 'package:kaydetmail/config/app_config.dart';

void main() {
  setUp(() => AppConfig.resetForTest());
  testWidgets('app boots to the login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const KaydetApp());

    expect(find.text('KAYDET'), findsOneWidget);
    expect(find.text('Your secure mail client'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Advanced server settings'), findsOneWidget);
  });

  testWidgets('login with valid credentials opens the inbox',
      (WidgetTester tester) async {
    await tester.pumpWidget(const KaydetApp());

    await tester.enterText(find.byType(TextFormField).at(0), 'me@kaydet.app');
    await tester.enterText(find.byType(TextFormField).at(1), 'secret123');

    await tester.tap(find.text('Login'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Mock auth latency plus page transition.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Inbox'), findsWidgets);
    // Newest inbox mail is rendered first.
    expect(find.text('Fixing the CI pipeline'), findsOneWidget);
  });

  testWidgets('login shows validation errors for bad input',
      (WidgetTester tester) async {
    await tester.pumpWidget(const KaydetApp());

    await tester.enterText(find.byType(TextFormField).at(0), 'not-an-email');
    await tester.enterText(find.byType(TextFormField).at(1), '123');
    await tester.tap(find.text('Login'));
    await tester.pump();

    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Password must be at least 6 characters'), findsOneWidget);
    expect(find.text('Inbox'), findsNothing);
  });
}