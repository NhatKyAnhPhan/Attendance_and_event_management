import '../api/api_client.dart';
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
}
