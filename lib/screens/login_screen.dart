import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../repositories/mail_repository.dart';
import '../services/api_exception.dart';
import '../services/session_store.dart';
import '../theme/app_theme.dart';
import '../widgets/mail_avatar.dart';
import '../widgets/manual_mail_setup_dialog.dart';
import '../widgets/server_address_dialog.dart';

/// Two-step login: an email step that slides horizontally into a password
/// step and back. Step 1 shows branding plus only the email field; step 2
/// confirms the account being signed into and asks for the password.
///
/// Reconnect mode (`reconnect: true` with [initialEmail]) reuses the same
/// password step to repair stale credentials (`POST /api/account/reconnect`)
/// instead of signing in — the session survives, only the password is
/// replaced. The login flow itself switches to this mode when the server
/// reports `mail_account_needs_reauthentication`/`credential_missing`.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.reconnect = false,
    this.initialEmail,
    this.onAuthenticated,
  });

  /// When true, the screen opens directly on the password step and submits
  /// to `MailRepository.reconnect` instead of `login`.
  final bool reconnect;

  /// Prefilled account address for reconnect mode.
  final String? initialEmail;

  /// Lets the persistent app-level auth coordinator reveal the mailbox
  /// without replacing the route that owns sync and push subscriptions.
  final VoidCallback? onAuthenticated;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const int _emailPage = 0;
  static const int _passwordPage = 1;

  final _emailFormKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();
  final _pageController = PageController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _obscurePassword = true;
  bool _loading = false;
  int _page = _emailPage;
  bool _reconnect = false;
  bool _autofillFinished = false;

  @override
  void initState() {
    super.initState();
    _reconnect = widget.reconnect;
    final initialEmail = widget.initialEmail?.trim() ?? '';
    if (_reconnect && initialEmail.isNotEmpty) {
      _emailController.text = initialEmail;
      _page = _passwordPage;
      // The PageView builds on the email page; slide over once laid out.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(_passwordPage);
        }
        if (mounted) _passwordFocus.requestFocus();
      });
    }
  }

  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    if (!_autofillFinished) {
      TextInput.finishAutofillContext(shouldSave: false);
    }
    _pageController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _slideTo(int page) {
    setState(() => _page = page);
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOut,
    );
  }

  void _continue() {
    if (!_emailFormKey.currentState!.validate()) return;
    // The password page's field is already mounted (PageView builds both
    // children up front); without an explicit handoff its autofocus loses
    // to the still-focused email field and keystrokes land in the wrong
    // controller.
    _emailFocus.unfocus();
    _slideTo(_passwordPage);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _passwordFocus.requestFocus();
    });
  }

  void _back() {
    _passwordFocus.unfocus();
    setState(() {
      _obscurePassword = true;
      _passwordController.clear();
    });
    _slideTo(_emailPage);
  }

  Future<void> _login({MailServerSettings? serverSettings}) async {
    if (!_passwordFormKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      if (_reconnect) {
        await AppConfig.mailRepository.reconnect(
          password: _passwordController.text,
        );
        if (!mounted) return;
        _autofillFinished = true;
        TextInput.finishAutofillContext();
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hesap yeniden bağlandı.')),
        );
        widget.onAuthenticated?.call();
        return;
      }
      final ok = await AppConfig.mailRepository.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        serverSettings: serverSettings,
      );

      if (!mounted) return;

      if (ok) {
        await SessionStore.addEmail(_emailController.text.trim());
        if (!mounted) return;
        _autofillFinished = true;
        TextInput.finishAutofillContext();
        widget.onAuthenticated?.call();
      } else {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Giriş başarısız. Tekrar deneyin.')),
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      // The account exists but its stored credentials stopped working —
      // stay on this screen and switch it into reconnect mode instead of a
      // dead-end error (reconnect is Bearer-authenticated, login is not).
      if (!(_reconnect) &&
          (e.code == 'mail_account_needs_reauthentication' ||
              e.code == 'credential_missing')) {
        setState(() {
          _loading = false;
          _reconnect = true;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.userMessage)));
        return;
      }
      // Automatic discovery couldn't find the IMAP/SMTP servers for this
      // domain — offer manual entry instead of a dead-end error.
      if (e.code == 'mail_discovery_failed' &&
          e.details['manualSetupAvailable'] == true) {
        setState(() => _loading = false);
        final settings = await ManualMailSetupDialog.show(
          context,
          email: _emailController.text.trim(),
        );
        if (settings != null && mounted) {
          await _login(serverSettings: settings);
        }
        return;
      }
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.userMessage)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Giriş başarısız. Tekrar deneyin.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // On the password step the system back gesture slides to the email step
      // instead of exiting the app; on the email step it behaves normally.
      canPop: _page == _emailPage && !_loading,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_loading) _back();
      },
      child: Scaffold(
        body: SafeArea(
          child: AutofillGroup(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [_buildEmailStep(), _buildPasswordStep()],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailStep() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  key: const Key('server-address-button'),
                  onPressed: () => ServerAddressDialog.show(context),
                  tooltip: 'Sunucu adresi',
                  icon: const Icon(LucideIcons.settings, size: 20),
                ),
              ),
              Center(
                child: Column(
                  children: [
                    const MailAvatar(
                      identity: 'kaydet@app',
                      displayName: 'KAYDET',
                      size: 72,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'KAYDET',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'E-postalarınız için güvenli bir uygulama',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.colors(context).secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              Form(
                key: _emailFormKey,
                child: TextFormField(
                  key: const Key('email-field'),
                  controller: _emailController,
                  focusNode: _emailFocus,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [
                    AutofillHints.email,
                    AutofillHints.username,
                  ],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _continue(),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) return 'E-posta adresi zorunludur';
                    if (!_emailPattern.hasMatch(text)) {
                      return 'Geçerli bir e-posta adresi girin';
                    }
                    return null;
                  },
                  decoration: const InputDecoration(
                    labelText: 'E-posta',
                    prefixIcon: Icon(LucideIcons.mail, size: 20),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                key: const Key('continue-button'),
                onPressed: _continue,
                child: const Text('Devam'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordStep() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  key: const Key('back-button'),
                  onPressed: _loading ? null : _back,
                  tooltip: 'Geri',
                  icon: const Icon(LucideIcons.arrowLeft, size: 22),
                ),
              ),
              const SizedBox(height: 8),
              ListenableBuilder(
                listenable: _emailController,
                builder: (context, _) {
                  final email = _emailController.text.trim();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _reconnect
                            ? 'Şu hesabı yeniden bağlıyorsunuz'
                            : 'Şu hesapla oturum açıyorsunuz',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.colors(context).secondaryText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        email,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  );
                },
              ),
              Form(
                key: _passwordFormKey,
                child: TextFormField(
                  key: const Key('password-field'),
                  controller: _passwordController,
                  focusNode: _passwordFocus,
                  obscureText: _obscurePassword,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _loading ? null : _login(),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Şifre zorunludur';
                    }
                    return null;
                  },
                  decoration: InputDecoration(
                    labelText: 'Şifre',
                    prefixIcon: const Icon(LucideIcons.lock, size: 20),
                    suffixIcon: IconButton(
                      tooltip: _obscurePassword
                          ? 'Şifreyi göster'
                          : 'Şifreyi gizle',
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      icon: Icon(
                        _obscurePassword ? LucideIcons.eye : LucideIcons.eyeOff,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                key: const Key('signin-button'),
                onPressed: _loading ? null : _login,
                child: _loading
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      )
                    : Text(_reconnect ? 'Yeniden Bağlan' : 'Giriş Yap'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
