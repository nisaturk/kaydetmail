import 'package:flutter/material.dart';

/// Deterministic avatar colors.
///
/// The same identity (email address) always maps to the same color, no matter
/// how often the widget rebuilds. A custom FNV-1a hash is used instead of
/// `String.hashCode` so the result is stable across platforms and runs.
class AvatarColors {
  const AvatarColors._();

  static const List<Color> palette = [
    Color(0xFFDCE8F5), // powder blue
    Color(0xFFE3DCF2), // lavender
    Color(0xFFF5DCDE), // blush
    Color(0xFFDCF0E4), // mint
    Color(0xFFF7E8DC), // peach
    Color(0xFFE8E3DC), // sand
    Color(0xFFDDF0F0), // teal-sky
    Color(0xFFF0E3EC), // mauve
  ];

  static int _fnv1a(String s) {
    var hash = 0x811c9dc5;
    for (final unit in s.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  static Color colorFor(String identity) =>
      palette[_fnv1a(identity.trim().toLowerCase()) % palette.length];
}