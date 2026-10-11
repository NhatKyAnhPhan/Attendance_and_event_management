import '../../core/utils/archive_policy.dart';

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
  final int capacity;
  final int credits;
  final String semester;
  final String startTime;
  final String subjectId;
  final String subjectCode;
  final String departmentId;
  final String majorId;
  final String majorName;
  final String majorAbbreviation;
  final String cohortCode;
  final String status;
  final String room; // phòng học mặc định
  final String schedule; // vd "Thứ 3, 13:00–15:00"

  bool get isClosed => status.toLowerCase() == 'đã đóng';

  bool get isArchived =>
      isClosed ||
      isOlderThanOneYear(DateTime.tryParse(startTime)?.toLocal());

  const ClassModel({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
    required this.lecturerId,
    required this.lecturerName,
    required this.studentCount,
    this.capacity = 0,
    this.credits = 0,
    required this.semester,
    this.startTime = '',
    this.subjectId = '',
    this.subjectCode = '',
    this.departmentId = '',
    this.majorId = '',
    this.majorName = '',
    this.majorAbbreviation = '',
    this.cohortCode = '',
    this.status = '',
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
      studentCount: _parseCount(json['studentCount']),
      capacity: _parseCount(json['capacity']),
      credits: _parseCount(json['credits']),
      semester: json['semester'] as String? ?? '',
      startTime: json['startTime']?.toString() ?? '',
      subjectId: json['subjectId']?.toString() ?? '',
      subjectCode: json['subjectCode']?.toString() ?? '',
      departmentId: json['departmentId']?.toString() ?? '',
      majorId: json['majorId']?.toString() ?? '',
      majorName: json['majorName']?.toString() ?? '',
      majorAbbreviation: json['majorAbbreviation']?.toString() ?? '',
      cohortCode: json['cohortCode']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      room: json['room'] as String? ?? '',
      schedule: json['schedule'] as String? ?? '',
    );
  }

  static int _parseCount(dynamic value) =>
      num.tryParse(value?.toString() ?? '')?.round() ?? 0;

  // Chuyển model lớp học phần thành dữ liệu JSON.
  Map<String, dynamic> toJson() => {
    'id': id,
    'code': code,
    'name': name,
    'type': type == ClassType.homeroom ? 'homeroom' : 'courseSection',
    'lecturerId': lecturerId,
    'lecturerName': lecturerName,
    'studentCount': studentCount,
    'capacity': capacity,
    'credits': credits,
    'semester': semester,
    'startTime': startTime,
    'subjectId': subjectId,
    'subjectCode': subjectCode,
    'departmentId': departmentId,
    'majorId': majorId,
    'majorName': majorName,
    'majorAbbreviation': majorAbbreviation,
    'cohortCode': cohortCode,
    'status': status,
    'room': room,
    'schedule': schedule,
  };
}

class ClassCohort {
  final String code;

  const ClassCohort({required this.code});

  factory ClassCohort.fromJson(Map<String, dynamic> json) =>
      ClassCohort(code: json['code']?.toString() ?? '');
}

class ClassOptions {
  final List<ClassCohort> cohorts;
  final List<ClassSubjectOption> subjects;

  const ClassOptions({required this.cohorts, required this.subjects});
}

class ClassSubjectOption {
  final String id;
  final String code;
  final String name;
  final String majorId;
  final String majorName;
  final String departmentId;
  final String semester;
  final int credits;

  const ClassSubjectOption({
    required this.id,
    required this.code,
    required this.name,
    required this.majorId,
    required this.majorName,
    required this.departmentId,
    required this.semester,
    this.credits = 0,
  });

  factory ClassSubjectOption.fromJson(Map<String, dynamic> json) =>
      ClassSubjectOption(
        id: json['id']?.toString() ?? '',
        code: json['code']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        majorId: json['majorId']?.toString() ?? '',
        majorName: json['majorName']?.toString() ?? '',
        departmentId: json['departmentId']?.toString() ?? '',
        semester: json['semester']?.toString() ?? '',
        credits: int.tryParse(json['credits']?.toString() ?? '') ?? 0,
      );
}

class ClassLecturer {
  final String id;
  final String name;

  const ClassLecturer({required this.id, required this.name});

  factory ClassLecturer.fromJson(Map<String, dynamic> json) => ClassLecturer(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
  );
}

class ClassStudentImportResult {
  final int importedCount;
  final int alreadyMemberCount;
  final List<String> unknownStudentIds;

  const ClassStudentImportResult({
    required this.importedCount,
    required this.alreadyMemberCount,
    required this.unknownStudentIds,
  });

  factory ClassStudentImportResult.fromJson(Map<String, dynamic> json) =>
      ClassStudentImportResult(
        importedCount: int.tryParse(json['importedCount']?.toString() ?? '') ?? 0,
        alreadyMemberCount:
            int.tryParse(json['alreadyMemberCount']?.toString() ?? '') ?? 0,
        unknownStudentIds: json['unknownStudentIds'] is List
            ? (json['unknownStudentIds'] as List)
                  .map((id) => id.toString())
                  .toList()
            : const [],
      );
}
