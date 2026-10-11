import 'dart:async';

import 'package:get/get.dart';

import '../data/models/student_summaries.dart';
import '../data/repositories/class_repository.dart';

class ClassesController extends GetxController {
  final ClassRepository _repository = ClassRepository();
  final RxList<StudentClassSummary> items = <StudentClassSummary>[].obs;
  final RxBool loading = false.obs;
  final RxString error = ''.obs;
  Timer? _refreshTimer;

  @override
  void onInit() {
    super.onInit();
    load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => load());
  }

  @override
  void onClose() {
    _refreshTimer?.cancel();
    super.onClose();
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

  Future<Map<String, dynamic>> getFeedback(String classId) {
    return _repository.getClassFeedback(classId);
  }

  Future<void> submitFeedback({
    required String classId,
    required int rating,
    required String comment,
  }) {
    return _repository.submitClassFeedback(
      classId: classId,
      rating: rating,
      comment: comment,
    );
  }
}
