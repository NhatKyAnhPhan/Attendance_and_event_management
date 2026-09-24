import 'package:get/get.dart';

import '../core/constants/role.dart';
import '../data/models/notification_model.dart';

class NotificationController extends GetxController {
  final RxList<AppNotificationItem> items = <AppNotificationItem>[].obs;

  @override
  void onInit() {
    super.onInit();
    _seedNotifications();
  }

  void _seedNotifications() {
    final now = DateTime.now();
    items.assignAll([
      AppNotificationItem(
        id: 'n1',
        recipients: const [Role.student],
        title: 'Điểm danh mở',
        message: 'Lớp CS101 đã mở điểm danh. Vui lòng xác nhận trong 15 phút tới.',
        type: NotificationType.attendance,
        priority: NotificationPriority.high,
        createdAt: now.subtract(const Duration(minutes: 12)),
        actionLabel: 'Điểm danh',
        route: '/student',
      ),
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
