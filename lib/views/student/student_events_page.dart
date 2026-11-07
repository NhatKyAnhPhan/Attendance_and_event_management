import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../data/api/api_client.dart';
import '../../controllers/events_controller.dart';
import '../../controllers/classes_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/models/student_summaries.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/app_badge.dart';
import '../../widgets/student_form_dialogs.dart';

// Đăng ký và hỏi xác nhận nếu sự kiện trùng lịch học.
Future<bool> registerStudentEventWithConflictHandling(
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
    return true;
  } on ApiException catch (exception) {
    if (!context.mounted) return false;
    if (exception.data?['type'] != 'class_schedule_conflict') {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(exception.message)));
      return false;
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
    if (confirmed != true || !context.mounted) return false;

    try {
      await controller.register(event.id, allowClassConflict: true);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đăng ký sự kiện thành công.')),
        );
      }
      return true;
    } on ApiException catch (retryException) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(retryException.message)));
      }
      return false;
    }
  }
}

Future<void> _showEventFeedbackDialog(
  BuildContext context,
  EventsController eventsController,
  ClassesController classesController,
  String eventId,
) async {
  await showStudentFeedbackDialog(
    context: context,
    eventsController: eventsController,
    classesController: classesController,
    initialItemId: eventId,
  );
}

// Tải chi tiết sự kiện và hiển thị modal để người dùng xem hoặc đăng ký.
Future<void> showStudentEventDetails(
  BuildContext context,
  EventsController controller,
  ClassesController classesController,
  StudentEventSummary event,
  Future<bool> Function() onRegister,
) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final c = AppColors.of(isDark);
  final details = controller.getDetails(event.id);

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: c.card,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    clipBehavior: Clip.antiAlias,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SafeArea(
      child: FractionallySizedBox(
        heightFactor: MediaQuery.sizeOf(sheetContext).width <= 700
            ? 0.92
            : 0.88,
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
              padding: EdgeInsets.fromLTRB(
                MediaQuery.sizeOf(context).width <= 430 ? 16 : 20,
                8,
                MediaQuery.sizeOf(context).width <= 430 ? 16 : 20,
                20 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        data['name']?.toString() ?? event.name,
                        style: AppTextStyles.displayLg(c.foreground).copyWith(
                          fontSize: MediaQuery.sizeOf(context).width <= 430
                              ? 22
                              : 25,
                          height: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Đóng chi tiết',
                      onPressed: () => Navigator.pop(sheetContext),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  data['description']?.toString().trim().isNotEmpty == true
                      ? data['description'].toString()
                      : 'Chưa có mô tả cho sự kiện này.',
                  style: AppTextStyles.bodySm(c.mutedForeground)
                      .copyWith(height: 1.5),
                ),
                const SizedBox(height: 18),
                _EventDetailRow(
                  icon: Icons.apartment_outlined,
                  label: 'Đơn vị tổ chức',
                  value: data['organizerName']?.toString() ?? event.org,
                  c: c,
                ),
                _EventDetailRow(
                  icon: Icons.schedule_outlined,
                  label: 'Thời gian',
                  value: start == null
                      ? 'Chưa cập nhật'
                      : '${DateFormat('dd/MM/yyyy HH:mm').format(start)} - ${end == null ? '' : DateFormat('HH:mm').format(end)}',
                  c: c,
                ),
                if (event.eventStatus.isNotEmpty)
                  _EventDetailRow(
                    icon: Icons.info_outline_rounded,
                    label: 'Trạng thái',
                    value: event.eventStatus,
                    c: c,
                    status: true,
                  ),
                _EventDetailRow(
                  icon: Icons.location_on_outlined,
                  label: 'Địa điểm',
                  value: data['location']?.toString().trim().isNotEmpty == true
                      ? data['location'].toString()
                      : 'Chưa cập nhật',
                  c: c,
                ),
                _EventDetailRow(
                  icon: Icons.groups_outlined,
                  label: 'Đăng ký',
                  value: capacity > 0
                      ? '$registeredCount / $capacity sinh viên'
                      : '$registeredCount sinh viên',
                  c: c,
                ),
                const SizedBox(height: 8),
                _EventDetailSection(
                  title: 'Quyền lợi',
                  c: c,
                  child: benefits.isEmpty
                      ? Text(
                          'Chưa có thông tin quyền lợi.',
                          style: AppTextStyles.bodySm(c.mutedForeground),
                        )
                      : Column(
                          children: benefits.map((benefit) {
                            final points =
                                (benefit['points'] as num?)?.toInt() ?? 0;
                            final pointLabel = points > 0
                                ? ' · $points điểm'
                                : '';
                            final content =
                                benefit['content']?.toString() ?? '';
                            return _EventSectionItem(
                              text:
                                  '${benefit['type'] ?? 'Quyền lợi'}$pointLabel${content.isEmpty ? '' : ': $content'}',
                              c: c,
                            );
                          }).toList(),
                        ),
                ),
                const SizedBox(height: 12),
                _EventDetailSection(
                  title: 'Nội quy',
                  c: c,
                  child: rules.isEmpty
                      ? Text(
                          'Chưa có nội quy.',
                          style: AppTextStyles.bodySm(c.mutedForeground),
                        )
                      : Column(
                          children: rules
                              .map(
                                (rule) => _EventSectionItem(
                                  text:
                                      '${rule['sortOrder'] ?? ''}. ${rule['text'] ?? ''}',
                                  c: c,
                                ),
                              )
                              .toList(),
                        ),
                ),
                const SizedBox(height: 12),
                _EventDetailSection(
                  title: 'Phản hồi và đánh giá',
                  c: c,
                  child: FutureBuilder<Map<String, dynamic>>(
                    future: controller.getFeedback(event.id),
                    builder: (context, feedbackSnapshot) {
                      if (feedbackSnapshot.connectionState !=
                          ConnectionState.done) {
                        return const LinearProgressIndicator();
                      }
                      if (feedbackSnapshot.hasError) {
                        return Text(
                          'Không tải được đánh giá: ${feedbackSnapshot.error}',
                          style: AppTextStyles.bodySm(c.mutedForeground),
                        );
                      }
                      final feedback = feedbackSnapshot.data ?? const {};
                      final items = (feedback['items'] as List? ?? const [])
                          .whereType<Map>()
                          .map((item) => Map<String, dynamic>.from(item))
                          .toList();
                      final average =
                          (feedback['averageRating'] as num?)?.toDouble() ?? 0;
                      final count =
                          (feedback['ratingCount'] as num?)?.toInt() ?? 0;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            count == 0
                                ? 'Chưa có lượt đánh giá.'
                                : '${average.toStringAsFixed(1)} / 5 sao · $count lượt đánh giá',
                            style: AppTextStyles.bodySm(c.foreground),
                          ),
                          ...items
                              .take(5)
                              .map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: InkWell(
                                    onTap: () => showDialog<void>(
                                      context: context,
                                      builder: (dialogContext) => AlertDialog(
                                        title: const Text('Chi tiết đánh giá'),
                                        content: SingleChildScrollView(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                '${(item['rating'] as num?)?.round() ?? 0} / 5 sao',
                                              ),
                                              const SizedBox(height: 12),
                                              Text(
                                                item['comment']
                                                            ?.toString()
                                                            .trim()
                                                            .isNotEmpty ==
                                                        true
                                                    ? item['comment'].toString()
                                                    : 'Không có nhận xét.',
                                              ),
                                              if (item['createdAt'] !=
                                                  null) ...[
                                                const SizedBox(height: 12),
                                                Text(
                                                  'Gửi lúc ${item['createdAt']}',
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(dialogContext),
                                            child: const Text('Đóng'),
                                          ),
                                        ],
                                      ),
                                    ),
                                    child: Text(
                                      '${List.filled(((item['rating'] as num?)?.round() ?? 0).clamp(0, 5), '★').join()}'
                                      '${List.filled(5 - ((item['rating'] as num?)?.round() ?? 0).clamp(0, 5), '☆').join()}'
                                      '  ${item['comment'] ?? ''}',
                                      style: AppTextStyles.bodySm(
                                        c.mutedForeground,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                        ],
                      );
                    },
                  ),
                ),
                if (event.registered && event.isEnded) ...[
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final narrow = constraints.maxWidth <= 390;
                      final feedbackButton = OutlinedButton.icon(
                        onPressed: () => _showEventFeedbackDialog(
                          context,
                          controller,
                          classesController,
                          event.id,
                        ),
                        icon: const Icon(Icons.rate_review_outlined, size: 18),
                        label: const Text('Gửi phản hồi'),
                      );
                      final ratingButton = FilledButton.tonalIcon(
                        onPressed: () => showStudentRatingDialog(
                          context: context,
                          eventsController: controller,
                          classesController: classesController,
                          initialItemId: event.id,
                        ),
                        icon: const Icon(Icons.star_outline_rounded, size: 18),
                        label: const Text('Đánh giá'),
                      );
                      if (narrow) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            feedbackButton,
                            const SizedBox(height: 8),
                            ratingButton,
                          ],
                        );
                      }
                      return Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 10,
                        runSpacing: 8,
                        children: [feedbackButton, ratingButton],
                      );
                    },
                  ),
                ],
                if (!event.registered && !event.isEnded) ...[
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(sheetContext);
                        await showStudentRegistrationDialog(
                          context: context,
                          events: controller.items,
                          initialEventId: event.id,
                          onSubmit: (_) => onRegister(),
                        );
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

class StudentEventsPage extends StatefulWidget {
  const StudentEventsPage({super.key});

  @override
  State<StudentEventsPage> createState() => _StudentEventsPageState();
}

class _StudentEventsPageState extends State<StudentEventsPage> {
  String _query = '';
  String _statusFilter = 'all';
  String _searchField = 'all';

  Future<void> _showFilters(AppColors c) async {
    var status = _statusFilter;
    var searchField = _searchField;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.card,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Lọc sự kiện', style: AppTextStyles.displaySm(c.foreground)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Trạng thái'),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('Tất cả')),
                  DropdownMenuItem(value: 'latest', child: Text('Mới nhất')),
                  DropdownMenuItem(value: 'closed', child: Text('Đã đóng')),
                  DropdownMenuItem(
                    value: 'upcoming',
                    child: Text('Sắp diễn ra'),
                  ),
                  DropdownMenuItem(value: 'ended', child: Text('Đã kết thúc')),
                  DropdownMenuItem(
                    value: 'ongoing',
                    child: Text('Đang diễn ra'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setSheetState(() => status = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: searchField,
                decoration: const InputDecoration(labelText: 'Tìm theo'),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('Tất cả')),
                  DropdownMenuItem(value: 'name', child: Text('Tên sự kiện')),
                  DropdownMenuItem(value: 'location', child: Text('Địa điểm')),
                  DropdownMenuItem(
                    value: 'faculty',
                    child: Text('Khoa/đơn vị tổ chức'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setSheetState(() => searchField = value);
                  }
                },
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  TextButton(
                    onPressed: () => setSheetState(() {
                      status = 'all';
                      searchField = 'all';
                    }),
                    child: const Text('Xóa lọc'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () {
                      setState(() {
                        _statusFilter = status;
                        _searchField = searchField;
                      });
                      Navigator.pop(sheetContext);
                    },
                    child: const Text('Áp dụng'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);
    final controller = Get.put(EventsController());
    final classesController = Get.isRegistered<ClassesController>()
        ? Get.find<ClassesController>()
        : Get.put(ClassesController());

    return Obx(() {
      controller.statusRefreshTick.value;
      final events = controller.items;
      final query = _query.trim().toLowerCase();
      final searchedEvents = events.where((event) {
        if (query.isEmpty) return true;
        final fields = switch (_searchField) {
          'name' => [event.name],
          'location' => [event.location],
          'faculty' => [event.org],
          _ => [
            event.id,
            event.name,
            event.org,
            event.location,
            event.date,
            event.eventStatus,
          ],
        };
        return fields.any((value) => value.toLowerCase().contains(query));
      }).toList();
      final filteredEvents =
          searchedEvents.where((event) {
            return switch (_statusFilter) {
              'closed' => event.eventStatus == 'Đã đóng',
              'upcoming' => event.eventStatus == 'Sắp diễn ra',
              'ongoing' => event.eventStatus == 'Đang diễn ra',
              'ended' => event.eventStatus == 'Đã kết thúc',
              _ => true,
            };
          }).toList()..sort((a, b) {
            if (_statusFilter == 'latest') {
              final aStart = a.startTime;
              final bStart = b.startTime;
              if (aStart == null) return bStart == null ? 0 : 1;
              if (bStart == null) return -1;
              return bStart.compareTo(aStart);
            }

            int rank(StudentEventSummary event) {
              if (event.eventStatus == 'Sắp diễn ra') return 0;
              if (event.eventStatus == 'Đang diễn ra') return 1;
              return 2;
            }

            final statusOrder = rank(a).compareTo(rank(b));
            if (statusOrder != 0) return statusOrder;
            final aStart = a.startTime;
            final bStart = b.startTime;
            if (aStart == null) return bStart == null ? 0 : 1;
            if (bStart == null) return -1;
            return aStart.compareTo(bStart);
          });
      if (controller.loading.value && events.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (controller.error.value.isNotEmpty && events.isEmpty) {
        return Center(child: Text(controller.error.value));
      }
      return RefreshIndicator(
        onRefresh: controller.load,
        child: ListView(
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
                  Row(
                    children: [
                      Expanded(
                        child: AppSearchField(
                          colors: c,
                          hintText: 'Tìm sự kiện, địa điểm...',
                          onChanged: (value) => setState(() => _query = value),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => _showFilters(c),
                        icon: const Icon(Icons.filter_list_rounded),
                        label: const Text('Lọc'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (filteredEvents.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Text(
                        events.isEmpty
                            ? 'Chưa có sự kiện nào.'
                            : 'Không tìm thấy sự kiện phù hợp.',
                        style: AppTextStyles.bodySm(c.mutedForeground),
                      ),
                    ),
                  ...filteredEvents.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _EventCard(
                        event: e,
                        c: c,
                        onRegister: () => showStudentRegistrationDialog(
                          context: context,
                          events: controller.items,
                          initialEventId: e.id,
                          onSubmit: (event) =>
                              registerStudentEventWithConflictHandling(
                                context,
                                controller,
                                event,
                              ),
                        ),
                        onCancel: () =>
                            _cancelRegistration(context, controller, e),
                        onDetails: () => showStudentEventDetails(
                          context,
                          controller,
                          classesController,
                          e,
                          () => registerStudentEventWithConflictHandling(
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
        ),
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
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.displaySm(c.foreground),
                    ),
                    Text(
                      '${event.date} · ${event.org}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
              if (event.registered && event.attendanceStatus.isNotEmpty)
                AppBadge(
                  label: event.attendanceStatus,
                  status: switch (event.attendanceStatus) {
                    'Có mặt' => BadgeStatus.present,
                    'Vắng mặt' => BadgeStatus.absent,
                    _ => BadgeStatus.pending,
                  },
                ),
              if (event.eventStatus.isNotEmpty)
                AppBadge(
                  label: event.eventStatus,
                  status: switch (event.eventStatus) {
                    'Sắp diễn ra' || 'Mới' => BadgeStatus.blue,
                    'Đang diễn ra' => BadgeStatus.late,
                    'Đã đóng' || 'Đã kết thúc' => BadgeStatus.absent,
                    _ => BadgeStatus.pending,
                  },
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
              if (event.registered && !event.isEnded && event.isAttended)
                Text(
                  'Đã điểm danh, không thể hủy đăng ký',
                  style: AppTextStyles.bodyXs(c.mutedForeground),
                ),
              if (event.registered &&
                  !event.isEnded &&
                  !event.isAttended &&
                  event.registrationLocked)
                Text(
                  event.registrationLockHours == null
                      ? 'Đã đến thời gian khóa đăng ký, không thể hủy'
                      : 'Đã đến thời gian khóa đăng ký trước sự kiện ${event.registrationLockHours} giờ',
                  style: AppTextStyles.bodyXs(c.mutedForeground),
                ),
              if (!event.registered &&
                  !event.isEnded &&
                  event.registrationLocked)
                Text(
                  event.registrationLockHours == null
                      ? 'Đã khóa đăng ký sự kiện'
                      : 'Đã khóa đăng ký trước sự kiện ${event.registrationLockHours} giờ',
                  style: AppTextStyles.bodyXs(c.mutedForeground),
                ),
              if (!event.registered &&
                  !event.isEnded &&
                  !event.registrationLocked)
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

// Chỉ cho phép hủy trước mốc khóa do quản trị viên cấu hình.
bool _canCancelRegistration(StudentEventSummary event) {
  return event.registered &&
      !event.isAttended &&
      !event.isEnded &&
      !event.registrationLocked;
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

class _EventDetailSection extends StatelessWidget {
  const _EventDetailSection({
    required this.title,
    required this.c,
    required this.child,
  });

  final String title;
  final AppColors c;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: c.card,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: c.border),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .025),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTextStyles.displayXs(c.foreground)),
        const SizedBox(height: 10),
        child,
      ],
    ),
  );
}

class _EventSectionItem extends StatelessWidget {
  const _EventSectionItem({required this.text, required this.c});

  final String text;
  final AppColors c;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 7),
          child: Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.bodySm(c.foreground).copyWith(height: 1.45),
          ),
        ),
      ],
    ),
  );
}

class _EventDetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final AppColors c;
  final bool status;

  const _EventDetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.c,
    this.status = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: c.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: c.primary),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.bodyXs(c.mutedForeground)),
                const SizedBox(height: 3),
                if (status)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: c.primary.withValues(alpha: .09),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        value,
                        style: AppTextStyles.bodyXs(c.primary)
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  )
                else
                  Text(
                    value,
                    style: AppTextStyles.bodySm(c.foreground)
                        .copyWith(fontWeight: FontWeight.w600, height: 1.35),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
