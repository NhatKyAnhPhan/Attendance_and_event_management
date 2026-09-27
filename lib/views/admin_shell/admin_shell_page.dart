import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/theme_controller.dart';
import '../../core/constants/admin_page.dart';
import '../../core/constants/role.dart';
import '../../core/routes/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../settings/admin_settings_page.dart';
import '../staff/staff_records_page.dart';
import '../dashboard/dashboard_page.dart';
import '../attendance/attendance_page.dart';
import '../classes/classes_page.dart';
import '../notifications/notifications_page.dart';
import '../reports/reports_page.dart';
import '../events/organizer_events_page.dart';
import '../shared/admin_data_page.dart';
import 'widgets/app_header.dart';
import 'widgets/app_sidebar.dart';

/// Tương ứng phần layout chính (Sidebar + Header + renderPage) trong App.tsx,
/// dùng chung cho 3 role: admin, lecturer, organizer.
class AdminShellPage extends StatefulWidget {
  const AdminShellPage({super.key});

  @override
  /// Tạo stateful shell cho điều hướng quản trị và cán bộ.
  State<AdminShellPage> createState() => _AdminShellPageState();
}

class _AdminShellPageState extends State<AdminShellPage> {
  AdminPage _activePage = AdminPage.dashboard;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _routingAway = false;

  /// Chuyển trang hiện tại và đóng drawer nếu ứng dụng đang ở màn hình hẹp.
  void _navigate(AdminPage page) {
    setState(() => _activePage = page);
    Navigator.of(context).maybePop(); // đóng Drawer nếu đang mở (màn hẹp)
  }

  /// Chọn nội dung tương ứng với mục điều hướng đang được mở.
  Widget _buildBody(bool isDark) {
    // Chọn màn hình theo mục đang hoạt động trong thanh điều hướng quản trị.
    switch (_activePage) {
      case AdminPage.dashboard:
        return DashboardPage(role: Get.find<AuthController>().role.value);
      case AdminPage.users:
        return const AdminDataPage(
          title: 'Quản lý người dùng',
          endpoint: '/api/admin/users',
          columns: ['Mã', 'Họ tên', 'Email', 'Vai trò', 'Trạng thái'],
        );
      case AdminPage.orgUnits:
        return const AdminDataPage(
          title: 'Đơn vị tổ chức',
          endpoint: '/api/organizer/units',
          columns: ['Mã đơn vị', 'Tên đơn vị'],
        );
      case AdminPage.classes:
        return const ClassesPage();
      case AdminPage.events:
        return const OrganizerEventsPage();
      case AdminPage.attendance:
        return const AttendancePage();
      case AdminPage.reports:
        return const ReportsPage();
      case AdminPage.feedback:
        return const StaffRecordsPage(kind: StaffRecordKind.feedback);
      case AdminPage.certificates:
        return const StaffRecordsPage(kind: StaffRecordKind.certificates);
      case AdminPage.notifications:
        return NotificationsPage(role: Get.find<AuthController>().role.value);
      case AdminPage.settings:
        return const AdminSettingsPage();
    }
  }

  @override
  /// Dựng layout responsive gồm sidebar, header và nội dung trang.
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();
    final theme = Get.find<ThemeController>();

    return Obx(() {
      if (!auth.isReady.value || !auth.isAuthed.value) {
        if (auth.isReady.value) {
          _redirectForSession(auth, Role.student);
        }
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (auth.role.value == Role.student) {
        _redirectForSession(auth, Role.student);
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }

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

  /// Điều hướng khỏi shell khi phiên hết hạn hoặc tài khoản có vai trò khác.
  void _redirectForSession(AuthController auth, Role role) {
    if (_routingAway) return;
    _routingAway = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Get.offAllNamed(
        !auth.isAuthed.value
            ? AppRoutes.login
            : role == Role.student
            ? AppRoutes.studentHome
            : AppRoutes.adminShell,
      );
      _routingAway = false;
    });
  }
}
