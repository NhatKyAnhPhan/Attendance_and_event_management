import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/notification_controller.dart';
import '../../core/constants/role.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/models/notification_model.dart';

Future<void> showNotificationDetails(BuildContext context, AppNotificationItem item) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final c = AppColors.of(isDark);
  final controller = Get.find<NotificationController>();
  if (!item.read) controller.markAsRead(item.id);

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: c.card,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(item.icon, color: c.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(item.title, style: AppTextStyles.displaySm(c.foreground)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(item.message, style: AppTextStyles.bodyMd(c.foreground)),
          const SizedBox(height: 12),
          Text(item.timeLabel, style: AppTextStyles.bodySm(c.mutedForeground)),
          if (item.actionLabel != null) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(item.actionLabel!),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class NotificationsPage extends StatefulWidget {
  final Role role;

  const NotificationsPage({super.key, required this.role});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    unawaited(Get.find<NotificationController>().refreshActiveAttendance());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);
    final controller = Get.find<NotificationController>();

    return Obx(() {
      final items = controller.notificationsFor(widget.role);
      final filtered = switch (_filter) {
        'unread' => items.where((item) => !item.read).toList(),
        'important' => items.where((item) => item.priority == NotificationPriority.high).toList(),
        _ => items,
      };

      return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.card,
        foregroundColor: c.foreground,
        title: Text('Thông báo', style: AppTextStyles.displaySm(c.foreground)),
        actions: [
          if (controller.unreadCount(widget.role) > 0)
            TextButton(
              onPressed: () => controller.markAllAsRead(widget.role),
              child: Text('Đánh dấu đã đọc', style: AppTextStyles.bodySm(c.primary)),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: c.card,
                  border: Border.all(color: c.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    _FilterChip(
                      active: _filter == 'all',
                      label: 'Tất cả',
                      onTap: () => setState(() => _filter = 'all'),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      active: _filter == 'unread',
                      label: 'Chưa đọc',
                      onTap: () => setState(() => _filter = 'unread'),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      active: _filter == 'important',
                      label: 'Quan trọng',
                      onTap: () => setState(() => _filter = 'important'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.notifications_none, size: 48),
                            const SizedBox(height: 12),
                            Text('Không có thông báo nào', style: AppTextStyles.displaySm(c.foreground)),
                            const SizedBox(height: 8),
                            Text('Bạn đã xem hết thông báo của vai trò này.', style: AppTextStyles.bodySm(c.mutedForeground)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          return _NotificationTile(
                            item: item,
                            c: c,
                            onTap: () => showNotificationDetails(context, item),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      );
    });
  }
}

class _FilterChip extends StatelessWidget {
  final bool active;
  final String label;
  final VoidCallback onTap;

  const _FilterChip({required this.active, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? c.secondary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: AppTextStyles.bodySm(active ? c.primary : c.mutedForeground).copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotificationItem item;
  final AppColors c;
  final VoidCallback onTap;

  const _NotificationTile({required this.item, required this.c, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = switch (item.priority) {
      NotificationPriority.high => c.danger,
      NotificationPriority.normal => c.primary,
      NotificationPriority.low => c.success,
    };

    return Opacity(
      opacity: item.read ? 0.7 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.card,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(item.icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(item.title, style: AppTextStyles.displaySm(c.foreground)),
                        ),
                        if (!item.read)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(item.message, style: AppTextStyles.bodySm(c.mutedForeground)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(item.timeLabel, style: AppTextStyles.bodyXs(c.mutedForeground)),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            switch (item.priority) {
                              NotificationPriority.high => 'Quan trọng',
                              NotificationPriority.normal => 'Bình thường',
                              NotificationPriority.low => 'Thấp',
                            },
                            style: AppTextStyles.bodyXs(color),
                          ),
                        ),
                      ],
                    ),
                    if (item.actionLabel != null) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 32,
                        child: OutlinedButton(
                          onPressed: onTap,
                          child: Text(item.actionLabel!),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
