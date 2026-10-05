String semesterForDate(DateTime date) {
  if (date.month >= 9) return 'HK1';
  if (date.month >= 6) return 'HK3';
  return 'HK2';
}
