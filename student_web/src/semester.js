export function semesterForDate(date) {
  const month = date.getMonth() + 1;
  if (month >= 9) return 'HK1';
  if (month >= 6) return 'HK3';
  return 'HK2';
}
