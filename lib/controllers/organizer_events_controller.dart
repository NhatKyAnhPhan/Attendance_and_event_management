import 'package:get/get.dart';

import '../data/models/event_model.dart';
import '../data/repositories/event_repository.dart';

class OrganizerEventsController extends GetxController {
  OrganizerEventsController({EventRepository? repository})
    : _repository = repository ?? EventRepository();

  final EventRepository _repository;

  // Trạng thái được Obx theo dõi để cập nhật danh sách và biểu mẫu.
  final RxList<OrganizerEventSummary> items = <OrganizerEventSummary>[].obs;
  final RxList<OrganizerUnit> units = <OrganizerUnit>[].obs;
  final RxBool loading = false.obs;
  final RxBool unitsLoading = false.obs;
  final RxString error = ''.obs;
  final RxString unitsError = ''.obs;

  @override
  void onInit() {
    super.onInit();
    load();
    loadUnits();
  }

  // Nạp danh sách đơn vị cho biểu mẫu tạo hoặc sửa sự kiện.
  Future<void> loadUnits() async {
    unitsLoading.value = true;
    unitsError.value = '';
    try {
      units.assignAll(await _repository.getOrganizerUnits());
    } catch (exception) {
      unitsError.value = exception.toString();
    } finally {
      unitsLoading.value = false;
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

  // Gọi repository để tạo, sửa hoặc xóa rồi tải lại danh sách.
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
