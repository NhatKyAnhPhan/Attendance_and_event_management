import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'controllers/auth_controller.dart';
import 'controllers/notification_controller.dart';
import 'controllers/theme_controller.dart';
import 'data/api/api_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  var apiBaseUrl = prefs.getString('apiBaseUrl');
  if (apiBaseUrl == 'http://127.0.0.1:3001' ||
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

  runApp(const App());
}
