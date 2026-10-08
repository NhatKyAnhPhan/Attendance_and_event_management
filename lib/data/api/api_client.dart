import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

String _resolveBaseUrl(String? baseUrl) {
  final configured = (baseUrl ?? const String.fromEnvironment('API_BASE_URL'))
      .trim();
  if (configured.isNotEmpty) return configured;
  return kIsWeb ? 'http://127.0.0.1:3000' : 'http://10.0.2.2:3000';
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final Map<String, dynamic>? data;
  const ApiException(this.message, {this.statusCode, this.data});

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({String? baseUrl})
    : _dio = Dio(
        BaseOptions(
          baseUrl: _resolveBaseUrl(baseUrl ?? _configuredBaseUrl),
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 10),
          headers: const {'Accept': 'application/json'},
        ),
      );

  final Dio _dio;
  static String? _sharedToken;
  static String? _configuredBaseUrl;
  static Future<void> Function()? onUnauthorized;

  static String get baseUrl => _resolveBaseUrl(_configuredBaseUrl);

  static void configureBaseUrl(String? baseUrl) {
    _configuredBaseUrl = baseUrl?.trim();
  }

  bool get isConfigured => _dio.options.baseUrl.isNotEmpty;

  // Cập nhật token dùng chung cho các yêu cầu HTTP tiếp theo.
  void setToken(String? token) {
    _sharedToken = token;
    if (token == null || token.isEmpty) {
      _dio.options.headers.remove('Authorization');
    } else {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    }
  }

  // Các phương thức HTTP dùng chung, tự gắn token và chuẩn hóa lỗi ở _request.
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? data,
    Duration? receiveTimeout,
  }) async {
    return _request(
      () => _dio.post<Map<String, dynamic>>(
        path,
        data: data,
        options: receiveTimeout == null
            ? null
            : Options(receiveTimeout: receiveTimeout),
      ),
    );
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

  Future<Map<String, dynamic>> postMultipart(String path, FormData data) async {
    return _request(() => _dio.post<Map<String, dynamic>>(path, data: data));
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
      if (error.response?.statusCode == 401 &&
          error.requestOptions.path != '/api/auth/login') {
        await onUnauthorized?.call();
      }
      final responseData = error.response?.data;
      final message = responseData is Map
          ? (responseData['message']?.toString() ?? 'Yêu cầu API thất bại.')
          : error.response == null
          ? 'Không thể kết nối tới máy chủ.'
          : 'Máy chủ trả về lỗi HTTP ${error.response?.statusCode}.';
      throw ApiException(
        message,
        statusCode: error.response?.statusCode,
        data: responseData is Map
            ? Map<String, dynamic>.from(responseData)
            : null,
      );
    }
  }
}
