import 'dart:async';

import 'package:get/get.dart';

import 'auth_controller.dart';
import '../core/constants/role.dart';
import '../data/api/api_client.dart';
import '../data/models/notification_model.dart';

class NotificationController extends GetxController {
  final RxList<AppNotificationItem> items = <AppNotificationItem>[].obs;
  final ApiClient _apiClient = ApiClient();
  Timer? _refreshTimer;
  Worker? _authWorker;
  bool _refreshingAttendance = false;

  /// Chỉ đồng bộ thông báo thật sau khi trạng thái đăng nhập đã được xác minh.
  @override
  void onInit() {
    super.onInit();
    final auth = Get.find<AuthController>();
    _authWorker = everAll([auth.isReady, auth.isAuthed], (_) {
      if (auth.isReady.value && auth.isAuthed.value) {
        unawaited(refreshActiveAttendance());
      } else if (auth.isReady.value) {
        items.clear();
      }
    });
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => refreshActiveAttendance(),
    );
  }

  /// Dừng bộ đếm và listener xác thực khi controller bị hủy.
  @override
  void onClose() {
    _refreshTimer?.cancel();
    _authWorker?.dispose();
    super.onClose();
  }

  /// Đồng bộ các phiên điểm danh đang mở khi phiên người dùng còn hợp lệ.
  Future<void> refreshActiveAttendance() async {
    if (_refreshingAttendance) return;
    final auth = Get.find<AuthController>();
    if (!auth.isReady.value || !auth.isAuthed.value) return;
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
          message:
              '${content.isEmpty ? 'Phiên điểm danh' : content} đang mở bằng $method$closingTime.',
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

  // Lọc thông báo theo vai trò và sắp xếp thông báo mới nhất lên trước.
  List<AppNotificationItem> notificationsFor(Role role) {
    return items.where((item) => item.recipients.contains(role)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  // Lọc tiếp danh sách theo trạng thái chưa đọc hoặc mức độ quan trọng.
  List<AppNotificationItem> visibleFor(
    Role role, {
    bool unreadOnly = false,
    bool importantOnly = false,
  }) {
    final list = notificationsFor(role);
    return list.where((item) {
      if (unreadOnly && item.read) {
        return false;
      }
      if (importantOnly && item.priority == NotificationPriority.low) {
        return false;
      }
      return true;
    }).toList();
  }

  int unreadCount(Role role) =>
      notificationsFor(role).where((item) => !item.read).length;
  // Đánh dấu một thông báo cụ thể là đã đọc.

  void markAsRead(String id) {
    final index = items.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final current = items[index];
    items[index] = current.copyWith(read: true);
  }

  // Đánh dấu toàn bộ thông báo thuộc vai trò hiện tại là đã đọc.
  void markAllAsRead(Role role) {
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item.recipients.contains(role) && !item.read) {
        items[i] = item.copyWith(read: true);
      }
    }
  }
}
