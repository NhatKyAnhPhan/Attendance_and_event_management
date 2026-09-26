import 'package:get/get.dart';

import '../data/mock/student_mock_data.dart';
import '../data/repositories/event_repository.dart';

class EventsController extends GetxController {
  final EventRepository _repository = EventRepository();
  final RxList<StudentEventSummary> items = <StudentEventSummary>[].obs;
  final RxBool loading = false.obs;
  final RxString error = ''.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    loading.value = true;
    error.value = '';
    try {
      items.assignAll(await _repository.getEvents());
    } catch (exception) {
      error.value = exception.toString();
    } finally {
      loading.value = false;
    }
  }

  Future<void> register(String eventId) async {
    await _repository.register(eventId);
    await load();
  }

  Future<Map<String, dynamic>> getDetails(String eventId) {
    return _repository.getEventDetails(eventId);
  }
}
