import 'package:flutter/material.dart';

import 'app.dart';
import 'config/app_config.dart';
import 'services/firebase_monitoring.dart';
import 'services/push_service.dart';
import 'state/app_settings_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseMonitoring.initialize();
  await AppSettingsController.instance.loadThemeMode();
  runApp(const KaydetApp());
  if (!AppConfig.pushEnabled || !PushService.isSupportedPlatform) return;
  // Best-effort: without Firebase config files this no-ops and the app runs
  // push-free; with them, the device registers and foreground pushes route
  // through the API. Never throws, so no guard needed here.
  await PushService.initialize(AppConfig.mailRepository);
}
