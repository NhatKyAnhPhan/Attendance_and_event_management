import '../../core/constants/role.dart';

enum UserStatus { active, locked }

/// Tương ứng object trong mảng `users` của UsersPage.tsx
class UserModel {
  final String id;
  final String name;
  final String code; // mã SV / mã GV, vd 21IT001, GV001
  final Role role;
  final String department; // đơn vị, vd "CNTT"
  final String email;
  final UserStatus status;

  const UserModel({
    required this.id,
    required this.name,
    required this.code,
    required this.role,
    required this.department,
    required this.email,
    this.status = UserStatus.active,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      name: json['name'] as String,
      code: json['code'] as String,
      role: RoleX.fromString(json['role'] as String),
      department: json['dept'] as String? ?? json['department'] as String? ?? '',
      email: json['email'] as String,
      status: (json['status'] as String?) == 'locked'
          ? UserStatus.locked
          : UserStatus.active,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'code': code,
        'role': role.name,
        'dept': department,
        'email': email,
        'status': status.name,
      };
}