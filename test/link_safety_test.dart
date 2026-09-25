import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/utils/link_safety.dart';

void main() {
  group('unsafe and invalid schemes are blocked', () {
    for (final href in [
      'javascript:alert(1)',
      'JaVaScRiPt:alert(1)',
      'data:text/html;base64,PHNjcmlwdD4=',
      'file:///etc/passwd',
      'intent://scan/#Intent;scheme=zxing;end',
      'vbscript:msgbox(1)',
      'sms:+905551112233',
      'content://com.android.contacts/data',
    ]) {
      test(href, () {
        final result = assessMailLink(href, displayText: 'Tıklayın');
        expect(result.verdict, LinkVerdict.blocked);
        expect(result.blockReason, LinkBlockReason.unsupportedScheme);
        expect(result.uri, isNull);
      });
    }

    test('relative, empty and host-less web links are invalid', () {
      for (final href in ['', '/path/only', 'https://', 'https:///x']) {
        final result = assessMailLink(href);
        expect(result.verdict, LinkVerdict.blocked, reason: href);
        expect(result.blockReason, LinkBlockReason.invalidAddress);
      }
    });
  });

  group('display text versus target domain', () {
    test('text showing another domain is suspicious', () {
      final result = assessMailLink(
        'https://login-secure.example.net/verify',
        displayText: 'https://www.paypal.com/signin',
      );
      expect(result.verdict, LinkVerdict.suspicious);
      expect(result.warnings, {LinkWarning.displayMismatch});
      expect(result.displayedDomain, 'www.paypal.com');
      expect(result.unicodeHost, 'login-secure.example.net');
    });

    test('bare domain text pointing elsewhere is suspicious', () {
      final result = assessMailLink(
        'http://203.0.113.9/login',
        displayText: 'garantibbva.com.tr',
      );
      expect(result.warnings, contains(LinkWarning.displayMismatch));
    });

    test('same registrable domain with www and subdomains opens directly', () {
      for (final pair in [
        ('https://www.paypal.com/x', 'paypal.com'),
        ('https://paypal.com/x', 'www.paypal.com'),
        ('https://login.paypal.com/x', 'https://www.paypal.com'),
        ('https://e.garanti.com.tr/kampanya', 'www.garanti.com.tr'),
        ('https://PayPal.COM./x', 'PAYPAL.com'),
      ]) {
        final result = assessMailLink(pair.$1, displayText: pair.$2);
        expect(result.verdict, LinkVerdict.safe, reason: pair.toString());
      }
    });

    test('siblings under a shared public suffix are not the same site', () {
      expect(
        assessMailLink(
          'https://attacker.co.uk/',
          displayText: 'bank.co.uk',
        ).warnings,
        contains(LinkWarning.displayMismatch),
      );
      expect(
        assessMailLink(
          'https://evil.github.io/',
          displayText: 'https://good.github.io',
        ).warnings,
        contains(LinkWarning.displayMismatch),
      );
    });

    test('ordinary words and file names are not treated as domains', () {
      for (final text in ['Hemen giriş yapın', 'rapor.pdf', 'v1.2', '']) {
        final result = assessMailLink(
          'https://files.example.com/a',
          displayText: text,
        );
        expect(result.verdict, LinkVerdict.safe, reason: text);
      }
    });
  });

  group('international hosts', () {
    test('punycode host is flagged and decoded for display', () {
      final result = assessMailLink('https://xn--bcher-kva.example/');
      expect(result.verdict, LinkVerdict.suspicious);
      expect(result.warnings, {LinkWarning.punycodeHost});
      expect(result.asciiHost, 'xn--bcher-kva.example');
      expect(result.unicodeHost, 'bücher.example');
    });

    test('Cyrillic look-alike of a Latin brand is a homograph', () {
      final result = assessMailLink(
        'https://xn--pple-43d.com/',
        displayText: 'Apple hesabınız',
      );
      expect(result.unicodeHost, 'аpple.com');
      expect(
        result.warnings,
        containsAll([LinkWarning.punycodeHost, LinkWarning.mixedScripts]),
      );
    });

    test('whole-script Cyrillic look-alike is a confusable', () {
      final result = assessMailLink('https://аррӏе.com/');
      expect(result.asciiHost, startsWith('xn--'));
      expect(result.unicodeHost, 'аррӏе.com');
      expect(result.warnings, contains(LinkWarning.confusableCharacters));
      expect(result.uri!.host, result.asciiHost);
    });

    test(
      'unicode display text of the same punycode host is not a mismatch',
      () {
        final result = assessMailLink(
          'https://xn--bcher-kva.example/',
          displayText: 'bücher.example',
        );
        expect(result.warnings, isNot(contains(LinkWarning.displayMismatch)));
      },
    );

    test('credentials before the host are flagged', () {
      final result = assessMailLink('https://paypal.com@evil.example/');
      expect(result.warnings, {LinkWarning.embeddedCredentials});
      expect(result.unicodeHost, 'evil.example');
    });
  });

  group('mailto and tel', () {
    test('mailto and tel open directly', () {
      expect(assessMailLink('mailto:destek@example.com').isSafe, isTrue);
      expect(
        assessMailLink(
          'mailto:destek@example.com?subject=Merhaba',
          displayText: 'destek@example.com',
        ).isSafe,
        isTrue,
      );
      expect(
        assessMailLink(
          'tel:+902121234567',
          displayText: '0212 123 45 67',
        ).isSafe,
        isTrue,
      );
    });

    test('mailto whose shown address belongs to another domain warns', () {
      final result = assessMailLink(
        'mailto:hesap@evil.example',
        displayText: 'destek@bankam.com.tr',
      );
      expect(result.warnings, {LinkWarning.displayMismatch});
      expect(result.unicodeHost, 'evil.example');
    });
  });

  test('punycode round-trips RFC 3492 samples', () {
    expect(punycodeEncode('bücher'), 'bcher-kva');
    expect(punycodeEncode('münchen'), 'mnchen-3ya');
    expect(punycodeDecode('mnchen-3ya'), 'münchen');
    expect(punycodeDecode('pple-43d'), 'аpple');
    expect(punycodeDecode('!!!'), isNull);
  });
}
