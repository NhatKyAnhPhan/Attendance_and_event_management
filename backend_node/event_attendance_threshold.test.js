const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  eventAttendanceThresholdOptions,
  isValidEventAttendanceThreshold,
} = require('./event_attendance_threshold');

test('offers attendance thresholds derived from configured periods', () => {
  assert.deepEqual(eventAttendanceThresholdOptions(1), [100]);
  assert.deepEqual(eventAttendanceThresholdOptions(2), [50, 100]);
  assert.deepEqual(eventAttendanceThresholdOptions(3), [33, 66, 100]);
});

test('validates only integer options for the configured period count', () => {
  assert.equal(isValidEventAttendanceThreshold(50, 2), true);
  assert.equal(isValidEventAttendanceThreshold(33, 3), true);
  assert.equal(isValidEventAttendanceThreshold(50, 3), false);
  assert.equal(isValidEventAttendanceThreshold(33.3, 3), false);
});
