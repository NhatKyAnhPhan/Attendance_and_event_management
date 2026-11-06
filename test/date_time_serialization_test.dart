import 'package:attendance_and_event_management/core/utils/date_time_serialization.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serializes local event times as UTC instants', () {
    final localTime = DateTime(2026, 11, 7, 1, 40);
    final serialized = dateTimeToUtcIso8601(localTime);

    expect(serialized, localTime.toUtc().toIso8601String());
    expect(DateTime.parse(serialized).toLocal(), localTime);
  });
}
