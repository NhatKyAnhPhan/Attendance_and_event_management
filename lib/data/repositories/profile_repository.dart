import '../api/api_client.dart';

class ProfileRepository {
  ProfileRepository({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  Future<Map<String, dynamic>> updateContact({required String email}) async {
    final body = await _client.put('/api/me', data: {'email': email.trim()});
    final user = body['user'];
    if (user is! Map) {
      throw const ApiException('Phản hồi cập nhật hồ sơ không hợp lệ.');
    }
    return Map<String, dynamic>.from(user);
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _client.put(
      '/api/me?action=password',
      data: {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      },
    );
  }
}