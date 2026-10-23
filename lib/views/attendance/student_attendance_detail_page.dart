import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../lecturer_profile/widgets/profile_info_section.dart';

class StudentAttendanceDetailPage extends StatelessWidget {
  const StudentAttendanceDetailPage({
    super.key,
    required this.student,
    required this.contextTitle,
  });

  final Map<String, dynamic> student;
  final String contextTitle;

  String _value(String key) {
    final value = student[key]?.toString().trim();
    return value == null || value.isEmpty || value.toLowerCase() == 'null'
        ? 'Chưa cập nhật'
        : value;
  }

  String _formatDateTime(dynamic value) {
    final dateTime = DateTime.tryParse(value?.toString() ?? '');
    if (dateTime == null) return _value('checkedInAt');
    return DateFormat('dd/MM/yyyy-HH:mm:ss').format(dateTime.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(
      Theme.of(context).brightness == Brightness.dark,
    );
    final name = _value('studentName');
    final studentId = _value('studentId');
    final initial = name == 'Chưa cập nhật'
        ? '?'
        : name.characters.first.toUpperCase();

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text('Chi tiết sinh viên')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.card,
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(AppColors.radiusLg),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: colors.secondary,
                  child: Text(
                    initial,
                    style: AppTextStyles.displaySm(colors.primary),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: AppTextStyles.displaySm(colors.foreground),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        studentId,
                        style: AppTextStyles.bodySm(colors.mutedForeground),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ProfileInfoSection(
            title: 'Thông tin cơ bản',
            colors: colors,
            items: [
              ProfileInfoItem(
                icon: Icons.groups_outlined,
                label: 'Lớp',
                value: _value('className'),
              ),
              ProfileInfoItem(
                icon: Icons.menu_book_outlined,
                label: 'Chuyên ngành',
                value: _value('major'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ProfileInfoSection(
            title: contextTitle,
            colors: colors,
            items: [
              ProfileInfoItem(
                icon: Icons.fact_check_outlined,
                label: 'Trạng thái điểm danh',
                value: _value('attendanceStatus'),
              ),
              if (student['checkedInAt'] != null)
                ProfileInfoItem(
                  icon: Icons.schedule_outlined,
                  label: 'Thời gian điểm danh',
                  value: _formatDateTime(student['checkedInAt']),
                ),
              if (student['status'] != null)
                ProfileInfoItem(
                  icon: Icons.event_available_outlined,
                  label: 'Trạng thái đăng ký',
                  value: _value('status'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
