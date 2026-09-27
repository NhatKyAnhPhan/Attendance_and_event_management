/// Vai trò nội bộ của ứng dụng.
enum Role { admin, lecturer, organizer, student }

extension RoleX on Role {
  /// Kiểm tra vai trò gốc có được phép tạo hoặc cập nhật sự kiện không.
  static bool canManageEvents(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'admin' ||
        normalized == 'quản trị viên' ||
        normalized == 'ban tổ chức' ||
        normalized == 'event_organizer';
  }

  /// Nhãn tiếng Việt — tương ứng `roleLabels` trong Sidebar.tsx / UsersPage.tsx
  String get label {
    switch (this) {
      case Role.admin:
        return 'Quản trị viên';
      case Role.lecturer:
        return 'Giảng viên';
      case Role.organizer:
        return 'Cán bộ';
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
        return 'CB';
      case Role.student:
        return 'SV';
    }
  }

  static Role fromString(String value) {
    final normalized = value.trim().toLowerCase();
    // Quy đổi tên vai trò từ API hoặc dữ liệu đăng nhập về enum nội bộ.
    return switch (normalized) {
      'admin' || 'administrator' || 'quản trị viên' => Role.admin,
      'lecturer' || 'teacher' || 'giảng viên' => Role.lecturer,
      'organizer' ||
      'event_organizer' ||
      'ban tổ chức' ||
      'cán bộ' ||
      'nhân viên' ||
      'staff' ||
      'employee' => Role.organizer,
      'student' || 'sinh viên' => Role.student,
      _ => Role.student,
    };
  }
}
