import 'dart:async';

import 'package:get/get.dart';

import '../data/models/student_summaries.dart';
import '../data/repositories/event_repository.dart';

class EventsController extends GetxController {
  final EventRepository _repository = EventRepository();
  final RxList<StudentEventSummary> items = <StudentEventSummary>[].obs;
  final RxBool loading = false.obs;
  final RxString error = ''.obs;
  final RxInt statusRefreshTick = 0.obs;
  Timer? _statusRefreshTimer;

  @override
  void onInit() {
    super.onInit();
    load();
    _statusRefreshTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => statusRefreshTick.value++,
    );
  }

  @override
  void onClose() {
    _statusRefreshTimer?.cancel();
    super.onClose();
  }

  // Tải danh sách sự kiện và phản ánh kết quả vào state của màn hình.
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

  // Đăng ký sự kiện rồi tải lại danh sách để cập nhật trạng thái.
  Future<void> register(
    String eventId, {
    bool allowClassConflict = false,
  }) async {
    await _repository.register(eventId, allowClassConflict: allowClassConflict);
    await load();
  }

  // Hủy đăng ký hợp lệ rồi tải lại danh sách sự kiện.
  Future<void> cancelRegistration(String eventId) async {
    await _repository.cancelRegistration(eventId);
    await load();
  }

  // Lấy dữ liệu chi tiết của một sự kiện từ repository.
  Future<Map<String, dynamic>> getDetails(String eventId) {
    return _repository.getEventDetails(eventId);
  }
}
