import 'package:flutter/material.dart';

import 'lecturer_attendance_detail_page.dart';
import 'lecturer_attendance_qr_page.dart';

class LecturerAttendancePage extends StatelessWidget {
  const LecturerAttendancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final sessions = [
      {
        'code': 'BDDTEST01',
        'classCode': 'LHPTEST01',
        'subject': 'Kiểm thử phần mềm',
        'session': 'Buổi 1 — Giới thiệu kiểm thử phần mềm',
        'time': '24/09/2026 · 07:00 - 09:30',
        'room': 'Phòng B203',
        'method': 'QR',
        'status': 'Đang mở',
        'total': 8,
        'present': 5,
        'late': 2,
        'absent': 1,
      },
      {
        'code': 'BDDTEST03',
        'classCode': 'LHPTEST02',
        'subject': 'Lập trình mạng',
        'session': 'Buổi 1 — Lập trình Socket cơ bản',
        'time': '26/09/2026 · 13:00 - 15:30',
        'room': 'Phòng C301',
        'method': 'Khuôn mặt',
        'status': 'Đã đóng',
        'total': 7,
        'present': 5,
        'late': 1,
        'absent': 1,
      },
      {
        'code': 'BDDTEST02',
        'classCode': 'LHPTEST01',
        'subject': 'Kiểm thử phần mềm',
        'session': 'Buổi 2 — Thiết kế Test Case',
        'time': '01/10/2026 · 07:00 - 09:30',
        'room': 'Phòng B203',
        'method': 'QR',
        'status': 'Chưa mở',
        'total': 8,
        'present': 0,
        'late': 0,
        'absent': 8,
      },
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 760;

        return SingleChildScrollView(
          padding: EdgeInsets.all(isMobile ? 16 : 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTopSection(context, isMobile),
              const SizedBox(height: 24),

              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: sessions.map((session) {
                  return SizedBox(
                    width: isMobile
                        ? constraints.maxWidth
                        : constraints.maxWidth > 1200
                        ? (constraints.maxWidth - 32) / 3
                        : constraints.maxWidth > 800
                        ? (constraints.maxWidth - 16) / 2
                        : constraints.maxWidth,
                    child: _AttendanceSessionCard(
                      session: session,
                      isDark: isDark,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopSection(BuildContext context, bool isMobile) {
    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quản lý điểm danh',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          const Text(
            'Các phiên điểm danh của lớp học',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Chức năng tạo phiên điểm danh sẽ làm sau.'),
                  ),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('Tạo phiên điểm danh'),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quản lý điểm danh',
                style: TextStyle(fontSize: 27, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 5),
              Text(
                'Các phiên điểm danh của lớp học',
                style: TextStyle(color: Colors.grey, fontSize: 15),
              ),
            ],
          ),
        ),

        ElevatedButton.icon(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Chức năng tạo phiên điểm danh sẽ làm sau.'),
              ),
            );
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1F5EA8),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: const Icon(Icons.add),
          label: const Text(
            'Tạo phiên điểm danh',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _AttendanceSessionCard extends StatelessWidget {
  final Map<String, dynamic> session;
  final bool isDark;

  const _AttendanceSessionCard({required this.session, required this.isDark});

  Color _statusColor(String status) {
    switch (status) {
      case 'Đang mở':
        return const Color(0xFF16A34A);
      case 'Đã đóng':
        return const Color(0xFF64748B);
      default:
        return const Color(0xFF1F5EA8);
    }
  }

  Color _statusBackground(String status) {
    switch (status) {
      case 'Đang mở':
        return const Color(0xFFDCFCE7);
      case 'Đã đóng':
        return const Color(0xFFE2E8F0);
      default:
        return const Color(0xFFDBEAFE);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = session['status'] as String;
    final statusColor = _statusColor(status);

    return Container(
      padding: const EdgeInsets.all(20),
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
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _statusBackground(status),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),

              const Spacer(),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF25364E)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  session['method'],
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          Text(
            '${session['classCode']} — ${session['subject']}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),

          const SizedBox(height: 6),

          Text(session['session'], style: const TextStyle(color: Colors.grey)),

          const SizedBox(height: 16),

          _InfoRow(icon: Icons.access_time_outlined, text: session['time']),
          const SizedBox(height: 8),
          _InfoRow(icon: Icons.location_on_outlined, text: session['room']),
          const SizedBox(height: 8),
          _InfoRow(icon: Icons.tag, text: session['code']),

          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  value: '${session['total']}',
                  label: 'Tổng',
                  color: const Color(0xFF1F5EA8),
                  background: const Color(0xFFEAF1FF),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniStat(
                  value: '${session['present']}',
                  label: 'Có mặt',
                  color: const Color(0xFF16A34A),
                  background: const Color(0xFFDCFCE7),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniStat(
                  value: '${session['late']}',
                  label: 'Muộn',
                  color: const Color(0xFFD97706),
                  background: const Color(0xFFFEF3C7),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniStat(
                  value: '${session['absent']}',
                  label: 'Vắng',
                  color: const Color(0xFFDC2626),
                  background: const Color(0xFFFEE2E2),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (status == 'Đang mở')
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const LecturerAttendanceQrPage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.qr_code_2, size: 19),
                  label: const Text('Xem QR'),
                ),

              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LecturerAttendanceDetailPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.people_outline, size: 19),
                label: const Text('Danh sách'),
              ),

              if (status == 'Chưa mở')
                ElevatedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Phiên điểm danh đã được mở thử.'),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Mở điểm danh'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final Color background;

  const _MiniStat({
    required this.value,
    required this.label,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
