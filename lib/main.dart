import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'controllers/auth_controller.dart';
import 'controllers/notification_controller.dart';
import 'controllers/push_notification_service.dart';
import 'controllers/theme_controller.dart';
import 'data/api/api_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (defaultTargetPlatform != TargetPlatform.linux) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  final prefs = await SharedPreferences.getInstance();
  var apiBaseUrl = prefs.getString('apiBaseUrl');
  const buildApiBaseUrl = String.fromEnvironment('API_BASE_URL');
  if (isLocalApiBaseUrl(apiBaseUrl)) {
    apiBaseUrl = buildApiBaseUrl.trim().isNotEmpty
        ? buildApiBaseUrl.trim()
        : productionApiBaseUrl;
    await prefs.setString('apiBaseUrl', apiBaseUrl);
  } else if (apiBaseUrl == 'http://127.0.0.1:3001' ||
      apiBaseUrl == 'http://10.0.2.2:3001') {
    apiBaseUrl = apiBaseUrl!.replaceFirst(':3001', ':3000');
    await prefs.setString('apiBaseUrl', apiBaseUrl);
  }
  ApiClient.configureBaseUrl(apiBaseUrl);

  // Controller nền tảng, cần có trước khi bất kỳ trang nào build.
  Get.put(ThemeController());
  final authController = Get.put(AuthController());
  ApiClient.onUnauthorized = authController.handleUnauthorized;
  Get.put(NotificationController());
  Get.put(PushNotificationService());

  runApp(const App());
}
