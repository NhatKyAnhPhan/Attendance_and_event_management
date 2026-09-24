import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../controllers/notification_controller.dart';
import '../../../core/constants/role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<String>? breadcrumb;
  final Role role;
  final bool isDarkMode;
  final VoidCallback onToggleDark;
  final VoidCallback? onMenuTap; // hiện nút menu khi màn hẹp (mở Drawer)
  final VoidCallback? onNotificationsTap;

  const AppHeader({
    super.key,
    required this.title,
    this.breadcrumb,
    required this.role,
    required this.isDarkMode,
    required this.onToggleDark,
    this.onMenuTap,
    this.onNotificationsTap,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(isDarkMode);
    final notifications = Get.find<NotificationController>();
    final unread = notifications.unreadCount(role);

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: c.card, border: Border(bottom: BorderSide(color: c.border))),
      child: Row(
        children: [
          if (onMenuTap != null)
            IconButton(icon: Icon(Icons.menu, color: c.foreground), onPressed: onMenuTap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (breadcrumb != null)
                  Text(breadcrumb!.join(' / '), style: AppTextStyles.bodyXs(c.mutedForeground).copyWith(fontSize: 11)),
                Text(title, style: AppTextStyles.displaySm(c.foreground)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(isDarkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined, color: c.mutedForeground),
            onPressed: onToggleDark,
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: Icon(Icons.notifications_outlined, color: c.mutedForeground),
                onPressed: onNotificationsTap,
              ),
              if (unread > 0)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: c.danger, shape: BoxShape.circle),
                    child: Text(
                      unread > 9 ? '9+' : unread.toString(),
                      style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
            child: const Text('N', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}