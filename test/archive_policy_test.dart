import 'package:attendance_and_event_management/core/utils/archive_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isOlderThanOneYear', () {
    final now = DateTime(2026, 10, 6);

    test('does not archive dates before the one-year cutoff', () {
      expect(isOlderThanOneYear(DateTime(2025, 10, 6), now: now), isFalse);
      expect(isOlderThanOneYear(DateTime(2025, 10, 7), now: now), isFalse);
    });

    test('archives dates strictly before the one-year cutoff', () {
      expect(isOlderThanOneYear(DateTime(2025, 10, 5), now: now), isTrue);
    });

    test('does not archive an unknown date', () {
      expect(isOlderThanOneYear(null, now: now), isFalse);
    });
  });
}
