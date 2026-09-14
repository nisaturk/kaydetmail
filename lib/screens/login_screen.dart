import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../repositories/mail_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/mail_avatar.dart';
import 'home_screen.dart';

/// Login screen with branding, credentials and simulated advanced server
/// settings. Authentication is mocked while `AppConfig.useMockApi` is true.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // Advanced server settings (simulated).
  final _imapServerController =
      TextEditingController(text: 'imap.example.com');
  final _imapPortController = TextEditingController(text: '993');
  final _smtpServerController =
      TextEditingController(text: 'smtp.example.com');
  final _smtpPortController = TextEditingController(text: '587');
  bool _useTls = true;

  bool _obscurePassword = true;
  bool _loading = false;
  bool _showAdvanced = false;

  static final RegExp _emailPattern =
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _imapServerController.dispose();
    _imapPortController.dispose();
    _smtpServerController.dispose();
    _smtpPortController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    final server = MailServerSettings(
      imapServer: _imapServerController.text.trim().isEmpty
          ? 'imap.example.com'
          : _imapServerController.text.trim(),
      imapPort: int.tryParse(_imapPortController.text.trim()) ?? 993,
      smtpServer: _smtpServerController.text.trim().isEmpty
          ? 'smtp.example.com'
          : _smtpServerController.text.trim(),
      smtpPort: int.tryParse(_smtpPortController.text.trim()) ?? 587,
      useTls: _useTls,
    );

    try {
      final ok = await AppConfig.mailRepository.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        serverSettings: server,
      );

      if (!mounted) return;

      if (ok) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      } else {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Login failed. Try again.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
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
                            'Your secure mail client',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppTheme.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (text.isEmpty) return 'Email is required';
                        if (!_emailPattern.hasMatch(text)) {
                          return 'Enter a valid email address';
                        }
                        return null;
                      },
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(LucideIcons.mail, size: 20),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _loading ? null : _login(),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Password is required';
                        }
                        if (value.length < 6) {
                          return 'Password must be at least 6 characters';
                        }
                        return null;
                      },
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(LucideIcons.lock, size: 20),
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                          icon: Icon(
                            _obscurePassword
                                ? LucideIcons.eye
                                : LucideIcons.eyeOff,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildAdvancedSettings(),
                    const SizedBox(height: 24),
                    FilledButton(
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
                          : const Text('Login'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAdvancedSettings() {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: _showAdvanced,
        onExpansionChanged: (open) => setState(() => _showAdvanced = open),
        shape: const Border(),
        collapsedShape: const Border(),
        title: const Text(
          'Advanced server settings',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
        leading: const Icon(LucideIcons.server, size: 20),
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _imapServerController,
                  decoration:
                      const InputDecoration(labelText: 'IMAP server', isDense: true),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 80,
                child: TextFormField(
                  controller: _imapPortController,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Port', isDense: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _smtpServerController,
                  decoration:
                      const InputDecoration(labelText: 'SMTP server', isDense: true),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 80,
                child: TextFormField(
                  controller: _smtpPortController,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Port', isDense: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Use SSL/TLS',
              style: TextStyle(fontSize: 14, color: Colors.black),
            ),
            value: _useTls,
            activeThumbColor: Colors.black,
            onChanged: (v) => setState(() => _useTls = v),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}