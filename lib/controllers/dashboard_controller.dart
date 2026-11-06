import 'package:get/get.dart';

import '../core/utils/semester.dart';
import '../data/api/api_client.dart';

class DashboardController extends GetxController {
  final RxMap<String, dynamic> summary = <String, dynamic>{}.obs;
  final RxBool loading = false.obs;
  final RxString error = ''.obs;
  final RxString selectedSemester = semesterForDate(DateTime.now()).obs;

  /// Tải dữ liệu tổng quan khi khởi tạo controller.
  @override
  void onInit() {
    super.onInit();
    load();
  }

  /// Đồng bộ thống kê sinh viên từ endpoint thật.
  Future<void> load({String? semester}) async {
    if (semester != null) selectedSemester.value = semester;
    loading.value = true;
    error.value = '';
    try {
      final path = Uri(
        path: '/api/dashboard',
        queryParameters: {'semester': selectedSemester.value},
      ).toString();
      summary.assignAll(await ApiClient().get(path));
    } on ApiException catch (exception) {
      error.value = exception.message;
    } finally {
      loading.value = false;
    }
  }
}
