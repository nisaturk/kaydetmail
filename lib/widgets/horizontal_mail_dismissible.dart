import 'package:flutter/material.dart';

/// Keeps vertical scrolling and short flings from committing mail actions.
class HorizontalMailDismissible extends StatefulWidget {
  const HorizontalMailDismissible({
    super.key,
    required this.direction,
    required this.threshold,
    required this.onAction,
    required this.background,
    required this.secondaryBackground,
    required this.child,
  });

  final DismissDirection direction;
  final double threshold;
  final Future<void> Function(DismissDirection) onAction;
  final Widget background;
  final Widget secondaryBackground;
  final Widget child;

  @override
  State<HorizontalMailDismissible> createState() =>
      _HorizontalMailDismissibleState();
}

class _HorizontalMailDismissibleState extends State<HorizontalMailDismissible> {
  int? _pointer;
  Offset _origin = Offset.zero;
  Offset _delta = Offset.zero;
  double _maxVertical = 0;
  bool _cancelled = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Listener(
        onPointerDown: (event) {
          if (_pointer != null) {
            _cancelled = true;
            return;
          }
          _pointer = event.pointer;
          _origin = event.position;
          _delta = Offset.zero;
          _maxVertical = 0;
          _cancelled = false;
        },
        onPointerMove: (event) {
          if (event.pointer != _pointer) return;
          _delta = event.position - _origin;
          if (_delta.dy.abs() > _maxVertical) {
            _maxVertical = _delta.dy.abs();
          }
        },
        onPointerUp: (event) {
          if (event.pointer == _pointer) _pointer = null;
        },
        onPointerCancel: (event) {
          if (event.pointer != _pointer) return;
          _cancelled = true;
          _pointer = null;
        },
        child: Dismissible(
          key: const ValueKey('horizontal-mail-swipe'),
          direction: widget.direction,
          dismissThresholds: {
            DismissDirection.startToEnd: widget.threshold,
            DismissDirection.endToStart: widget.threshold,
          },
          confirmDismiss: (direction) async {
            // Dismissible can complete a fling below its distance threshold.
            // Require actual distance and at least a 2:1 horizontal intent.
            if (!_cancelled &&
                _delta.dx.abs() >= constraints.maxWidth * widget.threshold &&
                _delta.dx.abs() >= _maxVertical * 2) {
              await widget.onAction(direction);
            }
            return false;
          },
          background: widget.background,
          secondaryBackground: widget.secondaryBackground,
          child: widget.child,
        ),
      ),
    );
  }
}
