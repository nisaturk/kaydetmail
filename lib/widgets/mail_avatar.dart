import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../utils/avatar_color.dart';

/// Deterministic circular avatar.
///
/// The background color is derived from [identity] (the email address) so a
/// sender always keeps the same color. While [selected] (selection mode) the
/// avatar turns black and shows a check icon.
class MailAvatar extends StatelessWidget {
  const MailAvatar({
    super.key,
    required this.identity,
    required this.displayName,
    this.size = 40,
    this.selected = false,
  });

  final String identity;
  final String displayName;
  final double size;
  final bool selected;

  String get _initials {
    final parts = displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    final first = parts.first[0];
    final last = parts.length > 1 ? parts.last[0] : '';
    return '$first$last'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final fontSize = size * 0.38;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: selected ? Colors.black : AvatarColors.colorFor(identity),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: selected
          ? Icon(LucideIcons.check, color: Colors.white, size: size * 0.5)
          : Text(
              _initials,
              style: TextStyle(
                color: Colors.black,
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }
}
