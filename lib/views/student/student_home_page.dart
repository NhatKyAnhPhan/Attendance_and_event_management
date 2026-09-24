import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/classes_controller.dart';
import '../../controllers/events_controller.dart';
import '../../controllers/notification_controller.dart';
import '../../core/constants/role.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/mock/student_mock_data.dart';
import '../../data/models/notification_model.dart';
import '../../widgets/app_badge.dart';
import '../notifications/notifications_page.dart';
import 'student_checkin_page.dart';
import 'student_classes_page.dart';
import 'student_events_page.dart';
import 'student_profile_page.dart';

/// Shell chứa bottom nav — tương ứng phần `navItems` + IndexedStack theo `tab`
/// trong StudentMobilePage.tsx. Nội dung tab "Trang chủ" viết thẳng ở đây
/// (widget _HomeTabContent bên dưới) vì đây cũng là file duy nhất đại diện
/// cho mục 18 (Student Mobile Home) trong bản thiết kế.
class StudentHomePage extends StatefulWidget {
  const StudentHomePage({super.key});

  @override
  State<StudentHomePage> createState() => _StudentHomePageState();
}

class _StudentHomePageState extends State<StudentHomePage> {
  int _index = 0;

  void _goTo(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);

    final pages = [
      _HomeTabContent(onScan: () => _goTo(3), onGoToClasses: () => _goTo(1)),
      const StudentClassesPage(),
      const StudentEventsPage(),
      const StudentCheckinPage(),
      const StudentProfilePage(),
    ];

    return Scaffold(
      backgroundColor: c.background,
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: _goTo,
        type: BottomNavigationBarType.fixed,
        backgroundColor: c.card,
        selectedItemColor: c.primary,
        unselectedItemColor: c.mutedForeground,
        selectedLabelStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Trang chủ',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.menu_book_outlined),
            activeIcon: Icon(Icons.menu_book),
            label: 'Lớp học',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.event_outlined),
            activeIcon: Icon(Icons.event),
            label: 'Sự kiện',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.qr_code_scanner_outlined),
            activeIcon: Icon(Icons.qr_code_scanner),
            label: 'Điểm danh',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Cá nhân',
          ),
        ],
      ),
    );
  }
}

// ============ Nội dung tab "Trang chủ" (mục 18) ============

class _HomeTabContent extends StatelessWidget {
  final VoidCallback onScan;
  final VoidCallback onGoToClasses;
  const _HomeTabContent({required this.onScan, required this.onGoToClasses});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);
    final classesController = Get.put(ClassesController());
    final eventsController = Get.put(EventsController());
    final notifications = Get.find<NotificationController>();
    final auth = Get.find<AuthController>();

    return Obx(() {
      final classes = classesController.items;
      final events = eventsController.items;
      final user = auth.currentUser.value ?? const <String, dynamic>{};
      return ListView(
        padding: EdgeInsets.zero,
        children: [
          _buildHeader(c, user, notifications.unreadCount(Role.student)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('Thao tác nhanh', c),
                const SizedBox(height: 12),
                _buildQuickActions(c),
                const SizedBox(height: 20),

                _sectionTitle('Lớp học hôm nay', c),
                const SizedBox(height: 12),
                ...classes
                    .take(2)
                    .map(
                      (cls) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _TodayClassCard(cls: cls, c: c),
                      ),
                    ),
                const SizedBox(height: 8),

                _sectionTitle('Sự kiện sắp tới', c),
                const SizedBox(height: 12),
                ...events.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _EventRow(event: e, c: c),
                  ),
                ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    Expanded(child: _sectionTitle('Thông báo', c)),
                    TextButton(
                      onPressed: () => Get.to(() => const NotificationsPage(role: Role.student)),
                      child: Text('Xem tất cả', style: AppTextStyles.bodySm(c.primary)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...notifications
                    .notificationsFor(Role.student)
                    .take(3)
                    .map(
                      (n) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _NotificationRow(
                          notif: StudentNotification(
                            id: n.id.hashCode,
                            type: switch (n.type) {
                              NotificationType.attendance => 'attendance',
                              NotificationType.classUpdate => 'class',
                              NotificationType.event => 'event',
                              NotificationType.certificate => 'certificate',
                              NotificationType.system => 'class',
                              NotificationType.approval => 'event',
                            },
                            text: n.message,
                            time: n.timeLabel,
                            read: n.read,
                          ),
                          c: c,
                          onTap: () => showNotificationDetails(context, n),
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

  Widget _sectionTitle(String text, AppColors c) =>
      Text(text, style: AppTextStyles.displaySm(c.foreground));

  Widget _buildHeader(AppColors c, Map<String, dynamic> user, int unreadCount) {
    const summary = [
      {'label': 'Có mặt', 'val': '89%'},
      {'label': 'Muộn', 'val': '8%'},
      {'label': 'Vắng', 'val': '3%'},
    ];
    return Container(
      color: c.primary,
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Xin chào',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  Text(
                    user['name']?.toString() ?? 'Người dùng',
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Nunito',
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                    ),
                  ),
                  Text(
                    'Tài khoản dữ liệu thật',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  InkWell(
                    onTap: () => Get.to(() => const NotificationsPage(role: Role.student)),
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.notifications_none,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        width: 16,
                        height: 16,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: Color(0xFFDC2626),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          unreadCount > 9 ? '9+' : unreadCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: summary.map((s) {
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        s['val']!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'Nunito',
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                        ),
                      ),
                      Text(
                        s['label']!,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(AppColors c) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: onScan,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.qr_code_scanner,
                    color: Colors.white,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quét QR',
                          style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'Nunito',
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          'Điểm danh ngay',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            onTap: onGoToClasses,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.card,
                border: Border.all(color: c.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.menu_book_outlined, color: c.primary, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lớp học',
                          style: AppTextStyles.displayXs(c.foreground)
                              .copyWith(fontSize: 14),
                        ),
                        Text(
                          'Xem tất cả lớp',
                          style: AppTextStyles.bodyXs(c.mutedForeground),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TodayClassCard extends StatelessWidget {
  final StudentClassSummary cls;
  final AppColors c;
  const _TodayClassCard({required this.cls, required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFDBEAFE),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.menu_book,
              color: Color(0xFF1E56A0),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cls.name,
                  style: AppTextStyles.displayXs(c.foreground)
                      .copyWith(fontSize: 14),
                ),
                Text(
                  '${cls.time} · Phòng ${cls.room}',
                  style: AppTextStyles.bodyXs(c.mutedForeground),
                ),
              ],
            ),
          ),
          const AppBadge(label: 'Chưa mở', status: BadgeStatus.pending),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final StudentEventSummary event;
  final AppColors c;
  const _EventRow({required this.event, required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF3E8FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.event, color: Color(0xFF7C3AED), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.name,
                  style: AppTextStyles.displayXs(c.foreground)
                      .copyWith(fontSize: 13),
                ),
                Text(
                  '${event.date} · ${event.org}',
                  style: AppTextStyles.bodyXs(c.mutedForeground),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: event.registered
                ? const Align(
                    alignment: Alignment.topRight,
                    child: AppBadge(
                      label: 'Đã đăng ký',
                      status: BadgeStatus.present,
                    ),
                  )
                : Align(
                    alignment: Alignment.topRight,
                    child: SizedBox(
                      height: 28,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        onPressed: () {},
                        child: const Text(
                          'Đăng ký',
                          style: TextStyle(fontSize: 11),
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

class _NotificationRow extends StatelessWidget {
  final StudentNotification notif;
  final AppColors c;
  final VoidCallback onTap;
  const _NotificationRow({required this.notif, required this.c, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: notif.read ? 0.6 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.card,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(notif.emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(notif.text, style: AppTextStyles.bodySm(c.foreground)),
                    const SizedBox(height: 2),
                    Text(
                      notif.time,
                      style: AppTextStyles.bodyXs(c.mutedForeground),
                    ),
                  ],
                ),
              ),
              if (!notif.read)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: c.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
