import '../api/api_client.dart';
import '../models/event_model.dart';
import '../mock/student_mock_data.dart';

class EventRepository {
  EventRepository({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

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

  Future<void> register(String eventId) async {
    await _client.post('/api/events/$eventId/register');
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

  Future<List<OrganizerUnit>> getOrganizerUnits() async {
    final body = await _client.get('/api/organizer/units');
    final items = body['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((item) => OrganizerUnit.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<void> createOrganizerEvent({
    required String id,
    required String name,
    required String organizerId,
    required DateTime startTime,
    required DateTime endTime,
    required String location,
    required int capacity,
  }) async {
    await _client.post(
      '/api/organizer/events',
      data: {
        'id': id,
        'name': name,
        'organizerId': organizerId,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'location': location,
        'capacity': capacity,
      },
    );
  }

  Future<void> updateOrganizerEvent({
    required String id,
    required String name,
    required String organizerId,
    required DateTime startTime,
    required DateTime endTime,
    required String location,
    required int capacity,
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
      },
    );
  }

  Future<void> deleteOrganizerEvent(String id) async {
    await _client.delete('/api/organizer/events/$id');
  }
}
