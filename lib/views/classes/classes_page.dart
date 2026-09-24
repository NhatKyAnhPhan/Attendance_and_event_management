import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

class ClassesPage extends StatelessWidget {
  const ClassesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);

    final classes = [
      {
        'code': 'CS101',
        'name': 'Lập trình cơ bản',
        'lecturer': 'TS. Trần Văn Bình',
        'time': 'Thứ Hai · 07:00 - 09:00',
        'room': 'A301',
        'students': 42,
        'semester': '2024-2025 HK2',
      },
      {
        'code': 'CS202',
        'name': 'Cơ sở dữ liệu',
        'lecturer': 'ThS. Lê Thị Cẩm',
        'time': 'Thứ Tư · 09:00 - 11:00',
        'room': 'B204',
        'students': 38,
        'semester': '2024-2025 HK2',
      },
      {
        'code': 'CS301',
        'name': 'Công nghệ phần mềm',
        'lecturer': 'TS. Phạm Quốc Huy',
        'time': 'Thứ Sáu · 13:00 - 15:00',
        'room': 'C105',
        'students': 46,
        'semester': '2024-2025 HK2',
      },
    ];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Quản lý lớp học', style: AppTextStyles.displayLg(c.foreground)),
        const SizedBox(height: 8),
        Text(
          'Tổng quan các lớp đang mở trong học kỳ hiện tại',
          style: AppTextStyles.bodySm(c.mutedForeground),
        ),
        const SizedBox(height: 20),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 2.3,
          children: [
            _SummaryTile(title: 'Tổng lớp', value: '28', color: c.primary, bg: c.secondary),
            _SummaryTile(title: 'Đang hoạt động', value: '18', color: c.success, bg: const Color(0xFFDCFCE7)),
            _SummaryTile(title: 'Sinh viên', value: '1,240', color: c.info, bg: const Color(0xFFE0F2FE)),
          ],
        ),
        const SizedBox(height: 20),
        ...classes.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                decoration: BoxDecoration(
                  color: c.card,
                  border: Border.all(color: c.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFFDBEAFE),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.menu_book, color: Color(0xFF1E56A0), size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                item['code'] as String,
                                style: AppTextStyles.mono(c.primary, fontSize: 12),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: c.secondary,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'Lớp học phần',
                                  style: AppTextStyles.bodyXs(c.primary),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item['name'] as String,
                            style: AppTextStyles.displaySm(c.foreground),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${item['lecturer']} · ${item['semester']}',
                            style: AppTextStyles.bodySm(c.mutedForeground),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.schedule, size: 14, color: c.mutedForeground),
                              const SizedBox(width: 6),
                              Text(item['time'] as String, style: AppTextStyles.bodyXs(c.mutedForeground)),
                              const SizedBox(width: 12),
                              Icon(Icons.location_on_outlined, size: 14, color: c.mutedForeground),
                              const SizedBox(width: 6),
                              Text(item['room'] as String, style: AppTextStyles.bodyXs(c.mutedForeground)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${item['students']} SV', style: AppTextStyles.displayXs(c.foreground)),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: () {},
                          child: const Text('Chi tiết'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final Color bg;

  const _SummaryTile({
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
