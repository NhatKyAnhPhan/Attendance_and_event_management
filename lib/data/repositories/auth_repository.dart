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
}
