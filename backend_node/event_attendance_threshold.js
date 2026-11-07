function eventAttendanceThresholdOptions(periodCount) {
  if (!Number.isInteger(periodCount) || periodCount <= 0) return [100];
  return Array.from(
    { length: periodCount },
    (_, index) => Math.floor(((index + 1) * 100) / periodCount),
  );
}

function isValidEventAttendanceThreshold(threshold, periodCount) {
  return Number.isInteger(threshold)
    && eventAttendanceThresholdOptions(periodCount).includes(threshold);
}

module.exports = {
  eventAttendanceThresholdOptions,
  isValidEventAttendanceThreshold,
};
