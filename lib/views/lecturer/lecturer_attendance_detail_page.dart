import 'package:flutter/material.dart';

class LecturerAttendanceDetailPage extends StatefulWidget {
  const LecturerAttendanceDetailPage({super.key});

  @override
  State<LecturerAttendanceDetailPage> createState() =>
      _LecturerAttendanceDetailPageState();
}

class _LecturerAttendanceDetailPageState
    extends State<LecturerAttendanceDetailPage> {
  String _filter = 'Tất cả';

  final List<Map<String, dynamic>> _students = [
    {
      'id': 'SVTEST01',
      'name': 'Phạm Thanh Tâm',
      'time': '06:58',
      'method': 'QR',
      'status': 'Có mặt',
    },
    {
      'id': 'SVTEST02',
      'name': 'Nguyễn Quốc An',
      'time': '07:01',
      'method': 'QR',
      'status': 'Có mặt',
    },
    {
      'id': 'SVTEST03',
      'name': 'Lê Minh Tuấn',
      'time': '07:04',
      'method': 'QR',
      'status': 'Có mặt',
    },
    {
      'id': 'SVTEST04',
      'name': 'Trần Ngọc Bích',
      'time': '07:18',
      'method': 'QR',
      'status': 'Muộn',
    },
    {
      'id': 'SVTEST05',
      'name': 'Võ Gia Hưng',
      'time': '--',
      'method': '--',
      'status': 'Vắng',
    },
    {
      'id': 'SVTEST06',
      'name': 'Nguyễn Minh Anh',
      'time': '07:03',
      'method': 'QR',
      'status': 'Có mặt',
    },
    {
      'id': 'SVTEST07',
      'name': 'Đặng Quốc Bảo',
      'time': '07:19',
      'method': 'QR',
      'status': 'Muộn',
    },
    {
      'id': 'SVTEST08',
      'name': 'Phan Hoàng Duy',
      'time': '07:00',
      'method': 'QR',
      'status': 'Có mặt',
    },
  ];

  List<Map<String, dynamic>> get _filteredStudents {
    if (_filter == 'Tất cả') {
      return _students;
    }

    return _students.where((student) => student['status'] == _filter).toList();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Có mặt':
        return const Color(0xFF16A34A);
      case 'Muộn':
        return const Color(0xFFD97706);
      default:
        return const Color(0xFFDC2626);
    }
  }

  Color _statusBackground(String status) {
    switch (status) {
      case 'Có mặt':
        return const Color(0xFFDCFCE7);
      case 'Muộn':
        return const Color(0xFFFEF3C7);
      default:
        return const Color(0xFFFEE2E2);
    }
  }

  void _changeStatus(Map<String, dynamic> student, String newStatus) {
    setState(() {
      student['status'] = newStatus;

      if (newStatus == 'Vắng') {
        student['time'] = '--';
        student['method'] = '--';
      } else if (student['time'] == '--') {
        student['time'] = '07:05';
        student['method'] = 'Thủ công';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF111827)
          : const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('Chi tiết điểm danh'),
        backgroundColor: isDark ? const Color(0xFF1E2A3D) : Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 760;

          return SingleChildScrollView(
            padding: EdgeInsets.all(isMobile ? 16 : 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context, isMobile),
                const SizedBox(height: 22),

                _buildStats(isMobile),
                const SizedBox(height: 22),

                _buildFilters(),
                const SizedBox(height: 18),

                if (isMobile)
                  _buildMobileList()
                else
                  _buildDesktopTable(isDark),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isMobile) {
    final info = const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'LHPTEST01 — Kiểm thử phần mềm',
          style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 5),
        Text(
          'Buổi 1 · 24/09/2026 · 07:00 - 09:30 · Phòng B203',
          style: TextStyle(color: Colors.grey),
        ),
      ],
    );

    final actions = Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.qr_code_2),
          label: const Text('Xem QR'),
        ),
        FilledButton.icon(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Phiên điểm danh đã được đóng thử.'),
              ),
            );
          },
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFDC2626),
          ),
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('Đóng điểm danh'),
        ),
        ElevatedButton.icon(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Đã xác nhận kết quả thử nghiệm.')),
            );
          },
          icon: const Icon(Icons.verified_outlined),
          label: const Text('Xác nhận kết quả'),
        ),
      ],
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [info, const SizedBox(height: 16), actions],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: info),
        actions,
      ],
    );
  }

  Widget _buildStats(bool isMobile) {
    final present = _students.where((e) => e['status'] == 'Có mặt').length;

    final late = _students.where((e) => e['status'] == 'Muộn').length;

    final absent = _students.where((e) => e['status'] == 'Vắng').length;

    final stats = [
      _AttendanceStatData(
        label: 'Tổng sinh viên',
        value: '${_students.length}',
        color: const Color(0xFF1F5EA8),
        background: const Color(0xFFEAF1FF),
      ),
      _AttendanceStatData(
        label: 'Có mặt',
        value: '$present',
        color: const Color(0xFF16A34A),
        background: const Color(0xFFDCFCE7),
      ),
      _AttendanceStatData(
        label: 'Muộn',
        value: '$late',
        color: const Color(0xFFD97706),
        background: const Color(0xFFFEF3C7),
      ),
      _AttendanceStatData(
        label: 'Vắng',
        value: '$absent',
        color: const Color(0xFFDC2626),
        background: const Color(0xFFFEE2E2),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: stats.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isMobile ? 2 : 4,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: isMobile ? 1.7 : 2.2,
      ),
      itemBuilder: (context, index) {
        final stat = stats[index];

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: stat.background,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                stat.value,
                style: TextStyle(
                  color: stat.color,
                  fontSize: 27,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                stat.label,
                style: TextStyle(
                  color: stat.color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilters() {
    const filters = ['Tất cả', 'Có mặt', 'Muộn', 'Vắng'];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: filters.map((item) {
        final selected = _filter == item;

        return ChoiceChip(
          selected: selected,
          label: Text(item),
          onSelected: (_) {
            setState(() {
              _filter = item;
            });
          },
        );
      }).toList(),
    );
  }

  Widget _buildDesktopTable(bool isDark) {
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE5E7EB);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2A3D) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            color: isDark ? const Color(0xFF25364E) : const Color(0xFFF1F5F9),
            child: const Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text('MÃ SV', style: _tableHeaderStyle),
                ),
                Expanded(
                  flex: 4,
                  child: Text('HỌ TÊN', style: _tableHeaderStyle),
                ),
                Expanded(
                  flex: 2,
                  child: Text('GIỜ VÀO', style: _tableHeaderStyle),
                ),
                Expanded(
                  flex: 2,
                  child: Text('PHƯƠNG THỨC', style: _tableHeaderStyle),
                ),
                Expanded(
                  flex: 2,
                  child: Text('TRẠNG THÁI', style: _tableHeaderStyle),
                ),
                Expanded(
                  flex: 2,
                  child: Text('ĐIỀU CHỈNH', style: _tableHeaderStyle),
                ),
              ],
            ),
          ),

          ..._filteredStudents.map(
            (student) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: borderColor)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      student['id'],
                      style: const TextStyle(
                        color: Color(0xFF1F5EA8),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: Text(
                      student['name'],
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Expanded(flex: 2, child: Text(student['time'])),
                  Expanded(flex: 2, child: Text(student['method'])),
                  Expanded(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _StatusBadge(
                        text: student['status'],
                        color: _statusColor(student['status']),
                        background: _statusBackground(student['status']),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: DropdownButton<String>(
                      value: student['status'],
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(
                          value: 'Có mặt',
                          child: Text('Có mặt'),
                        ),
                        DropdownMenuItem(value: 'Muộn', child: Text('Muộn')),
                        DropdownMenuItem(value: 'Vắng', child: Text('Vắng')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          _changeStatus(student, value);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileList() {
    return Column(
      children: _filteredStudents.map((student) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          student['name'],
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      _StatusBadge(
                        text: student['status'],
                        color: _statusColor(student['status']),
                        background: _statusBackground(student['status']),
                      ),
                    ],
                  ),

                  const SizedBox(height: 5),

                  Text(
                    student['id'],
                    style: const TextStyle(
                      color: Color(0xFF1F5EA8),
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text('Giờ vào: ${student['time']}'),
                  const SizedBox(height: 4),
                  Text('Phương thức: ${student['method']}'),

                  const SizedBox(height: 12),

                  DropdownButtonFormField<String>(
                    value: student['status'],
                    decoration: const InputDecoration(
                      labelText: 'Điều chỉnh trạng thái',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Có mặt', child: Text('Có mặt')),
                      DropdownMenuItem(value: 'Muộn', child: Text('Muộn')),
                      DropdownMenuItem(value: 'Vắng', child: Text('Vắng')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        _changeStatus(student, value);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _AttendanceStatData {
  final String label;
  final String value;
  final Color color;
  final Color background;

  const _AttendanceStatData({
    required this.label,
    required this.value,
    required this.color,
    required this.background,
  });
}

class _StatusBadge extends StatelessWidget {
  final String text;
  final Color color;
  final Color background;

  const _StatusBadge({
    required this.text,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

const _tableHeaderStyle = TextStyle(
  color: Colors.grey,
  fontSize: 12,
  fontWeight: FontWeight.w700,
);
