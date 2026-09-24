import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../config/app_config.dart';
import '../models/mail_folder.dart';
import '../services/session_store.dart';
import '../state/app_settings_controller.dart';
import '../state/outbox_store.dart';
import '../state/pending_send_queue.dart';
import 'screens/compose_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/outbox_screen.dart';
import 'screens/mail_detail_screen.dart';
import 'services/home_widget_compose_router.dart';
import 'services/mail_rules_engine.dart';
import 'services/push_service.dart';
import 'theme/app_theme.dart';
import 'widgets/biometric_lock_gate.dart';

/// Root widget of the KAYDET application.
class KaydetApp extends StatelessWidget {
  const KaydetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettingsController.instance,
      builder: (context, _) => MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'KAYDET',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: AppSettingsController.instance.themeMode,
        locale: const Locale('tr'),
        supportedLocales: const [Locale('tr')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const _AuthGate(),
      ),
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

  bool _handlingLogout = false;
  String? _pendingMailId;

  /// Routes the home-screen widget's "Yaz" compose shortcut, gated on
  /// [_loggedIn] — see `HomeWidgetComposeRouter`. Deferred to the next
  /// frame like [_pendingMailId]'s consumption below, since this can fire
  /// mid-[setState] (from [_setAuthenticated]).
  late final HomeWidgetComposeRouter _composeRouter = HomeWidgetComposeRouter(
    onComposeRequested: () {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pushCompose();
      });
    },
  );

  @override
  void initState() {
    super.initState();
    AppSettingsController.instance.addListener(_onSettingsChanged);
    AppConfig.mailRepository.addListener(_onRepositoryChanged);
    _check();
    if (AppConfig.pushEnabled) {
      _mailTapSub = PushService.onMailTapped.listen(_openTappedMail);
    }
    _composeRouter.start();
  }

  @override
  void dispose() {
    _mailTapSub?.cancel();
    _composeRouter.dispose();
    AppSettingsController.instance.removeListener(_onSettingsChanged);
    AppConfig.mailRepository.removeListener(_onRepositoryChanged);
    _syncTimer?.cancel();
    super.dispose();
  }

  void _openTappedMail(String mailId) {
    if (_loggedIn != true) {
      _pendingMailId = mailId;
      return;
    }
    _pushMailDetail(mailId);
  }

  void _pushMailDetail(String mailId) {
    _navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => MailDetailScreen(emailId: mailId)),
    );
  }

  void _pushCompose() {
    _navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => const ComposeScreen()),
    );
  }

  Future<void> _check() async {
    await Future.wait([
      AppSettingsController.instance.loadServerAddress(),
      AppSettingsController.instance.loadBehaviorPreferences(),
    ]);
    if (!mounted) return;
    final emails = await SessionStore.loadEmails();
    if (!mounted) return;
    if (emails.isEmpty) {
      _composeRouter.resolveAuth(false);
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
    if (anyRestored) {
      _setAuthenticated();
    } else {
      _composeRouter.resolveAuth(false);
      setState(() => _loggedIn = false);
    }
  }

  void _setAuthenticated() {
    if (!mounted) return;
    setState(() => _loggedIn = true);
    _rescheduleSync();
    if (AppConfig.pushEnabled) {
      unawaited(PushService.registerAuthenticatedDevice());
    }
    unawaited(_recoverPendingSends());
    final pendingMailId = _pendingMailId;
    if (pendingMailId != null) {
      _pendingMailId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pushMailDetail(pendingMailId);
      });
    }
    _composeRouter.resolveAuth(true);
  }

  Future<void> _recoverPendingSends() async {
    try {
      await PendingSendQueue.instance.recoverPersisted();
      final ids = AppConfig.mailRepository.accounts
          .map((account) => account.id)
          .toSet();
      final items = await PendingSendQueue.instance.items();
      final attention = items
          .where(
            (item) =>
                ids.contains(item.send.fromAccountId) &&
                (item.status == OutboxStatus.failed ||
                    item.status == OutboxStatus.uncertain),
          )
          .length;
      if (attention == 0 || !mounted) return;
      final context = _navigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$attention gönderi Giden Kutusu’nda incelenmeyi bekliyor.',
          ),
          action: SnackBarAction(
            label: 'Aç',
            onPressed: () => _navigatorKey.currentState?.push(
              MaterialPageRoute(builder: (_) => const OutboxScreen()),
            ),
          ),
        ),
      );
    } catch (_) {
      final context = _navigatorKey.currentContext;
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Giden Kutusu açılamadı. Yeniden deneyin.'),
          ),
        );
      }
    }
  }

  void _onRepositoryChanged() {
    if (_loggedIn != true ||
        AppConfig.mailRepository.isLoggedIn ||
        _handlingLogout) {
      return;
    }
    _handlingLogout = true;
    _syncTimer?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _navigatorKey.currentState?.popUntil((route) => route.isFirst);
      setState(() {
        _loggedIn = false;
        _handlingLogout = false;
      });
    });
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
    unawaited(MailRulesEngine.runAfterSync(repo));
  }

  @override
  Widget build(BuildContext context) {
    if (_loggedIn == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _loggedIn!
        ? const BiometricLockGate(child: HomeScreen())
        : LoginScreen(onAuthenticated: _setAuthenticated);
  }
}
