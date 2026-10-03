import 'package:get/get.dart';

import '../data/models/student_summaries.dart';
import '../data/repositories/class_repository.dart';

class ClassesController extends GetxController {
  final ClassRepository _repository = ClassRepository();
  final RxList<StudentClassSummary> items = <StudentClassSummary>[].obs;
  final RxBool loading = false.obs;
  final RxString error = ''.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  // Tải danh sách lớp của sinh viên và cập nhật trạng thái loading/lỗi.
  Future<void> load() async {
    loading.value = true;
    error.value = '';
    try {
      items.assignAll(await _repository.getStudentClasses());
    } catch (exception) {
      error.value = exception.toString();
    } finally {
      loading.value = false;
    }
  }

  Future<void> joinClass(String classCode) async {
    await _repository.joinClass(classCode);
    await load();
  }
}
