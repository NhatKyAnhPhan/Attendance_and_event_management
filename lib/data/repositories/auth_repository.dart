import '../api/api_client.dart';
import '../api/endpoints.dart';

class AuthSession {
  final String token;
  final String role;
  final Map<String, dynamic> user;

  const AuthSession({
    required this.token,
    required this.role,
    required this.user,
  });
}

class AuthRepository {
  AuthRepository({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  bool get isConfigured => _client.isConfigured;

  void setToken(String? token) => _client.setToken(token);

  /// Đọc hồ sơ hiện tại từ token đã xác thực để đồng bộ vai trò với backend.
  Future<Map<String, dynamic>> getCurrentUser() async {
    final body = await _client.get(ApiEndpoints.currentUser);
    final user = body['user'];
    if (user is! Map) {
      throw const ApiException('Phản hồi hồ sơ người dùng không hợp lệ.');
    }
    return Map<String, dynamic>.from(user);
  }

  // Gửi thông tin đăng nhập và chuyển phản hồi API thành AuthSession.
  Future<AuthSession> login({
    required String identifier,
    required String password,
  }) async {
    final body = await _client.post(
      ApiEndpoints.login,
      data: {'identifier': identifier, 'password': password},
    );
    final token = body['token']?.toString();
    final user = body['user'];
    final role = user is Map
        ? user['role']?.toString()
        : body['role']?.toString();
    if (token == null || role == null) {
      throw const ApiException('Phản hồi đăng nhập không hợp lệ.');
    }
    return AuthSession(
      token: token,
      role: role,
      user: user is Map ? Map<String, dynamic>.from(user) : <String, dynamic>{},
    );
  }

  Future<void> requestPasswordReset(String email) async {
    await _client.post(
      ApiEndpoints.requestPasswordReset,
      data: {'email': email.trim()},
    );
  }

  Future<String> verifyPasswordResetCode({
    required String email,
    required String code,
  }) async {
    final body = await _client.post(
      ApiEndpoints.verifyPasswordReset,
      data: {'email': email.trim(), 'code': code},
    );
    final resetToken = body['resetToken']?.toString();
    if (resetToken == null || resetToken.isEmpty) {
      throw const ApiException('Phản hồi xác nhận mã không hợp lệ.');
    }
    return resetToken;
  }

  Future<void> completePasswordReset({
    required String email,
    required String resetToken,
    required String newPassword,
  }) async {
    await _client.post(
      ApiEndpoints.completePasswordReset,
      data: {
        'email': email.trim(),
        'resetToken': resetToken,
        'newPassword': newPassword,
      },
    );
  }
}
