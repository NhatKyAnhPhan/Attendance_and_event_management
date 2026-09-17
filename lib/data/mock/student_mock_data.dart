import '../models/attendance_model.dart';

/// TODO: thay bằng gọi API thật (ClassRepository/EventRepository) khi có backend.
/// Các class dưới đây CHỈ để hiển thị demo, không phải model domain chính thức
/// (khác với ClassModel/EventModel trong data/models — vì màn Student cần vài
/// số liệu tổng hợp riêng như present/late/absent/rate).

class StudentClassSummary {
  final String id; // mã lớp, vd "CS101"
  final String name;
  final String lecturer;
  final String time; // vd "Thứ Hai 07:00"
  final String room;
  final int present;
  final int late;
  final int absent;
  final int sessions;
  final int rate; // %

  const StudentClassSummary({
    required this.id,
    required this.name,
    required this.lecturer,
    required this.time,
    required this.room,
    required this.present,
    required this.late,
    required this.absent,
    required this.sessions,
    required this.rate,
  });
}

class StudentEventSummary {
  final String id;
  final String name;
  final String date;
  final String org;
  final bool registered;

  const StudentEventSummary({
    required this.id,
    required this.name,
    required this.date,
    required this.org,
    required this.registered,
  });
}

class StudentNotification {
  final int id;
  final String type; // attendance | class | certificate | event
  final String text;
  final String time;
  final bool read;

  const StudentNotification({
    required this.id,
    required this.type,
    required this.text,
    required this.time,
    required this.read,
  });

  String get emoji {
    switch (type) {
      case 'attendance':
        return '✅';
      case 'class':
        return '📚';
      case 'certificate':
        return '🏆';
      case 'event':
        return '🎉';
      default:
        return '🔔';
    }
  }
}

class AttendanceHistoryItem {
  final String session;
  final String date;
  final AttendanceStatus status;
  final String time;

  const AttendanceHistoryItem({
    required this.session,
    required this.date,
    required this.status,
    required this.time,
  });
}

class StudentMockData {
  StudentMockData._();

  static const myClasses = <StudentClassSummary>[
    StudentClassSummary(
      id: 'CS101',
      name: 'Lập trình cơ bản',
      lecturer: 'TS. Trần Văn Bình',
      time: 'Thứ Hai 07:00',
      room: 'A301',
      present: 11,
      late: 1,
      absent: 0,
      sessions: 12,
      rate: 97,
    ),
    StudentClassSummary(
      id: 'CS202',
      name: 'Cơ sở dữ liệu',
      lecturer: 'ThS. Lê Thị Cẩm',
      time: 'Thứ Tư 09:00',
      room: 'B204',
      present: 10,
      late: 0,
      absent: 1,
      sessions: 11,
      rate: 91,
    ),
    StudentClassSummary(
      id: 'MA101',
      name: 'Toán rời rạc',
      lecturer: 'TS. Bùi Hữu Hùng',
      time: 'Thứ Sáu 13:00',
      room: 'C102',
      present: 9,
      late: 2,
      absent: 1,
      sessions: 12,
      rate: 85,
    ),
  ];

  static const upcomingEvents = <StudentEventSummary>[
    StudentEventSummary(
      id: 'EV001',
      name: 'Ngày hội Việc làm IT 2025',
      date: '15–16/04/2025',
      org: 'Khoa CNTT',
      registered: true,
    ),
    StudentEventSummary(
      id: 'EV002',
      name: 'Workshop AI ứng dụng',
      date: '28/03/2025',
      org: 'CLB AI HUIT',
      registered: false,
    ),
  ];

  static const notifications = <StudentNotification>[
    StudentNotification(
      id: 1,
      type: 'attendance',
      text: 'Điểm danh CS101 đã mở — Hãy điểm danh ngay!',
      time: '08:00',
      read: false,
    ),
    StudentNotification(
      id: 2,
      type: 'class',
      text: 'Lịch học CS202 đổi phòng: B204 → B301',
      time: 'Hôm qua',
      read: false,
    ),
    StudentNotification(
      id: 3,
      type: 'certificate',
      text: 'Chứng chỉ Workshop AI đã được cấp',
      time: '23/03',
      read: true,
    ),
    StudentNotification(
      id: 4,
      type: 'event',
      text: 'Đăng ký sự kiện Ngày hội Việc làm đã được duyệt',
      time: '22/03',
      read: true,
    ),
  ];

  static const attendanceHistory = <AttendanceHistoryItem>[
    AttendanceHistoryItem(
      session: 'CS101 — Buổi 4',
      date: '2025-03-24',
      status: AttendanceStatus.present,
      time: '07:02',
    ),
    AttendanceHistoryItem(
      session: 'CS202 — Buổi 3',
      date: '2025-03-24',
      status: AttendanceStatus.present,
      time: '09:05',
    ),
    AttendanceHistoryItem(
      session: 'MA101 — Buổi 6',
      date: '2025-03-21',
      status: AttendanceStatus.late,
      time: '13:22',
    ),
    AttendanceHistoryItem(
      session: 'CS101 — Buổi 3',
      date: '2025-03-17',
      status: AttendanceStatus.present,
      time: '07:01',
    ),
    AttendanceHistoryItem(
      session: 'CS202 — Buổi 2',
      date: '2025-03-12',
      status: AttendanceStatus.absent,
      time: '—',
    ),
  ];
}