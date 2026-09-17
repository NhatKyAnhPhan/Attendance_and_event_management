/// 4 vai trò trong hệ thống — tương ứng `export type Role` trong Sidebar.tsx
enum Role { admin, lecturer, organizer, student }

extension RoleX on Role {
  /// Nhãn tiếng Việt — tương ứng `roleLabels` trong Sidebar.tsx / UsersPage.tsx
  String get label {
    switch (this) {
      case Role.admin:
        return 'Quản trị viên';
      case Role.lecturer:
        return 'Giảng viên';
      case Role.organizer:
        return 'Ban tổ chức';
      case Role.student:
        return 'Sinh viên';
    }
  }

  /// Chữ viết tắt hiển thị trên avatar — tương ứng badge "AD/GV/TC/SV" trong Sidebar.tsx
  String get shortCode {
    switch (this) {
      case Role.admin:
        return 'AD';
      case Role.lecturer:
        return 'GV';
      case Role.organizer:
        return 'TC';
      case Role.student:
        return 'SV';
    }
  }

  static Role fromString(String value) {
    return Role.values.firstWhere(
      (r) => r.name == value,
      orElse: () => Role.student,
    );
  }
}