import '../../core/constants/role.dart';

/// Dữ liệu chỉ đọc dành cho hồ sơ Giảng viên/Cán bộ.
///
/// Các alias giúp giao diện tiếp tục dùng được nếu session được bổ sung field
/// trong tương lai mà không cần tạo repository hoặc API riêng cho màn hình này.
class ProfileViewModel {
  ProfileViewModel._({
    required this.role,
    required this.name,
    required this.code,
    required this.email,
    required this.phone,
    required this.birthDate,
    required this.gender,
    required this.hometown,
    required this.currentAddress,
    required this.subjectDepartment,
    required this.unit,
    required this.position,
    required this.degree,
    required this.workStartDate,
    required this.tenure,
    required this.accountStatus,
    required this.avatarUrl,
  });

  static const unavailable = 'Chưa cập nhật';

  final Role role;
  final String name;
  final String code;
  final String email;
  final String phone;
  final String birthDate;
  final String gender;
  final String hometown;
  final String currentAddress;
  final String subjectDepartment;
  final String unit;
  final String position;
  final String degree;
  final String workStartDate;
  final String tenure;
  final String accountStatus;
  final String? avatarUrl;

  bool get isLecturer => role == Role.lecturer;
  String get roleLabel => role.label;
  String get codeLabel => isLecturer ? 'Mã giảng viên' : 'Mã nhân viên';
  String get pageTitle =>
      isLecturer ? 'Thông tin giảng viên' : 'Thông tin cán bộ';

  String get initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return isLecturer ? 'GV' : 'CB';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  factory ProfileViewModel.fromSession({
    required Map<String, dynamic> user,
    required Role role,
  }) {
    final startDate = _firstValue(user, const [
      'workStartDate',
      'startDate',
      'employmentDate',
      'joinedAt',
      'ngayBatDau',
      'ngaybatdau',
    ]);

    return ProfileViewModel._(
      role: role,
      name: _valueOrUnavailable(
        _firstValue(user, const ['name', 'fullName', 'displayName', 'hoTen']),
        fallback: role.label,
      ),
      code: _valueOrUnavailable(
        _firstValue(user, const [
          'code',
          'lecturerCode',
          'teacherCode',
          'staffCode',
          'employeeCode',
          'id',
        ]),
      ),
      email: _valueOrUnavailable(_firstValue(user, const ['email'])),
      phone: _valueOrUnavailable(
        _firstValue(user, const [
          'phone',
          'phoneNumber',
          'mobile',
          'soDienThoai',
          'sodienthoai',
        ]),
      ),
      birthDate: _formatDate(
        _firstValue(user, const [
          'birthDate',
          'dateOfBirth',
          'dob',
          'ngaySinh',
          'ngaysinh',
        ]),
      ),
      gender: _valueOrUnavailable(
        _firstValue(user, const ['gender', 'gioiTinh', 'gioitinh']),
      ),
      hometown: _valueOrUnavailable(
        _firstValue(user, const [
          'hometown',
          'placeOfOrigin',
          'queQuan',
          'quequan',
        ]),
      ),
      currentAddress: _valueOrUnavailable(
        _firstValue(user, const [
          'currentAddress',
          'address',
          'diaChiHienTai',
          'diaChi',
          'diachi',
        ]),
      ),
      subjectDepartment: _valueOrUnavailable(
        _firstValue(user, const [
          'subjectDepartment',
          'subject',
          'boMon',
          'bomon',
        ]),
      ),
      unit: _valueOrUnavailable(
        _firstValue(user, const [
          'unitName',
          'unit',
          'departmentName',
          'department',
          'dept',
          'faculty',
          'donVi',
          'donvi',
          'khoa',
        ]),
      ),
      position: _valueOrUnavailable(
        _firstValue(user, const [
          'position',
          'jobTitle',
          'title',
          'chucVu',
          'chucvu',
        ]),
      ),
      degree: _valueOrUnavailable(
        _firstValue(user, const [
          'academicDegree',
          'degree',
          'qualification',
          'hocVi',
          'hocvi',
          'trinhDo',
          'trinhdo',
        ]),
      ),
      workStartDate: _formatDate(startDate),
      tenure: _formatTenure(startDate),
      accountStatus: _valueOrUnavailable(
        _firstValue(user, const ['status', 'accountStatus']),
      ),
      avatarUrl: _firstValue(user, const [
        'avatarUrl',
        'avatar',
        'photoUrl',
        'profileImage',
      ]),
    );
  }

  static String? _firstValue(Map<String, dynamic> user, List<String> keys) {
    for (final key in keys) {
      final value = user[key]?.toString().trim();
      if (value != null && value.isNotEmpty && value.toLowerCase() != 'null') {
        return value;
      }
    }
    return null;
  }

  static String _valueOrUnavailable(String? value, {String? fallback}) {
    return value ?? fallback ?? unavailable;
  }

  static String _formatDate(String? value) {
    if (value == null) return unavailable;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    final day = parsed.day.toString().padLeft(2, '0');
    final month = parsed.month.toString().padLeft(2, '0');
    return '$day/$month/${parsed.year}';
  }

  static String _formatTenure(String? value) {
    if (value == null) return unavailable;
    final start = DateTime.tryParse(value);
    if (start == null || start.isAfter(DateTime.now())) return unavailable;

    final today = DateTime.now();
    var years = today.year - start.year;
    var months = today.month - start.month;
    if (today.day < start.day) months--;
    if (months < 0) {
      years--;
      months += 12;
    }

    if (years == 0 && months == 0) return 'Dưới 1 tháng';
    if (years == 0) return '$months tháng';
    if (months == 0) return '$years năm';
    return '$years năm $months tháng';
  }
}