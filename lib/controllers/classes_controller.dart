import 'package:get/get.dart';

import '../data/mock/student_mock_data.dart';
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
}
