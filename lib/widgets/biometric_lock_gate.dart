import 'package:flutter/material.dart';

/// Gates [child] behind a biometric/device-credential check when
/// [AppSettingsController.biometricLockEnabled] is on — re-checked on cold
/// start and every time the app returns from the background.
///
/// Placeholder: currently a passthrough. Real `local_auth` integration is
/// implemented in a follow-up change; wired here so the hook point in
/// `app.dart` never needs to move again.
class BiometricLockGate extends StatelessWidget {
  const BiometricLockGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
