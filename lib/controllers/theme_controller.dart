import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tương ứng state `darkMode` + hàm `setDarkMode` trong App.tsx.
class ThemeController extends GetxController {
  static const _prefKey = 'isDarkMode';

  final RxBool isDark = false.obs;

  @override
  void onInit() {
    super.onInit();
    _loadFromPrefs();
  }

  // Đọc chế độ giao diện đã lưu và áp dụng ngay khi ứng dụng khởi động.
  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    isDark.value = prefs.getBool(_prefKey) ?? false;
    Get.changeThemeMode(isDark.value ? ThemeMode.dark : ThemeMode.light);
  }

  // Đổi chế độ sáng/tối, cập nhật giao diện và lưu lựa chọn của người dùng.
  Future<void> toggle() async {
    isDark.value = !isDark.value;
    Get.changeThemeMode(isDark.value ? ThemeMode.dark : ThemeMode.light);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, isDark.value);
  }
}