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

  test('student events are ordered by upcoming, ongoing, and ended status', () {
    final now = DateTime.now();
    StudentEventSummary event({
      required String id,
      required DateTime start,
      required DateTime end,
    }) => StudentEventSummary(
      id: id,
      name: id,
      date: start.toIso8601String(),
      org: '',
      startTime: start,
      endTime: end,
      registered: false,
    );

    final events =
        [
          event(
            id: 'ended',
            start: now.subtract(const Duration(days: 2)),
            end: now.subtract(const Duration(days: 1)),
          ),
          event(
            id: 'later',
            start: now.add(const Duration(days: 2)),
            end: now.add(const Duration(days: 2, hours: 1)),
          ),
          event(
            id: 'ongoing',
            start: now.subtract(const Duration(minutes: 30)),
            end: now.add(const Duration(minutes: 30)),
          ),
          event(
            id: 'sooner',
            start: now.add(const Duration(days: 1)),
            end: now.add(const Duration(days: 1, hours: 1)),
          ),
        ]..sort((a, b) {
          final statusOrder = a.eventSortOrder.compareTo(b.eventSortOrder);
          if (statusOrder != 0) return statusOrder;
          return a.startTime!.compareTo(b.startTime!);
        });

    expect(events.map((event) => event.id), [
      'sooner',
      'later',
      'ongoing',
      'ended',
    ]);
  });
}
