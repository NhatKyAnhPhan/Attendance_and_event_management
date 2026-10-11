import 'dart:async';

import 'package:get/get.dart';

import '../data/models/class_model.dart';
import '../data/models/student_roster_entry.dart';
import '../data/repositories/class_repository.dart';

class AdminClassesController extends GetxController {
  AdminClassesController({ClassRepository? repository})
    : _repository = repository ?? ClassRepository();

  final ClassRepository _repository;
  final RxList<ClassModel> items = <ClassModel>[].obs;
  final RxList<ClassLecturer> lecturers = <ClassLecturer>[].obs;
  final RxList<ClassCohort> cohorts = <ClassCohort>[].obs;
  final RxList<ClassSubjectOption> subjects = <ClassSubjectOption>[].obs;
  final RxBool loading = false.obs;
  final RxString error = ''.obs;
  Timer? _refreshTimer;

  @override
  void onInit() {
    super.onInit();
    load();
    loadLecturers();
    loadClassOptions();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => load());
  }

  @override
  void onClose() {
    _refreshTimer?.cancel();
    super.onClose();
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

  Future<void> loadClassOptions() async {
    try {
      final options = await _repository.getClassOptions();
      cohorts.assignAll(options.cohorts);
      subjects.assignAll(options.subjects);
    } catch (_) {
      cohorts.clear();
      subjects.clear();
    }
  }

  Future<void> createClass({
    required String name,
    required String subjectId,
    required String cohortCode,
    required String semester,
    required String startTime,
    required String? lecturerId,
    required int capacity,
  }) async {
    await _repository.createClass(
      name: name,
      subjectId: subjectId,
      cohortCode: cohortCode,
      semester: semester,
      startTime: startTime,
      lecturerId: lecturerId,
      capacity: capacity,
    );
    await load();
  }

  Future<void> updateClass({
    required String id,
    required String name,
    required String semester,
    required String startTime,
    required String? lecturerId,
    required int capacity,
  }) async {
    await _repository.updateClass(
      id: id,
      name: name,
      semester: semester,
      startTime: startTime,
      lecturerId: lecturerId,
      capacity: capacity,
    );
    await load();
  }

  Future<ClassStudentImportResult> importStudents({
    required String classId,
    required List<String> studentIds,
  }) async {
    final result = await _repository.importStudents(
      classId: classId,
      studentIds: studentIds,
    );
    await load();
    return result;
  }

  Future<List<StudentRosterEntry>> getClassStudents(String classId) {
    return _repository.getClassStudents(classId);
  }

  Future<void> deleteClass(String id) async {
    await _repository.deleteClass(id);
    await load();
  }

  Future<void> closeClass(String id) async {
    await _repository.closeClass(id);
    await load();
  }
}
