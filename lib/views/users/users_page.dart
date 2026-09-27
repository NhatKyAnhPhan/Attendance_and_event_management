import 'package:flutter/material.dart';

import '../shared/admin_data_page.dart';

class UsersPage extends StatelessWidget {
  const UsersPage({super.key});

  /// Tải danh sách người dùng từ API quản trị.
  @override
  Widget build(BuildContext context) {
    return const AdminDataPage(
      title: 'Quản lý người dùng',
      endpoint: '/api/admin/users',
      columns: ['Mã', 'Họ tên', 'Email', 'Vai trò', 'Trạng thái'],
    );
  }
}
