import '../api/api_client.dart';
import '../api/endpoints.dart';
import '../models/class_model.dart';
import '../models/student_roster_entry.dart';
import '../models/student_summaries.dart';

class ClassRepository {
  ClassRepository({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  // Đọc danh sách lớp từ API và chuyển từng bản ghi thành model ứng dụng.
  Future<List<StudentClassSummary>> getStudentClasses() async {
    final body = await _client.get(ApiEndpoints.classes);
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

  Future<Map<String, dynamic>> getClassFeedback(String classId) {
    return _client.get('/api/classes/$classId/feedback');
  }

  Future<void> submitClassComment({
    required String classId,
    required String comment,
  }) async {
    await _client.post(
      '/api/classes/$classId/feedback',
      data: {'comment': comment},
    );
  }

  Future<void> submitClassRating({
    required String classId,
    required int rating,
    required String comment,
  }) async {
    await _client.post(
      '/api/classes/$classId/feedback',
      data: {'rating': rating, if (comment.isNotEmpty) 'comment': comment},
    );
  }

  Future<List<ClassModel>> getManagedClasses() async {
    final body = await _client.get(ApiEndpoints.adminClasses);
    final items = body['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((item) => ClassModel.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<List<StudentRosterEntry>> getClassStudents(String classId) async {
    final body = await _client.get(
      '${ApiEndpoints.adminClasses}/$classId/students',
    );
    final items = body['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map(
          (item) =>
              StudentRosterEntry.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<ClassStudentImportResult> importStudents({
    required String classId,
    required List<String> studentIds,
  }) async {
    final body = await _client.post(
      '${ApiEndpoints.adminClasses}/$classId/students/import',
      data: {'studentIds': studentIds},
    );
    return ClassStudentImportResult.fromJson(body);
  }

  Future<ClassOptions> getClassOptions() async {
    final body = await _client.get('/api/admin/class-options');
    final cohorts = body['cohorts'];
    final subjects = body['subjects'];
    return ClassOptions(
      cohorts: cohorts is List
          ? cohorts
                .whereType<Map>()
                .map(
                  (item) =>
                      ClassCohort.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList()
          : const [],
      subjects: subjects is List
          ? subjects
                .whereType<Map>()
                .map(
                  (item) => ClassSubjectOption.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList()
          : const [],
    );
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
    required String subjectId,
    required String cohortCode,
    required String semester,
    required String startTime,
    required String? lecturerId,
    required int capacity,
  }) async {
    await _client.post(
      ApiEndpoints.adminClasses,
      data: {
        'name': name,
        'subjectId': subjectId,
        'cohortCode': cohortCode,
        'semester': semester,
        'startTime': startTime,
        'lecturerId': lecturerId,
        'capacity': capacity,
      },
    );
  }

  Future<void> updateClass({
    required String id,
    required String name,
    required String semester,
    required String startTime,
    required String? lecturerId,
    required int capacity,
  }) async {
    await _client.put(
      '${ApiEndpoints.adminClasses}/$id',
      data: {
        'name': name,
        'semester': semester,
        'startTime': startTime,
        'lecturerId': lecturerId,
        'capacity': capacity,
      },
    );
  }

  Future<void> deleteClass(String id) async {
    await _client.delete('${ApiEndpoints.adminClasses}/$id');
  }

  Future<void> closeClass(String id) async {
    await _client.post('${ApiEndpoints.adminClasses}/$id/close');
  }
}
