import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/reports_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/attendance_report_export.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/statistics_charts.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  String _query = '';
  bool _exporting = false;

  Future<void> _exportReport(ReportsController controller) async {
    if (_exporting) return;
    final selectedClass = controller.selectedClass.value;
    if (selectedClass == null) return;

    setState(() => _exporting = true);
    try {
      final className = selectedClass['name']?.toString() ?? '';
      final bytes = buildAttendanceReportWorkbook(
        className: className,
        sessionCount: controller.sessionCount.value,
        students: controller.students.toList(),
      );
      final classId = selectedClass['id']?.toString() ?? 'lop';
      final safeClassId = classId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final fileName = 'bao_cao_diem_danh_$safeClassId.xlsx';
      final path = await FilePicker.saveFile(
        dialogTitle: 'Lưu báo cáo điểm danh lớp $className',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        bytes: Uint8List.fromList(bytes),
      );
      if (!mounted) return;
      if (kIsWeb) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Báo cáo đã được tải xuống.')),
        );
      } else if (path != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Đã lưu báo cáo tại $path')));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Không thể xuất báo cáo: $error')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = AppColors.of(isDark);
    final controller = Get.put(ReportsController());

    return Obx(() {
      final selectedClass = controller.selectedClass.value;
      final selectedClassId = selectedClass?['id']?.toString();
      final query = _query.trim().toLowerCase();
      final filteredStudents = controller.students.where((student) {
        return query.isEmpty ||
            '${student['studentId']} ${student['studentName']}'
                .toLowerCase()
                .contains(query);
      }).toList();
      final studentCount = controller.students.length;
      final report = controller.summary;
      final totalCount = _number(report['total']);
      final presentCount = _number(report['present']);
      final lateCount = _number(report['late']);
      final absentCount = _number(report['absent']);
      final excusedCount = _number(report['excused']);

      return RefreshIndicator(
        onRefresh: controller.loadClasses,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final exportButton = FilledButton.icon(
                  onPressed: _exporting ||
                          controller.loading.value ||
                          controller.loadingStudents.value ||
                          selectedClass == null
                      ? null
                      : () => _exportReport(controller),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: colors.primaryForeground,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: _exporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_outlined),
                  label: Text(_exporting ? 'Đang xuất...' : 'Xuất Excel'),
                );
                if (constraints.maxWidth < 480) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Báo cáo & thống kê',
                        style: AppTextStyles.displayLg(colors.foreground),
                      ),
                      const SizedBox(height: 8),
                      exportButton,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Báo cáo & thống kê',
                        style: AppTextStyles.displayLg(colors.foreground),
                      ),
                    ),
                    exportButton,
                  ],
                );
              },
            ),
            const SizedBox(height: 6),
            Text(
              'Chọn lớp để xem và xuất danh sách điểm danh từng sinh viên.',
              style: AppTextStyles.bodySm(colors.mutedForeground),
            ),
            const SizedBox(height: 16),
            if (controller.loading.value && controller.classes.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (controller.error.value.isNotEmpty)
              _MessagePanel(
                message: controller.error.value,
                colors: colors,
                isError: true,
              )
            else if (controller.classes.isEmpty)
              _MessagePanel(
                message: 'Bạn chưa có lớp học để lập báo cáo.',
                colors: colors,
              )
            else
              _SectionCard(
                colors: colors,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionHeading(
                      icon: Icons.filter_alt_outlined,
                      title: 'Chọn lớp học phần',
                      subtitle: 'Lọc báo cáo theo lớp bạn muốn xem',
                      colors: colors,
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: selectedClassId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        hintText: 'Chọn lớp cần xem báo cáo',
                        prefixIcon: Icon(
                          Icons.class_outlined,
                          color: colors.primary,
                        ),
                        filled: true,
                        fillColor: colors.background,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: colors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: colors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: colors.primary,
                            width: 1.5,
                          ),
                        ),
                      ),
                      items: controller.classes.map((item) {
                        final id = item['id']?.toString() ?? '';
                        final name = item['name']?.toString() ?? id;
                        return DropdownMenuItem(
                          value: id,
                          child: Text(
                            '$name · ${_number(item['studentCount'])} sinh viên',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: controller.selectClass,
                    ),
                  ],
                ),
              ),
            if (selectedClass != null) ...[
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 900
                      ? 5
                      : constraints.maxWidth >= 560
                      ? 3
                      : 2;
                  return GridView.count(
                    crossAxisCount: columns,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    mainAxisExtent: 100,
                    children: [
                      _ReportMetricCard(
                        title: 'Tổng kết quả',
                        value: '$totalCount',
                        icon: Icons.summarize_outlined,
                        color: colors.primary,
                        colors: colors,
                      ),
                      _ReportMetricCard(
                        title: 'Có mặt',
                        value: _percentage(presentCount, totalCount),
                        icon: Icons.check_circle_outline,
                        color: colors.success,
                        colors: colors,
                      ),
                      _ReportMetricCard(
                        title: 'Đi muộn',
                        value: _percentage(lateCount, totalCount),
                        icon: Icons.schedule_rounded,
                        color: colors.warning,
                        colors: colors,
                      ),
                      _ReportMetricCard(
                        title: 'Vắng',
                        value: _percentage(absentCount, totalCount),
                        icon: Icons.event_busy_outlined,
                        color: colors.danger,
                        colors: colors,
                      ),
                      _ReportMetricCard(
                        title: 'Vắng có phép',
                        value: _percentage(excusedCount, totalCount),
                        icon: Icons.event_available_outlined,
                        color: colors.primary,
                        colors: colors,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              _SectionCard(
                colors: colors,
                padding: const EdgeInsets.all(8),
                child: StatisticsDonutChart(
                  title: 'Phân bổ kết quả điểm danh',
                  colors: colors,
                  data: [
                    StatisticsChartDatum(
                      label: 'Có mặt',
                      value: presentCount,
                      color: colors.success,
                    ),
                    StatisticsChartDatum(
                      label: 'Đi muộn',
                      value: lateCount,
                      color: colors.warning,
                    ),
                    StatisticsChartDatum(
                      label: 'Vắng',
                      value: absentCount,
                      color: colors.danger,
                    ),
                    StatisticsChartDatum(
                      label: 'Vắng có phép',
                      value: excusedCount,
                      color: colors.primary,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Chi tiết theo ngày',
                style: AppTextStyles.displaySm(colors.foreground),
              ),
              const SizedBox(height: 12),
              if (controller.dailyItems.isEmpty)
                _SectionCard(
                  colors: colors,
                  child: Text(
                    'Chưa có dữ liệu điểm danh theo ngày cho lớp này.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySm(colors.mutedForeground),
                  ),
                )
              else
                _SectionCard(
                  colors: colors,
                  child: Column(
                    children: [
                      StatisticsBarChart(
                        title: 'Kết quả điểm danh theo ngày',
                        colors: colors,
                        categories: controller.dailyItems
                            .map((item) => _dateLabel(item['date']))
                            .toList(),
                        series: [
                          StatisticsChartSeries(
                            label: 'Có mặt',
                            color: colors.success,
                            values: controller.dailyItems
                                .map((item) => _number(item['present']))
                                .toList(),
                          ),
                          StatisticsChartSeries(
                            label: 'Đi muộn',
                            color: colors.warning,
                            values: controller.dailyItems
                                .map((item) => _number(item['late']))
                                .toList(),
                          ),
                          StatisticsChartSeries(
                            label: 'Vắng',
                            color: colors.danger,
                            values: controller.dailyItems
                                .map((item) => _number(item['absent']))
                                .toList(),
                          ),
                          StatisticsChartSeries(
                            label: 'Vắng có phép',
                            color: colors.primary,
                            values: controller.dailyItems
                                .map((item) => _number(item['excused']))
                                .toList(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...controller.dailyItems.map(
                        (item) => _DailyRow(item: item, colors: colors),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              _SectionCard(
                colors: colors,
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: colors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.groups_2_outlined,
                              color: colors.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  selectedClass['name']?.toString() ??
                                      'Danh sách sinh viên',
                                  style: AppTextStyles.displaySm(
                                    colors.foreground,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '$studentCount sinh viên · '
                                  '${controller.sessionCount.value} buổi điểm danh',
                                  style: AppTextStyles.bodyXs(
                                    colors.mutedForeground,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      height: 1,
                      color: colors.border,
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: AppSearchField(
                        colors: colors,
                        hintText: 'Tìm mã hoặc tên sinh viên...',
                        onChanged: (value) => setState(() => _query = value),
                      ),
                    ),
                    if (controller.loadingStudents.value)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (controller.studentError.value.isNotEmpty)
                      _MessagePanel(
                        message: controller.studentError.value,
                        colors: colors,
                        isError: true,
                      )
                    else if (controller.students.isEmpty)
                      _MessagePanel(
                        message: 'Lớp này chưa có sinh viên trong danh sách.',
                        colors: colors,
                      )
                    else if (filteredStudents.isEmpty)
                      _MessagePanel(
                        message: 'Không tìm thấy sinh viên phù hợp.',
                        colors: colors,
                      )
                    else
                      _StudentAttendanceTable(
                        students: filteredStudents,
                        colors: colors,
                      ),
                  ],
                ),
              ),
            ] else if (controller.classes.isNotEmpty &&
                controller.error.value.isEmpty) ...[
              const SizedBox(height: 28),
              _MessagePanel(
                message: 'Chọn một lớp để xem thống kê điểm danh sinh viên.',
                colors: colors,
              ),
            ],
          ],
        ),
      );
    });
  }

  static int _number(Object? value) =>
      int.tryParse(value?.toString() ?? '') ?? 0;

  static String _percentage(int value, int total) =>
      total == 0 ? '0%' : '${(value * 100 / total).round()}%';

  static String _dateLabel(Object? value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    return date == null
        ? value?.toString() ?? ''
        : '${date.day.toString().padLeft(2, '0')}/'
              '${date.month.toString().padLeft(2, '0')}';
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.colors,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final AppColors colors;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.045),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colors,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: colors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.displaySm(colors.foreground)),
              const SizedBox(height: 3),
              Text(subtitle, style: AppTextStyles.bodyXs(colors.mutedForeground)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReportMetricCard extends StatelessWidget {
  const _ReportMetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.colors,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.055),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyXs(colors.mutedForeground),
                ),
                const SizedBox(height: 5),
                Text(value, style: AppTextStyles.displayMd(color)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentAttendanceTable extends StatelessWidget {
  const _StudentAttendanceTable({
    required this.students,
    required this.colors,
  });

  final List<Map<String, dynamic>> students;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              headingRowColor: WidgetStatePropertyAll(
                colors.primary.withValues(alpha: 0.08),
              ),
              headingTextStyle: AppTextStyles.label(
                colors.primary,
              ).copyWith(fontWeight: FontWeight.w700),
              dataTextStyle: AppTextStyles.bodySm(colors.foreground),
              horizontalMargin: 20,
              columnSpacing: 28,
              dataRowMinHeight: 58,
              dataRowMaxHeight: 66,
              columns: const [
                DataColumn(label: Text('Mã sinh viên')),
                DataColumn(label: Text('Họ và tên')),
                DataColumn(label: Text('Tổng buổi')),
                DataColumn(label: Text('Có mặt')),
                DataColumn(label: Text('Đi muộn')),
                DataColumn(label: Text('Vắng')),
                DataColumn(label: Text('Vắng có phép')),
                DataColumn(label: Text('Tỷ lệ đi học')),
                DataColumn(label: Text('Kết quả')),
              ],
              rows: students.indexed.map((entry) {
                final index = entry.$1;
                final student = entry.$2;
                return DataRow(
                  color: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.hovered)) {
                      return colors.primary.withValues(alpha: 0.055);
                    }
                    return index.isOdd
                        ? colors.primary.withValues(alpha: 0.018)
                        : null;
                  }),
                  cells: [
                    DataCell(Text(student['studentId']?.toString() ?? '')),
                    DataCell(Text(student['studentName']?.toString() ?? '')),
                    DataCell(Text('${_number(student['totalSessions'])}')),
                    DataCell(
                      Text(
                        '${_number(student['present'])}',
                        style: TextStyle(color: colors.success),
                      ),
                    ),
                    DataCell(
                      Text(
                        '${_number(student['late'])}',
                        style: TextStyle(color: colors.warning),
                      ),
                    ),
                    DataCell(
                      Text(
                        '${_number(student['absent'])}',
                        style: TextStyle(color: colors.danger),
                      ),
                    ),
                    DataCell(
                      Text(
                        '${_number(student['excused'])}',
                        style: TextStyle(color: colors.primary),
                      ),
                    ),
                    DataCell(Text('${_number(student['attendancePercent'])}%')),
                    DataCell(Text(
                      student['attendanceResult']?.toString() ?? 'Chưa xác định',
                      style: TextStyle(
                        color: student['attendanceEligible'] == true
                            ? colors.success
                            : colors.danger,
                        fontWeight: FontWeight.w700,
                      ),
                    )),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  static int _number(Object? value) =>
      int.tryParse(value?.toString() ?? '') ?? 0;
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({
    required this.message,
    required this.colors,
    this.isError = false,
  });

  final String message;
  final AppColors colors;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 12),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySm(
            isError ? Theme.of(context).colorScheme.error : colors.mutedForeground,
          ),
        ),
      ),
    );
  }
}

class _DailyRow extends StatelessWidget {
  const _DailyRow({required this.item, required this.colors});

  final Map<String, dynamic> item;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Wrap(
        spacing: 18,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              _dateLabel(item['date']),
              style: AppTextStyles.bodySm(colors.foreground),
            ),
          ),
          _DailyCount(
            label: 'Có mặt',
            value: item['present'],
            color: colors.success,
          ),
          _DailyCount(
            label: 'Đi muộn',
            value: item['late'],
            color: colors.warning,
          ),
          _DailyCount(
            label: 'Vắng',
            value: item['absent'],
            color: colors.danger,
          ),
          _DailyCount(
            label: 'Vắng có phép',
            value: item['excused'],
            color: colors.primary,
          ),
        ],
      ),
    );
  }

  static String _dateLabel(Object? value) {
    final raw = value?.toString() ?? '';
    final date = DateTime.tryParse(raw);
    if (date == null) return raw;
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}

class _DailyCount extends StatelessWidget {
  const _DailyCount({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final Object? value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${int.tryParse(value?.toString() ?? '') ?? 0}',
          style: AppTextStyles.bodySm(color).copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: AppTextStyles.bodyXs(color)),
      ],
    );
  }
}
