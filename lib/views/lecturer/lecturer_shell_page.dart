import 'package:flutter/material.dart';

import 'lecturer_attendance_page.dart';
import 'lecturer_classes_page.dart';
import 'lecturer_dashboard_page.dart';
import 'lecturer_notifications_page.dart';
import 'lecturer_reports_page.dart';
import 'widgets/header_actions.dart';
import 'widgets/lecturer_sidebar.dart';

class LecturerShellPage extends StatefulWidget {
  const LecturerShellPage({super.key});

  @override
  State<LecturerShellPage> createState() => _LecturerShellPageState();
}

class _LecturerShellPageState extends State<LecturerShellPage> {
  int _selectedIndex = 0;
  String _endDrawerType = 'notification';
  final GlobalKey<ScaffoldState> _desktopScaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<ScaffoldState> _mobileScaffoldKey = GlobalKey<ScaffoldState>();

  void _openEndDrawer(String type, bool isDesktop) {
    setState(() {
      _endDrawerType = type;
    });
    if (isDesktop) {
      _desktopScaffoldKey.currentState?.openEndDrawer();
    } else {
      _mobileScaffoldKey.currentState?.openEndDrawer();
    }
  }

  Widget _buildEndDrawer() {
    if (_endDrawerType == 'notification') {
      return LecturerNotificationPanel(
        onSeeAll: () {
          setState(() {
            _selectedIndex = 4;
          });
        },
      );
    } else {
      return LecturerProfilePanel(
        onViewProfile: () {},
      );
    }
  }

  Widget _buildCurrentPage() {
    switch (_selectedIndex) {
      case 0:
        return LecturerDashboardPage(
          onNavigate: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
        );

      case 1:
        return const LecturerClassesPage();

      case 2:
        return const LecturerAttendancePage();

      case 3:
        return const LecturerReportsPage();

      case 4:
        return const LecturerNotificationsPage();

      default:
        return LecturerDashboardPage(
          onNavigate: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
        );
    }
  }

  String _currentTitle() {
    switch (_selectedIndex) {
      case 0:
        return 'Dashboard';
      case 1:
        return 'Lớp của tôi';
      case 2:
        return 'Điểm danh';
      case 3:
        return 'Báo cáo';
      case 4:
        return 'Thông báo';
      default:
        return 'Dashboard';
    }
  }

  String _currentBreadcrumb() {
    switch (_selectedIndex) {
      case 0:
        return 'Trang chủ';
      case 1:
        return 'Trang chủ / Lớp học của tôi';
      case 2:
        return 'Trang chủ / Điểm danh';
      case 3:
        return 'Trang chủ / Báo cáo';
      case 4:
        return 'Trang chủ / Thông báo';
      default:
        return 'Trang chủ';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        // Desktop / Web lớn
        final isDesktop = width >= 1000;

        // Tablet hoặc màn hình nhỏ
        final isTablet = width >= 650 && width < 1000;

        if (isDesktop) {
          return _buildDesktop(context, isDark);
        }

        return _buildMobileTablet(context, isDark, isTablet);
      },
    );
  }

  // =========================================================
  // DESKTOP
  // =========================================================

  Widget _buildDesktop(BuildContext context, bool isDark) {
    return Scaffold(
      key: _desktopScaffoldKey,
      backgroundColor: isDark
          ? const Color(0xFF111827)
          : const Color(0xFFF5F7FB),
      endDrawer: _buildEndDrawer(),
      body: Row(
        children: [
          LecturerSidebar(
            selectedIndex: _selectedIndex,
            onItemSelected: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
          ),

          Expanded(
            child: Column(
              children: [
                _buildDesktopHeader(context, isDark),

                Expanded(child: _buildCurrentPage()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // TABLET + MOBILE
  // =========================================================

  Widget _buildMobileTablet(BuildContext context, bool isDark, bool isTablet) {
    return Scaffold(
      key: _mobileScaffoldKey,
      backgroundColor: isDark
          ? const Color(0xFF111827)
          : const Color(0xFFF5F7FB),
      endDrawer: _buildEndDrawer(),
      drawer: Drawer(
        width: 300,
        child: LecturerSidebar(
          selectedIndex: _selectedIndex,
          onItemSelected: (index) {
            setState(() {
              _selectedIndex = index;
            });

            Navigator.of(context).pop();
          },
        ),
      ),

      appBar: AppBar(
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF1E2A3D) : Colors.white,
        surfaceTintColor: Colors.transparent,

        titleSpacing: 4,

        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isTablet)
              Text(
                _currentBreadcrumb(),
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),

            Text(
              _currentTitle(),
              style: TextStyle(
                fontSize: isTablet ? 19 : 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),

        actions: [
          IconButton(
            tooltip: 'Tìm kiếm',
            onPressed: () {},
            icon: const Icon(Icons.search),
          ),

          IconButton(
            tooltip: 'Đổi giao diện',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Light/Dark mode sẽ nối ThemeController sau.'),
                ),
              );
            },
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            ),
          ),

          LecturerNotificationAction(
            onTap: () => _openEndDrawer('notification', false),
          ),

          LecturerAvatarAction(
            onTap: () => _openEndDrawer('profile', false),
          ),
        ],
      ),

      body: _buildCurrentPage(),
    );
  }

  // =========================================================
  // HEADER DESKTOP
  // =========================================================

  Widget _buildDesktopHeader(BuildContext context, bool isDark) {
    return Container(
      height: 82,
      padding: const EdgeInsets.symmetric(horizontal: 30),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2A3D) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE5E7EB),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentBreadcrumb(),
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),

                const SizedBox(height: 3),

                Text(
                  _currentTitle(),
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          SizedBox(
            width: 280,
            height: 42,
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Tìm kiếm...',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF25364E)
                    : const Color(0xFFF3F6FA),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          const SizedBox(width: 16),

          IconButton(
            tooltip: 'Đổi giao diện',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Light/Dark mode sẽ nối ThemeController sau.'),
                ),
              );
            },
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            ),
          ),

          LecturerNotificationAction(
            onTap: () => _openEndDrawer('notification', true),
          ),

          const SizedBox(width: 8),

          LecturerAvatarAction(
            onTap: () => _openEndDrawer('profile', true),
          ),
        ],
      ),
    );
  }
}
