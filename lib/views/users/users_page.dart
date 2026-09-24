import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

class UsersPage extends StatelessWidget {
  const UsersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);

    final users = [
      {'name': 'Nguyễn Văn An', 'code': '21IT001', 'role': 'Sinh viên', 'dept': 'CNTT', 'status': 'Hoạt động'},
      {'name': 'Lê Thị Bích', 'code': '22IT014', 'role': 'Sinh viên', 'dept': 'CNTT', 'status': 'Hoạt động'},
      {'name': 'TS. Trần Văn Bình', 'code': 'GV001', 'role': 'Giảng viên', 'dept': 'CNTT', 'status': 'Hoạt động'},
      {'name': 'ThS. Lê Thị Cẩm', 'code': 'GV013', 'role': 'Giảng viên', 'dept': 'CNTT', 'status': 'Tạm khóa'},
    ];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Quản lý người dùng', style: AppTextStyles.displayLg(c.foreground)),
        const SizedBox(height: 8),
        Text('Danh sách tài khoản và trạng thái hoạt động', style: AppTextStyles.bodySm(c.mutedForeground)),
        const SizedBox(height: 20),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 2.5,
          children: [
            _StatTile(title: 'Tổng tài khoản', value: '1,456', color: c.primary, bg: c.secondary),
            _StatTile(title: 'Sinh viên', value: '1,240', color: c.info, bg: const Color(0xFFE0F2FE)),
            _StatTile(title: 'Giảng viên', value: '184', color: c.success, bg: const Color(0xFFDCFCE7)),
            _StatTile(title: 'Tạm khóa', value: '32', color: c.danger, bg: const Color(0xFFFEE2E2)),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          decoration: BoxDecoration(
            color: c.card,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Họ tên')),
                DataColumn(label: Text('Mã')),
                DataColumn(label: Text('Vai trò')),
                DataColumn(label: Text('Khoa')),
                DataColumn(label: Text('Trạng thái')),
              ],
              rows: users
                  .map(
                    (user) => DataRow(
                      cells: [
                        DataCell(Text(user['name'] as String)),
                        DataCell(Text(user['code'] as String)),
                        DataCell(Text(user['role'] as String)),
                        DataCell(Text(user['dept'] as String)),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: (user['status'] as String) == 'Tạm khóa'
                                  ? const Color(0xFFFEE2E2)
                                  : const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              user['status'] as String,
                              style: AppTextStyles.bodyXs(
                                (user['status'] as String) == 'Tạm khóa' ? c.danger : c.success,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final Color bg;

  const _StatTile({
    required this.title,
    required this.value,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: AppTextStyles.bodySm(color)),
          const SizedBox(height: 8),
          Text(value, style: AppTextStyles.displayLg(color).copyWith(fontSize: 22)),
        ],
      ),
    );
  }
}
