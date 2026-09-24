import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../widgets/app_badge.dart';

class AttendancePage extends StatelessWidget {
  const AttendancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);

    final sessions = [
      {
        'name': 'CS101 — Lập trình cơ bản',
        'time': '07:00 - 09:00',
        'room': 'A301',
        'method': 'QR',
        'present': 38,
        'late': 4,
        'absent': 2,
      },
      {
        'name': 'CS202 — Cơ sở dữ liệu',
        'time': '09:00 - 11:00',
        'room': 'B204',
        'method': 'Face',
        'present': 31,
        'late': 5,
        'absent': 3,
      },
      {
        'name': 'CS301 — Công nghệ phần mềm',
        'time': '13:00 - 15:00',
        'room': 'C105',
        'method': 'Manual',
        'present': 42,
        'late': 2,
        'absent': 1,
      },
    ];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Điểm danh', style: AppTextStyles.displayLg(c.foreground)),
        const SizedBox(height: 8),
        Text('Tổng quan buổi học và tình trạng tham dự', style: AppTextStyles.bodySm(c.mutedForeground)),
        const SizedBox(height: 20),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 2.2,
          children: [
            _SummaryCard(title: 'Buổi mở', value: '12', color: c.primary, bg: c.secondary),
            _SummaryCard(title: 'Có mặt', value: '86%', color: c.success, bg: const Color(0xFFDCFCE7)),
            _SummaryCard(title: 'Chưa điểm danh', value: '7', color: c.warning, bg: const Color(0xFFFEF3C7)),
          ],
        ),
        const SizedBox(height: 20),
        ...sessions.map(
          (session) => Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: c.card,
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(session['name'] as String, style: AppTextStyles.displaySm(c.foreground)),
                          const SizedBox(height: 4),
                          Text('${session['time']} · Phòng ${session['room']}', style: AppTextStyles.bodySm(c.mutedForeground)),
                        ],
                      ),
                    ),
                    const AppBadge(label: 'Đang mở', status: BadgeStatus.present),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _MiniStat(label: 'Có mặt', value: '${session['present']}', color: c.success),
                    const SizedBox(width: 12),
                    _MiniStat(label: 'Muộn', value: '${session['late']}', color: c.warning),
                    const SizedBox(width: 12),
                    _MiniStat(label: 'Vắng', value: '${session['absent']}', color: c.danger),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: c.secondary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        session['method'] as String,
                        style: AppTextStyles.bodyXs(c.primary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final Color bg;

  const _SummaryCard({required this.title, required this.value, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
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

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.bodyXs(color)),
          Text(value, style: AppTextStyles.displayXs(color)),
        ],
      ),
    );
  }
}
