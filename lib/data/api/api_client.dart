import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

String _resolveBaseUrl(String? baseUrl) {
  final configured = (baseUrl ?? const String.fromEnvironment('API_BASE_URL'))
      .trim();
  if (configured.isNotEmpty) return configured;
  return kIsWeb ? 'http://127.0.0.1:3000' : '';
}

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({String? baseUrl})
    : _dio = Dio(
        BaseOptions(
          baseUrl: _resolveBaseUrl(baseUrl),
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 10),
          headers: const {'Accept': 'application/json'},
        ),
      );

  final Dio _dio;
  static String? _sharedToken;

  bool get isConfigured => _dio.options.baseUrl.isNotEmpty;

  void setToken(String? token) {
    _sharedToken = token;
    if (token == null || token.isEmpty) {
      _dio.options.headers.remove('Authorization');
    } else {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    }
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    return _request(() => _dio.post<Map<String, dynamic>>(path, data: data));
  }

  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    return _request(() => _dio.put<Map<String, dynamic>>(path, data: data));
  }

  Future<Map<String, dynamic>> get(String path) async {
    return _request(() => _dio.get<Map<String, dynamic>>(path));
  }

  Future<Map<String, dynamic>> delete(String path) async {
    return _request(() => _dio.delete<Map<String, dynamic>>(path));
  }

  Future<Map<String, dynamic>> _request(
    Future<Response<Map<String, dynamic>>> Function() call,
  ) async {
    if (!isConfigured) {
      throw const ApiException('Chưa cấu hình API_BASE_URL.');
    }

    try {
      if (_sharedToken != null && _sharedToken!.isNotEmpty) {
        _dio.options.headers['Authorization'] = 'Bearer $_sharedToken';
      }
      final response = await call();
      final body = response.data;
      if (body == null) throw const ApiException('API trả về dữ liệu rỗng.');
      return body;
    } on DioException catch (error) {
      final responseData = error.response?.data;
      final message = responseData is Map
          ? (responseData['message']?.toString() ?? 'Yêu cầu API thất bại.')
          : 'Không thể kết nối tới máy chủ.';
      throw ApiException(message);
    }
  }
}
