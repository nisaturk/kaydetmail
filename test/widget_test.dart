import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kaydetmail/app.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/repositories/mock_mail_repository.dart';

void main() {
  setUp(() => AppConfig.resetForTest());

  testWidgets('app boots to the email step of the login screen',
      (WidgetTester tester) async {
    await tester.pumpWidget(const KaydetApp());

    expect(find.text('KAYDET'), findsOneWidget);
    expect(find.text('E-postalarınız için güvenli bir uygulama'), findsOneWidget);
    expect(find.byKey(const Key('email-field')), findsOneWidget);
    expect(find.byKey(const Key('password-field')), findsNothing);
    expect(find.text('Devam'), findsOneWidget);
    expect(find.text('Giriş Yap'), findsNothing);
    expect(find.text('Advanced server settings'), findsNothing);
  });

  testWidgets('continue slides to the password step', (WidgetTester tester) async {
    await tester.pumpWidget(const KaydetApp());

    await tester.enterText(find.byKey(const Key('email-field')), 'me@example.com');
    await tester.tap(find.text('Devam'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('password-field')), findsOneWidget);
    expect(find.byKey(const Key('signin-button')), findsOneWidget);
    expect(find.text('Şu hesapla oturum açıyorsunuz'), findsOneWidget);
    expect(find.text('me@example.com'), findsOneWidget);
  });

  testWidgets('back returns to the email step and preserves the email',
      (WidgetTester tester) async {
    await tester.pumpWidget(const KaydetApp());

    await tester.enterText(find.byKey(const Key('email-field')), 'me@example.com');
    await tester.tap(find.text('Devam'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Geri'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('email-field')), findsOneWidget);
    expect(find.byKey(const Key('password-field')), findsNothing);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('email-field')))
          .controller!
          .text,
      'me@example.com',
    );
  });

  testWidgets('login with valid credentials opens the inbox',
      (WidgetTester tester) async {
    await tester.pumpWidget(const KaydetApp());

    await tester.enterText(find.byKey(const Key('email-field')), 'me@kaydet.app');
    await tester.tap(find.text('Devam'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('password-field')), 'secret123');
    await tester.tap(find.byKey(const Key('signin-button')));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Mock auth latency plus page transition.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Gelen Kutusu'), findsWidgets);
    // Newest inbox mail is rendered first.
    expect(find.text('Fixing the CI pipeline'), findsOneWidget);
  });

  testWidgets('invalid email is rejected on the email step',
      (WidgetTester tester) async {
    await tester.pumpWidget(const KaydetApp());

    await tester.enterText(find.byKey(const Key('email-field')), 'not-an-email');
    await tester.tap(find.text('Devam'));
    await tester.pump();

    expect(find.text('Geçerli bir e-posta adresi girin'), findsOneWidget);
    expect(find.byKey(const Key('password-field')), findsNothing);
    expect(find.text('Gelen Kutusu'), findsNothing);
  });

  testWidgets('short password is rejected on the password step',
      (WidgetTester tester) async {
    await tester.pumpWidget(const KaydetApp());

    await tester.enterText(find.byKey(const Key('email-field')), 'me@example.com');
    await tester.tap(find.text('Devam'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('password-field')), '123');
    await tester.tap(find.byKey(const Key('signin-button')));
    await tester.pump();

    expect(
        find.text('Şifre en az 6 karakter olmalıdır'), findsOneWidget);
    expect(find.text('Gelen Kutusu'), findsNothing);
  });

  testWidgets('documented mock credentials sign in', (WidgetTester tester) async {
    expect(MockMailRepository.demoEmail, 'nisa@kaydet.com');
    expect(MockMailRepository.demoPassword, 'kaydet123');

    await tester.pumpWidget(const KaydetApp());

    await tester.enterText(
        find.byKey(const Key('email-field')), MockMailRepository.demoEmail);
    await tester.tap(find.text('Devam'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('password-field')), MockMailRepository.demoPassword);
    await tester.tap(find.byKey(const Key('signin-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Gelen Kutusu'), findsWidgets);
  });
}