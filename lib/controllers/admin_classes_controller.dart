import 'package:get/get.dart';

import '../data/models/class_model.dart';
import '../data/repositories/class_repository.dart';

class AdminClassesController extends GetxController {
  AdminClassesController({ClassRepository? repository})
    : _repository = repository ?? ClassRepository();

  final ClassRepository _repository;
  final RxList<ClassModel> items = <ClassModel>[].obs;
  final RxList<ClassLecturer> lecturers = <ClassLecturer>[].obs;
  final RxBool loading = false.obs;
  final RxString error = ''.obs;

  @override
  void onInit() {
    super.onInit();
    load();
    loadLecturers();
  }

  Future<void> load() async {
    loading.value = true;
    error.value = '';
    try {
      items.assignAll(await _repository.getManagedClasses());
    } catch (exception) {
      error.value = exception.toString();
    } finally {
      loading.value = false;
    }
  }

  Future<void> loadLecturers() async {
    try {
      lecturers.assignAll(await _repository.getLecturers());
    } catch (_) {
      lecturers.clear();
    }
  }

  Future<void> createClass({
    required String name,
    required String semester,
    required String schoolYear,
    required String? lecturerId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    await _repository.createClass(
      name: name,
      semester: semester,
      schoolYear: schoolYear,
      lecturerId: lecturerId,
      startDate: startDate,
      endDate: endDate,
    );
    await load();
  }

  Future<void> updateClass({
    required String id,
    required String name,
    required String semester,
    required String schoolYear,
    required String? lecturerId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    await _repository.updateClass(
      id: id,
      name: name,
      semester: semester,
      schoolYear: schoolYear,
      lecturerId: lecturerId,
      startDate: startDate,
      endDate: endDate,
    );
    await load();
  }

  Future<void> deleteClass(String id) async {
    await _repository.deleteClass(id);
    await load();
  }
}
