class StudentRosterEntry {
  final String studentId;
  final String studentName;
  final String email;
  final String status;
  final String dateLabel;

  const StudentRosterEntry({
    required this.studentId,
    required this.studentName,
    this.email = '',
    this.status = '',
    this.dateLabel = '',
  });

  factory StudentRosterEntry.fromJson(Map<String, dynamic> json) {
    return StudentRosterEntry(
      studentId: json['studentId']?.toString() ?? '',
      studentName: json['studentName']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      dateLabel: json['dateLabel']?.toString() ?? '',
    );
  }
}
