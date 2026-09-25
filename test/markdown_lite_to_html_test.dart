import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/utils/markdown_lite_to_html.dart';

void main() {
  test('bold/italic/underline wrap into inline tags', () {
    expect(markdownLiteToHtml('**bold**'), '<p><b>bold</b></p>');
    expect(markdownLiteToHtml('*italic*'), '<p><i>italic</i></p>');
    expect(markdownLiteToHtml('__underline__'), '<p><u>underline</u></p>');
  });

  test(
    'a bold span next to a separate italic span does not confuse the two',
    () {
      expect(
        markdownLiteToHtml('**bold** and *italic*'),
        '<p><b>bold</b> and <i>italic</i></p>',
      );
    },
  );

  test('bullet lines become a single ul/li block', () {
    expect(
      markdownLiteToHtml('- one\n- two'),
      '<ul><li>one</li><li>two</li></ul>',
    );
  });

  test('bullets interrupt surrounding paragraphs and close correctly', () {
    expect(
      markdownLiteToHtml('intro\n- one\n- two\noutro'),
      '<p>intro</p><ul><li>one</li><li>two</li></ul><p>outro</p>',
    );
  });

  test('links only become anchors for http(s)/mailto schemes', () {
    expect(
      markdownLiteToHtml('[site](https://example.com)'),
      '<p><a href="https://example.com">site</a></p>',
    );
    expect(
      markdownLiteToHtml('[mail](mailto:a@b.com)'),
      '<p><a href="mailto:a@b.com">mail</a></p>',
    );
  });

  test('an unsafe URL scheme degrades to plain text instead of an anchor', () {
    expect(markdownLiteToHtml('[bad](vbscript:msgbox)'), '<p>bad</p>');
  });

  test('HTML special characters are escaped before markers are applied', () {
    expect(
      markdownLiteToHtml('<script>&"'),
      '<p>&lt;script&gt;&amp;&quot;</p>',
    );
  });

  test('blank lines become a line break', () {
    expect(markdownLiteToHtml('a\n\nb'), '<p>a</p><br><p>b</p>');
  });

  test('empty input returns an empty string', () {
    expect(markdownLiteToHtml(''), '');
  });

  group('hasMarkdownLiteMarkup', () {
    test('detects each formatting kind the toolbar produces', () {
      expect(hasMarkdownLiteMarkup('**bold**'), isTrue);
      expect(hasMarkdownLiteMarkup('*italic*'), isTrue);
      expect(hasMarkdownLiteMarkup('__underline__'), isTrue);
      expect(hasMarkdownLiteMarkup('- madde'), isTrue);
      expect(hasMarkdownLiteMarkup('metin\n- madde\ndevam'), isTrue);
      expect(hasMarkdownLiteMarkup('[site](https://example.com)'), isTrue);
    });

    test('plain unformatted text is not flagged', () {
      expect(
        hasMarkdownLiteMarkup('sadece düz metin, hiçbir işaretleme yok'),
        isFalse,
      );
      expect(hasMarkdownLiteMarkup(''), isFalse);
    });

    test('a lone unpaired dash or star is not mistaken for markup', () {
      expect(hasMarkdownLiteMarkup('geçen yıl - bu yıl'), isFalse);
      expect(hasMarkdownLiteMarkup('3 * 4 = 12'), isFalse);
    });
  });
}
