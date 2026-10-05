bool isOlderThanOneYear(DateTime? date, {DateTime? now}) {
  if (date == null) return false;
  final reference = now ?? DateTime.now();
  final cutoff = DateTime(reference.year - 1, reference.month, reference.day);
  return date.isBefore(cutoff);
}
