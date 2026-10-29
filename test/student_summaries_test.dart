import 'package:flutter_test/flutter_test.dart';

import 'package:attendance_and_event_management/data/models/event_model.dart';
import 'package:attendance_and_event_management/data/models/student_summaries.dart';

void main() {
  test(
    'student class summary keeps class ID separate from its display code',
    () {
      final summary = StudentClassSummary.fromJson({
        'id': 'section-id',
        'code': 'SECTION-CODE',
        'name': 'Lớp học phần',
      });

      expect(summary.id, 'section-id');
      expect(summary.code, 'SECTION-CODE');
      expect(summary.name, 'Lớp học phần');
    },
  );

  test('organizer event summary reads certificate eligibility', () {
    final summary = OrganizerEventSummary.fromJson({
      'id': 'event-1',
      'name': 'Sự kiện',
      'organizerId': 'unit-1',
      'startTime': '2026-10-30T08:00:00.000Z',
      'endTime': '2026-10-30T10:00:00.000Z',
      'capacity': 100,
      'registeredCount': 20,
      'certificateEnabled': 1,
    });

    expect(summary.certificateEnabled, isTrue);
  });
}
