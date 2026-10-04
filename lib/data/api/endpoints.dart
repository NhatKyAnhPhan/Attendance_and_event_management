class ApiEndpoints {
  ApiEndpoints._();

  static const login = '/api/auth/login';
  static const logout = '/api/auth/logout';
  static const currentUser = '/api/me';
  static const events = '/api/events';
  static const classes = '/api/classes';
  static const adminClasses = '/api/admin/classes';
  static const attendance = '/api/attendance';
  static const attendanceSessions = '/api/attendance/sessions';
  static const adminAttendanceSessions = '/api/admin/attendance/sessions';
  static const attendanceCheckIn = '/api/attendance/check-in';
  static const attendanceFaceCheckIn = '/api/attendance/face-check-in';
  static const reports = '/api/reports';
  static const attendanceReport = '/api/reports/attendance';
  static const staffCertificates = '/api/staff/certificates';
  static const staffFeedback = '/api/staff/feedback';
}
