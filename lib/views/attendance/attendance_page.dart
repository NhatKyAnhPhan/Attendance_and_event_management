import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../controllers/attendance_controller.dart';
import '../../controllers/auth_controller.dart';
import '../../core/constants/role.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/app_badge.dart';
import '../../widgets/statistics_charts.dart';
import 'attendance_roster_page.dart';
import 'event_attendance_section.dart';
import 'qr_generator_page.dart';

class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key});

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  String _query = '';
  bool _showEventAttendance = false;
  final GlobalKey<EventAttendanceSectionState> _eventAttendanceKey =
      GlobalKey<EventAttendanceSectionState>();

  /// Hiển thị phiên điểm danh và kết quả truy vấn theo quyền hiện tại.
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);
    final controller = Get.put(AttendanceController());
    final role = Get.find<AuthController>().role.value;
    final canCreateSession = role == Role.admin || role == Role.lecturer;
    final canViewEventAttendance = role == Role.admin || role == Role.organizer;

    return Obx(() {
      final query = _query.trim().toLowerCase();
      final sessions = controller.sessions.where((session) {
        return query.isEmpty ||
            session.values.join(' ').toLowerCase().contains(query);
      }).toList();
      final classSummaries = _aggregateByClass(sessions);
      final present = sessions.fold<int>(
        0,
        (total, item) => total + _count(item['present']),
      );
      final late = sessions.fold<int>(
        0,
        (total, item) => total + _count(item['late']),
      );
      final absent = sessions.fold<int>(
        0,
        (total, item) => total + _count(item['absent']),
      );
      final resultCount = present + late + absent;
      final attendanceRate = resultCount == 0
          ? 0
          : (present * 100 / resultCount).round();

      return RefreshIndicator(
        onRefresh: () => _showEventAttendance
            ? _eventAttendanceKey.currentState?.load() ?? Future<void>.value()
            : controller.load(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Điểm danh',
                    style: AppTextStyles.displayLg(c.foreground),
                  ),
                ),
                if (canCreateSession)
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const QrGeneratorPage(),
                      ),
                    ),
                    icon: const Icon(Icons.qr_code_2),
                    label: const Text('Tạo QR'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Phiên học và kết quả tham dự từ cơ sở dữ liệu.',
              style: AppTextStyles.bodySm(c.mutedForeground),
            ),
            const SizedBox(height: 16),
            if (canViewEventAttendance) ...[
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Điểm danh lớp học'),
                    selected: !_showEventAttendance,
                    onSelected: (_) =>
                        setState(() => _showEventAttendance = false),
                  ),
                  ChoiceChip(
                    label: const Text('Điểm danh sự kiện'),
                    selected: _showEventAttendance,
                    onSelected: (_) =>
                        setState(() => _showEventAttendance = true),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            if (_showEventAttendance)
              EventAttendanceSection(key: _eventAttendanceKey)
            else ...[
              AppSearchField(
                colors: c,
                hintText: 'Tìm mã lớp, sự kiện, trạng thái...',
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) => GridView.count(
                  crossAxisCount: constraints.maxWidth >= 720 ? 3 : 1,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent: 92,
                  children: [
                    _SummaryCard(
                      title: 'Phiên điểm danh',
                      value: '${sessions.length}',
                      color: c.primary,
                      bg: c.secondary,
                    ),
                    _SummaryCard(
                      title: 'Tỷ lệ có mặt',
                      value: '$attendanceRate%',
                      color: c.success,
                      bg: const Color(0xFFDCFCE7),
                    ),
                    _SummaryCard(
                      title: 'Chưa điểm danh',
                      value: '$absent',
                      color: c.warning,
                      bg: const Color(0xFFFEF3C7),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              StatisticsDonutChart(
                title: 'Phân bổ kết quả điểm danh',
                colors: c,
                data: [
                  StatisticsChartDatum(
                    label: 'Có mặt',
                    value: present,
                    color: c.success,
                  ),
                  StatisticsChartDatum(
                    label: 'Muộn',
                    value: late,
                    color: c.warning,
                  ),
                  StatisticsChartDatum(
                    label: 'Vắng',
                    value: absent,
                    color: c.danger,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (controller.loading.value && sessions.isEmpty)
                const Center(child: CircularProgressIndicator())
              else if (controller.error.value.isNotEmpty)
                Text(
                  controller.error.value,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                )
              else if (sessions.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: Text(
                      controller.sessions.isEmpty
                          ? 'Chưa có phiên điểm danh trong dữ liệu.'
                          : 'Không tìm thấy phiên điểm danh phù hợp.',
                      style: AppTextStyles.bodySm(c.mutedForeground),
                    ),
                  ),
                )
              else ...[
                StatisticsBarChart(
                  title: 'Kết quả theo mã học phần',
                  colors: c,
                  categories: classSummaries
                      .map((item) => item['classId'].toString())
                      .toList(),
                  series: [
                    StatisticsChartSeries(
                      label: 'Có mặt',
                      color: c.success,
                      values: classSummaries
                          .map((item) => _count(item['present']))
                          .toList(),
                    ),
                    StatisticsChartSeries(
                      label: 'Muộn',
                      color: c.warning,
                      values: classSummaries
                          .map((item) => _count(item['late']))
                          .toList(),
                    ),
                    StatisticsChartSeries(
                      label: 'Vắng',
                      color: c.danger,
                      values: classSummaries
                          .map((item) => _count(item['absent']))
                          .toList(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...sessions.map(
                  (session) => _SessionCard(
                    session: session,
                    c: c,
                    onOpenRoster: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AttendanceRosterPage(
                          sessionId: session['id']?.toString() ?? '',
                          title:
                              session['className']?.toString().isNotEmpty ==
                                  true
                              ? session['className'].toString()
                              : 'Danh sách điểm danh',
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      );
    });
  }

  /// Chuyển số từ JSON API sang giá trị số nguyên an toàn.
  static int _count(dynamic value) =>
      int.tryParse(value?.toString() ?? '') ?? 0;

  /// Cộng số liệu API của các phiên theo mã học phần duy nhất.
  static List<Map<String, dynamic>> _aggregateByClass(
    List<Map<String, dynamic>> sessions,
  ) {
    final grouped = <String, Map<String, int>>{};
    for (final session in sessions) {
      final classId = session['classId']?.toString() ?? '';
      if (classId.isEmpty) continue;
      final counts = grouped.putIfAbsent(
        classId,
        () => {'present': 0, 'late': 0, 'absent': 0},
      );
      counts['present'] = counts['present']! + _count(session['present']);
      counts['late'] = counts['late']! + _count(session['late']);
      counts['absent'] = counts['absent']! + _count(session['absent']);
    }
    return grouped.entries
        .map((entry) => <String, dynamic>{'classId': entry.key, ...entry.value})
        .toList();
  }
}

class _SessionCard extends StatelessWidget {
  final Map<String, dynamic> session;
  final AppColors c;
  final VoidCallback onOpenRoster;

  const _SessionCard({
    required this.session,
    required this.c,
    required this.onOpenRoster,
  });

  /// Hiển thị thông tin phiên và số liệu truy vấn được.
  @override
  Widget build(BuildContext context) {
    final openedAt = DateTime.tryParse(session['openedAt']?.toString() ?? '');
    final status = session['status']?.toString() ?? 'Không rõ';
    final badgeStatus = status == 'Đang mở'
        ? BadgeStatus.present
        : BadgeStatus.pending;
    final subtitle = [
      session['classId']?.toString() ?? '',
      if (openedAt != null) DateFormat('dd/MM/yyyy HH:mm').format(openedAt),
      session['method']?.toString() ?? '',
    ].where((value) => value.isNotEmpty).join(' · ');

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(8),
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
                    Text(
                      session['className']?.toString().isNotEmpty == true
                          ? session['className'].toString()
                          : session['sessionName']?.toString() ?? 'Buổi học',
                      style: AppTextStyles.displaySm(c.foreground),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodySm(c.mutedForeground),
                    ),
                  ],
                ),
              ),
              AppBadge(label: status, status: badgeStatus),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _MiniStat(
                label: 'Có mặt',
                value: '${_AttendancePageState._count(session['present'])}',
                color: c.success,
              ),
              _MiniStat(
                label: 'Muộn',
                value: '${_AttendancePageState._count(session['late'])}',
                color: c.warning,
              ),
              _MiniStat(
                label: 'Vắng',
                value: '${_AttendancePageState._count(session['absent'])}',
                color: c.danger,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: onOpenRoster,
              icon: const Icon(Icons.groups_outlined),
              label: const Text('Danh sách sinh viên'),
            ),
          ),
        ],
      ),
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
          Text(
            value,
            style: AppTextStyles.displayLg(color).copyWith(fontSize: 22),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

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
