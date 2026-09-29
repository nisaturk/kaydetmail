import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../repositories/mail_repository.dart';
import '../services/api_exception.dart';
import '../services/session_store.dart';
import '../theme/app_theme.dart';
import '../utils/error_messages.dart';
import '../widgets/manual_mail_setup_dialog.dart';
import '../l10n/l10n.dart';

/// Account-connection flow: enter the address and password, connect through
/// [AppConfig.mailRepository].
class AddAccountScreen extends StatefulWidget {
  const AddAccountScreen({super.key});

  @override
  State<AddAccountScreen> createState() => _AddAccountScreenState();
}

class _AddAccountScreenState extends State<AddAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  var _connecting = false;
  String? _error;
  var _obscurePassword = true;
  var _autofillFinished = false;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    if (!_autofillFinished) {
      TextInput.finishAutofillContext(shouldSave: false);
    }
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _connect({MailServerSettings? serverSettings}) async {
    if (!_formKey.currentState!.validate() || _connecting) return;
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      final account = await AppConfig.mailRepository.connectAccount(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        serverSettings: serverSettings,
      );
      await SessionStore.addEmail(account.email);
      if (!mounted) return;
      _autofillFinished = true;
      TextInput.finishAutofillContext();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10nNow.connected(account.email))));
    } on ApiException catch (error) {
      if (!mounted) return;
      if (serverSettings == null &&
          error.code == 'mail_discovery_failed' &&
          error.details['manualSetupAvailable'] == true) {
        setState(() => _connecting = false);
        final settings = await ManualMailSetupDialog.show(
          context,
          email: _emailController.text.trim(),
        );
        if (settings != null && mounted) {
          await _connect(serverSettings: settings);
        }
        return;
      }
      setState(() {
        _connecting = false;
        _error = error.userMessage;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = error is ArgumentError
            ? '${error.message}'
            : friendlyErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(l10nNow.addNewAccount)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: AutofillGroup(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    key: const Key('new-email-field'),
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [
                      AutofillHints.email,
                      AutofillHints.username,
                    ],
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) return l10nNow.emailAddressIsRequired;
                      if (!_emailPattern.hasMatch(text)) {
                        return l10nNow.enterAValidEmailAddress2;
                      }
                      return null;
                    },
                    decoration: InputDecoration(
                      labelText: l10nNow.email,
                      prefixIcon: Icon(LucideIcons.mail, size: 20),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('new-password-field'),
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _connect(),
                    validator: (value) {
                      final text = value ?? '';
                      if (text.isEmpty) return l10nNow.passwordIsRequired;
                      return null;
                    },
                    decoration: InputDecoration(
                      labelText: l10nNow.password,
                      prefixIcon: const Icon(LucideIcons.lock, size: 20),
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword
                            ? l10nNow.showPassword
                            : l10nNow.hidePassword,
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        icon: Icon(
                          _obscurePassword
                              ? LucideIcons.eye
                              : LucideIcons.eyeOff,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.colors(context).destructive,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const Key('connect-button'),
                    onPressed: _connecting ? null : _connect,
                    child: _connecting
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                          )
                        : Text(l10nNow.connect),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
