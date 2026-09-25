import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/utils/markdown_lite_editing.dart';
import 'package:kaydetmail/utils/markdown_lite_to_html.dart';

void main() {
  TextEditingValue selected(String text) => TextEditingValue(
    text: text,
    selection: TextSelection(baseOffset: 0, extentOffset: text.length),
  );

  test('numbered list action numbers lines and stays readable as text', () {
    final value = toggleNumberedList(selected('bir\niki'));
    expect(value.text, '1. bir\n2. iki');
    expect(markdownLiteToHtml(value.text), '<ol><li>bir</li><li>iki</li></ol>');
  });

  test('quote action keeps readable markers and produces blockquote HTML', () {
    final value = toggleQuote(selected('bir\niki'));
    expect(value.text, '> bir\n> iki');
    expect(
      markdownLiteToHtml(value.text),
      '<blockquote><p>bir</p><p>iki</p></blockquote>',
    );
  });

  test('indent and outdent preserve nested numbered list structure', () {
    var value = toggleNumberedList(selected('ana\nalt\nson'));
    value = value.copyWith(selection: const TextSelection.collapsed(offset: 9));
    value = increaseIndent(value);
    expect(value.text, '1. ana\n  1. alt\n2. son');
    expect(
      markdownLiteToHtml(value.text),
      '<ol><li>ana<ol><li>alt</li></ol></li><li>son</li></ol>',
    );
    value = decreaseIndent(value);
    expect(value.text, '1. ana\n2. alt\n3. son');
  });

  test(
    'clear formatting removes inline and block markers from touched lines',
    () {
      final value = clearFormatting(
        selected('> 1. **kalın** ve [site](https://x.test)'),
      );
      expect(value.text, 'kalın ve site');
      expect(hasMarkdownLiteMarkup(value.text), isFalse);
      expect(markdownLiteToHtml(value.text), '<p>kalın ve site</p>');
    },
  );

  test('clear formatting at cursor clears current line only', () {
    final value = clearFormatting(
      const TextEditingValue(
        text: '**bir**\n> iki',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    expect(value.text, 'bir\n> iki');
  });

  test('paste normalizes common list markers and keeps quote structure', () {
    final value = MarkdownLitePasteFormatter().formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(
        text: '• bir\n  2) iki\n> alıntı',
        selection: TextSelection.collapsed(offset: 22),
      ),
    );
    expect(value.text, '- bir\n  2. iki\n> alıntı');
    expect(
      markdownLiteToHtml(value.text),
      '<ul><li>bir<ol start="2"><li>iki</li></ol></li></ul><blockquote><p>alıntı</p></blockquote>',
    );
  });
}
