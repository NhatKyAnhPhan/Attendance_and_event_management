import 'package:flutter/material.dart';

import '../shared/admin_data_page.dart';

class EventsPage extends StatelessWidget {
  const EventsPage({super.key});

  /// Tải danh sách sự kiện và lượt đăng ký từ API.
  @override
  Widget build(BuildContext context) {
    return const AdminDataPage(
      title: 'Quản lý sự kiện',
      endpoint: '/api/admin/events',
      columns: ['Mã', 'Tên sự kiện', 'Địa điểm', 'Thời gian', 'Lượt đăng ký'],
    );
  }
}
