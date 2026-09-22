import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../config/app_config.dart';
import '../models/mail_folder.dart';
import '../services/session_store.dart';
import '../state/app_settings_controller.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/mail_detail_screen.dart';
import 'services/push_service.dart';
import 'theme/app_theme.dart';

/// Root widget of the KAYDET application.
class KaydetApp extends StatelessWidget {
  const KaydetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'KAYDET',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('tr'),
      supportedLocales: const [Locale('tr')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _AuthGate(),
    );
  }
}

/// Shared with [PushService.initialize] callers so tapping a notification —
/// or cold-starting the app from one — can push a route without a
/// `BuildContext` on hand.
final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

/// Checks the persisted session at startup so a logged-in user never sees
/// the login screen flash. Simple loading state, no splash screen.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool? _loggedIn;
  StreamSubscription<String>? _mailTapSub;
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    // Persisted server base URL loads before any screen reads it. The future
    // API repository will read the same controller value.
    AppSettingsController.instance.loadServerAddress();
    AppSettingsController.instance.addListener(_onSettingsChanged);
    _check();
    if (AppConfig.pushEnabled) {
      _mailTapSub = PushService.onMailTapped.listen(_openTappedMail);
    }
  }

  @override
  void dispose() {
    _mailTapSub?.cancel();
    AppSettingsController.instance.removeListener(_onSettingsChanged);
    _syncTimer?.cancel();
    super.dispose();
  }

  void _openTappedMail(String mailId) {
    _navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => MailDetailScreen(emailId: mailId)),
    );
  }

  Future<void> _check() async {
    final emails = await SessionStore.loadEmails();
    if (!mounted) return;
    if (emails.isEmpty) {
      setState(() => _loggedIn = false);
      return;
    }
    // One stale/revoked account must never block restoring the others —
    // only fall back to the login screen when every restore failed.
    var anyRestored = false;
    for (final email in emails) {
      try {
        await AppConfig.mailRepository.restoreSession(email);
        anyRestored = true;
      } catch (_) {
        // Fall through to the next stored account.
      }
      if (!mounted) return;
    }
    setState(() => _loggedIn = anyRestored);
    if (_loggedIn == true) _rescheduleSync();
  }

  /// The Settings "Senkronizasyon" section only ever changes
  /// [AppSettingsController.syncInterval] while logged in, so this only
  /// reschedules — it never needs to start a session on its own.
  void _onSettingsChanged() {
    if (_loggedIn == true) _rescheduleSync();
  }

  /// (Re)starts the background mailbox refresh at the configured interval.
  /// `manual` cancels any running timer instead — pull-to-refresh, push
  /// notifications and reopening the app remain the only triggers then.
  void _rescheduleSync() {
    _syncTimer?.cancel();
    final interval = AppSettingsController.instance.syncInterval.duration;
    if (interval == null) return;
    _syncTimer = Timer.periodic(interval, (_) => _syncLoadedFolders());
  }

  /// Refreshes every folder that already has mail loaded — matches what
  /// pull-to-refresh does per folder, just on a timer instead of a gesture.
  Future<void> _syncLoadedFolders() async {
    final repo = AppConfig.mailRepository;
    for (final folder in MailFolder.values) {
      if (repo.getEmailsInFolder(folder).isEmpty) continue;
      try {
        await repo.refreshEmails(folder);
      } catch (_) {
        // The next tick retries; a transient failure here is invisible to
        // the user since the last snapshot stays on screen either way.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loggedIn == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _loggedIn! ? const HomeScreen() : const LoginScreen();
  }
}
