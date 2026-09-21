import 'package:flutter/material.dart';

import 'app.dart';
import 'config/app_config.dart';
import 'services/push_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KaydetApp());
  if (!AppConfig.pushEnabled) return;
  // Best-effort: without Firebase config files this no-ops and the app runs
  // push-free; with them, the device registers and foreground pushes route
  // through the API. Never throws, so no guard needed here.
  await PushService.initialize(AppConfig.mailRepository);
}
