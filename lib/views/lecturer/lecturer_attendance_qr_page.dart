import 'package:flutter/material.dart';

import 'lecturer_attendance_detail_page.dart';

class LecturerAttendanceQrPage extends StatefulWidget {
  const LecturerAttendanceQrPage({super.key});

  @override
  State<LecturerAttendanceQrPage> createState() =>
      _LecturerAttendanceQrPageState();
}

class _LecturerAttendanceQrPageState extends State<LecturerAttendanceQrPage> {
  int _secondsRemaining = 145;

  String _formatTime(int seconds) {
    final minute = seconds ~/ 60;
    final second = seconds % 60;

    return '${minute.toString().padLeft(2, '0')}:'
        '${second.toString().padLeft(2, '0')}';
  }

  void _regenerateQr() {
    setState(() {
      _secondsRemaining = 180;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã tạo lại mã QR thử nghiệm.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF111827)
          : const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('QR Điểm danh'),
        backgroundColor: isDark ? const Color(0xFF1E2A3D) : Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 750;

          return SingleChildScrollView(
            padding: EdgeInsets.all(isMobile ? 16 : 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1050),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Điểm danh bằng QR',
                      style: TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'LHPTEST01 — Kiểm thử phần mềm · Buổi 1',
                      style: TextStyle(color: Colors.grey, fontSize: 15),
                    ),

                    const SizedBox(height: 24),

                    if (isMobile)
                      Column(
                        children: [
                          _buildQrCard(isDark),
                          const SizedBox(height: 20),
                          _buildInfoCard(isDark),
                        ],
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: _buildQrCard(isDark)),
                          const SizedBox(width: 20),
                          Expanded(flex: 2, child: _buildInfoCard(isDark)),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildQrCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2A3D) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE5E7EB),
        ),
      ),
      child: Column(
        children: [
          const Text(
            'Quét mã để điểm danh',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Sinh viên mở ứng dụng và quét mã QR bên dưới',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),

          const SizedBox(height: 26),

          Container(
            width: 270,
            height: 270,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const _QrPlaceholder(),
          ),

          const SizedBox(height: 22),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.timer_outlined,
                  color: Color(0xFFD97706),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Hết hạn sau ${_formatTime(_secondsRemaining)}',
                  style: const TextStyle(
                    color: Color(0xFFD97706),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _regenerateQr,
                icon: const Icon(Icons.refresh),
                label: const Text('Tạo lại QR'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LecturerAttendanceDetailPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.people_outline),
                label: const Text('Xem danh sách'),
              ),
              FilledButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('QR đã được tắt thử nghiệm.')),
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                ),
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Tắt QR'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(bool isDark) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E2A3D) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE5E7EB),
            ),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Thông tin phiên',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 18),
              _QrInfoRow(
                icon: Icons.tag,
                label: 'Mã phiên',
                value: 'BDDTEST01',
              ),
              _QrInfoRow(
                icon: Icons.access_time,
                label: 'Thời gian',
                value: '07:00 - 09:30',
              ),
              _QrInfoRow(
                icon: Icons.location_on_outlined,
                label: 'Phòng',
                value: 'B203',
              ),
              _QrInfoRow(
                icon: Icons.qr_code,
                label: 'Phương thức',
                value: 'QR',
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        Row(
          children: const [
            Expanded(
              child: _QrStatCard(
                value: '5',
                label: 'Có mặt',
                color: Color(0xFF16A34A),
                background: Color(0xFFDCFCE7),
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _QrStatCard(
                value: '2',
                label: 'Muộn',
                color: Color(0xFFD97706),
                background: Color(0xFFFEF3C7),
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _QrStatCard(
                value: '1',
                label: 'Vắng',
                color: Color(0xFFDC2626),
                background: Color(0xFFFEE2E2),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _QrPlaceholder extends StatelessWidget {
  const _QrPlaceholder();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 9,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: 81,
      itemBuilder: (context, index) {
        final black =
            index % 3 == 0 ||
            index % 7 == 0 ||
            index == 10 ||
            index == 11 ||
            index == 19 ||
            index == 60 ||
            index == 61;

        return Container(color: black ? Colors.black : Colors.transparent);
      },
    );
  }
}

class _QrInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _QrInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF1F5EA8), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _QrStatCard extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final Color background;

  const _QrStatCard({
    required this.value,
    required this.label,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
