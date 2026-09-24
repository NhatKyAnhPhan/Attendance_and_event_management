import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);

    final stats = [
      {'label': 'Tổng điểm danh', 'value': '8,742', 'color': c.primary},
      {'label': 'Có mặt', 'value': '82.3%', 'color': c.success},
      {'label': 'Muộn', 'value': '9.1%', 'color': c.warning},
      {'label': 'Vắng', 'value': '6.4%', 'color': c.danger},
    ];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Báo cáo & thống kê', style: AppTextStyles.displayLg(c.foreground)),
        const SizedBox(height: 8),
        Text(
          'Tổng quan hiệu suất học tập và điểm danh theo thời gian',
          style: AppTextStyles.bodySm(c.mutedForeground),
        ),
        const SizedBox(height: 20),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 2.5,
          children: stats
              .map((item) => Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: c.card,
                      border: Border.all(color: c.border),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item['label'] as String, style: AppTextStyles.bodySm(c.mutedForeground)),
                        const SizedBox(height: 8),
                        Text(
                          item['value'] as String,
                          style: AppTextStyles.displayLg(item['color'] as Color).copyWith(fontSize: 22),
                        ),
                      ],
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 900;
            final charts = [
              _ReportChartCard(title: 'Xu hướng điểm danh theo tuần', child: SizedBox(height: 220, child: _WeeklyChart(c: c))),
              _ReportChartCard(title: 'Tỷ lệ điểm danh', child: SizedBox(height: 220, child: _PieChart(c: c))),
            ];
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: charts[0]),
                  const SizedBox(width: 16),
                  Expanded(child: charts[1]),
                ],
              );
            }
            return Column(
              children: [charts[0], const SizedBox(height: 16), charts[1]],
            );
          },
        ),
      ],
    );
  }
}

class _ReportChartCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _ReportChartCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.displaySm(c.foreground)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _WeeklyChart extends StatelessWidget {
  final AppColors c;
  const _WeeklyChart({required this.c});

  @override
  Widget build(BuildContext context) {
    final weeks = [
      {'day': 'T2', 'value': 78.0},
      {'day': 'T3', 'value': 83.0},
      {'day': 'T4', 'value': 69.0},
      {'day': 'T5', 'value': 92.0},
      {'day': 'T6', 'value': 88.0},
      {'day': 'T7', 'value': 73.0},
      {'day': 'CN', 'value': 64.0},
    ];

    return BarChart(
      BarChartData(
        maxY: 100,
        barGroups: List.generate(weeks.length, (index) {
          final item = weeks[index];
          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: item['value'] as double,
                width: 18,
                borderRadius: BorderRadius.circular(6),
                color: c.primary,
              ),
            ],
          );
        }),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= weeks.length) return const SizedBox.shrink();
                return Text(weeks[i]['day'] as String, style: AppTextStyles.bodyXs(c.mutedForeground));
              },
            ),
          ),
        ),
        gridData: FlGridData(show: true, getDrawingHorizontalLine: (value) => FlLine(color: c.border, strokeWidth: 1)),
        borderData: FlBorderData(show: false),
      ),
    );
  }
}

class _PieChart extends StatelessWidget {
  final AppColors c;
  const _PieChart({required this.c});

  @override
  Widget build(BuildContext context) {
    final pieData = [
      {'label': 'Có mặt', 'value': 76.0, 'color': const Color(0xFF16A34A)},
      {'label': 'Muộn', 'value': 12.0, 'color': const Color(0xFFD97706)},
      {'label': 'Vắng', 'value': 8.0, 'color': const Color(0xFFDC2626)},
      {'label': 'Phép', 'value': 4.0, 'color': const Color(0xFF7C3AED)},
    ];

    return Column(
      children: [
        SizedBox(
          height: 150,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 38,
              sections: pieData
                  .map(
                    (item) => PieChartSectionData(
                      value: item['value'] as double,
                      color: item['color'] as Color,
                      title: '',
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        ...pieData.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: item['color'] as Color, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 8),
                Expanded(child: Text(item['label'] as String, style: AppTextStyles.bodySm(c.foreground))),
                Text('${item['value']}%', style: AppTextStyles.bodySm(c.foreground).copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
