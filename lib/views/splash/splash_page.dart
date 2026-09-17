import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/auth_controller.dart';
import '../../core/constants/role.dart';
import '../../core/routes/app_routes.dart';
import '../../core/theme/app_colors.dart';

/// Không có trang tương ứng bên React (App.tsx đọc state đồng bộ ngay khi
/// render), nhưng ở Flutter cần chờ SharedPreferences đọc xong (bất đồng bộ)
/// nên có SplashPage để tránh nháy màn hình sai.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();

    return Obx(() {
      if (auth.isReady.value) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!auth.isAuthed.value) {
            Get.offAllNamed(AppRoutes.login);
          } else if (auth.role.value == Role.student) {
            Get.offAllNamed(AppRoutes.studentHome);
          } else {
            Get.offAllNamed(AppRoutes.adminShell);
          }
        });
      }

      final isDark = Theme.of(context).brightness == Brightness.dark;
      final c = AppColors.of(isDark);
      return Scaffold(
        backgroundColor: c.background,
        body: Center(
          child: CircularProgressIndicator(color: c.primary),
        ),
      );
    });
  }
}