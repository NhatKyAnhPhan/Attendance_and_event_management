import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/constants/role.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_button.dart';

class _DayStat {
  final String day;
  final double present;
  final double late;
  final double absent;
  const _DayStat(this.day, this.present, this.late, this.absent);
}

const _weekData = [
  _DayStat('T2', 82, 10, 8),
  _DayStat('T3', 78, 14, 8),
  _DayStat('T4', 90, 6, 4),
  _DayStat('T5', 75, 16, 9),
  _DayStat('T6', 88, 8, 4),
  _DayStat('T7', 65, 20, 15),
  _DayStat('CN', 55, 25, 20),
];

const _pieData = [
  ['Có mặt', 76.0, 0xFF16A34A],
  ['Muộn', 12.0, 0xFFD97706],
  ['Vắng', 8.0, 0xFFDC2626],
  ['Phép', 4.0, 0xFF7C3AED],
];

class _StatCardData {
  final IconData icon;
  final String label, value, sub;
  final Color color, bg;
  const _StatCardData(this.icon, this.label, this.value, this.sub, this.color, this.bg);
}

const _adminStats = [
  _StatCardData(Icons.people_outline, 'Tổng người dùng', '1,456', '+12 tuần này', Color(0xFF1E56A0), Color(0xFFDBEAFE)),
  _StatCardData(Icons.school_outlined, 'Sinh viên', '1,240', '94 lớp học', Color(0xFF0891B2), Color(0xFFE0F2FE)),
  _StatCardData(Icons.menu_book_outlined, 'Lớp đang học', '94', '12 học kỳ này', Color(0xFF16A34A), Color(0xFFDCFCE7)),
  _StatCardData(Icons.event_outlined, 'Sự kiện', '28', '8 sắp diễn ra', Color(0xFF7C3AED), Color(0xFFF3E8FF)),
  _StatCardData(Icons.check_box_outlined, 'Phiên điểm danh', '342', '47 hôm nay', Color(0xFFD97706), Color(0xFFFEF3C7)),
  _StatCardData(Icons.trending_up, 'Tỷ lệ có mặt', '82.4%', '+2.1% so tháng trước', Color(0xFFDC2626), Color(0xFFFEE2E2)),
];

const _lecturerStats = [
  _StatCardData(Icons.menu_book_outlined, 'Lớp của tôi', '5', 'HK 2024–2025', Color(0xFF1E56A0), Color(0xFFDBEAFE)),
  _StatCardData(Icons.people_outline, 'Sinh viên', '186', '5 lớp học', Color(0xFF0891B2), Color(0xFFE0F2FE)),
  _StatCardData(Icons.check_box_outlined, 'Buổi hôm nay', '2', '1 đang mở', Color(0xFF16A34A), Color(0xFFDCFCE7)),
  _StatCardData(Icons.trending_up, 'Tỷ lệ có mặt TB', '84.7%', 'Học kỳ này', Color(0xFFD97706), Color(0xFFFEF3C7)),
];

const _activities = [
  ['08:42', 'Mở điểm danh', 'CS101 — Lập trình cơ bản', 0xFF16A34A],
  ['09:15', 'Sinh viên điểm danh', 'Nguyễn Văn An — 21IT001', 0xFF0891B2],
  ['10:00', 'Đóng điểm danh', 'CS202 — Cơ sở dữ liệu', 0xFF6B7280],
  ['10:30', 'Tạo sự kiện', 'Ngày hội Việc làm IT 2025', 0xFF7C3AED],
  ['11:05', 'Xét duyệt đăng ký', '62 đơn đăng ký sự kiện', 0xFFD97706],
];

const _upcoming = [
  ['13:00', 'CS301 — Công nghệ phần mềm', 'A301', '42'],
  ['15:00', 'CS202 — Cơ sở dữ liệu', 'B204', '38'],
  ['17:00', 'CS401 — Trí tuệ nhân tạo', 'A501', '35'],
];

class DashboardPage extends StatelessWidget {
  final Role role;
  const DashboardPage({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);
    final stats = (role == Role.lecturer || role == Role.organizer) ? _lecturerStats : _adminStats;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1280),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Xin chào, ${role.label} 👋', style: AppTextStyles.displayLg(c.foreground)),
            const SizedBox(height: 4),
            Text('Học kỳ 2 — 2024/2025', style: AppTextStyles.bodySm(c.mutedForeground)),
            const SizedBox(height: 20),

            // Stat cards
            LayoutBuilder(builder: (context, constraints) {
              final cols = constraints.maxWidth > 900 ? 3 : (constraints.maxWidth > 560 ? 2 : 1);
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 2.6,
                children: stats.map((s) => _StatCard(data: s, c: c)).toList(),
              );
            }),
            const SizedBox(height: 20),

            // Charts row
            LayoutBuilder(builder: (context, constraints) {
              final isWide = constraints.maxWidth > 900;
              final barChart = AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Thống kê điểm danh tuần này', style: AppTextStyles.displaySm(c.foreground)),
                    const SizedBox(height: 16),
                    SizedBox(height: 220, child: _WeeklyBarChart(c: c)),
                  ],
                ),
              );
              final pieChart = AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tỷ lệ điểm danh', style: AppTextStyles.displaySm(c.foreground)),
                    const SizedBox(height: 16),
                    SizedBox(height: 150, child: _AttendancePieChart()),
                    const SizedBox(height: 12),
                    ..._pieData.map((d) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(children: [
                                Container(width: 10, height: 10, decoration: BoxDecoration(color: Color(d[2] as int), borderRadius: BorderRadius.circular(2))),
                                const SizedBox(width: 8),
                                Text(d[0] as String, style: AppTextStyles.bodySm(c.foreground)),
                              ]),
                              Text('${d[1]}%', style: AppTextStyles.bodySm(c.foreground).copyWith(fontWeight: FontWeight.w600)),
                            ],
                          ),
                        )),
                  ],
                ),
              );

              return isWide
                  ? IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 2, child: barChart),
                          const SizedBox(width: 16),
                          Expanded(child: pieChart),
                        ],
                      ),
                    )
                  : Column(children: [barChart, const SizedBox(height: 16), pieChart]);
            }),
            const SizedBox(height: 20),

            // Bottom row
            LayoutBuilder(builder: (context, constraints) {
              final isWide = constraints.maxWidth > 900;
              final recent = AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Hoạt động gần đây', style: AppTextStyles.displaySm(c.foreground)),
                    ),
                    Divider(height: 1, color: c.border),
                    ..._activities.map((a) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(top: 5),
                                decoration: BoxDecoration(color: Color(a[3] as int), shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(a[1] as String, style: AppTextStyles.bodySm(c.foreground).copyWith(fontWeight: FontWeight.w600)),
                                    Text(a[2] as String, style: AppTextStyles.bodyXs(c.mutedForeground)),
                                  ],
                                ),
                              ),
                              Text(a[0] as String, style: AppTextStyles.bodyXs(c.mutedForeground)),
                            ],
                          ),
                        )),
                    const SizedBox(height: 8),
                  ],
                ),
              );

              final upcoming = AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Buổi học hôm nay', style: AppTextStyles.displaySm(c.foreground)),
                    ),
                    Divider(height: 1, color: c.border),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          ..._upcoming.map((s) => Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: c.muted, borderRadius: BorderRadius.circular(8)),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 44,
                                      child: Text(s[0], style: AppTextStyles.mono(c.primary, fontSize: 13)),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(s[1], style: AppTextStyles.bodySm(c.foreground).copyWith(fontWeight: FontWeight.w600)),
                                          Text('Phòng ${s[2]} · ${s[3]} SV', style: AppTextStyles.bodyXs(c.mutedForeground)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                          AppButton(label: 'Xem tất cả buổi học', variant: AppButtonVariant.secondary, size: AppButtonSize.sm, expand: true, onPressed: () {}),
                        ],
                      ),
                    ),
                  ],
                ),
              );

              return isWide
                  ? IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [Expanded(flex: 2, child: recent), const SizedBox(width: 16), Expanded(child: upcoming)],
                      ),
                    )
                  : Column(children: [recent, const SizedBox(height: 16), upcoming]);
            }),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final _StatCardData data;
  final AppColors c;
  const _StatCard({required this.data, required this.c});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: data.bg, borderRadius: BorderRadius.circular(12)),
            child: Icon(data.icon, color: data.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(data.label, style: AppTextStyles.bodyXs(c.mutedForeground), overflow: TextOverflow.ellipsis),
                Text(data.value, style: AppTextStyles.displayLg(c.foreground).copyWith(fontSize: 22)),
                Text(data.sub, style: AppTextStyles.bodyXs(data.color), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WeeklyBarChart extends StatelessWidget {
  final AppColors c;
  const _WeeklyBarChart({required this.c});

  @override
  Widget build(BuildContext context) {
    return BarChart(
      BarChartData(
        maxY: 100,
        gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 25, getDrawingHorizontalLine: (v) => FlLine(color: c.border, strokeWidth: 1)),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32, interval: 25, getTitlesWidget: (v, meta) => Text('${v.toInt()}', style: AppTextStyles.bodyXs(c.mutedForeground)))),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= _weekData.length) return const SizedBox.shrink();
                return Padding(padding: const EdgeInsets.only(top: 6), child: Text(_weekData[i].day, style: AppTextStyles.bodyXs(c.mutedForeground)));
              },
            ),
          ),
        ),
        barGroups: List.generate(_weekData.length, (i) {
          final d = _weekData[i];
          return BarChartGroupData(x: i, barsSpace: 3, barRods: [
            BarChartRodData(toY: d.present, color: const Color(0xFF16A34A), width: 7, borderRadius: BorderRadius.circular(2)),
            BarChartRodData(toY: d.late, color: const Color(0xFFD97706), width: 7, borderRadius: BorderRadius.circular(2)),
            BarChartRodData(toY: d.absent, color: const Color(0xFFDC2626), width: 7, borderRadius: BorderRadius.circular(2)),
          ]);
        }),
      ),
    );
  }
}

class _AttendancePieChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 40,
        sections: _pieData
            .map((d) => PieChartSectionData(
                  value: d[1] as double,
                  color: Color(d[2] as int),
                  title: '',
                  radius: 32,
                ))
            .toList(),
      ),
    );
  }
}