import 'package:get/get.dart';

import '../data/models/event_model.dart';
import '../data/repositories/event_repository.dart';

class OrganizerEventsController extends GetxController {
  OrganizerEventsController({EventRepository? repository})
    : _repository = repository ?? EventRepository();

  final EventRepository _repository;
  final RxList<OrganizerEventSummary> items = <OrganizerEventSummary>[].obs;
  final RxList<OrganizerUnit> units = <OrganizerUnit>[].obs;
  final RxBool loading = false.obs;
  final RxString error = ''.obs;

  @override
  void onInit() {
    super.onInit();
    load();
    loadUnits();
  }

  Future<void> loadUnits() async {
    try {
      units.assignAll(await _repository.getOrganizerUnits());
    } catch (_) {
      units.clear();
    }
  }

  Future<void> load() async {
    loading.value = true;
    error.value = '';
    try {
      items.assignAll(await _repository.getOrganizerEvents());
    } catch (exception) {
      error.value = exception.toString();
    } finally {
      loading.value = false;
    }
  }

  Future<void> createEvent({
    required String id,
    required String name,
    required String organizerId,
    required DateTime startTime,
    required DateTime endTime,
    required String location,
    required int capacity,
  }) async {
    await _repository.createOrganizerEvent(
      id: id,
      name: name,
      organizerId: organizerId,
      startTime: startTime,
      endTime: endTime,
      location: location,
      capacity: capacity,
    );
    await load();
  }

  Future<void> updateEvent({
    required String id,
    required String name,
    required String organizerId,
    required DateTime startTime,
    required DateTime endTime,
    required String location,
    required int capacity,
  }) async {
    await _repository.updateOrganizerEvent(
      id: id,
      name: name,
      organizerId: organizerId,
      startTime: startTime,
      endTime: endTime,
      location: location,
      capacity: capacity,
    );
    await load();
  }

  Future<void> deleteEvent(String id) async {
    await _repository.deleteOrganizerEvent(id);
    await load();
  }
}
