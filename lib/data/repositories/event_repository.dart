import '../api/api_client.dart';
import '../api/endpoints.dart';
import '../models/event_model.dart';
import '../models/student_roster_entry.dart';
import '../models/student_summaries.dart';

class EventRepository {
  EventRepository({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  // Lấy danh sách sự kiện sinh viên có thể xem hoặc đăng ký.
  Future<List<StudentEventSummary>> getEvents() async {
    final body = await _client.get('/api/events');
    final items = body['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map(
          (item) =>
              StudentEventSummary.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  // Lấy dữ liệu chi tiết của sự kiện theo mã định danh.
  Future<Map<String, dynamic>> getEventDetails(String eventId) async {
    return _client.get('/api/events/$eventId');
  }

  Future<List<StudentRosterEntry>> getEventStudents(String eventId) async {
    final body = await _client.get('/api/organizer/events/$eventId/students');
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

  // Gửi yêu cầu đăng ký và trạng thái xác nhận trùng lịch học.
  Future<void> register(
    String eventId, {
    bool allowClassConflict = false,
  }) async {
    await _client.post(
      '/api/events/$eventId/register',
      data: {'allowClassConflict': allowClassConflict},
    );
  }

  // Gửi yêu cầu hủy đăng ký sự kiện.
  Future<void> cancelRegistration(String eventId) async {
    await _client.delete('/api/events/$eventId/register');
  }

  Future<Map<String, dynamic>> getEventFeedback(String eventId) {
    return _client.get('/api/events/$eventId/feedback');
  }

  Future<Map<String, dynamic>> getMyFeedback() {
    return _client.get('/api/student/my-feedback');
  }

  Future<void> submitEventComment({
    required String eventId,
    required String comment,
  }) async {
    await _client.post(
      '/api/events/$eventId/feedback',
      data: {'comment': comment},
    );
  }

  Future<void> submitEventRating({
    required String eventId,
    required int rating,
    required String comment,
  }) async {
    await _client.post(
      '/api/events/$eventId/feedback',
      data: {'rating': rating, if (comment.isNotEmpty) 'comment': comment},
    );
  }

  // Các yêu cầu đọc và ghi sự kiện trong khu vực ban tổ chức.
  Future<List<OrganizerEventSummary>> getOrganizerEvents() async {
    final body = await _client.get('/api/organizer/events');
    final items = body['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map(
          (item) =>
              OrganizerEventSummary.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  // Tải các đơn vị để làm dữ liệu lựa chọn khi tạo hoặc sửa sự kiện.
  Future<List<OrganizerUnit>> getOrganizerUnits() async {
    final body = await _client.get('/api/organizer/units');
    final items = body['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((item) => OrganizerUnit.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  // Tạo sự kiện mới bằng dữ liệu từ biểu mẫu ban tổ chức.
  Future<void> createOrganizerEvent({
    required String name,
    required String organizerId,
    required DateTime startTime,
    required DateTime endTime,
    required String location,
    required int capacity,
    required String description,
    required List<Map<String, dynamic>> benefits,
    required List<String> rules,
  }) async {
    await _client.post(
      '/api/organizer/events',
      data: {
        'name': name,
        'organizerId': organizerId,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'location': location,
        'capacity': capacity,
        'description': description,
        'benefits': benefits,
        'rules': rules,
      },
    );
  }

  // Cập nhật sự kiện hiện có bằng dữ liệu mới từ biểu mẫu.
  Future<void> updateOrganizerEvent({
    required String id,
    required String name,
    required String organizerId,
    required DateTime startTime,
    required DateTime endTime,
    required String location,
    required int capacity,
    required String description,
    required List<Map<String, dynamic>> benefits,
    required List<String> rules,
  }) async {
    await _client.put(
      '/api/organizer/events/$id',
      data: {
        'name': name,
        'organizerId': organizerId,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'location': location,
        'capacity': capacity,
        'description': description,
        'benefits': benefits,
        'rules': rules,
      },
    );
  }

  // Xóa sự kiện theo mã định danh.
  Future<void> deleteOrganizerEvent(String id) async {
    await _client.delete('/api/organizer/events/$id');
  }

  Future<void> closeOrganizerEvent(String id) async {
    await _client.post('/api/organizer/events/$id/close');
  }

  Future<String> createEventAttendanceQr(String eventId) async {
    final body = await _client.post(ApiEndpoints.eventAttendanceQr(eventId));
    final qr = body['qr']?.toString();
    if (qr == null || qr.isEmpty) {
      throw const FormatException('Máy chủ không trả về mã QR sự kiện.');
    }
    return qr;
  }

  Future<Map<String, dynamic>> sendEventCertificates(String eventId) {
    return _client.post(
      ApiEndpoints.sendEventCertificates(eventId),
      receiveTimeout: const Duration(minutes: 10),
    );
  }
}
