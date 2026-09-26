import 'dart:async';

import 'package:get/get.dart';

import '../core/constants/role.dart';
import '../data/api/api_client.dart';
import '../data/models/notification_model.dart';

class NotificationController extends GetxController {
  final RxList<AppNotificationItem> items = <AppNotificationItem>[].obs;
  final ApiClient _apiClient = ApiClient();
  Timer? _refreshTimer;
  bool _refreshingAttendance = false;

  @override
  void onInit() {
    super.onInit();
    _seedNotifications();
    unawaited(refreshActiveAttendance());
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => refreshActiveAttendance(),
    );
  }

  @override
  void onClose() {
    _refreshTimer?.cancel();
    super.onClose();
  }

  Future<void> refreshActiveAttendance() async {
    if (_refreshingAttendance) return;
    _refreshingAttendance = true;
    try {
      final response = await _apiClient.get('/api/notifications');
      final responseItems = response['items'];
      if (responseItems is! List) return;

      final previousAttendance = {
        for (final item in items.where(
          (item) => item.type == NotificationType.attendance,
        ))
          item.id: item,
      };
      final activeAttendance = responseItems.whereType<Map>().map((raw) {
        final item = Map<String, dynamic>.from(raw);
        final sessionId = item['sessionId']?.toString() ?? '';
        final id = 'attendance-$sessionId';
        final classId = item['classId']?.toString() ?? '';
        final content = item['content']?.toString() ?? '';
        final method = item['method']?.toString() ?? 'QR';
        final closesAt = DateTime.tryParse(item['closesAt']?.toString() ?? '')
            ?.toLocal();
        final closingTime = closesAt == null
            ? ''
            : ' đến ${closesAt.hour.toString().padLeft(2, '0')}:${closesAt.minute.toString().padLeft(2, '0')}';

        return AppNotificationItem(
          id: id,
          recipients: const [Role.student],
          title: 'Điểm danh lớp $classId đã mở',
          message: '${content.isEmpty ? 'Phiên điểm danh' : content} đang mở bằng $method$closingTime.',
          type: NotificationType.attendance,
          priority: NotificationPriority.high,
          createdAt:
              DateTime.tryParse(item['createdAt']?.toString() ?? '') ??
              DateTime.now(),
          read: previousAttendance[id]?.read ?? false,
          actionLabel: 'Điểm danh',
          route: '/student',
        );
      }).toList();

      items.assignAll([
        ...items.where((item) => item.type != NotificationType.attendance),
        ...activeAttendance,
      ]);
    } catch (_) {
      // Keep the last known notifications while the API is unavailable.
    } finally {
      _refreshingAttendance = false;
    }
  }

  void _seedNotifications() {
    final now = DateTime.now();
    items.assignAll([
      AppNotificationItem(
        id: 'n2',
        recipients: const [Role.student],
        title: 'Lịch học thay đổi',
        message: 'Buổi CS202 đã đổi phòng từ B204 sang B301.',
        type: NotificationType.classUpdate,
        priority: NotificationPriority.normal,
        createdAt: now.subtract(const Duration(hours: 3)),
      ),
      AppNotificationItem(
        id: 'n3',
        recipients: const [Role.student],
        title: 'Chứng chỉ đã cấp',
        message: 'Workshop AI của bạn đã được cấp chứng nhận thành công.',
        type: NotificationType.certificate,
        priority: NotificationPriority.low,
        createdAt: now.subtract(const Duration(days: 1)),
      ),
      AppNotificationItem(
        id: 'n4',
        recipients: const [Role.lecturer, Role.admin],
        title: 'Phân tích điểm danh',
        message: 'Tỷ lệ có mặt của CS101 tuần này giảm 7% so với tuần trước.',
        type: NotificationType.system,
        priority: NotificationPriority.high,
        createdAt: now.subtract(const Duration(hours: 8)),
      ),
      AppNotificationItem(
        id: 'n5',
        recipients: const [Role.organizer, Role.admin],
        title: 'Đơn đăng ký sự kiện cần duyệt',
        message: 'Có 64 sinh viên đăng ký sự kiện Ngày hội Việc làm IT 2025.',
        type: NotificationType.approval,
        priority: NotificationPriority.high,
        createdAt: now.subtract(const Duration(hours: 2)),
        actionLabel: 'Duyệt ngay',
      ),
      AppNotificationItem(
        id: 'n6',
        recipients: const [Role.admin],
        title: 'Báo cáo cuối ngày',
        message: 'Hệ thống đã cập nhật báo cáo điểm danh và báo cáo sự kiện ngày hôm nay.',
        type: NotificationType.system,
        priority: NotificationPriority.normal,
        createdAt: now.subtract(const Duration(days: 2)),
      ),
      AppNotificationItem(
        id: 'n7',
        recipients: const [Role.lecturer],
        title: 'Sinh viên muộn',
        message: '3 sinh viên đã điểm danh muộn trong buổi CS301 hôm nay.',
        type: NotificationType.attendance,
        priority: NotificationPriority.normal,
        createdAt: now.subtract(const Duration(minutes: 46)),
      ),
    ]);
  }

  List<AppNotificationItem> notificationsFor(Role role) {
    return items.where((item) => item.recipients.contains(role)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<AppNotificationItem> visibleFor(Role role, {bool unreadOnly = false, bool importantOnly = false}) {
    final list = notificationsFor(role);
    return list.where((item) {
      if (unreadOnly && item.read) return false;
      if (importantOnly && item.priority == NotificationPriority.low) return false;
      return true;
    }).toList();
  }

  int unreadCount(Role role) => notificationsFor(role).where((item) => !item.read).length;

  void markAsRead(String id) {
    final index = items.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final current = items[index];
    items[index] = current.copyWith(read: true);
  }

  void markAllAsRead(Role role) {
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item.recipients.contains(role) && !item.read) {
        items[i] = item.copyWith(read: true);
      }
    }
  }
}
