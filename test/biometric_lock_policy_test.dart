import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/state/app_settings_controller.dart';
import 'package:kaydetmail/utils/biometric_lock_policy.dart';

void main() {
  const minute = Duration(minutes: 1);

  test('cold start and immediate timeout always lock', () {
    expect(
      shouldLockBiometric(
        timeout: BiometricLockTimeout.fifteenMinutes,
        coldStart: true,
        monotonicElapsed: Duration.zero,
        wallClockElapsed: Duration.zero,
      ),
      isTrue,
    );
    expect(
      shouldLockBiometric(
        timeout: BiometricLockTimeout.immediately,
        coldStart: false,
        monotonicElapsed: Duration.zero,
        wallClockElapsed: Duration.zero,
      ),
      isTrue,
    );
  });

  test('stays unlocked below the timeout and locks at the boundary', () {
    bool lock(Duration elapsed) => shouldLockBiometric(
      timeout: BiometricLockTimeout.fiveMinutes,
      coldStart: false,
      monotonicElapsed: elapsed,
      wallClockElapsed: elapsed,
    );
    expect(lock(minute * 4), isFalse);
    expect(lock(minute * 5), isTrue);
  });

  test('either clock reaching the timeout locks; bad clocks fail closed', () {
    expect(
      shouldLockBiometric(
        timeout: BiometricLockTimeout.oneMinute,
        coldStart: false,
        monotonicElapsed: const Duration(seconds: 10),
        wallClockElapsed: minute * 2,
      ),
      isTrue,
    );
    expect(
      shouldLockBiometric(
        timeout: BiometricLockTimeout.oneMinute,
        coldStart: false,
        monotonicElapsed: const Duration(seconds: 10),
        wallClockElapsed: const Duration(seconds: -30),
      ),
      isTrue,
    );
    expect(
      shouldLockBiometric(
        timeout: BiometricLockTimeout.oneMinute,
        coldStart: false,
      ),
      isTrue,
    );
  });
}
