import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:kaydetmail/widgets/mail_link_handler.dart';

const _pixel =
    'data:image/png;base64,'
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==';

void main() {
  for (final (width, fixedHeight) in [
    (240.0, false),
    (360.0, false),
    (240.0, true),
    (360.0, true),
  ]) {
    testWidgets(
      'selectable HTML table at $width with fixed height $fixedHeight',
      (tester) async {
        final tapped = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: SingleChildScrollView(
                    child: SelectionArea(
                      child: HtmlWidget(
                        '''
<table style="width:600px;${fixedHeight ? 'height:300px;' : ''}border:1px solid black">
  <tr ${fixedHeight ? 'style="height:230px"' : ''}>
    <td style="width:70%">
      Before <span style="display:inline-block;width:130px;height:30px">Inline label</span>
      <a data-remote-href="https://example.com/details">Details</a>
      <p style="text-align:center"><img src="$_pixel" width="200" height="40" /></p> After
    </td>
    <td><span style="display:inline-block;width:80px;height:20px">Other cell</span></td>
  </tr>
  <tr><td colspan="2">
    <table style="width:100%"><tr><td>Nested cell</td><td>
      <span style="vertical-align:middle;display:inline-block;width:100px;height:25px">Aligned label</span>
    </td></tr></table>
  </td></tr>
</table>
''',
                        textStyle: const TextStyle(fontSize: 15, height: 1.6),
                        factoryBuilder: () => MailLinkWidgetFactory(
                          onLinkTap: (href, text) => tapped.add(href),
                        ),
                        customStylesBuilder: (element) =>
                            element.localName == 'table' ||
                                element.localName == 'img'
                            ? {'max-width': '100%'}
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        // Image codecs complete outside the test's fake clock. Wait for actual
        // decoded pixels, not just a sized loading placeholder.
        await tester.runAsync(() async {
          final image = find.byType(Image);
          await precacheImage(
            tester.widget<Image>(image).image,
            tester.element(image),
          );
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final label in [
          'Inline label',
          'Other cell',
          'Nested cell',
          'Aligned label',
        ]) {
          expect(find.textContaining(label, findRichText: true), findsWidgets);
        }
        expect(find.byType(HtmlTable), findsNWidgets(2));
        for (final element in find.byType(HtmlTable).evaluate()) {
          final box = element.renderObject! as RenderBox;
          expect(box.size.width, lessThanOrEqualTo(width));
          expect(box.size.height, greaterThan(0));
        }
        final image = find.byType(Image);
        expect(image, findsOneWidget);
        expect(tester.getSize(image).width, lessThanOrEqualTo(width));
        expect(tester.getSize(image).height, greaterThan(0));
        expect(
          tester.renderObject<RenderImage>(find.byType(RawImage)).image,
          isNotNull,
        );
        await tester.tapOnText(find.textRange.ofSubstring('Details'));
        await tester.pumpAndSettle();
        expect(tapped, ['https://example.com/details']);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
