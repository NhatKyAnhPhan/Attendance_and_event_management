import 'package:attendance_and_event_management/core/utils/semester.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('semesterForDate', () {
    test('starts semester 1 on September 1 and runs through December', () {
      expect(semesterForDate(DateTime(2026, 9, 1)), 'HK1');
      expect(semesterForDate(DateTime(2026, 12, 31)), 'HK1');
    });

    test('starts semester 2 on January 1 and runs through May', () {
      expect(semesterForDate(DateTime(2027, 1, 1)), 'HK2');
      expect(semesterForDate(DateTime(2027, 5, 31)), 'HK2');
    });

    test(
      'starts semester 3 on June 1 and resets to semester 1 in September',
      () {
        expect(semesterForDate(DateTime(2027, 6, 1)), 'HK3');
        expect(semesterForDate(DateTime(2027, 8, 31)), 'HK3');
        expect(semesterForDate(DateTime(2027, 9, 1)), 'HK1');
      },
    );
  });
}
