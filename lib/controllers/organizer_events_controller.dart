import 'package:get/get.dart';

import 'dart:async';

import '../data/models/event_model.dart';
import '../data/models/student_roster_entry.dart';
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
  final RxInt statusRefreshTick = 0.obs;
  Timer? _statusRefreshTimer;

  // Khởi tạo bộ đếm cập nhật trạng thái và tải dữ liệu màn hình.
  @override
  void onInit() {
    super.onInit();
    load();
    loadUnits();
    _statusRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      statusRefreshTick.value++;
      load();
    });
  }

  // Dừng bộ đếm khi controller không còn được sử dụng.
  @override
  void onClose() {
    _statusRefreshTimer?.cancel();
    super.onClose();
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

  // Tải danh sách sự kiện dành cho khu vực ban tổ chức.
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

  /// Lấy thông tin đầy đủ của sự kiện để hiển thị ở hộp thoại chi tiết.
  Future<Map<String, dynamic>> getEventDetails(String eventId) {
    return _repository.getEventDetails(eventId);
  }

  Future<List<StudentRosterEntry>> getEventStudents(String eventId) {
    return _repository.getEventStudents(eventId);
  }

  Future<EventStudentImportResult> importEventStudents({
    required String eventId,
    required List<String> studentIds,
  }) {
    return _repository.importEventStudents(
      eventId: eventId,
      studentIds: studentIds,
    );
  }

  // Gọi repository để tạo, sửa hoặc xóa rồi tải lại danh sách.
  Future<void> createEvent({
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
    await _repository.createOrganizerEvent(
      name: name,
      organizerId: organizerId,
      startTime: startTime,
      endTime: endTime,
      location: location,
      capacity: capacity,
      description: description,
      benefits: benefits,
      rules: rules,
    );
    await load();
  }

  // Gửi dữ liệu chỉnh sửa và tải lại danh sách sự kiện.
  Future<void> updateEvent({
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
    await _repository.updateOrganizerEvent(
      id: id,
      name: name,
      organizerId: organizerId,
      startTime: startTime,
      endTime: endTime,
      location: location,
      capacity: capacity,
      description: description,
      benefits: benefits,
      rules: rules,
    );
    await load();
  }

  // Xóa sự kiện rồi đồng bộ lại danh sách đang hiển thị.
  Future<void> deleteEvent(String id) async {
    await _repository.deleteOrganizerEvent(id);
    await load();
  }

  Future<void> closeEvent(String id) async {
    await _repository.closeOrganizerEvent(id);
    await load();
  }

  Future<Map<String, dynamic>> createAttendanceQr(
    String eventId, {
    required double latitude,
    required double longitude,
  }) {
    return _repository.createEventAttendanceQr(
      eventId,
      latitude: latitude,
      longitude: longitude,
    );
  }

  Future<void> closeAttendanceSession(String eventId, String sessionId) {
    return _repository.closeEventAttendanceSession(eventId, sessionId);
  }

  Future<Map<String, dynamic>> sendCertificates(String eventId) {
    return _repository.sendEventCertificates(eventId);
  }
}
