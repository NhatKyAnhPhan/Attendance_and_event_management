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

  /// Tạo endpoint lấy danh sách sinh viên của phiên điểm danh.
  static String attendanceSessionStudents(String sessionId) =>
      '$adminAttendanceSessions/${Uri.encodeComponent(sessionId)}/students';
  static const attendanceCheckIn = '/api/attendance/check-in';
  static const attendanceFaceCheckIn = '/api/attendance/face-check-in';
  static const eventAttendanceCheckIn = '/api/events/attendance/check-in';
  static String eventAttendanceQr(String eventId) =>
      '/api/organizer/events/${Uri.encodeComponent(eventId)}/attendance/qr';
  static String sendEventCertificates(String eventId) =>
      '/api/organizer/events/${Uri.encodeComponent(eventId)}/certificates/send';
  static const reports = '/api/reports';
  static const attendanceReport = '/api/reports/attendance';
  static const staffCertificates = '/api/staff/certificates';
  static const staffFeedback = '/api/staff/feedback';
}
