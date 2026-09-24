import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/theme_controller.dart';
import '../../core/constants/admin_page.dart';
import '../../core/theme/app_colors.dart';
import '../dashboard/dashboard_page.dart';
import '../attendance/attendance_page.dart';
import '../attendance/qr_scan_page.dart';
import '../classes/classes_page.dart';
import '../events/events_page.dart';
import '../notifications/notifications_page.dart';
import '../reports/reports_page.dart';
import '../shared/placeholder_page.dart';
import '../shared/admin_data_page.dart';
import '../users/users_page.dart';
import 'widgets/app_header.dart';
import 'widgets/app_sidebar.dart';

/// Tương ứng phần layout chính (Sidebar + Header + renderPage) trong App.tsx,
/// dùng chung cho 3 role: admin, lecturer, organizer.
class AdminShellPage extends StatefulWidget {
  const AdminShellPage({super.key});

  @override
  State<AdminShellPage> createState() => _AdminShellPageState();
}

class _AdminShellPageState extends State<AdminShellPage> {
  AdminPage _activePage = AdminPage.dashboard;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  void _navigate(AdminPage page) {
    setState(() => _activePage = page);
    Navigator.of(context).maybePop(); // đóng Drawer nếu đang mở (màn hẹp)
  }

  Widget _buildBody(bool isDark) {
    switch (_activePage) {
      case AdminPage.dashboard:
        return DashboardPage(role: Get.find<AuthController>().role.value);
      case AdminPage.users:
        return const UsersPage();
      case AdminPage.orgUnits:
        return const PlaceholderPage(title: 'Đơn vị tổ chức');
      case AdminPage.classes:
        return const ClassesPage();
      case AdminPage.events:
        return const EventsPage();
      case AdminPage.attendance:
        return const AttendancePage();
      case AdminPage.reports:
        return const ReportsPage();
      case AdminPage.feedback:
        return const PlaceholderPage(title: 'Phản hồi');
      case AdminPage.certificates:
        return const PlaceholderPage(title: 'Chứng chỉ');
      case AdminPage.notifications:
        return NotificationsPage(role: Get.find<AuthController>().role.value);
      case AdminPage.settings:
        return const PlaceholderPage(title: 'Cài đặt');
      default:
        return PlaceholderPage(title: _activePage.title);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();
    final theme = Get.find<ThemeController>();

    return Obx(() {
      final isDark = theme.isDark.value;
      final c = AppColors.of(isDark);
      final role = auth.role.value;

      return LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 1024;

          final sidebar = AppSidebar(
            role: role,
            activePage: _activePage,
            onNavigate: _navigate,
            onLogout: auth.logout,
          );

          final header = AppHeader(
            title: _activePage.title,
            breadcrumb: _activePage == AdminPage.dashboard
                ? ['Trang chủ']
                : ['Trang chủ', _activePage.title],
            role: role,
            isDarkMode: isDark,
            onToggleDark: theme.toggle,
            onMenuTap: isWide
                ? null
                : () => _scaffoldKey.currentState?.openDrawer(),
            onNotificationsTap: () => _navigate(AdminPage.notifications),
          );

          return Scaffold(
            key: _scaffoldKey,
            backgroundColor: c.background,
            drawer: isWide ? null : Drawer(child: sidebar),
            body: Row(
              children: [
                if (isWide) sidebar,
                Expanded(
                  child: Column(
                    children: [
                      header,
                      Expanded(child: _buildBody(isDark)),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    });
  }
}
