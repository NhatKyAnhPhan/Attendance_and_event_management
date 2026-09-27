import 'package:get/get.dart';

import '../data/api/api_client.dart';

class DashboardController extends GetxController {
  final RxMap<String, dynamic> summary = <String, dynamic>{}.obs;
  final RxBool loading = false.obs;
  final RxString error = ''.obs;

  /// Tải dữ liệu tổng quan khi khởi tạo controller.
  @override
  void onInit() {
    super.onInit();
    load();
  }

  /// Đồng bộ thống kê sinh viên từ endpoint thật.
  Future<void> load() async {
    loading.value = true;
    error.value = '';
    try {
      summary.assignAll(await ApiClient().get('/api/dashboard'));
    } on ApiException catch (exception) {
      error.value = exception.message;
    } finally {
      loading.value = false;
    }
  }
}
