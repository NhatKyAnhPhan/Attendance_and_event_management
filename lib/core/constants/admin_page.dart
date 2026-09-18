/// Tương ứng `type Page` trong Sidebar.tsx — các trang bên trong admin_shell.
enum AdminPage {
  dashboard,
  users,
  orgUnits,
  classes,
  events,
  attendance,
  reports,
  feedback,
  certificates,
  notifications,
  settings,
}

extension AdminPageX on AdminPage {
  /// Tương ứng `pageTitles` trong App.tsx
  String get title {
    switch (this) {
      case AdminPage.dashboard:
        return 'Dashboard';
      case AdminPage.users:
        return 'Quản lý người dùng';
      case AdminPage.orgUnits:
        return 'Đơn vị tổ chức';
      case AdminPage.classes:
        return 'Quản lý lớp học';
      case AdminPage.events:
        return 'Quản lý sự kiện';
      case AdminPage.attendance:
        return 'Điểm danh';
      case AdminPage.reports:
        return 'Báo cáo & Thống kê';
      case AdminPage.feedback:
        return 'Phản hồi';
      case AdminPage.certificates:
        return 'Chứng chỉ';
      case AdminPage.notifications:
        return 'Thông báo';
      case AdminPage.settings:
        return 'Cài đặt';
    }
  }
}