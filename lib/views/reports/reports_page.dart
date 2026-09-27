import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/reports_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  /// Hiển thị thống kê điểm danh được truy vấn trực tiếp từ backend.
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = AppColors.of(isDark);
    final controller = Get.put(ReportsController());

    return Obx(() {
      final summary = controller.summary;
      final present = _number(summary['present']);
      final late = _number(summary['late']);
      final absent = _number(summary['absent']);
      final total = _number(summary['total']);

      return RefreshIndicator(
        onRefresh: controller.load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Báo cáo & thống kê',
              style: AppTextStyles.displayLg(colors.foreground),
            ),
            const SizedBox(height: 6),
            Text(
              'Kết quả điểm danh trong cơ sở dữ liệu.',
              style: AppTextStyles.bodySm(colors.mutedForeground),
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) => GridView.count(
                crossAxisCount: constraints.maxWidth >= 800
                    ? 4
                    : constraints.maxWidth >= 520
                    ? 2
                    : 1,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                mainAxisExtent: 92,
                children: [
                  _SummaryTile(
                    title: 'Tổng kết quả',
                    value: '$total',
                    color: colors.primary,
                  ),
                  _SummaryTile(
                    title: 'Có mặt',
                    value: _percentage(present, total),
                    color: colors.success,
                  ),
                  _SummaryTile(
                    title: 'Muộn',
                    value: _percentage(late, total),
                    color: colors.warning,
                  ),
                  _SummaryTile(
                    title: 'Vắng',
                    value: _percentage(absent, total),
                    color: colors.danger,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Theo ngày',
              style: AppTextStyles.displaySm(colors.foreground),
            ),
            const SizedBox(height: 12),
            if (controller.loading.value && controller.dailyItems.isEmpty)
              const Center(child: CircularProgressIndicator())
            else if (controller.error.value.isNotEmpty)
              Text(
                controller.error.value,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            else if (controller.dailyItems.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    'Chưa có kết quả điểm danh để lập báo cáo.',
                    style: AppTextStyles.bodySm(colors.mutedForeground),
                  ),
                ),
              )
            else
              ...controller.dailyItems.map(
                (item) => _DailyRow(item: item, colors: colors),
              ),
          ],
        ),
      );
    });
  }

  /// Chuyển giá trị JSON sang số nguyên, mặc định 0 nếu dữ liệu trống.
  static int _number(dynamic value) =>
      int.tryParse(value?.toString() ?? '') ?? 0;

  /// Định dạng tỷ lệ từ tổng số kết quả đã được truy vấn.
  static String _percentage(int value, int total) =>
      total == 0 ? '0%' : '${(value * 100 / total).round()}%';
}

class _SummaryTile extends StatelessWidget {
  final String title;
  final String value;
  final Color color;

  const _SummaryTile({
    required this.title,
    required this.value,
    required this.color,
  });

  /// Hiển thị một chỉ số tổng hợp từ API.
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = AppColors.of(isDark);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: AppTextStyles.bodySm(colors.mutedForeground)),
          const SizedBox(height: 4),
          Text(value, style: AppTextStyles.displaySm(color)),
        ],
      ),
    );
  }
}

class _DailyRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final AppColors colors;

  const _DailyRow({required this.item, required this.colors});

  /// Hiển thị số lượt theo ngày từ kết quả API.
  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(item['date']?.toString() ?? '');
    final label = date == null
        ? item['date']?.toString() ?? ''
        : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: AppTextStyles.bodySm(colors.foreground)),
          ),
          _CountLabel(
            label: 'Có mặt',
            value: item['present'],
            color: colors.success,
          ),
          const SizedBox(width: 12),
          _CountLabel(
            label: 'Muộn',
            value: item['late'],
            color: colors.warning,
          ),
          const SizedBox(width: 12),
          _CountLabel(
            label: 'Vắng',
            value: item['absent'],
            color: colors.danger,
          ),
        ],
      ),
    );
  }
}

class _CountLabel extends StatelessWidget {
  final String label;
  final dynamic value;
  final Color color;

  const _CountLabel({
    required this.label,
    required this.value,
    required this.color,
  });

  /// Hiển thị một trạng thái điểm danh trong dòng báo cáo.
  @override
  Widget build(BuildContext context) {
    final count = int.tryParse(value?.toString() ?? '') ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('$count', style: AppTextStyles.bodySm(color)),
        Text(label, style: AppTextStyles.bodyXs(color)),
      ],
    );
  }
}
