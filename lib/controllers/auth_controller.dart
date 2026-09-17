import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/role.dart';
import '../core/routes/app_routes.dart';

/// Tương ứng state `authed` + `role` + hàm `handleLogin`/`handleLogout` trong App.tsx.
class AuthController extends GetxController {
  static const _authKey = 'isAuthed';
  static const _roleKey = 'currentRole';

  final RxBool isAuthed = false.obs;
  final Rx<Role> role = Role.admin.obs;

  /// SplashPage chờ cờ này = true rồi mới điều hướng, để không bị
  /// "nháy" sang màn login trước khi đọc xong SharedPreferences.
  final RxBool isReady = false.obs;

  @override
  void onInit() {
    super.onInit();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    isAuthed.value = prefs.getBool(_authKey) ?? false;
    final savedRole = prefs.getString(_roleKey);
    if (savedRole != null) role.value = RoleX.fromString(savedRole);
    isReady.value = true;
  }

  /// Gọi khi đăng nhập thành công — TODO: thay bằng gọi AuthRepository thật
  /// khi có API, hiện tại chỉ set role như trong AuthPage.tsx (demo).
  Future<void> login(Role r) async {
    role.value = r;
    isAuthed.value = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_authKey, true);
    await prefs.setString(_roleKey, r.name);
    Get.offAllNamed(
      r == Role.student ? AppRoutes.studentHome : AppRoutes.adminShell,
    );
  }

  Future<void> logout() async {
    isAuthed.value = false;
    role.value = Role.admin;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_authKey);
    await prefs.remove(_roleKey);
    Get.offAllNamed(AppRoutes.login);
  }
}