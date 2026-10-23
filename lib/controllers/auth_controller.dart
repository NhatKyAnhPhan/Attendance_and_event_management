import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:convert';

import '../core/constants/role.dart';
import '../core/routes/app_routes.dart';
import '../data/api/api_client.dart';
import '../data/repositories/auth_repository.dart';

/// Tương ứng state `authed` + `role` + hàm `handleLogin`/`handleLogout` trong App.tsx.
class AuthController extends GetxController {
  static const _authKey = 'isAuthed';
  static const _roleKey = 'currentRole';

  final RxBool isAuthed = false.obs;
  final Rx<Role> role = Role.admin.obs;
  final Rxn<Map<String, dynamic>> currentUser = Rxn<Map<String, dynamic>>();

  /// Quyền quản lý cụ thể của từng đơn vị được backend xác thực.
  bool get canManageEvents =>
      RoleX.canManageEvents(currentUser.value?['role']?.toString() ?? '');

  /// SplashPage chờ cờ này = true rồi mới điều hướng, để không bị
  /// "nháy" sang màn login trước khi đọc xong SharedPreferences.
  final RxBool isReady = false.obs;
  final AuthRepository _authRepository = AuthRepository();

  Future<void> requestPasswordReset(String email) =>
      _authRepository.requestPasswordReset(email);

  Future<String> verifyPasswordResetCode({
    required String email,
    required String code,
  }) => _authRepository.verifyPasswordResetCode(email: email, code: code);

  Future<void> completePasswordReset({
    required String email,
    required String resetToken,
    required String newPassword,
  }) => _authRepository.completePasswordReset(
    email: email,
    resetToken: resetToken,
    newPassword: newPassword,
  );

  @override
  void onInit() {
    super.onInit();
    _restoreSession();
  }

  /// Khôi phục token rồi đồng bộ người dùng và quyền từ API trước khi mở shell.
  Future<void> _restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    isAuthed.value = prefs.getBool(_authKey) ?? false;
    final savedRole = prefs.getString(_roleKey);
    if (savedRole != null) role.value = RoleX.fromString(savedRole);
    final savedUser = prefs.getString('currentUser');
    if (savedUser != null) {
      currentUser.value = Map<String, dynamic>.from(
        jsonDecode(savedUser) as Map,
      );
    }
    final token = prefs.getString('authToken');
    _authRepository.setToken(token);
    if (isAuthed.value && token != null && token.isNotEmpty) {
      try {
        final user = await _authRepository.getCurrentUser();
        final roleValue = user['role']?.toString();
        if (roleValue != null && roleValue.isNotEmpty) {
          final restoredRole = RoleX.fromString(roleValue);
          currentUser.value = user;
          role.value = restoredRole;
          await prefs.setString('currentUser', jsonEncode(user));
          await prefs.setString('currentRole', restoredRole.name);
        }
      } on ApiException catch (error) {
        if (error.statusCode == 401) {
          isAuthed.value = false;
          currentUser.value = null;
          await prefs.remove(_authKey);
          await prefs.remove(_roleKey);
          await prefs.remove('authToken');
          await prefs.remove('currentUser');
          _authRepository.setToken(null);
        }
      }
    }
    isReady.value = true;
  }

  // Gửi thông tin đăng nhập, lưu phiên và điều hướng theo vai trò người dùng.
  Future<void> login({
    required String identifier,
    required String password,
  }) async {
    if (!_authRepository.isConfigured) {
      throw const ApiException('Chưa cấu hình API_BASE_URL.');
    }
    final session = await _authRepository.login(
      identifier: identifier,
      password: password,
    );
    final r = RoleX.fromString(session.role);
    _authRepository.setToken(session.token);
    var user = session.user;
    try {
      user = await _authRepository.getCurrentUser();
    } on ApiException catch (_) {
      // Hồ sơ đăng nhập vẫn là dữ liệu API hợp lệ nếu endpoint hồ sơ tạm lỗi.
    }
    currentUser.value = user;
    role.value = r;
    isAuthed.value = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('authToken', session.token);
    await prefs.setString('currentUser', jsonEncode(user));
    await prefs.setBool(_authKey, true);
    await prefs.setString(_roleKey, r.name);
    Get.offAllNamed(
      r == Role.student ? AppRoutes.studentHome : AppRoutes.adminShell,
    );
  }

  // Xóa toàn bộ dữ liệu phiên hiện tại rồi đưa người dùng về màn đăng nhập.
  Future<void> logout() async {
    isAuthed.value = false;
    role.value = Role.admin;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_authKey);
    await prefs.remove(_roleKey);
    await prefs.remove('authToken');
    await prefs.remove('currentUser');
    _authRepository.setToken(null);
    Get.offAllNamed(AppRoutes.login);
  }

  /// Xóa phiên hiện tại nếu API xác nhận token đã hết hạn.
  Future<void> handleUnauthorized() async {
    if (!isAuthed.value) return;
    await logout();
  }
}
