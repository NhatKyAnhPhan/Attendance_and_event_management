import '../../core/theme/app_colors.dart';

/// Trạng thái điểm danh của 1 sinh viên trong 1 phiên — tương ứng
/// .badge-present / .badge-late / .badge-absent / .badge-excused / .badge-pending
enum AttendanceStatus { present, late, absent, excused, pending }

extension AttendanceStatusX on AttendanceStatus {
  /// Nhãn tiếng Việt — tương ứng statusStyle().label trong StudentMobilePage.tsx
  String get label {
    switch (this) {
      case AttendanceStatus.present:
        return 'Có mặt';
      case AttendanceStatus.late:
        return 'Muộn';
      case AttendanceStatus.absent:
        return 'Vắng';
      case AttendanceStatus.excused:
        return 'Có phép';
      case AttendanceStatus.pending:
        return 'Chưa xác định';
    }
  }

  /// Tên khớp với BadgeStatus trong core/theme/app_colors.dart để tái dùng badgeColors()
  BadgeStatus get badgeStatus {
    switch (this) {
      case AttendanceStatus.present:
        return BadgeStatus.present;
      case AttendanceStatus.late:
        return BadgeStatus.late;
      case AttendanceStatus.absent:
        return BadgeStatus.absent;
      case AttendanceStatus.excused:
        return BadgeStatus.excused;
      case AttendanceStatus.pending:
        return BadgeStatus.pending;
    }
  }
}

/// Phương thức điểm danh — tương ứng SubView "qr" | "face" trong AttendancePage.tsx
enum AttendanceMethod { qr, face, manual }

/// Một phiên điểm danh (1 buổi học hoặc 1 sự kiện) — tương ứng object
/// trong mảng mock của AttendancePage.tsx (id AS00x).
class AttendanceSession {
  final String id;
  final String classOrEventId;
  final String classOrEventName; // vd "CS301 — Công nghệ phần mềm"
  final String sessionName; // vd "Buổi 5 — Design Pattern"
  final DateTime date;
  final String time; // vd "13:00–15:00"
  final String room;
  final AttendanceMethod method;
  final AttendanceStatus status; // trạng thái tổng của phiên (đã mở/đóng/chờ)
  final int total;
  final int present;
  final int late;
  final int absent;

  const AttendanceSession({
    required this.id,
    required this.classOrEventId,
    required this.classOrEventName,
    required this.sessionName,
    required this.date,
    required this.time,
    required this.room,
    required this.method,
    required this.status,
    required this.total,
    required this.present,
    required this.late,
    required this.absent,
  });

  factory AttendanceSession.fromJson(Map<String, dynamic> json) {
    return AttendanceSession(
      id: json['id'] as String,
      classOrEventId: json['classOrEventId'] as String? ?? '',
      classOrEventName: json['class'] as String? ?? json['classOrEventName'] as String? ?? '',
      sessionName: json['session'] as String? ?? '',
      date: DateTime.parse(json['date'] as String),
      time: json['time'] as String? ?? '',
      room: json['room'] as String? ?? '',
      method: _methodFromString(json['method'] as String?),
      status: _statusFromString(json['status'] as String?),
      total: json['total'] as int? ?? 0,
      present: json['present'] as int? ?? 0,
      late: json['late'] as int? ?? 0,
      absent: json['absent'] as int? ?? 0,
    );
  }

  static AttendanceMethod _methodFromString(String? v) {
    switch (v) {
      case 'Face':
      case 'face':
        return AttendanceMethod.face;
      case 'Manual':
      case 'manual':
        return AttendanceMethod.manual;
      default:
        return AttendanceMethod.qr;
    }
  }

  static AttendanceStatus _statusFromString(String? v) {
    return AttendanceStatus.values.firstWhere(
      (s) => s.name == v,
      orElse: () => AttendanceStatus.pending,
    );
  }
}

/// Bản ghi điểm danh của 1 sinh viên trong 1 phiên cụ thể.
class AttendanceRecord {
  final String id;
  final String sessionId;
  final String studentId;
  final String studentName;
  final String studentCode;
  final AttendanceStatus status;
  final DateTime? checkedInAt;
  final AttendanceMethod method;

  const AttendanceRecord({
    required this.id,
    required this.sessionId,
    required this.studentId,
    required this.studentName,
    required this.studentCode,
    required this.status,
    this.checkedInAt,
    this.method = AttendanceMethod.qr,
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    return AttendanceRecord(
      id: json['id'] as String,
      sessionId: json['sessionId'] as String,
      studentId: json['studentId'] as String,
      studentName: json['studentName'] as String,
      studentCode: json['studentCode'] as String,
      status: AttendanceSession._statusFromString(json['status'] as String?),
      checkedInAt: json['checkedInAt'] != null
          ? DateTime.parse(json['checkedInAt'] as String)
          : null,
      method: AttendanceSession._methodFromString(json['method'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sessionId': sessionId,
        'studentId': studentId,
        'studentName': studentName,
        'studentCode': studentCode,
        'status': status.name,
        'checkedInAt': checkedInAt?.toIso8601String(),
        'method': method.name,
      };
}