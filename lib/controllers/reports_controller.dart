import 'package:get/get.dart';

import '../data/api/api_client.dart';
import '../data/api/endpoints.dart';

class ReportsController extends GetxController {
  final RxMap<String, dynamic> summary = <String, dynamic>{}.obs;
  final RxList<Map<String, dynamic>> dailyItems = <Map<String, dynamic>>[].obs;
  final RxBool loading = false.obs;
  final RxString error = ''.obs;

  /// Nạp báo cáo thật khi mở trang.
  @override
  void onInit() {
    super.onInit();
    load();
  }

  /// Tải thống kê điểm danh và dữ liệu theo ngày từ backend.
  Future<void> load() async {
    loading.value = true;
    error.value = '';
    try {
      final response = await ApiClient().get(ApiEndpoints.attendanceReport);
      final rawSummary = response['summary'];
      final rawItems = response['items'];
      if (rawSummary is Map) {
        summary.assignAll(Map<String, dynamic>.from(rawSummary));
      }
      dailyItems.assignAll(
        rawItems is List
            ? rawItems.whereType<Map>().map(Map<String, dynamic>.from).toList()
            : <Map<String, dynamic>>[],
      );
    } on ApiException catch (exception) {
      error.value = exception.message;
    } finally {
      loading.value = false;
    }
  }
}
