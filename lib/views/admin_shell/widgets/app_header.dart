import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../controllers/auth_controller.dart';
import '../../../controllers/notification_controller.dart';
import '../../../core/constants/role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../lecturer_profile/lecturer_profile_page.dart';

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
  /// Hiển thị tiêu đề và thông tin hồ sơ đã đồng bộ từ API.
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 480;
    final c = AppColors.of(isDarkMode);
    final notifications = Get.find<NotificationController>();
    final unread = notifications.unreadCount(role);
    final userName =
        Get.find<AuthController>().currentUser.value?['name']?.toString() ?? '';
    final initials = userName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();

    return Container(
      height: 64,
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 20),
      decoration: BoxDecoration(
        color: c.card,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          if (onMenuTap != null)
            IconButton(
              visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
              constraints: compact
                  ? const BoxConstraints.tightFor(width: 40, height: 40)
                  : null,
              icon: Icon(Icons.menu, color: c.foreground),
              onPressed: onMenuTap,
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (breadcrumb != null && !compact)
                  Text(
                    breadcrumb!.join(' / '),
                    style: AppTextStyles.bodyXs(c.mutedForeground)
                        .copyWith(fontSize: 11),
                  ),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.displaySm(c.foreground).copyWith(
                    fontSize: compact ? 16 : null,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
            constraints: compact
                ? const BoxConstraints.tightFor(width: 40, height: 40)
                : null,
            icon: Icon(
              isDarkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              color: c.mutedForeground,
            ),
            onPressed: onToggleDark,
          ),
          if (role == Role.student)
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.notifications_outlined,
                    color: c.mutedForeground,
                  ),
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
                      decoration: BoxDecoration(
                        color: c.danger,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        unread > 9 ? '9+' : unread.toString(),
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          SizedBox(width: compact ? 4 : 8),
          Tooltip(
            message: role == Role.lecturer || role == Role.organizer
                ? 'Mở hồ sơ cá nhân'
                : '',
            child: Material(
              color: c.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: role == Role.lecturer || role == Role.organizer
                    ? () => Get.to<void>(() => const LecturerProfilePage())
                    : null,
                child: SizedBox(
                  width: compact ? 32 : 34,
                  height: compact ? 32 : 34,
                  child: Center(
                    child: Text(
                      initials.isEmpty ? 'U' : initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
