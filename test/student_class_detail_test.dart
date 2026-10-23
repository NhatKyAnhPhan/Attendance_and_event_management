import 'package:attendance_and_event_management/data/models/student_class_detail.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses per-session attendance results for a student class', () {
    final detail = StudentClassDetail.fromJson({
      'class': {'id': 'CLS01', 'name': 'Lớp kiểm thử'},
      'schedules': [],
      'attendanceSessions': [
        {
          'id': 'ATT01',
          'name': 'Buổi 1',
          'startTime': '23/10/2026 08:00',
          'checkedInAt': '23/10/2026 08:05',
          'status': 'Có mặt',
          'method': 'QR',
        },
      ],
      'students': [],
    });

    expect(detail.attendanceSessions, hasLength(1));
    expect(detail.attendanceSessions.single.id, 'ATT01');
    expect(detail.attendanceSessions.single.status, 'Có mặt');
    expect(detail.attendanceSessions.single.checkedInAt, '23/10/2026 08:05');
  });

  test('rejects class details without attendance session results', () {
    expect(
      () => StudentClassDetail.fromJson({
        'class': {'id': 'CLS01'},
        'schedules': [],
        'students': [],
      }),
      throwsFormatException,
    );
  });
}
