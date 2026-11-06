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
  final bool initialShowEventAttendance;

  const AttendancePage({super.key, this.initialShowEventAttendance = false});

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  String _query = '';
  String? _selectedClassId;
  late bool _showEventAttendance;
  final GlobalKey<EventAttendanceSectionState> _eventAttendanceKey =
      GlobalKey<EventAttendanceSectionState>();

  @override
  void initState() {
    super.initState();
    _showEventAttendance = widget.initialShowEventAttendance;
  }

  /// Hiển thị phiên điểm danh và kết quả truy vấn theo quyền hiện tại.
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);
    final auth = Get.find<AuthController>();
    final role = auth.role.value;
    final sourceRole = auth.currentUser.value?['role']?.toString() ?? '';
    final isEmployee =
        role == Role.organizer &&
        (sourceRole.isEmpty || RoleX.isEmployee(sourceRole));
    if (isEmployee) {
      return RefreshIndicator(
        onRefresh: () =>
            _eventAttendanceKey.currentState?.load() ?? Future<void>.value(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [EventAttendanceSection(key: _eventAttendanceKey)],
        ),
      );
    }
    final controller = Get.put(AttendanceController());
    final canCreateSession = role == Role.admin || role == Role.lecturer;
    final canViewEventAttendance = role == Role.admin || role == Role.organizer;

    return Obx(() {
      final query = _query.trim().toLowerCase();
      final sessions = controller.sessions.where((session) {
        return query.isEmpty ||
            session.values.join(' ').toLowerCase().contains(query);
      }).toList();
      final summarySessions = _selectedClassId == null
          ? sessions
          : sessions
                .where(
                  (session) =>
                      session['classId']?.toString() == _selectedClassId,
                )
                .toList();
      final classSummaries = _aggregateByClass(summarySessions);
      final present = summarySessions.fold<int>(
        0,
        (total, item) => total + _count(item['present']),
      );
      final late = summarySessions.fold<int>(
        0,
        (total, item) => total + _count(item['late']),
      );
      final absent = summarySessions.fold<int>(
        0,
        (total, item) => total + _count(item['absent']),
      );
      final resultCount = present + late + absent;
      final attendanceRate = resultCount == 0
          ? 0
          : (present * 100 / resultCount).round();
      final selectedClassName = summarySessions.isEmpty
          ? null
          : summarySessions.first['className']?.toString().trim();
      final summaryTitle = _selectedClassId == null
          ? 'Tổng hợp tất cả lớp'
          : selectedClassName?.isNotEmpty == true
          ? selectedClassName!
          : 'Lớp $_selectedClassId';

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
                builder: (context, constraints) {
                  final desktop = constraints.maxWidth >= 1000;
                  final sessionsPanel = _buildSessionsPanel(
                    context,
                    c,
                    controller,
                    sessions,
                    selectedClassId: _selectedClassId,
                    onSelectClass: (classId) =>
                        setState(() => _selectedClassId = classId),
                    scroll: desktop,
                  );
                  final overview = _buildAttendanceOverview(
                    c,
                    summarySessions,
                    classSummaries,
                    present,
                    late,
                    absent,
                    attendanceRate,
                    summaryTitle,
                  );
                  if (!desktop) {
                    return Column(
                      children: [
                        overview,
                        const SizedBox(height: 20),
                        sessionsPanel,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 44, child: sessionsPanel),
                      const SizedBox(width: 18),
                      Expanded(flex: 56, child: overview),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      );
    });
  }

  /// Chuyển số từ JSON API sang giá trị số nguyên an toàn.
  static int _count(dynamic value) =>
      int.tryParse(value?.toString() ?? '') ?? 0;

  Widget _buildSessionsPanel(
    BuildContext context,
    AppColors colors,
    AttendanceController controller,
    List<Map<String, dynamic>> sessions, {
    required String? selectedClassId,
    required ValueChanged<String?> onSelectClass,
    required bool scroll,
  }) {
    final panelHeight = (MediaQuery.sizeOf(context).height - 210).clamp(
      480.0,
      720.0,
    );
    Widget content;
    if (controller.loading.value && sessions.isEmpty) {
      content = const Center(child: CircularProgressIndicator());
    } else if (controller.error.value.isNotEmpty) {
      content = Text(
        controller.error.value,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    } else if (sessions.isEmpty) {
      content = Center(
        child: Text(
          controller.sessions.isEmpty
              ? 'Chưa có phiên điểm danh trong dữ liệu.'
              : 'Không tìm thấy phiên điểm danh phù hợp.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySm(colors.mutedForeground),
        ),
      );
    } else {
      final cards = sessions
          .map(
            (session) => _SessionCard(
              session: session,
              c: colors,
              selected:
                  session['classId']?.toString() == selectedClassId &&
                  selectedClassId != null,
              onSelect: () {
                final classId = session['classId']?.toString();
                if (classId != null && classId.isNotEmpty) {
                  onSelectClass(classId);
                }
              },
              onOpenRoster: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AttendanceRosterPage(
                    sessionId: session['id']?.toString() ?? '',
                    title: session['className']?.toString().isNotEmpty == true
                        ? session['className'].toString()
                        : 'Danh sách điểm danh',
                  ),
                ),
              ),
            ),
          )
          .toList();
      content = scroll
          ? Scrollbar(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _SessionsPanelHeader(
                    colors: colors,
                    isSummary: selectedClassId == null,
                    onShowSummary: () => onSelectClass(null),
                  ),
                  ...cards,
                ],
              ),
            )
          : Column(
              children: [
                _SessionsPanelHeader(
                  colors: colors,
                  isSummary: selectedClassId == null,
                  onShowSummary: () => onSelectClass(null),
                ),
                ...cards,
              ],
            );
    }
    return Container(
      height: scroll ? panelHeight : null,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: content,
    );
  }

  Widget _buildAttendanceOverview(
    AppColors colors,
    List<Map<String, dynamic>> sessions,
    List<Map<String, dynamic>> classSummaries,
    int present,
    int late,
    int absent,
    int attendanceRate,
    String title,
  ) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              title,
              style: AppTextStyles.displaySm(colors.foreground),
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) => GridView.count(
            crossAxisCount: constraints.maxWidth >= 560 ? 3 : 1,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: 92,
            children: [
              _SummaryCard(
                title: 'Phiên điểm danh',
                value: '${sessions.length}',
                color: colors.primary,
                bg: colors.secondary,
              ),
              _SummaryCard(
                title: 'Tỷ lệ có mặt',
                value: '$attendanceRate%',
                color: colors.success,
                bg: const Color(0xFFDCFCE7),
              ),
              _SummaryCard(
                title: 'Vắng mặt',
                value: '$absent',
                color: colors.warning,
                bg: const Color(0xFFFEF3C7),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        StatisticsDonutChart(
          title: 'Phân bổ kết quả điểm danh',
          colors: colors,
          data: [
            StatisticsChartDatum(
              label: 'Có mặt',
              value: present,
              color: colors.success,
            ),
            StatisticsChartDatum(
              label: 'Muộn',
              value: late,
              color: colors.warning,
            ),
            StatisticsChartDatum(
              label: 'Vắng',
              value: absent,
              color: colors.danger,
            ),
          ],
        ),
        if (sessions.isNotEmpty) ...[
          const SizedBox(height: 20),
          StatisticsBarChart(
            title: 'Kết quả theo mã học phần',
            colors: colors,
            verticalCategories: true,
            categories: classSummaries
                .map((item) {
                  final className = item['className']?.toString().trim() ?? '';
                  return className.isNotEmpty
                      ? className
                      : item['classId'].toString();
                })
                .toList(),
            series: [
              StatisticsChartSeries(
                label: 'Có mặt',
                color: colors.success,
                values: classSummaries
                    .map((item) => _count(item['present']))
                    .toList(),
              ),
              StatisticsChartSeries(
                label: 'Muộn',
                color: colors.warning,
                values: classSummaries
                    .map((item) => _count(item['late']))
                    .toList(),
              ),
              StatisticsChartSeries(
                label: 'Vắng',
                color: colors.danger,
                values: classSummaries
                    .map((item) => _count(item['absent']))
                    .toList(),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// Cộng số liệu API của các phiên theo mã học phần duy nhất.
  static List<Map<String, dynamic>> _aggregateByClass(
    List<Map<String, dynamic>> sessions,
  ) {
    final grouped = <String, Map<String, int>>{};
    final classNames = <String, String>{};
    for (final session in sessions) {
      final classId = session['classId']?.toString() ?? '';
      if (classId.isEmpty) continue;
      final className = session['className']?.toString().trim() ?? '';
      if (className.isNotEmpty) {
        classNames.putIfAbsent(classId, () => className);
      }
      final counts = grouped.putIfAbsent(
        classId,
        () => {'present': 0, 'late': 0, 'absent': 0},
      );
      counts['present'] = counts['present']! + _count(session['present']);
      counts['late'] = counts['late']! + _count(session['late']);
      counts['absent'] = counts['absent']! + _count(session['absent']);
    }
    return grouped.entries
        .map(
          (entry) => <String, dynamic>{
            'classId': entry.key,
            'className': classNames[entry.key] ?? '',
            ...entry.value,
          },
        )
        .toList();
  }
}

class _SessionCard extends StatelessWidget {
  final Map<String, dynamic> session;
  final AppColors c;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onOpenRoster;

  const _SessionCard({
    required this.session,
    required this.c,
    required this.selected,
    required this.onSelect,
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

    return Material(
      color: selected ? c.secondary : c.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            border: Border.all(color: selected ? c.primary : c.border),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: c.secondary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.qr_code_2_outlined,
                      size: 20,
                      color: c.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session['className']?.toString().isNotEmpty == true
                              ? session['className'].toString()
                              : session['sessionName']?.toString() ??
                                    'Buổi học',
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
        ),
      ),
    );
  }
}

class _SessionsPanelHeader extends StatelessWidget {
  const _SessionsPanelHeader({
    required this.colors,
    required this.isSummary,
    required this.onShowSummary,
  });

  final AppColors colors;
  final bool isSummary;
  final VoidCallback onShowSummary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Phiên điểm danh theo lớp',
              style: AppTextStyles.displaySm(colors.foreground),
            ),
          ),
          TextButton.icon(
            onPressed: isSummary ? null : onShowSummary,
            icon: const Icon(Icons.analytics_outlined),
            label: const Text('Xem tổng hợp'),
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
