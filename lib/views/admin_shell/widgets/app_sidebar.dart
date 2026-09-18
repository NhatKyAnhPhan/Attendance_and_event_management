import 'package:flutter/material.dart';
import '../../../core/constants/admin_page.dart';
import '../../../core/constants/role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

class _NavItem {
  final IconData icon;
  final AdminPage page;
  const _NavItem(this.icon, this.page);
}

const _adminNav = [
  _NavItem(Icons.home_outlined, AdminPage.dashboard),
  _NavItem(Icons.people_outline, AdminPage.users),
  _NavItem(Icons.apartment_outlined, AdminPage.orgUnits),
  _NavItem(Icons.menu_book_outlined, AdminPage.classes),
  _NavItem(Icons.event_outlined, AdminPage.events),
  _NavItem(Icons.check_box_outlined, AdminPage.attendance),
  _NavItem(Icons.bar_chart_outlined, AdminPage.reports),
  _NavItem(Icons.forum_outlined, AdminPage.feedback),
  _NavItem(Icons.workspace_premium_outlined, AdminPage.certificates),
  _NavItem(Icons.notifications_outlined, AdminPage.notifications),
  _NavItem(Icons.settings_outlined, AdminPage.settings),
];

const _lecturerNav = [
  _NavItem(Icons.home_outlined, AdminPage.dashboard),
  _NavItem(Icons.menu_book_outlined, AdminPage.classes),
  _NavItem(Icons.check_box_outlined, AdminPage.attendance),
  _NavItem(Icons.bar_chart_outlined, AdminPage.reports),
  _NavItem(Icons.notifications_outlined, AdminPage.notifications),
];

const _organizerNav = [
  _NavItem(Icons.home_outlined, AdminPage.dashboard),
  _NavItem(Icons.event_outlined, AdminPage.events),
  _NavItem(Icons.people_outline, AdminPage.users),
  _NavItem(Icons.check_box_outlined, AdminPage.attendance),
  _NavItem(Icons.workspace_premium_outlined, AdminPage.certificates),
  _NavItem(Icons.forum_outlined, AdminPage.feedback),
  _NavItem(Icons.bar_chart_outlined, AdminPage.reports),
];

List<_NavItem> _navFor(Role role) {
  switch (role) {
    case Role.admin:
      return _adminNav;
    case Role.lecturer:
      return _lecturerNav;
    case Role.organizer:
      return _organizerNav;
    case Role.student:
      return const [];
  }
}

class AppSidebar extends StatelessWidget {
  final Role role;
  final AdminPage activePage;
  final ValueChanged<AdminPage> onNavigate;
  final VoidCallback onLogout;
  final bool collapsed;

  const AppSidebar({
    super.key,
    required this.role,
    required this.activePage,
    required this.onNavigate,
    required this.onLogout,
    this.collapsed = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);
    final nav = _navFor(role);

    return Container(
      width: collapsed ? 64 : 256,
      color: c.card,
      child: Column(
        children: [
          // Logo
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.school, color: Colors.white, size: 20),
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('HUIT', style: AppTextStyles.displayXs(c.primary).copyWith(fontSize: 13)),
                        Text('Điểm danh thông minh', style: AppTextStyles.bodyXs(c.mutedForeground).copyWith(fontSize: 10)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Role badge
          if (!collapsed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: c.secondary, borderRadius: BorderRadius.circular(999)),
                  child: Text(role.label,
                      style: AppTextStyles.bodyXs(c.primary).copyWith(fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ),
            ),

          // Nav
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: nav.map((item) {
                final active = item.page == activePage;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Material(
                    color: active ? c.secondary : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => onNavigate(item.page),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        child: Row(
                          children: [
                            Icon(item.icon, size: 18, color: active ? c.primary : c.mutedForeground),
                            if (!collapsed) ...[
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  item.page.title,
                                  style: AppTextStyles.bodySm(active ? c.primary : c.mutedForeground)
                                      .copyWith(fontWeight: active ? FontWeight.w600 : FontWeight.w500),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // Footer — user info + logout
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border))),
            child: Column(
              children: [
                if (!collapsed)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(color: c.muted, borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
                          child: Text(role.shortCode,
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(role.label,
                              style: AppTextStyles.bodySm(c.foreground).copyWith(fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: onLogout,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.logout, size: 18, color: c.danger),
                          if (!collapsed) ...[
                            const SizedBox(width: 10),
                            Text('Đăng xuất', style: AppTextStyles.bodySm(c.danger).copyWith(fontWeight: FontWeight.w500)),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}