import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/theme_controller.dart';
import '../../core/constants/admin_page.dart';
import '../../core/theme/app_colors.dart';
import '../dashboard/dashboard_page.dart';
import '../shared/placeholder_page.dart';
import '../shared/admin_data_page.dart';
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
        return const AdminDataPage(
          title: 'Quản lý người dùng',
          endpoint: '/api/admin/users',
          columns: ['Mã', 'Họ tên', 'Email', 'Vai trò', 'Trạng thái'],
        );
      case AdminPage.classes:
        return const AdminDataPage(
          title: 'Quản lý lớp học',
          endpoint: '/api/admin/classes',
          columns: [
            'Mã lớp',
            'Tên lớp',
            'Giảng viên',
            'Học kỳ',
            'Số sinh viên',
          ],
        );
      case AdminPage.events:
        return const AdminDataPage(
          title: 'Quản lý sự kiện',
          endpoint: '/api/admin/events',
          columns: ['Mã', 'Tên sự kiện', 'Địa điểm', 'Thời gian', 'Số đăng ký'],
        );
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
            isDarkMode: isDark,
            onToggleDark: theme.toggle,
            onMenuTap: isWide
                ? null
                : () => _scaffoldKey.currentState?.openDrawer(),
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
