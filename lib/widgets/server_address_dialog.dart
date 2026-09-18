import 'package:flutter/material.dart';

import '../state/app_settings_controller.dart';

/// Dialog to view/edit the API base URL, shared by the login screen (so it's
/// reachable before an account exists) and the settings screen.
class ServerAddressDialog extends StatefulWidget {
  const ServerAddressDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const ServerAddressDialog(),
  );

  @override
  State<ServerAddressDialog> createState() => _ServerAddressDialogState();
}

class _ServerAddressDialogState extends State<ServerAddressDialog> {
  late final TextEditingController _controller;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: AppSettingsController.instance.serverBaseUrl,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AppSettingsController.instance.setServerAddress(_controller.text);
      if (mounted) Navigator.of(context).pop();
    } on ArgumentError catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sunucu adresi'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          labelText: 'Adres',
          hintText: 'http://192.168.1.100:8080',
          errorText: _error,
          errorMaxLines: 2,
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(onPressed: _save, child: const Text('Kaydet')),
      ],
    );
  }
}
