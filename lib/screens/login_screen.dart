import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../services/session_store.dart';
import '../theme/app_theme.dart';
import '../widgets/mail_avatar.dart';
import 'home_screen.dart';

/// Two-step login: an email step that slides horizontally into a password
/// step and back. Step 1 shows branding plus only the email field; step 2
/// confirms the account being signed into and asks for the password.
///
/// Authentication is mocked while `AppConfig.useMockApi` is true.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

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

  bool _obscurePassword = true;
  bool _loading = false;
  int _page = _emailPage;

  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _pageController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
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
    _slideTo(_passwordPage);
  }

  void _back() {
    setState(() {
      _obscurePassword = true;
      _passwordController.clear();
    });
    _slideTo(_emailPage);
  }

  Future<void> _login() async {
    if (!_passwordFormKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      final ok = await AppConfig.mailRepository.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;

      if (ok) {
        await SessionStore.saveEmail(_emailController.text.trim());
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      } else {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Giriş başarısız. Tekrar deneyin.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Giriş başarısız: $e')));
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
          child: PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            children: [_buildEmailStep(), _buildPasswordStep()],
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
              const Center(
                child: Column(
                  children: [
                    MailAvatar(
                      identity: 'kaydet@app',
                      displayName: 'KAYDET',
                      size: 72,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'KAYDET',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: Colors.black,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'E-postalarınız için güvenli bir uygulama',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.secondaryText,
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
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
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
                      const Text(
                        'Şu hesapla oturum açıyorsunuz',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.secondaryText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        email,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
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
                  obscureText: _obscurePassword,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _loading ? null : _login(),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Şifre zorunludur';
                    }
                    if (value.length < 6) {
                      return 'Şifre en az 6 karakter olmalıdır';
                    }
                    return null;
                  },
                  decoration: InputDecoration(
                    labelText: 'Şifre',
                    prefixIcon: const Icon(LucideIcons.lock, size: 20),
                    suffixIcon: IconButton(
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
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Giriş Yap'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
