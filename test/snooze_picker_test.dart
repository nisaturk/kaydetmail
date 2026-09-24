import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/widgets/snooze_picker.dart';

void main() {
  group('combineSnoozeDateTime', () {
    final now = DateTime(2026, 9, 24, 14, 30);

    test('accepts a date+time strictly after now', () {
      final result = combineSnoozeDateTime(
        date: DateTime(2026, 9, 24),
        time: const TimeOfDay(hour: 15, minute: 0),
        now: now,
      );
      expect(result, DateTime(2026, 9, 24, 15, 0));
    });

    test('rejects the same day at an hour that has already passed', () {
      final result = combineSnoozeDateTime(
        date: DateTime(2026, 9, 24),
        time: const TimeOfDay(hour: 9, minute: 0),
        now: now,
      );
      expect(result, isNull);
    });

    test('rejects a time equal to now (not strictly after)', () {
      final result = combineSnoozeDateTime(
        date: DateTime(2026, 9, 24),
        time: const TimeOfDay(hour: 14, minute: 30),
        now: now,
      );
      expect(result, isNull);
    });

    test('a future date is always accepted regardless of time of day', () {
      final result = combineSnoozeDateTime(
        date: DateTime(2026, 9, 25),
        time: const TimeOfDay(hour: 0, minute: 1),
        now: now,
      );
      expect(result, DateTime(2026, 9, 25, 0, 1));
    });
  });
}
