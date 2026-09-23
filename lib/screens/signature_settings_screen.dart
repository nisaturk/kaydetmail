import 'package:flutter/material.dart';

/// Per-account email signature, auto-inserted into new/reply/forward
/// compose bodies. Purely client-side (see `SignatureStore`) — no backend
/// endpoint exists for this, same as labels.
///
/// Placeholder: real signature editing UI lands in a follow-up change.
class SignatureSettingsScreen extends StatelessWidget {
  const SignatureSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('İmza')),
      body: const Center(child: Text('Yakında')),
    );
  }
}
