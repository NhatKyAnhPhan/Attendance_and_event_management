import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

class EventsPage extends StatelessWidget {
  const EventsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);

    final events = [
      {
        'name': 'Ngày hội Việc làm IT 2025',
        'date': '15/04/2025',
        'time': '08:30 - 17:00',
        'location': 'Sảnh A, HUIT',
        'participants': 240,
        'status': 'Đang mở',
      },
      {
        'name': 'Workshop AI ứng dụng',
        'date': '28/04/2025',
        'time': '09:00 - 12:00',
        'location': 'Phòng lab AI',
        'participants': 136,
        'status': 'Sắp diễn ra',
      },
      {
        'name': 'Chạy bộ cộng đồng HUIT',
        'date': '05/05/2025',
        'time': '06:30 - 08:00',
        'location': 'Công viên trường',
        'participants': 92,
        'status': 'Đã duyệt',
      },
    ];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Quản lý sự kiện', style: AppTextStyles.displayLg(c.foreground)),
        const SizedBox(height: 8),
        Text(
          'Theo dõi, duyệt và quản lý các hoạt động của trường',
          style: AppTextStyles.bodySm(c.mutedForeground),
        ),
        const SizedBox(height: 20),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 2.4,
          children: [
            _SummaryCard(title: 'Tổng sự kiện', value: '28', color: c.primary, bg: c.secondary),
            _SummaryCard(title: 'Đã duyệt', value: '18', color: c.success, bg: const Color(0xFFDCFCE7)),
            _SummaryCard(title: 'Đăng ký', value: '1,204', color: c.warning, bg: const Color(0xFFFEF3C7)),
          ],
        ),
        const SizedBox(height: 20),
        ...events.map((event) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: c.card,
                  border: Border.all(color: c.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3E8FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.event, color: Color(0xFF7C3AED), size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event['name'] as String,
                            style: AppTextStyles.displaySm(c.foreground),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.calendar_today_outlined, size: 14),
                              const SizedBox(width: 6),
                              Text('${event['date']} · ${event['time']}', style: AppTextStyles.bodySm(c.mutedForeground)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.location_on_outlined, size: 14),
                              const SizedBox(width: 6),
                              Text(event['location'] as String, style: AppTextStyles.bodySm(c.mutedForeground)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: c.secondary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            event['status'] as String,
                            style: AppTextStyles.bodyXs(c.primary),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '${event['participants']} người',
                          style: AppTextStyles.displayXs(c.foreground),
                        ),
                        const SizedBox(height: 6),
                        OutlinedButton(
                          onPressed: () {},
                          child: const Text('Xem chi tiết'),
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

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final Color bg;

  const _SummaryCard({
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
