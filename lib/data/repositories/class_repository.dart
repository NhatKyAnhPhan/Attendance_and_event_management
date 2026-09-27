import '../api/api_client.dart';
import '../models/class_model.dart';
import '../models/student_summaries.dart';

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

  Future<List<ClassModel>> getManagedClasses() async {
    final body = await _client.get('/api/admin/classes');
    final items = body['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((item) => ClassModel.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<List<ClassLecturer>> getLecturers() async {
    final body = await _client.get('/api/admin/lecturers');
    final items = body['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((item) => ClassLecturer.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<void> createClass({
    required String name,
    required String semester,
    required String schoolYear,
    required String? lecturerId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    await _client.post(
      '/api/admin/classes',
      data: {
        'name': name,
        'semester': semester,
        'schoolYear': schoolYear,
        'lecturerId': lecturerId,
        'startDate': _dateOnly(startDate),
        'endDate': _dateOnly(endDate),
      },
    );
  }

  Future<void> updateClass({
    required String id,
    required String name,
    required String semester,
    required String schoolYear,
    required String? lecturerId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    await _client.put(
      '/api/admin/classes/$id',
      data: {
        'name': name,
        'semester': semester,
        'schoolYear': schoolYear,
        'lecturerId': lecturerId,
        'startDate': _dateOnly(startDate),
        'endDate': _dateOnly(endDate),
      },
    );
  }

  Future<void> deleteClass(String id) async {
    await _client.delete('/api/admin/classes/$id');
  }

  String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
