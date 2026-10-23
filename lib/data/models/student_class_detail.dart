import 'student_roster_entry.dart';

class StudentClassDetail {
  final String id;
  final String name;
  final String cohortCode;
  final String semester;
  final String academicYear;
  final String startTime;
  final String lecturerId;
  final String lecturerName;
  final int credits;
  final int capacity;
  final int studentCount;
  final String status;
  final String subjectId;
  final String subjectName;
  final String departmentId;
  final String departmentName;
  final List<StudentClassSchedule> schedules;
  final List<StudentClassAttendance> attendanceSessions;
  final List<StudentRosterEntry> students;

  const StudentClassDetail({
    required this.id,
    required this.name,
    required this.cohortCode,
    required this.semester,
    required this.academicYear,
    required this.startTime,
    required this.lecturerId,
    required this.lecturerName,
    required this.credits,
    required this.capacity,
    required this.studentCount,
    required this.status,
    required this.subjectId,
    required this.subjectName,
    required this.departmentId,
    required this.departmentName,
    required this.schedules,
    required this.attendanceSessions,
    required this.students,
  });

  factory StudentClassDetail.fromJson(Map<String, dynamic> json) {
    final classInfo = json['class'];
    if (classInfo is! Map) {
      throw const FormatException('Dữ liệu chi tiết lớp học không hợp lệ.');
    }
    final data = Map<String, dynamic>.from(classInfo);
    final schedules = json['schedules'];
    final attendanceSessions = json['attendanceSessions'];
    final students = json['students'];
    if (schedules is! List ||
        attendanceSessions is! List ||
        students is! List) {
      throw const FormatException(
        'Thiếu lịch học, kết quả điểm danh hoặc danh sách sinh viên của lớp.',
      );
    }
    return StudentClassDetail(
      id: data['id']?.toString() ?? '',
      name: data['name']?.toString() ?? '',
      cohortCode: data['cohortCode']?.toString() ?? '',
      semester: data['semester']?.toString() ?? '',
      academicYear: data['academicYear']?.toString() ?? '',
      startTime: data['startTime']?.toString() ?? '',
      lecturerId: data['lecturerId']?.toString() ?? '',
      lecturerName: data['lecturerName']?.toString() ?? '',
      credits: _parseCount(data['credits']),
      capacity: _parseCount(data['capacity']),
      studentCount: _parseCount(data['studentCount']),
      status: data['status']?.toString() ?? '',
      subjectId: data['subjectId']?.toString() ?? '',
      subjectName: data['subjectName']?.toString() ?? '',
      departmentId: data['departmentId']?.toString() ?? '',
      departmentName: data['departmentName']?.toString() ?? '',
      schedules: schedules
          .whereType<Map>()
          .map(
            (schedule) => StudentClassSchedule.fromJson(
              Map<String, dynamic>.from(schedule),
            ),
          )
          .toList(),
      attendanceSessions: attendanceSessions
          .whereType<Map>()
          .map(
            (session) => StudentClassAttendance.fromJson(
              Map<String, dynamic>.from(session),
            ),
          )
          .toList(),
      students: students
          .whereType<Map>()
          .map(
            (student) =>
                StudentRosterEntry.fromJson(Map<String, dynamic>.from(student)),
          )
          .toList(),
    );
  }

  static int _parseCount(dynamic value) =>
      num.tryParse(value?.toString() ?? '')?.round() ?? 0;
}

class StudentClassAttendance {
  final String id;
  final String name;
  final String startTime;
  final String checkedInAt;
  final String status;
  final String method;

  const StudentClassAttendance({
    required this.id,
    required this.name,
    required this.startTime,
    required this.checkedInAt,
    required this.status,
    required this.method,
  });

  factory StudentClassAttendance.fromJson(Map<String, dynamic> json) =>
      StudentClassAttendance(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        startTime: json['startTime']?.toString() ?? '',
        checkedInAt: json['checkedInAt']?.toString() ?? '',
        status: json['status']?.toString() ?? 'Chưa điểm danh',
        method: json['method']?.toString() ?? '',
      );
}

class StudentClassSchedule {
  final int weekday;
  final String startTime;
  final String endTime;
  final String room;
  final String startsOn;
  final String endsOn;

  const StudentClassSchedule({
    required this.weekday,
    required this.startTime,
    required this.endTime,
    required this.room,
    required this.startsOn,
    required this.endsOn,
  });

  factory StudentClassSchedule.fromJson(Map<String, dynamic> json) =>
      StudentClassSchedule(
        weekday: int.tryParse(json['weekday']?.toString() ?? '') ?? 0,
        startTime: json['startTime']?.toString() ?? '',
        endTime: json['endTime']?.toString() ?? '',
        room: json['room']?.toString() ?? '',
        startsOn: json['startsOn']?.toString() ?? '',
        endsOn: json['endsOn']?.toString() ?? '',
      );

  String get weekdayLabel => switch (weekday) {
    1 => 'Thứ 2',
    2 => 'Thứ 3',
    3 => 'Thứ 4',
    4 => 'Thứ 5',
    5 => 'Thứ 6',
    6 => 'Thứ 7',
    7 => 'Chủ nhật',
    _ => 'Chưa xếp lịch',
  };
}
