import 'package:get/get.dart';

import '../data/api/api_client.dart';
import '../data/api/endpoints.dart';

class AttendanceController extends GetxController {
  final RxList<Map<String, dynamic>> sessions = <Map<String, dynamic>>[].obs;
  final RxBool loading = false.obs;
  final RxString error = ''.obs;

  /// Nạp các phiên điểm danh thật khi mở màn hình.
  @override
  void onInit() {
    super.onInit();
    load();
  }

  /// Tải danh sách phiên và tổng lượt tham dự từ backend.
  Future<void> load() async {
    loading.value = true;
    error.value = '';
    try {
      final response = await ApiClient().get(
        ApiEndpoints.adminAttendanceSessions,
      );
      final items = response['items'];
      sessions.assignAll(
        items is List
            ? items.whereType<Map>().map(Map<String, dynamic>.from).toList()
            : <Map<String, dynamic>>[],
      );
    } on ApiException catch (exception) {
      error.value = exception.message;
    } finally {
      loading.value = false;
    }
  }
}
