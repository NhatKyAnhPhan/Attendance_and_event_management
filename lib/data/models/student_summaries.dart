class StudentClassSummary {
  final String id;
  final String code;
  final String name;
  final String lecturer;
  final String time;
  final String room;
  final String todaySchedule;
  final int studentCount;
  final int capacity;
  final int credits;
  final int present;
  final int late;
  final int absent;
  final int sessions;
  final int rate;

  const StudentClassSummary({
    required this.id,
    this.code = '',
    required this.name,
    required this.lecturer,
    required this.time,
    required this.room,
    this.todaySchedule = '',
    this.studentCount = 0,
    this.capacity = 0,
    this.credits = 0,
    required this.present,
    required this.late,
    required this.absent,
    required this.sessions,
    required this.rate,
  });

  /// Chuyển dữ liệu lớp học trả về từ API thành model tóm tắt.
  factory StudentClassSummary.fromJson(Map<String, dynamic> json) {
    return StudentClassSummary(
      id: json['id']?.toString() ?? json['code']?.toString() ?? '',
      code: json['code']?.toString() ?? json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      lecturer: json['lecturerName']?.toString() ?? '',
      time: json['schedule']?.toString() ?? '',
      room: json['room']?.toString() ?? '',
      todaySchedule: json['todaySchedule']?.toString() ?? '',
      studentCount: _parseCount(json['studentCount']),
      capacity: _parseCount(json['capacity']),
      credits: _parseCount(json['credits']),
      present: _parseCount(json['present']),
      late: _parseCount(json['late']),
      absent: _parseCount(json['absent']),
      sessions: _parseCount(json['sessions']),
      rate: _parseCount(json['rate']),
    );
  }

  /// Chuyển số từ JSON/MySQL dù driver trả về dạng số hay chuỗi.
  static int _parseCount(dynamic value) =>
      num.tryParse(value?.toString() ?? '')?.round() ?? 0;
}

class StudentEventSummary {
  final String id;
  final String name;
  final String date;
  final String org;
  final String location;
  final bool registered;
  final DateTime? registeredAt;
  final DateTime? startTime;
  final DateTime? endTime;
  final String status;
  final String attendanceStatus;

  const StudentEventSummary({
    required this.id,
    required this.name,
    required this.date,
    required this.org,
    this.location = '',
    required this.registered,
    this.registeredAt,
    this.startTime,
    this.endTime,
    this.status = '',
    this.attendanceStatus = '',
  });

  /// Kiểm tra trạng thái kết thúc theo thời gian sự kiện từ API.
  bool get isEnded =>
      status == 'Đã đóng' ||
      (endTime != null && !DateTime.now().isBefore(endTime!));

  /// Tính trạng thái sự kiện theo thời gian bắt đầu và kết thúc thực tế.
  String get eventStatus {
    if (status == 'Đã đóng') return status;
    final end = endTime;
    if (end == null) return '';
    final now = DateTime.now();
    if (!now.isBefore(end)) return 'Đã kết thúc';
    if (startTime != null && now.isBefore(startTime!)) return 'Sắp diễn ra';
    return 'Đang diễn ra';
  }

  /// Chuyển dữ liệu sự kiện trả về từ API thành model tóm tắt.
  factory StudentEventSummary.fromJson(Map<String, dynamic> json) {
    return StudentEventSummary(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      date: json['startTime']?.toString() ?? '',
      org: json['organizerName']?.toString() ?? '',
      location: json['location']?.toString() ?? '',
      registered: json['registrationStatus']?.toString() != 'notRegistered',
      registeredAt: DateTime.tryParse(json['registeredAt']?.toString() ?? '')
          ?.toLocal(),
      startTime: DateTime.tryParse(json['startTime']?.toString() ?? '')
          ?.toLocal(),
      endTime: DateTime.tryParse(json['endTime']?.toString() ?? '')?.toLocal(),
      status: json['status']?.toString() ?? '',
      attendanceStatus: json['attendanceStatus']?.toString() ?? '',
    );
  }
}
