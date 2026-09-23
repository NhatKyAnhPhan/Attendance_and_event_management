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

  /// SplashPage chờ cờ này = true rồi mới điều hướng, để không bị
  /// "nháy" sang màn login trước khi đọc xong SharedPreferences.
  final RxBool isReady = false.obs;
  final AuthRepository _authRepository = AuthRepository();

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
    final savedUser = prefs.getString('currentUser');
    if (savedUser != null) {
      currentUser.value = Map<String, dynamic>.from(
        jsonDecode(savedUser) as Map,
      );
    }
    _authRepository.setToken(prefs.getString('authToken'));
    isReady.value = true;
  }

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
    currentUser.value = session.user;
    role.value = r;
    isAuthed.value = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('authToken', session.token);
    await prefs.setString('currentUser', jsonEncode(session.user));
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
    await prefs.remove('authToken');
    await prefs.remove('currentUser');
    _authRepository.setToken(null);
    Get.offAllNamed(AppRoutes.login);
  }
}
