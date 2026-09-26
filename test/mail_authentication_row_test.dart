import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/models/mail_authentication.dart';
import 'package:kaydetmail/widgets/mail_authentication_row.dart';

void main() {
  testWidgets('shows compact results and informational explanation', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MailAuthenticationRow(
            authentication: MailAuthentication(
              authservId: 'mx.example.test',
              spf: 'pass',
              dkim: 'pass',
              dmarc: 'fail',
            ),
          ),
        ),
      ),
    );

    expect(
      find.text('SPF geçti · DKIM geçti · DMARC başarısız'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('mail-authentication-row')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Yalnızca bilgi amaçlıdır.'), findsOneWidget);
    expect(find.textContaining('mx.example.test'), findsOneWidget);
  });

  testWidgets('absent authentication renders no row', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );

    expect(find.byKey(const Key('mail-authentication-row')), findsNothing);
  });
}
