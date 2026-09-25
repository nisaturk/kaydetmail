import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/utils/mail_unsubscribe.dart';

void main() {
  group('parseUnsubscribeHeaders', () {
    test('returns null when there is no list-unsubscribe header', () {
      expect(parseUnsubscribeHeaders(const {}), isNull);
      expect(parseUnsubscribeHeaders(const {'list-unsubscribe': '  '}), isNull);
    });

    test('parses a valid https URL as actionable', () {
      final info = parseUnsubscribeHeaders(const {
        'list-unsubscribe': '<https://example.com/unsub?id=1>',
      });
      expect(info, isNotNull);
      expect(info!.hasAction, isTrue);
      expect(info.webUrl, Uri.parse('https://example.com/unsub?id=1'));
      expect(info.mailtoUrl, isNull);
      expect(info.oneClick, isFalse);
    });

    test('parses a valid mailto URL as actionable', () {
      final info = parseUnsubscribeHeaders(const {
        'list-unsubscribe': '<mailto:unsub@example.com>',
      });
      expect(info!.hasAction, isTrue);
      expect(info.mailtoUrl, Uri.parse('mailto:unsub@example.com'));
      expect(info.webUrl, isNull);
    });

    test('prefers a web URL over a mailto one when both are present', () {
      final info = parseUnsubscribeHeaders(const {
        'list-unsubscribe':
            '<https://example.com/unsub>, <mailto:unsub@example.com>',
      });
      expect(info!.webUrl, isNotNull);
      expect(info.mailtoUrl, isNotNull);
    });

    test('sets oneClick only when a web URL and the RFC 8058 marker are both present', () {
      final withMarker = parseUnsubscribeHeaders(const {
        'list-unsubscribe': '<https://example.com/unsub>',
        'list-unsubscribe-post': 'List-Unsubscribe=One-Click',
      });
      expect(withMarker!.oneClick, isTrue);

      final withoutMarker = parseUnsubscribeHeaders(const {
        'list-unsubscribe': '<https://example.com/unsub>',
      });
      expect(withoutMarker!.oneClick, isFalse);

      final markerWithoutWebUrl = parseUnsubscribeHeaders(const {
        'list-unsubscribe': '<mailto:unsub@example.com>',
        'list-unsubscribe-post': 'List-Unsubscribe=One-Click',
      });
      expect(markerWithoutWebUrl!.oneClick, isFalse);
    });

    test(
      'is not actionable for a header present but with only malformed URLs',
      () {
        final noHost = parseUnsubscribeHeaders(const {
          'list-unsubscribe': '<https://>',
        });
        expect(noHost, isNotNull);
        expect(noHost!.hasAction, isFalse);
        expect(noHost.webUrl, isNull);

        final emptyMailto = parseUnsubscribeHeaders(const {
          'list-unsubscribe': '<mailto:>',
        });
        expect(emptyMailto!.hasAction, isFalse);

        final unsupportedScheme = parseUnsubscribeHeaders(const {
          'list-unsubscribe': '<ftp://example.com/unsub>',
        });
        expect(unsupportedScheme!.hasAction, isFalse);

        final unparseableGarbage = parseUnsubscribeHeaders(const {
          'list-unsubscribe': 'not-a-url-at-all-no-angle-brackets',
        });
        expect(unparseableGarbage!.hasAction, isFalse);
      },
    );

    test(
      'falls back to a later valid URL when an earlier one is malformed',
      () {
        final info = parseUnsubscribeHeaders(const {
          'list-unsubscribe': '<https://>, <https://example.com/unsub>',
        });
        expect(info!.hasAction, isTrue);
        expect(info.webUrl, Uri.parse('https://example.com/unsub'));
      },
    );
  });
}
