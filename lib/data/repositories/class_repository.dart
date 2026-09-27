import '../api/api_client.dart';
import '../mock/student_mock_data.dart';

class ClassRepository {
  ClassRepository({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  // Đọc danh sách lớp từ API và chuyển từng bản ghi thành model ứng dụng.
  Future<List<StudentClassSummary>> getStudentClasses() async {
    final body = await _client.get('/api/classes');
    final items = body['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map(
          (item) =>
              StudentClassSummary.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }
}
