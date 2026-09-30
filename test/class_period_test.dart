import 'package:attendance_and_event_management/data/models/class_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('class options from the current schema', () {
    test('reads a subject semester and its department fields', () {
      final subject = ClassSubjectOption.fromJson({
        'id': 'TH003',
        'code': 'TH003',
        'name': 'Lập trình Web',
        'semester': 2,
        'majorId': 'BM001',
        'majorName': 'Công nghệ phần mềm',
        'departmentId': 'DV001',
      });

      expect(subject.id, 'TH003');
      expect(subject.name, 'Lập trình Web');
      expect(subject.semester, '2');
      expect(subject.majorId, 'BM001');
    });

    test('reads the student cohort code without a year field', () {
      final cohort = ClassCohort.fromJson({'code': 'K26'});

      expect(cohort.code, 'K26');
    });

    test('reads class start time, subject, cohort, and semester', () {
      final item = ClassModel.fromJson({
        'id': '26DHTH01',
        'code': '26DHTH01',
        'name': 'Lập trình Web',
        'type': 'courseSection',
        'lecturerId': 'GV001',
        'lecturerName': 'Nguyễn Văn An',
        'studentCount': 20,
        'semester': 'HK2',
        'startTime': '2026-09-05 07:00:00',
        'subjectId': 'TH003',
        'subjectCode': 'TH003',
        'cohortCode': 'K26',
        'room': '',
        'schedule': '',
      });

      expect(item.startTime, '2026-09-05 07:00:00');
      expect(item.subjectId, 'TH003');
      expect(item.cohortCode, 'K26');
      expect(item.semester, 'HK2');
    });
  });
}
