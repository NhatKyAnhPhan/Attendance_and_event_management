import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';

/// Một nhãn và giá trị thật được dùng trong biểu đồ thống kê.
class StatisticsChartDatum {
  /// Tạo điểm dữ liệu với nhãn, số lượng và màu hiển thị.
  const StatisticsChartDatum({
    required this.label,
    required this.value,
    required this.color,
  });

  /// Tên nhóm dữ liệu nhận từ API hoặc được suy ra từ bản ghi API.
  final String label;

  /// Số lượng thật của nhóm dữ liệu.
  final int value;

  /// Màu đại diện cho nhóm dữ liệu.
  final Color color;
}

/// Một chuỗi số liệu dùng cho biểu đồ cột theo nhóm.
class StatisticsChartSeries {
  /// Tạo chuỗi có tên, màu và giá trị tương ứng với từng danh mục.
  const StatisticsChartSeries({
    required this.label,
    required this.color,
    required this.values,
    this.pointColors,
  });

  /// Tên chuỗi hiển thị trong chú giải.
  final String label;

  /// Màu của các cột trong chuỗi.
  final Color color;

  /// Giá trị thật theo thứ tự danh mục của biểu đồ.
  final List<int> values;

  /// Màu tùy chọn theo từng danh mục, cùng thứ tự với [values].
  final List<Color>? pointColors;
}

/// Biểu đồ donut kèm chú giải số lượng của từng nhóm.
class StatisticsDonutChart extends StatelessWidget {
  /// Tạo biểu đồ phân bổ từ các nhóm dữ liệu đã có.
  const StatisticsDonutChart({
    super.key,
    required this.title,
    required this.data,
    required this.colors,
  });

  /// Tiêu đề biểu đồ.
  final String title;

  /// Các nhóm dữ liệu và giá trị gốc cần biểu diễn.
  final List<StatisticsChartDatum> data;

  /// Bảng màu của giao diện hiện tại.
  final AppColors colors;

  /// Vẽ tỷ trọng chính xác và giữ cả nhóm có giá trị bằng không trong chú giải.
  @override
  Widget build(BuildContext context) {
    final visibleData = data.where((item) => item.value > 0).toList();
    final total = visibleData.fold<int>(0, (sum, item) => sum + item.value);
    if (total == 0) return const SizedBox.shrink();

    return _ChartFrame(
      title: title,
      colors: colors,
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 20,
        runSpacing: 12,
        children: [
          SizedBox(
            width: 180,
            height: 180,
            child: PieChart(
              PieChartData(
                centerSpaceRadius: 42,
                sectionsSpace: 2,
                sections: visibleData
                    .map(
                      (item) => PieChartSectionData(
                        value: item.value.toDouble(),
                        color: item.color,
                        radius: 58,
                        title: '${(item.value * 100 / total).round()}%',
                        titleStyle: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 150, maxWidth: 260),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: data
                  .map((item) => _ChartLegend(item: item, colors: colors))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Biểu đồ cột nhóm theo danh mục với trục giá trị nguyên.
class StatisticsBarChart extends StatelessWidget {
  /// Tạo biểu đồ từ các danh mục và chuỗi số liệu tương ứng.
  const StatisticsBarChart({
    super.key,
    required this.title,
    required this.categories,
    required this.series,
    required this.colors,
    this.verticalCategories = false,
  });

  /// Tiêu đề biểu đồ.
  final String title;

  /// Nhãn trên trục ngang.
  final List<String> categories;

  /// Các chuỗi số liệu có cùng thứ tự với danh mục.
  final List<StatisticsChartSeries> series;

  /// Bảng màu của giao diện hiện tại.
  final AppColors colors;

  /// Hiển thị danh mục theo chiều dọc, phù hợp với danh sách dài.
  final bool verticalCategories;

  /// Vẽ nguyên trạng giá trị số và cho phép cuộn khi có nhiều danh mục.
  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty || series.isEmpty) return const SizedBox.shrink();
    final maxValue = series
        .expand((item) => item.values)
        .fold<int>(0, math.max);
    if (maxValue == 0) return const SizedBox.shrink();
    if (verticalCategories) {
      return _VerticalCategoryBarChart(
        title: title,
        categories: categories,
        series: series,
        colors: colors,
        maxValue: maxValue,
      );
    }

    return _ChartFrame(
      title: title,
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (series.length > 1) ...[
            Wrap(
              spacing: 14,
              runSpacing: 8,
              children: series
                  .map((item) => _SeriesLegend(item: item, colors: colors))
                  .toList(),
            ),
            const SizedBox(height: 14),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final chartWidth = math.max(
                constraints.maxWidth,
                categories.length * 64.0,
              );
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: chartWidth,
                  height: 230,
                  child: BarChart(
                    BarChartData(
                      maxY: maxValue * 1.15,
                      minY: 0,
                      alignment: BarChartAlignment.spaceAround,
                      groupsSpace: 10,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (_) =>
                            FlLine(color: colors.border, strokeWidth: 1),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 34,
                            interval: math.max(
                              1,
                              (maxValue / 4).ceilToDouble(),
                            ),
                            getTitlesWidget: (value, _) => Text(
                              value.toInt().toString(),
                              style: AppTextStyles.bodyXs(
                                colors.mutedForeground,
                              ),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 38,
                            getTitlesWidget: (value, _) {
                              final index = value.toInt();
                              if (index < 0 || index >= categories.length) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  categories[index],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.bodyXs(
                                    colors.mutedForeground,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      barGroups: List.generate(categories.length, (index) {
                        return BarChartGroupData(
                          x: index,
                          barsSpace: 3,
                          barRods: series.map((item) {
                            final value = index < item.values.length
                                ? item.values[index]
                                : 0;
                            return BarChartRodData(
                              toY: value.toDouble(),
                              color:
                                  item.pointColors != null &&
                                      index < item.pointColors!.length
                                  ? item.pointColors![index]
                                  : item.color,
                              width: series.length > 2 ? 8 : 12,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(3),
                              ),
                            );
                          }).toList(),
                        );
                      }),
                    ),
                  ),
                ),
              );
            },
          ),
          if (series.length == 1 && series.single.pointColors == null) ...[
            const SizedBox(height: 10),
            _SeriesLegend(item: series.single, colors: colors),
          ],
        ],
      ),
    );
  }
}

/// Khung thống nhất tiêu đề, nền và đường viền cho các biểu đồ.
class _ChartFrame extends StatelessWidget {
  /// Tạo khung biểu đồ dùng màu theo giao diện hiện tại.
  const _ChartFrame({
    required this.title,
    required this.colors,
    required this.child,
  });

  /// Tiêu đề hiển thị phía trên biểu đồ.
  final String title;

  /// Bảng màu của giao diện hiện tại.
  final AppColors colors;

  /// Nội dung biểu đồ.
  final Widget child;

  /// Bố trí khung chung cho nội dung biểu đồ.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.displaySm(colors.foreground)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// Chú giải màu và số lượng cho từng phần của biểu đồ donut.
class _ChartLegend extends StatelessWidget {
  /// Tạo một dòng chú giải cho nhóm dữ liệu.
  const _ChartLegend({required this.item, required this.colors});

  /// Nhóm dữ liệu được giải thích.
  final StatisticsChartDatum item;

  /// Bảng màu của giao diện hiện tại.
  final AppColors colors;

  /// Hiển thị nhãn và giá trị nguyên của nhóm.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: item.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.label,
              style: AppTextStyles.bodySm(colors.mutedForeground),
            ),
          ),
          Text('${item.value}', style: AppTextStyles.bodySm(colors.foreground)),
        ],
      ),
    );
  }
}

/// Chú giải màu cho một chuỗi trong biểu đồ cột.
class _SeriesLegend extends StatelessWidget {
  /// Tạo dòng chú giải cho chuỗi số liệu.
  const _SeriesLegend({required this.item, required this.colors});

  /// Chuỗi được giải thích.
  final StatisticsChartSeries item;

  /// Bảng màu của giao diện hiện tại.
  final AppColors colors;

  /// Hiển thị màu và tên chuỗi số liệu.
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: item.color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(item.label, style: AppTextStyles.bodyXs(colors.mutedForeground)),
      ],
    );
  }
}

class _VerticalCategoryBarChart extends StatefulWidget {
  const _VerticalCategoryBarChart({
    required this.title,
    required this.categories,
    required this.series,
    required this.colors,
    required this.maxValue,
  });

  final String title;
  final List<String> categories;
  final List<StatisticsChartSeries> series;
  final AppColors colors;
  final int maxValue;

  @override
  State<_VerticalCategoryBarChart> createState() =>
      _VerticalCategoryBarChartState();
}

class _VerticalCategoryBarChartState extends State<_VerticalCategoryBarChart> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final chartHeight = math.min(widget.categories.length * 62.0, 372.0);

    return _ChartFrame(
      title: widget.title,
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.series.length > 1) ...[
            Wrap(
              spacing: 14,
              runSpacing: 8,
              children: widget.series
                  .map((item) => _SeriesLegend(item: item, colors: colors))
                  .toList(),
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            height: chartHeight,
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              interactive: true,
              child: ListView.separated(
                controller: _scrollController,
                padding: const EdgeInsets.only(right: 12),
                itemCount: widget.categories.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: colors.border),
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 96,
                        child: Text(
                          widget.categories[index],
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyXs(colors.mutedForeground),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: widget.series.map((item) {
                            final value = index < item.values.length
                                ? item.values[index]
                                : 0;
                            final color =
                                item.pointColors != null &&
                                    index < item.pointColors!.length
                                ? item.pointColors![index]
                                : item.color;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: value / widget.maxValue,
                                        minHeight: 7,
                                        backgroundColor: colors.border,
                                        color: color,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 24,
                                    child: Text(
                                      '$value',
                                      textAlign: TextAlign.end,
                                      style: AppTextStyles.bodyXs(
                                        colors.mutedForeground,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
