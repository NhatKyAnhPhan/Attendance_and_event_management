import 'package:attendance_and_event_management/data/models/class_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('class date range', () {
    test('accepts an end date after the start date', () {
      expect(
        isValidClassDateRange(DateTime(2026, 9, 1), DateTime(2027, 1, 31)),
        isTrue,
      );
    });

    test('accepts the same start and end date', () {
      expect(
        isValidClassDateRange(DateTime(2026, 9, 1), DateTime(2026, 9, 1)),
        isTrue,
      );
    });

    test('rejects an end date before the start date', () {
      expect(
        isValidClassDateRange(DateTime(2027, 1, 31), DateTime(2026, 9, 1)),
        isFalse,
      );
    });
  });
}
