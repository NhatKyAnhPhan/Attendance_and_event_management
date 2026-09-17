import 'package:get/get.dart';
import 'app_routes.dart';
import '../../views/splash/splash_page.dart';
import '../../views/shared/placeholder_page.dart';
import '../../views/auth/auth_page.dart';

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
      page: () => const PlaceholderPage(title: 'Trang sinh viên'),
    ),
    GetPage(
      name: AppRoutes.adminShell,
      page: () => const PlaceholderPage(title: 'Trang quản trị'),
    ),
  ];
}