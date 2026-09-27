import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../data/api/api_client.dart';
import '../../controllers/events_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/models/student_summaries.dart';
import '../../widgets/app_badge.dart';

// Đăng ký và hỏi xác nhận nếu sự kiện trùng lịch học.
Future<void> _registerWithConflictHandling(
  BuildContext context,
  EventsController controller,
  StudentEventSummary event,
) async {
  try {
    await controller.register(event.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đăng ký sự kiện thành công.')),
      );
    }
  } on ApiException catch (exception) {
    if (!context.mounted) return;
    if (exception.data?['type'] != 'class_schedule_conflict') {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(exception.message)));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Trùng lịch học'),
        content: Text(exception.message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Quay lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Vẫn đăng ký'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await controller.register(event.id, allowClassConflict: true);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đăng ký sự kiện thành công.')),
        );
      }
    } on ApiException catch (retryException) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(retryException.message)));
      }
    }
  }
}

// Tải chi tiết sự kiện và hiển thị modal để người dùng xem hoặc đăng ký.
Future<void> _showEventDetails(
  BuildContext context,
  EventsController controller,
  StudentEventSummary event,
  Future<void> Function() onRegister,
) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final c = AppColors.of(isDark);
  final details = controller.getDetails(event.id);

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: c.card,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.84,
        child: FutureBuilder<Map<String, dynamic>>(
          future: details,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    snapshot.error?.toString() ??
                        'Không tải được chi tiết sự kiện.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySm(c.mutedForeground),
                  ),
                ),
              );
            }

            final data = snapshot.data!;
            final benefits = (data['benefits'] as List? ?? const [])
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList();
            final rules = (data['rules'] as List? ?? const [])
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList();
            final start = DateTime.tryParse(data['startTime']?.toString() ?? '')
                ?.toLocal();
            final end =
                DateTime.tryParse(data['endTime']?.toString() ?? '')
                    ?.toLocal() ??
                event.endTime;
            final capacity = (data['capacity'] as num?)?.toInt() ?? 0;
            final registeredCount =
                (data['registeredCount'] as num?)?.toInt() ?? 0;

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        data['name']?.toString() ?? event.name,
                        style: AppTextStyles.displaySm(c.foreground),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Đóng chi tiết',
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  data['description']?.toString().trim().isNotEmpty == true
                      ? data['description'].toString()
                      : 'Chưa có mô tả cho sự kiện này.',
                  style: AppTextStyles.bodyMd(c.foreground),
                ),
                const SizedBox(height: 20),
                _EventDetailRow(
                  label: 'Đơn vị tổ chức',
                  value: data['organizerName']?.toString() ?? event.org,
                  c: c,
                ),
                _EventDetailRow(
                  label: 'Thời gian',
                  value: start == null
                      ? 'Chưa cập nhật'
                      : '${DateFormat('dd/MM/yyyy HH:mm').format(start)} - ${end == null ? '' : DateFormat('HH:mm').format(end)}',
                  c: c,
                ),
                if (event.eventStatus.isNotEmpty)
                  _EventDetailRow(
                    label: 'Trạng thái',
                    value: event.eventStatus,
                    c: c,
                  ),
                _EventDetailRow(
                  label: 'Địa điểm',
                  value: data['location']?.toString().trim().isNotEmpty == true
                      ? data['location'].toString()
                      : 'Chưa cập nhật',
                  c: c,
                ),
                _EventDetailRow(
                  label: 'Đăng ký',
                  value: capacity > 0
                      ? '$registeredCount / $capacity sinh viên'
                      : '$registeredCount sinh viên',
                  c: c,
                ),
                const SizedBox(height: 16),
                Text('Quyền lợi', style: AppTextStyles.displayXs(c.foreground)),
                const SizedBox(height: 8),
                if (benefits.isEmpty)
                  Text(
                    'Chưa có thông tin quyền lợi.',
                    style: AppTextStyles.bodySm(c.mutedForeground),
                  )
                else
                  ...benefits.map((benefit) {
                    final points = (benefit['points'] as num?)?.toInt() ?? 0;
                    final pointLabel = points > 0 ? ' · $points điểm' : '';
                    final content = benefit['content']?.toString() ?? '';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${benefit['type'] ?? 'Quyền lợi'}$pointLabel${content.isEmpty ? '' : ': $content'}',
                        style: AppTextStyles.bodySm(c.foreground),
                      ),
                    );
                  }),
                const SizedBox(height: 12),
                Text('Nội quy', style: AppTextStyles.displayXs(c.foreground)),
                const SizedBox(height: 8),
                if (rules.isEmpty)
                  Text(
                    'Chưa có nội quy.',
                    style: AppTextStyles.bodySm(c.mutedForeground),
                  )
                else
                  ...rules.map(
                    (rule) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${rule['sortOrder'] ?? ''}. ${rule['text'] ?? ''}',
                        style: AppTextStyles.bodySm(c.foreground),
                      ),
                    ),
                  ),
                if (!event.registered && !event.isEnded) ...[
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(sheetContext);
                        await onRegister();
                      },
                      child: const Text('Đăng ký sự kiện'),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    ),
  );
}

class StudentEventsPage extends StatelessWidget {
  const StudentEventsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);
    final controller = Get.put(EventsController());

    return Obx(() {
      controller.statusRefreshTick.value;
      final events = controller.items;
      if (controller.loading.value && events.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (controller.error.value.isNotEmpty && events.isEmpty) {
        return Center(child: Text(controller.error.value));
      }
      return ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
            decoration: BoxDecoration(
              color: c.card,
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sự kiện',
                  style: AppTextStyles.displayLg(c.foreground)
                      .copyWith(fontSize: 22),
                ),
                Text(
                  'Khám phá & đăng ký sự kiện',
                  style: AppTextStyles.bodySm(c.mutedForeground),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                ...events.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _EventCard(
                      event: e,
                      c: c,
                      onRegister: () =>
                          _registerWithConflictHandling(context, controller, e),
                      onCancel: () =>
                          _cancelRegistration(context, controller, e),
                      onDetails: () => _showEventDetails(
                        context,
                        controller,
                        e,
                        () => _registerWithConflictHandling(
                          context,
                          controller,
                          e,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }
}

class _EventCard extends StatelessWidget {
  final StudentEventSummary event;
  final AppColors c;
  final Future<void> Function() onRegister;
  final Future<void> Function() onCancel;
  final VoidCallback onDetails;
  const _EventCard({
    required this.event,
    required this.c,
    required this.onRegister,
    required this.onCancel,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3E8FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.event,
                  color: Color(0xFF7C3AED),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.name,
                      style: AppTextStyles.displaySm(c.foreground),
                    ),
                    Text(
                      '${event.date} · ${event.org}',
                      style: AppTextStyles.bodyXs(c.mutedForeground),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              event.registered
                  ? const AppBadge(
                      label: 'Đã đăng ký',
                      status: BadgeStatus.present,
                    )
                  : const AppBadge(
                      label: 'Chưa đăng ký',
                      status: BadgeStatus.pending,
                    ),
              if (event.eventStatus.isNotEmpty)
                AppBadge(
                  label: event.eventStatus,
                  status: event.isEnded
                      ? BadgeStatus.blue
                      : event.eventStatus == 'Đang diễn ra'
                      ? BadgeStatus.late
                      : BadgeStatus.pending,
                ),
              if (event.registered && event.registeredAt != null)
                Text(
                  'Đăng ký lúc ${DateFormat('dd/MM/yyyy HH:mm').format(event.registeredAt!)}',
                  style: AppTextStyles.bodyXs(c.mutedForeground),
                ),
              TextButton(
                onPressed: onDetails,
                child: const Text('Xem chi tiết'),
              ),
              if (event.registered && _canCancelRegistration(event))
                OutlinedButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.event_busy, size: 18),
                  label: const Text('Hủy đăng ký'),
                ),
              if (event.registered &&
                  !event.isEnded &&
                  event.registeredAt != null &&
                  !_canCancelRegistration(event))
                Text(
                  'Đã quá 24 giờ, không thể hủy',
                  style: AppTextStyles.bodyXs(c.mutedForeground),
                ),
              if (!event.registered && !event.isEnded)
                ElevatedButton(
                  onPressed: onRegister,
                  child: const Text('Đăng ký ngay'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// Cho phép hủy khi đã biết thời điểm đăng ký và chưa đủ 24 giờ.
bool _canCancelRegistration(StudentEventSummary event) {
  final registeredAt = event.registeredAt;
  final endTime = event.endTime;
  final elapsed = registeredAt == null
      ? null
      : DateTime.now().difference(registeredAt);
  return event.registered &&
      registeredAt != null &&
      endTime != null &&
      endTime.isAfter(DateTime.now()) &&
      elapsed != null &&
      !elapsed.isNegative &&
      elapsed <= const Duration(hours: 24);
}

// Hủy đăng ký và thông báo kết quả cho sinh viên.
Future<void> _cancelRegistration(
  BuildContext context,
  EventsController controller,
  StudentEventSummary event,
) async {
  try {
    await controller.cancelRegistration(event.id);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã hủy đăng ký sự kiện.')));
    }
  } on ApiException catch (exception) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(exception.message)));
    }
  }
}

class _EventDetailRow extends StatelessWidget {
  final String label;
  final String value;
  final AppColors c;

  const _EventDetailRow({
    required this.label,
    required this.value,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(label, style: AppTextStyles.bodySm(c.mutedForeground)),
          ),
          Expanded(
            child: Text(value, style: AppTextStyles.bodySm(c.foreground)),
          ),
        ],
      ),
    );
  }
}
