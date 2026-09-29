import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/utils/query_parameter_cleaner.dart';

void main() {
  group('cleanTrackingQueryParameters', () {
    test('removes supported tracking families case-insensitively', () {
      final cleaned = cleanTrackingQueryParameters(
        Uri.parse(
          'https://example.com/path?utm_source=newsletter&UTM_Campaign=sale'
          '&fbclid=fb&gclid=google&msclkid=ms&mc_eid=mailchimp'
          '&mtm_campaign=matomo&item=42#details',
        ),
      );

      expect(cleaned.toString(), 'https://example.com/path?item=42#details');
    });

    test('preserves legitimate repeated parameters and fragment', () {
      final cleaned = cleanTrackingQueryParameters(
        Uri.parse(
          'https://example.com/search?q=mail&q=privacy&utm_medium=email#top',
        ),
      );

      expect(cleaned.queryParametersAll['q'], ['mail', 'privacy']);
      expect(cleaned.fragment, 'top');
      expect(
        cleaned.toString(),
        'https://example.com/search?q=mail&q=privacy#top',
      );
    });

    test('returns unchanged URI when no tracking parameter exists', () {
      final original = Uri.parse(
        'mailto:destek@example.com?subject=Yard%C4%B1m#message',
      );

      expect(
        identical(cleanTrackingQueryParameters(original), original),
        isTrue,
      );
    });

    test('removes query entirely when every parameter tracks', () {
      final cleaned = cleanTrackingQueryParameters(
        Uri.parse('https://example.com/path?utm_source=x&fbclid=y#section'),
      );

      expect(cleaned.toString(), 'https://example.com/path#section');
    });
  });
}
