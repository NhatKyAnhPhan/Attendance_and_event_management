class ApiEndpoints {
  ApiEndpoints._();

  static const login = '/api/auth/login';
  static const requestPasswordReset = '/api/auth/password-reset/request';
  static const verifyPasswordReset = '/api/auth/password-reset/verify';
  static const completePasswordReset = '/api/auth/password-reset/complete';
  static const publicStats = '/api/public/stats';
  static const logout = '/api/auth/logout';
  static const currentUser = '/api/me';
  static const events = '/api/events';
  static const classes = '/api/classes';
  static const joinClass = '/api/classes/join';
  static String importEventStudents(String eventId) =>
      '/api/organizer/events/${Uri.encodeComponent(eventId)}/students/import';
  static const adminClasses = '/api/admin/classes';
  static const attendance = '/api/attendance';
  static const attendanceSessions = '/api/attendance/sessions';
  static String closeAttendanceSession(String sessionId) =>
      '$attendanceSessions/${Uri.encodeComponent(sessionId)}/close';
  static const adminAttendanceSessions = '/api/admin/attendance/sessions';

  /// Tạo endpoint lấy danh sách sinh viên của phiên điểm danh.
  static String attendanceSessionStudents(String sessionId) =>
      '$adminAttendanceSessions/${Uri.encodeComponent(sessionId)}/students';
  static const attendanceCheckIn = '/api/attendance/check-in';
  static const attendanceFaceOptions = '/api/attendance/face-options';
  static const attendanceFaceCheckIn = '/api/attendance/face-check-in';
  static const eventAttendanceCheckIn = '/api/events/attendance/check-in';
  static String eventAttendanceQr(String eventId) =>
      '/api/organizer/events/${Uri.encodeComponent(eventId)}/attendance/qr';
  static String closeEventAttendanceSession(String eventId, String sessionId) =>
      '/api/organizer/events/${Uri.encodeComponent(eventId)}/attendance/sessions/'
      '${Uri.encodeComponent(sessionId)}/close';
  static String sendEventCertificates(String eventId) =>
      '/api/organizer/events/${Uri.encodeComponent(eventId)}/certificates/send';
  static String issueEventCertificates(String eventId) =>
      '/api/organizer/events/${Uri.encodeComponent(eventId)}/certificates/issue';
  static const reports = '/api/reports';
  static const attendanceReport = '/api/reports/attendance';
  static const attendanceReportClasses = '$attendanceReport/classes';
  static String attendanceClassReport(String classId) =>
      '$attendanceReportClasses/${Uri.encodeComponent(classId)}';
  // Danh sách và tệp PDF chỉ dành cho chứng nhận của sinh viên đang đăng nhập.
  static const studentCertificates = '/api/student/certificates';
  static String studentCertificatePdf(String certificateId) =>
      '$studentCertificates/${Uri.encodeComponent(certificateId)}/pdf';
  static const staffCertificates = '/api/staff/certificates';
  static String staffCertificatePdf(String certificateId) =>
      '$staffCertificates/${Uri.encodeComponent(certificateId)}/pdf';
  static const staffFeedback = '/api/staff/feedback';
}
