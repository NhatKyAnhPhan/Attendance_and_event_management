import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/dashboard_controller.dart';
import '../../core/constants/role.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

class DashboardPage extends StatelessWidget {
  final Role role;

  const DashboardPage({super.key, required this.role});

  /// Hiển thị metric theo vai trò từ API, không dùng dữ liệu tĩnh.
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = AppColors.of(isDark);
    final controller = Get.put(DashboardController());

    return Obx(() {
      final rawMetrics = controller.summary['metrics'];
      final metrics = rawMetrics is List
          ? rawMetrics.whereType<Map>().map(Map<String, dynamic>.from).toList()
          : <Map<String, dynamic>>[];

      return RefreshIndicator(
        onRefresh: controller.load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Tổng quan',
              style: AppTextStyles.displayLg(colors.foreground),
            ),
            const SizedBox(height: 4),
            Text(
              'Số liệu hiện tại · ${role.label}',
              style: AppTextStyles.bodySm(colors.mutedForeground),
            ),
            const SizedBox(height: 20),
            if (controller.loading.value && metrics.isEmpty)
              const Center(child: CircularProgressIndicator())
            else if (controller.error.value.isNotEmpty)
              Text(
                controller.error.value,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            else if (metrics.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    'Chưa có dữ liệu tổng quan.',
                    style: AppTextStyles.bodySm(colors.mutedForeground),
                  ),
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) => GridView.builder(
                  itemCount: metrics.length,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: constraints.maxWidth >= 960
                        ? 3
                        : constraints.maxWidth >= 600
                        ? 2
                        : 1,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    mainAxisExtent: 112,
                  ),
                  itemBuilder: (context, index) => _MetricTile(
                    label: metrics[index]['label']?.toString() ?? '',
                    value: metrics[index]['value']?.toString() ?? '0',
                    colors: colors,
                    color: _metricColor(
                      metrics[index]['label']?.toString() ?? '',
                      colors,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }

  /// Chọn màu nhấn theo loại số liệu, không ảnh hưởng giá trị hiển thị.
  Color _metricColor(String label, AppColors colors) {
    final normalized = label.toLowerCase();
    if (normalized.contains('vắng')) return colors.danger;
    if (normalized.contains('muộn')) return colors.warning;
    if (normalized.contains('có mặt')) return colors.success;
    if (normalized.contains('sự kiện')) return colors.info;
    return colors.primary;
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final AppColors colors;
  final Color color;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.colors,
    required this.color,
  });

  /// Hiển thị một chỉ số do endpoint dashboard trả về.
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.analytics_outlined, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: AppTextStyles.bodySm(colors.mutedForeground),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(value, style: AppTextStyles.displayMd(colors.foreground)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
