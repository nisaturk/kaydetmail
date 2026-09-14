import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'theme/app_theme.dart';

/// Root widget of the KAYDET application.
class KaydetApp extends StatelessWidget {
  const KaydetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KAYDET',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const LoginScreen(),
    );
  }
}