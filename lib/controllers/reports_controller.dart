import 'package:get/get.dart';

import 'auth_controller.dart';
import '../core/constants/role.dart';
import '../data/api/api_client.dart';
import '../data/api/endpoints.dart';

class ReportsController extends GetxController {
  final RxList<Map<String, dynamic>> classes = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> students = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> dailyItems = <Map<String, dynamic>>[].obs;
  final RxMap<String, dynamic> summary = <String, dynamic>{}.obs;
  final Rxn<Map<String, dynamic>> selectedClass = Rxn<Map<String, dynamic>>();
  final RxBool loading = false.obs;
  final RxBool loadingStudents = false.obs;
  final RxString error = ''.obs;
  final RxString studentError = ''.obs;
  final RxInt sessionCount = 0.obs;

  /// Nạp báo cáo thật khi mở trang.
  @override
  void onInit() {
    super.onInit();
    loadClasses();
  }

  /// Tải các lớp mà người dùng hiện tại được phép lập báo cáo.
  Future<void> loadClasses() async {
    loading.value = true;
    error.value = '';
    try {
      final response = await ApiClient().get(
        ApiEndpoints.adminClasses,
      );
      final rawItems = response['items'];
      final allClasses = rawItems is List
          ? rawItems.whereType<Map>().map(Map<String, dynamic>.from).toList()
          : <Map<String, dynamic>>[];
      final auth = Get.find<AuthController>();
      final isAdmin = auth.role.value == Role.admin;
      final lecturerId = auth.currentUser.value?['id']?.toString();
      classes.assignAll(
        isAdmin
            ? allClasses
            : allClasses
                  .where(
                    (item) =>
                        item['lecturerId']?.toString() == lecturerId &&
                        lecturerId != null,
                  )
                  .toList(),
      );
      final currentSelection = selectedClass.value?['id']?.toString();
      if (currentSelection != null &&
          classes.any((item) => item['id']?.toString() == currentSelection)) {
        await selectClass(currentSelection);
      } else {
        selectedClass.value = null;
        students.clear();
        dailyItems.clear();
        summary.clear();
        sessionCount.value = 0;
      }
    } on ApiException catch (exception) {
      error.value = exception.message;
    } finally {
      loading.value = false;
    }
  }

  /// Chỉ tải dữ liệu sinh viên sau khi người dùng chọn một lớp cụ thể.
  Future<void> selectClass(String? classId) async {
    final item = classes.firstWhereOrNull(
      (entry) => entry['id']?.toString() == classId,
    );
    selectedClass.value = item;
    students.clear();
    dailyItems.clear();
    summary.clear();
    sessionCount.value = 0;
    studentError.value = '';
    if (item == null) return;

    loadingStudents.value = true;
    try {
      final client = ApiClient();
      final responses = await Future.wait([
        client.get('${ApiEndpoints.adminClasses}/$classId/students'),
        client.get(ApiEndpoints.adminAttendanceSessions),
      ]);
      final rawStudents = responses[0]['items'];
      final studentItems = rawStudents is List
          ? rawStudents.whereType<Map>().map(Map<String, dynamic>.from).toList()
          : <Map<String, dynamic>>[];
      final rawSessions = responses[1]['items'];
      final sessions = rawSessions is List
          ? rawSessions.whereType<Map>().map(Map<String, dynamic>.from).where(
              (session) =>
                  session['classId']?.toString() == classId &&
                  session['status']?.toString() != 'Đang mở',
            ).toList()
          : <Map<String, dynamic>>[];

      final studentById = <String, Map<String, dynamic>>{
        for (final student in studentItems)
          student['studentId']?.toString() ?? '':
              {
                'studentId': student['studentId']?.toString() ?? '',
                'studentName': student['studentName']?.toString() ?? '',
                'totalSessions': 0,
                'present': 0,
                'late': 0,
                'absent': 0,
                'excused': 0,
              },
      }..remove('');
      final dailyByDate = <String, Map<String, dynamic>>{};
      final totals = <String, int>{
        'present': 0,
        'late': 0,
        'absent': 0,
        'excused': 0,
      };

      for (var offset = 0; offset < sessions.length; offset += 8) {
        final batch = sessions.skip(offset).take(8).toList();
        final rosterResponses = await Future.wait(
          batch.map(
            (session) => client.get(
              ApiEndpoints.attendanceSessionStudents(
                session['id']?.toString() ?? '',
              ),
            ),
          ),
        );
        for (var index = 0; index < rosterResponses.length; index++) {
          final response = rosterResponses[index];
          final rawRoster = response['items'];
          if (rawRoster is! List) continue;
          final sessionDate = _dateKey(batch[index]['openedAt']);
          final dailyCounts = sessionDate == null
              ? null
              : dailyByDate.putIfAbsent(
                  sessionDate,
                  () => {
                    'date': sessionDate,
                    'present': 0,
                    'late': 0,
                    'absent': 0,
                    'excused': 0,
                  },
                );
          for (final rawEntry in rawRoster.whereType<Map>()) {
            final entry = Map<String, dynamic>.from(rawEntry);
            final stats = studentById[entry['studentId']?.toString()];
            if (stats == null) continue;
            final status = entry['attendanceStatus']?.toString() ?? 'Vắng mặt';
            final statusKey = switch (status) {
              'Có mặt' => 'present',
              'Đi trễ' || 'Đi muộn' => 'late',
              'Vắng có phép' => 'excused',
              'Vắng mặt' => 'absent',
              _ => null,
            };
            if (statusKey == null) continue;
            stats['totalSessions'] = (stats['totalSessions'] as int) + 1;
            stats[statusKey] = (stats[statusKey] as int) + 1;
            totals[statusKey] = totals[statusKey]! + 1;
            if (dailyCounts != null) {
              dailyCounts[statusKey] = (dailyCounts[statusKey] as int) + 1;
            }
          }
        }
      }
      students.assignAll(studentById.values.toList());
      summary.assignAll({
        'present': totals['present']!,
        'late': totals['late']!,
        'absent': totals['absent']!,
        'excused': totals['excused']!,
        'total': totals.values.fold<int>(0, (sum, count) => sum + count),
      });
      dailyItems.assignAll(
        dailyByDate.values.toList()
          ..sort((first, second) =>
              first['date'].toString().compareTo(second['date'].toString())),
      );
      sessionCount.value = sessions.length;
    } on ApiException catch (exception) {
      studentError.value = exception.message;
    } finally {
      loadingStudents.value = false;
    }
  }

  static String? _dateKey(Object? value) {
    final raw = value?.toString();
    if (raw == null || raw.length < 10) return null;
    return raw.substring(0, 10);
  }
}
