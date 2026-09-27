import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../controllers/attendance_controller.dart';
import '../../controllers/auth_controller.dart';
import '../../core/constants/role.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../widgets/app_badge.dart';
import 'qr_generator_page.dart';

class AttendancePage extends StatelessWidget {
  const AttendancePage({super.key});

  /// Hiển thị phiên điểm danh và kết quả truy vấn theo quyền hiện tại.
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);
    final controller = Get.put(AttendanceController());
    final role = Get.find<AuthController>().role.value;
    final canCreateSession = role == Role.admin || role == Role.lecturer;

    return Obx(() {
      final sessions = controller.sessions;
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
        onRefresh: controller.load,
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
                    'Chưa có phiên điểm danh trong dữ liệu.',
                    style: AppTextStyles.bodySm(c.mutedForeground),
                  ),
                ),
              )
            else
              ...sessions.map(
                (session) => _SessionCard(session: session, c: c),
              ),
          ],
        ),
      );
    });
  }

  /// Chuyển số từ JSON API sang giá trị số nguyên an toàn.
  static int _count(dynamic value) =>
      int.tryParse(value?.toString() ?? '') ?? 0;
}

class _SessionCard extends StatelessWidget {
  final Map<String, dynamic> session;
  final AppColors c;

  const _SessionCard({required this.session, required this.c});

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
                value: '${AttendancePage._count(session['present'])}',
                color: c.success,
              ),
              _MiniStat(
                label: 'Muộn',
                value: '${AttendancePage._count(session['late'])}',
                color: c.warning,
              ),
              _MiniStat(
                label: 'Vắng',
                value: '${AttendancePage._count(session['absent'])}',
                color: c.danger,
              ),
            ],
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
