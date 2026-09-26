import '../state/app_settings_controller.dart';

bool shouldLockBiometric({
  required BiometricLockTimeout timeout,
  required bool coldStart,
  Duration? monotonicElapsed,
  Duration? wallClockElapsed,
}) {
  if (coldStart || timeout.duration == Duration.zero) return true;
  if (monotonicElapsed == null || wallClockElapsed == null) return true;
  if (monotonicElapsed.isNegative || wallClockElapsed.isNegative) return true;
  return monotonicElapsed >= timeout.duration ||
      wallClockElapsed >= timeout.duration;
}
