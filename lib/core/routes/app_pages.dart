import 'package:get/get.dart';
import 'app_routes.dart';
import '../../views/splash/splash_page.dart';
import '../../views/auth/auth_page.dart';
import '../../views/student/student_home_page.dart';
import '../../views/admin_shell/admin_shell_page.dart';

/// TODO: thay dần các PlaceholderPage bằng trang thật theo lộ trình
/// (login → student flow → admin shell).
class AppPages {
  AppPages._();

  static final pages = [
    GetPage(name: AppRoutes.splash, page: () => const SplashPage()),
    GetPage(
      name: AppRoutes.login,
      page: () => const AuthPage(),
    ),
    GetPage(
      name: AppRoutes.studentHome,
      page: () => const StudentHomePage(),
    ),
    GetPage(
      name: AppRoutes.adminShell,
      page: () => const AdminShellPage(),
    ),
  ];
}