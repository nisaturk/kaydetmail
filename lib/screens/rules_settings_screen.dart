import 'package:flutter/material.dart';

/// CRUD for client-side mail rules ("gönderen X -> klasöre taşı / etiketle")
/// evaluated by `MailRulesEngine`. Purely client-side, same rationale as
/// labels — no backend endpoint exists for this.
///
/// Placeholder: real rule-management UI lands in a follow-up change.
class RulesSettingsScreen extends StatelessWidget {
  const RulesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kurallar')),
      body: const Center(child: Text('Yakında')),
    );
  }
}
