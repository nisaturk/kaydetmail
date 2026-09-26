import 'dart:async';

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../state/app_settings_controller.dart';
import '../theme/app_theme.dart';
import '../utils/biometric_lock_policy.dart';

/// Gates [child] behind a biometric/device-credential check when
/// [AppSettingsController.biometricLockEnabled] is on — re-checked on cold
/// start and when the app returns from the background after
/// [AppSettingsController.biometricLockTimeout] has elapsed.
///
/// When the setting is off this is a plain passthrough: no
/// [WidgetsBindingObserver] is registered and [child] renders directly, so
/// there's no lifecycle overhead for users who never turn the lock on.
class BiometricLockGate extends StatefulWidget {
  const BiometricLockGate({super.key, required this.child});

  final Widget child;

  @override
  State<BiometricLockGate> createState() => _BiometricLockGateState();
}

class _BiometricLockGateState extends State<BiometricLockGate>
    with WidgetsBindingObserver {
  final LocalAuthentication _auth = LocalAuthentication();

  bool _observing = false;
  bool _wasBackgrounded = false;
  bool _unlocked = false;
  bool _authenticating = false;
  Stopwatch? _backgroundedWatch;
  DateTime? _backgroundedAt;

  /// True once `local_auth` has reported this device can't authenticate at
  /// all (no biometrics enrolled and no device passcode/pattern/PIN set) —
  /// shows the degrade-gracefully path instead of a permanent lock.
  bool _deviceUnsupported = false;

  bool get _lockEnabled => AppSettingsController.instance.biometricLockEnabled;

  @override
  void initState() {
    super.initState();
    AppSettingsController.instance.addListener(_onSettingsChanged);
    _syncObserver();
    if (_lockEnabled) unawaited(_authenticate());
  }

  @override
  void dispose() {
    AppSettingsController.instance.removeListener(_onSettingsChanged);
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Registers/unregisters the lifecycle observer to match the current
  /// setting, so toggling it off at runtime immediately drops the overhead
  /// and toggling it on immediately starts re-locking on background return.
  void _syncObserver() {
    if (_lockEnabled && !_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    } else if (!_lockEnabled && _observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
  }

  void _onSettingsChanged() {
    final wasObserving = _observing;
    _syncObserver();
    if (_lockEnabled && !wasObserving) {
      // Just turned on while the app is already in the foreground — lock
      // immediately instead of waiting for the next background/foreground
      // cycle.
      setState(() {
        _unlocked = false;
        _deviceUnsupported = false;
      });
      unawaited(_authenticate());
    } else if (!_lockEnabled) {
      setState(() {}); // build() short-circuits to `widget.child` below.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_lockEnabled) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (!_wasBackgrounded) {
        _backgroundedWatch = Stopwatch()..start();
        _backgroundedAt = DateTime.now();
      }
      _wasBackgrounded = true;
      return;
    }
    if (state == AppLifecycleState.resumed && _wasBackgrounded) {
      _wasBackgrounded = false;
      final relock = shouldLockBiometric(
        timeout: AppSettingsController.instance.biometricLockTimeout,
        coldStart: false,
        monotonicElapsed: _backgroundedWatch?.elapsed,
        wallClockElapsed: _backgroundedAt == null
            ? null
            : DateTime.now().difference(_backgroundedAt!),
      );
      _backgroundedWatch = null;
      _backgroundedAt = null;
      if (!relock) return;
      setState(() {
        _unlocked = false;
        _deviceUnsupported = false;
      });
      unawaited(_authenticate());
    }
  }

  Future<void> _authenticate() async {
    if (_authenticating) return;
    setState(() => _authenticating = true);
    try {
      final canAuthenticate =
          await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
      if (!canAuthenticate) {
        if (!mounted) return;
        setState(() {
          _authenticating = false;
          _deviceUnsupported = true;
        });
        return;
      }
      final didAuthenticate = await _auth.authenticate(
        localizedReason: 'Postalarınıza erişmek için kimliğinizi doğrulayın',
        // Device passcode/pattern/PIN is an accepted fallback, not just
        // biometrics — a user without enrolled biometrics still has a way in.
        biometricOnly: false,
      );
      if (!mounted) return;
      setState(() {
        _authenticating = false;
        _unlocked = didAuthenticate;
      });
    } on LocalAuthException catch (e) {
      if (!mounted) return;
      final noCredentials =
          e.code == LocalAuthExceptionCode.noCredentialsSet ||
          e.code == LocalAuthExceptionCode.noBiometricHardware ||
          e.code == LocalAuthExceptionCode.noBiometricsEnrolled;
      setState(() {
        _authenticating = false;
        _deviceUnsupported = noCredentials;
      });
    } catch (_) {
      // Cancellation, temporary lockout, transient platform errors, etc. —
      // stay locked, let the user retry with the "Kilidi Aç" button.
      if (!mounted) return;
      setState(() => _authenticating = false);
    }
  }

  /// Escape hatch for the "no credentials configured at all" case: the app
  /// must never permanently lock a user out of their own mailbox because of
  /// a device limitation it can't fix.
  void _proceedAnyway() {
    setState(() {
      _unlocked = true;
      _deviceUnsupported = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_lockEnabled || _unlocked) return widget.child;
    return _LockScreen(
      authenticating: _authenticating,
      deviceUnsupported: _deviceUnsupported,
      onUnlock: _authenticate,
      onProceedAnyway: _proceedAnyway,
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({
    required this.authenticating,
    required this.deviceUnsupported,
    required this.onUnlock,
    required this.onProceedAnyway,
  });

  final bool authenticating;
  final bool deviceUnsupported;
  final Future<void> Function() onUnlock;
  final VoidCallback onProceedAnyway;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.space8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  deviceUnsupported
                      ? LucideIcons.triangleAlert
                      : LucideIcons.lock,
                  size: 48,
                  color: colors.tertiaryText,
                ),
                const SizedBox(height: AppTheme.space4),
                Text(
                  'Uygulama Kilitli',
                  style: AppTheme.titleText.copyWith(color: colors.bodyText),
                ),
                const SizedBox(height: AppTheme.space2),
                Text(
                  deviceUnsupported
                      ? 'Cihazınızda parmak izi, yüz tanıma veya ekran kilidi '
                            'tanımlı değil. Uygulama kilidi bu nedenle '
                            'doğrulanamıyor.'
                      : 'Devam etmek için parmak izi, yüz tanıma veya cihaz '
                            'şifrenizle kimliğinizi doğrulayın.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: colors.secondaryText),
                ),
                const SizedBox(height: AppTheme.space6),
                if (deviceUnsupported)
                  TextButton(
                    onPressed: onProceedAnyway,
                    child: const Text('Yine de devam et'),
                  )
                else
                  FilledButton.icon(
                    onPressed: authenticating ? null : onUnlock,
                    icon: authenticating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(LucideIcons.fingerprint, size: 18),
                    label: const Text('Kilidi Aç'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
