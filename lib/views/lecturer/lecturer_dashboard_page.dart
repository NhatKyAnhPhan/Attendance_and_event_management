import 'package:flutter/material.dart';

class LecturerDashboardPage extends StatelessWidget {
  final void Function(int index)? onNavigate;

  const LecturerDashboardPage({super.key, this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Xin chào, TS. Trần Văn Bình 👋',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Thứ Tư, 23 tháng 9, 2026',
                      style: TextStyle(fontSize: 15, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF25364E)
                      : const Color(0xFFEFF4FF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.access_time, size: 18, color: Color(0xFF1F5EA8)),
                    SizedBox(width: 8),
                    Text(
                      'Học kỳ 2 — 2024/2025',
                      style: TextStyle(
                        color: Color(0xFF1F5EA8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 28),

          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final crossAxisCount = width > 1100
                  ? 4
                  : width > 750
                  ? 2
                  : 1;

              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 18,
                mainAxisSpacing: 18,
                childAspectRatio: crossAxisCount == 4 ? 1.9 : 2.3,
                children: [
                  _StatCard(
                    title: 'Lớp của tôi',
                    value: '5',
                    subtitle: 'HK 2024–2025',
                    icon: Icons.menu_book_outlined,
                    iconColor: const Color(0xFF1F5EA8),
                    iconBackground: const Color(0xFFDCEAFF),
                    onTap: () => onNavigate?.call(1),
                  ),
                  _StatCard(
                    title: 'Sinh viên',
                    value: '186',
                    subtitle: '5 lớp học',
                    icon: Icons.people_outline,
                    iconColor: const Color(0xFF0097C4),
                    iconBackground: const Color(0xFFDDF4FB),
                    onTap: () => onNavigate?.call(1),
                  ),
                  _StatCard(
                    title: 'Buổi hôm nay',
                    value: '2',
                    subtitle: '1 đang mở',
                    icon: Icons.check_box_outlined,
                    iconColor: const Color(0xFF16A34A),
                    iconBackground: const Color(0xFFDDF8E7),
                    onTap: () => onNavigate?.call(2),
                  ),
                  _StatCard(
                    title: 'Tỷ lệ có mặt TB',
                    value: '84.7%',
                    subtitle: 'Học kỳ này',
                    icon: Icons.monitor_heart_outlined,
                    iconColor: const Color(0xFFD97706),
                    iconBackground: const Color(0xFFFFF0C8),
                    onTap: () => onNavigate?.call(3),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 24),

          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 900;

              final weekly = _DashboardPanel(
                title: 'Thống kê điểm danh tuần này',
                child: const SizedBox(
                  height: 260,
                  child: Center(
                    child: Text('Biểu đồ tuần sẽ bổ sung ở bước sau'),
                  ),
                ),
              );

              final ratio = _DashboardPanel(
                title: 'Tỷ lệ điểm danh',
                child: const SizedBox(
                  height: 260,
                  child: Center(
                    child: Text('Donut chart sẽ bổ sung ở bước sau'),
                  ),
                ),
              );

              if (stacked) {
                return Column(
                  children: [weekly, const SizedBox(height: 20), ratio],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: weekly),
                  const SizedBox(width: 20),
                  Expanded(flex: 2, child: ratio),
                ],
              );
            },
          ),

          const SizedBox(height: 24),

          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 900;

              final recent = const _DashboardPanel(
                title: 'Hoạt động gần đây',
                child: Column(
                  children: [
                    _ActivityItem(
                      title: 'Mở điểm danh',
                      subtitle: 'CS101 — Lập trình cơ bản',
                      time: '08:42',
                    ),
                    _ActivityItem(
                      title: 'Sinh viên điểm danh',
                      subtitle: 'Nguyễn Văn An — 21IT001',
                      time: '09:15',
                    ),
                    _ActivityItem(
                      title: 'Đóng điểm danh',
                      subtitle: 'CS202 — Cơ sở dữ liệu',
                      time: '10:00',
                    ),
                  ],
                ),
              );

              final today = const _DashboardPanel(
                title: 'Buổi học hôm nay',
                child: Column(
                  children: [
                    _TodayClassItem(
                      time: '13:00',
                      className: 'CS301 — Công nghệ phần mềm',
                      room: 'Phòng A301 · 42 SV',
                    ),
                    _TodayClassItem(
                      time: '15:00',
                      className: 'CS202 — Cơ sở dữ liệu',
                      room: 'Phòng B204 · 38 SV',
                    ),
                    _TodayClassItem(
                      time: '17:00',
                      className: 'CS401 — Trí tuệ nhân tạo',
                      room: 'Phòng A501 · 35 SV',
                    ),
                  ],
                ),
              );

              if (stacked) {
                return Column(
                  children: [recent, const SizedBox(height: 20), today],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: recent),
                  const SizedBox(width: 20),
                  Expanded(child: today),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final VoidCallback? onTap;

  const _StatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2A3D) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE5E7EB),
        ),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: iconColor, size: 28),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 13, color: iconColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
}

class _DashboardPanel extends StatelessWidget {
  final String title;
  final Widget child;

  const _DashboardPanel({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2A3D) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE5E7EB),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _ActivityItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final String time;

  const _ActivityItem({
    required this.title,
    required this.subtitle,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const CircleAvatar(
        radius: 8,
        backgroundColor: Color(0xFF16A34A),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      trailing: Text(time, style: const TextStyle(color: Colors.grey)),
    );
  }
}

class _TodayClassItem extends StatelessWidget {
  final String time;
  final String className;
  final String room;

  const _TodayClassItem({
    required this.time,
    required this.className,
    required this.room,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Text(
              time,
              style: const TextStyle(
                color: Color(0xFF1F5EA8),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  className,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  room,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFDDF4FB),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'Chờ mở',
              style: TextStyle(
                color: Color(0xFF027A9F),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
