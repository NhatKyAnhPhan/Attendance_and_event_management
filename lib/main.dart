import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'app.dart';
import 'controllers/auth_controller.dart';
import 'controllers/theme_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Controller nền tảng, cần có trước khi bất kỳ trang nào build.
  Get.put(ThemeController());
  Get.put(AuthController());

  runApp(const App());
}