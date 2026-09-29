import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Opens a colour picker (saturation/brightness pad, hue bar and a hex field)
/// and resolves to the chosen opaque colour, or null when dismissed.
Future<Color?> showColorPickerDialog(
  BuildContext context, {
  required Color initial,
  String title = 'Özel renk',
}) => showDialog<Color>(
  context: context,
  builder: (_) => ColorPickerDialog(initial: initial, title: title),
);

/// `#RRGGBB` for an opaque [color] (alpha is ignored).
String colorToHex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Parses `RRGGBB`, `#RRGGBB` or shorthand `RGB`; null when invalid.
Color? parseHexColor(String input) {
  var hex = input.trim().replaceFirst('#', '');
  if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
  if (hex.length != 6) return null;
  final value = int.tryParse(hex, radix: 16);
  return value == null ? null : Color(0xFF000000 | value);
}

class ColorPickerDialog extends StatefulWidget {
  const ColorPickerDialog({
    super.key,
    required this.initial,
    this.title = 'Özel renk',
  });

  final Color initial;
  final String title;

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late HSVColor _hsv;
  late final TextEditingController _hex;
  bool _hexInvalid = false;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
    _hex = TextEditingController(text: colorToHex(widget.initial));
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  Color get _color => _hsv.toColor();

  void _setHsv(HSVColor hsv) => setState(() {
    _hsv = hsv;
    _hexInvalid = false;
    _hex.value = TextEditingValue(
      text: colorToHex(hsv.toColor()),
      selection: TextSelection.collapsed(offset: 7),
    );
  });

  void _onHexChanged(String value) {
    final parsed = parseHexColor(value);
    setState(() {
      _hexInvalid = parsed == null;
      if (parsed != null) _hsv = HSVColor.fromColor(parsed);
    });
  }

  @override
  Widget build(BuildContext context) {
    final onColor = ThemeData.estimateBrightnessForColor(_color) ==
            Brightness.dark
        ? Colors.white
        : Colors.black;
    return AlertDialog(
      title: Text(widget.title),
      scrollable: true,
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1.5,
              child: _SaturationValuePad(
                key: const Key('color-picker-pad'),
                hsv: _hsv,
                onChanged: _setHsv,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: AppTheme.minTouchTarget,
              child: _HueBar(
                key: const Key('color-picker-hue'),
                hue: _hsv.hue,
                onChanged: (hue) => _setHsv(_hsv.withHue(hue)),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  key: const Key('color-picker-preview'),
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Text('Aa', style: TextStyle(color: onColor)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    key: const Key('color-picker-hex'),
                    controller: _hex,
                    autocorrect: false,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp('[#0-9a-fA-F]')),
                      LengthLimitingTextInputFormatter(7),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Hex kodu',
                      errorText: _hexInvalid ? 'Geçersiz renk' : null,
                    ),
                    onChanged: _onHexChanged,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          key: const Key('color-picker-confirm'),
          onPressed: _hexInvalid ? null : () => Navigator.of(context).pop(_color),
          child: const Text('Seç'),
        ),
      ],
    );
  }
}

/// Two-axis pad: saturation left→right, brightness bottom→top.
class _SaturationValuePad extends StatelessWidget {
  const _SaturationValuePad({
    super.key,
    required this.hsv,
    required this.onChanged,
  });

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  // No LayoutBuilder: this lives in an AlertDialog, which asks its content
  // for intrinsic sizes. The pad sizes itself from its parent instead.
  @override
  Widget build(BuildContext context) => Builder(
    builder: (context) {
      void update(Offset local) {
        final size = (context.findRenderObject()! as RenderBox).size;
        final s = (local.dx / size.width).clamp(0.0, 1.0);
        final v = 1 - (local.dy / size.height).clamp(0.0, 1.0);
        onChanged(hsv.withSaturation(s).withValue(v));
      }

      return Semantics(
        label: 'Renk tonu ve parlaklık',
        child: GestureDetector(
          onPanDown: (d) => update(d.localPosition),
          onPanUpdate: (d) => update(d.localPosition),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            child: CustomPaint(
              painter: _PadPainter(hsv),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
    },
  );
}

class _PadPainter extends CustomPainter {
  _PadPainter(this.hsv);

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor()],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
    final thumb = Offset(
      hsv.saturation * size.width,
      (1 - hsv.value) * size.height,
    );
    canvas
      ..drawCircle(
        thumb,
        11,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Colors.white,
      )
      ..drawCircle(
        thumb,
        12.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.black54,
      );
  }

  @override
  bool shouldRepaint(_PadPainter old) => old.hsv != hsv;
}

class _HueBar extends StatelessWidget {
  const _HueBar({super.key, required this.hue, required this.onChanged});

  final double hue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Builder(
    builder: (context) {
      void update(double dx) {
        final width = (context.findRenderObject()! as RenderBox).size.width;
        onChanged((dx / width).clamp(0.0, 1.0) * 359.99);
      }

      return Semantics(
        label: 'Renk',
        slider: true,
        child: GestureDetector(
          onHorizontalDragDown: (d) => update(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => update(d.localPosition.dx),
          onTapDown: (d) => update(d.localPosition.dx),
          child: CustomPaint(
            painter: _HuePainter(hue),
            child: const SizedBox.expand(),
          ),
        ),
      );
    },
  );
}

class _HuePainter extends CustomPainter {
  _HuePainter(this.hue);

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final bar = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, size.height / 2 - 8, size.width, 16),
      const Radius.circular(8),
    );
    canvas.drawRRect(
      bar,
      Paint()
        ..shader = LinearGradient(
          colors: [
            for (var h = 0; h <= 360; h += 60)
              HSVColor.fromAHSV(1, h.toDouble().clamp(0, 359.99), 1, 1).toColor(),
          ],
        ).createShader(bar.outerRect),
    );
    final thumb = Offset(hue / 360 * size.width, size.height / 2);
    canvas
      ..drawCircle(thumb, 11, Paint()..color = Colors.white)
      ..drawCircle(
        thumb,
        8,
        Paint()..color = HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
      )
      ..drawCircle(
        thumb,
        11,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.black38,
      );
  }

  @override
  bool shouldRepaint(_HuePainter old) => old.hue != hue;
}
