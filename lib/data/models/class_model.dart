/// Góp ý giảng viên: phải phân biệt rõ 2 loại lớp — sinh viên "Join" (tự
/// động thêm vào) chứ không "đăng ký" như sự kiện.
enum ClassType {
  /// Lớp học phần — theo môn học, theo học kỳ (vd CS301 — Công nghệ phần mềm)
  courseSection,

  /// Lớp chủ nhiệm — lớp cố định theo khóa/ngành (vd 21IT — do 1 GV chủ nhiệm)
  homeroom,
}

extension ClassTypeX on ClassType {
  String get label =>
      this == ClassType.courseSection ? 'Lớp học phần' : 'Lớp chủ nhiệm';
}

class ClassModel {
  final String id;
  final String code; // vd "CS301"
  final String name; // vd "Công nghệ phần mềm"
  final ClassType type;
  final String lecturerId;
  final String lecturerName;
  final int studentCount;
  final String semester; // vd "2024-2025 HK2"
  final String schoolYear;
  final DateTime? startDate;
  final DateTime? endDate;
  final String room; // phòng học mặc định
  final String schedule; // vd "Thứ 3, 13:00–15:00"

  const ClassModel({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
    required this.lecturerId,
    required this.lecturerName,
    required this.studentCount,
    required this.semester,
    this.schoolYear = '',
    this.startDate,
    this.endDate,
    required this.room,
    required this.schedule,
  });

  // Đọc lớp học phần từ dữ liệu API và áp dụng giá trị mặc định cho trường thiếu.
  factory ClassModel.fromJson(Map<String, dynamic> json) {
    return ClassModel(
      id: json['id'] as String,
      code: json['code'] as String,
      name: json['name'] as String,
      type: (json['type'] as String?) == 'homeroom'
          ? ClassType.homeroom
          : ClassType.courseSection,
      lecturerId: json['lecturerId'] as String? ?? '',
      lecturerName: json['lecturerName'] as String? ?? '',
      studentCount: json['studentCount'] as int? ?? 0,
      semester: json['semester'] as String? ?? '',
      schoolYear: json['schoolYear'] as String? ?? '',
      startDate: DateTime.tryParse(json['startDate']?.toString() ?? ''),
      endDate: DateTime.tryParse(json['endDate']?.toString() ?? ''),
      room: json['room'] as String? ?? '',
      schedule: json['schedule'] as String? ?? '',
    );
  }

  // Chuyển model lớp học phần thành dữ liệu JSON.
  Map<String, dynamic> toJson() => {
    'id': id,
    'code': code,
    'name': name,
    'type': type == ClassType.homeroom ? 'homeroom' : 'courseSection',
    'lecturerId': lecturerId,
    'lecturerName': lecturerName,
    'studentCount': studentCount,
    'semester': semester,
    'schoolYear': schoolYear,
    'startDate': startDate?.toIso8601String(),
    'endDate': endDate?.toIso8601String(),
    'room': room,
    'schedule': schedule,
  };
}

bool isValidClassDateRange(
  DateTime startDate,
  DateTime endDate, {
  int? schoolYear,
}) =>
    !endDate.isBefore(startDate) &&
    (schoolYear == null || startDate.year >= schoolYear);

class ClassLecturer {
  final String id;
  final String name;

  const ClassLecturer({required this.id, required this.name});

  factory ClassLecturer.fromJson(Map<String, dynamic> json) => ClassLecturer(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
  );
}
