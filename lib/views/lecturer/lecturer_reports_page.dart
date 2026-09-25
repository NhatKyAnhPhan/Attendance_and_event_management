import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/repositories/class_repository.dart';
import '../../services/class_service.dart';
import '../../data/repositories/report_repository.dart';
import '../../services/report_service.dart';
import '../../data/models/class_model.dart';
import '../../data/models/report_model.dart';
import '../../controllers/auth_controller.dart';
import 'package:get/get.dart';

class LecturerReportsPage extends StatefulWidget {
  const LecturerReportsPage({super.key});

  @override
  State<LecturerReportsPage> createState() => _LecturerReportsPageState();
}

class _LecturerReportsPageState extends State<LecturerReportsPage> {
  String _selectedClassId = 'all';
  String _dateFilter = 'month'; // 'today', '7days', 'month', 'custom'
  DateTime? _startDate;
  DateTime? _endDate;

  bool _isLoading = true;
  List<ClassModel> _classes = [];
  ReportSummary? _summary;

  late final ClassService _classService;
  late final ReportService _reportService;

  @override
  void initState() {
    super.initState();
    _classService = ClassService(MockClassRepository());
    _reportService = ReportService(MockReportRepository());
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final user = Get.find<AuthController>().currentUser.value;
      if (user != null) {
        final classes = await _classService.getClassesForLecturer(user.email);
        _classes = classes.map((e) => e.classData).toList();
      }

      await _fetchReport();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchReport() async {
    final filter = ReportFilter(
      classId: _selectedClassId,
      dateFilter: _dateFilter,
      startDate: _startDate,
      endDate: _endDate,
    );
    final summary = await _reportService.getReportSummary(filter);
    setState(() {
      _summary = summary;
    });
  }

  void _applyFilter() {
    setState(() {
      _isLoading = true;
    });
    _fetchReport().then((_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  void _resetFilter() {
    setState(() {
      _selectedClassId = 'all';
      _dateFilter = 'month';
      _startDate = null;
      _endDate = null;
      _isLoading = true;
    });
    _fetchReport().then((_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );
    if (range != null) {
      setState(() {
        _dateFilter = 'custom';
        _startDate = range.start;
        _endDate = range.end;
      });
    } else {
      if (_startDate == null) setState(() => _dateFilter = 'month');
    }
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    
    final selectedMonth = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chọn tháng'),
        content: SizedBox(
          width: 300,
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: 12,
            itemBuilder: (c, i) => InkWell(
              onTap: () => Navigator.pop(c, i + 1),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Tháng ${i + 1}'),
              ),
            ),
          ),
        ),
      ),
    );

    if (selectedMonth != null) {
      setState(() {
        _dateFilter = 'select_month';
        _startDate = DateTime(now.year, selectedMonth, 1);
        _endDate = DateTime(now.year, selectedMonth + 1, 0); // last day of month
      });
    } else {
      if (_startDate == null) setState(() => _dateFilter = 'month');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 760;

        return SingleChildScrollView(
          padding: EdgeInsets.all(isMobile ? 16 : 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, isMobile),
              const SizedBox(height: 22),

              _buildFilters(isDark, isMobile),
              const SizedBox(height: 22),

              if (_isLoading)
                const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
              else if (_summary != null) ...[
                _buildStats(isMobile),
                const SizedBox(height: 22),

                if (isMobile)
                  Column(
                    children: [
                      _buildWeeklyChart(isDark),
                      const SizedBox(height: 18),
                      _buildStatusChart(isDark),
                    ],
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: _buildWeeklyChart(isDark)),
                      const SizedBox(width: 18),
                      Expanded(flex: 2, child: _buildStatusChart(isDark)),
                    ],
                  ),

                const SizedBox(height: 22),

                _buildClassReport(isDark, isMobile),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, bool isMobile) {
    final title = const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Báo cáo điểm danh',
          style: TextStyle(fontSize: 27, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 5),
        Text(
          'Theo dõi và thống kê tình hình tham gia học tập',
          style: TextStyle(color: Colors.grey),
        ),
      ],
    );

    final exportButton = ElevatedButton.icon(
      onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chức năng xuất báo cáo sẽ kết nối sau.')),
        );
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF1F5EA8),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
      icon: const Icon(Icons.download_outlined),
      label: const Text('Xuất báo cáo'),
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: exportButton),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: title),
        exportButton,
      ],
    );
  }

  Widget _buildFilters(bool isDark, bool isMobile) {
    final background = isDark ? const Color(0xFF1E2A3D) : Colors.white;

    final classDropdown = DropdownButtonFormField<String>(
      value: _selectedClassId,
      decoration: const InputDecoration(
        labelText: 'Lớp học',
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: [
        const DropdownMenuItem(value: 'all', child: Text('Tất cả lớp')),
        ..._classes.map((c) => DropdownMenuItem(
              value: c.id,
              child: Text('${c.code} - ${c.name}'),
            )),
      ],
      onChanged: (value) {
        if (value != null) {
          setState(() {
            _selectedClassId = value;
          });
        }
      },
    );

    final dateDropdown = DropdownButtonFormField<String>(
      value: _dateFilter,
      decoration: const InputDecoration(
        labelText: 'Thời gian',
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: const [
        DropdownMenuItem(value: 'today', child: Text('Hôm nay')),
        DropdownMenuItem(value: '7days', child: Text('7 ngày gần nhất')),
        DropdownMenuItem(value: 'month', child: Text('Tháng này')),
        DropdownMenuItem(value: 'select_month', child: Text('Chọn tháng')),
        DropdownMenuItem(value: 'custom', child: Text('Khoảng ngày tùy chọn')),
      ],
      onChanged: (value) {
        if (value != null) {
          if (value == 'custom') {
            _pickDateRange();
          } else if (value == 'select_month') {
            _pickMonth();
          } else {
            setState(() {
              _dateFilter = value;
              _startDate = null;
              _endDate = null;
            });
          }
        }
      },
    );

    String dateText = '';
    if ((_dateFilter == 'custom' || _dateFilter == 'select_month') && _startDate != null && _endDate != null) {
      dateText = '${DateFormat('dd/MM/yyyy').format(_startDate!)} - ${DateFormat('dd/MM/yyyy').format(_endDate!)}';
    } else {
      dateText = 'Mặc định';
    }

    final dateField = InkWell(
      onTap: _dateFilter == 'select_month' ? _pickMonth : _pickDateRange,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Khoảng thời gian',
          prefixIcon: Icon(Icons.date_range_outlined),
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        child: Text(dateText),
      ),
    );

    final actions = Row(
      mainAxisAlignment: isMobile ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        TextButton(
          onPressed: _resetFilter,
          child: const Text('Đặt lại'),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: _applyFilter,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1F5EA8),
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.filter_list, size: 18),
          label: const Text('Lọc / Áp dụng'),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE5E7EB),
        ),
      ),
      child: isMobile
          ? Column(
              children: [
                classDropdown,
                const SizedBox(height: 12),
                dateDropdown,
                const SizedBox(height: 12),
                if (_dateFilter == 'custom' || _dateFilter == 'select_month') ...[
                  dateField,
                  const SizedBox(height: 12),
                ],
                actions,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: classDropdown),
                const SizedBox(width: 12),
                Expanded(child: dateDropdown),
                const SizedBox(width: 12),
                if (_dateFilter == 'custom' || _dateFilter == 'select_month') Expanded(child: dateField),
                if (_dateFilter == 'custom' || _dateFilter == 'select_month') const SizedBox(width: 12),
                actions,
              ],
            ),
    );
  }

  Widget _buildStats(bool isMobile) {
    final s = _summary!;
    final stats = [
      _ReportStat(
        title: 'Tổng sinh viên',
        value: '${s.totalStudents}',
        icon: Icons.groups_outlined,
        color: const Color(0xFF1F5EA8),
        background: const Color(0xFFEAF1FF),
      ),
      _ReportStat(
        title: 'Tỷ lệ có mặt',
        value: '${s.presentRate}%',
        icon: Icons.check_circle_outline,
        color: const Color(0xFF16A34A),
        background: const Color(0xFFDCFCE7),
      ),
      _ReportStat(
        title: 'Đi muộn',
        value: '${s.lateRate}%',
        icon: Icons.schedule,
        color: const Color(0xFFD97706),
        background: const Color(0xFFFEF3C7),
      ),
      _ReportStat(
        title: 'Vắng',
        value: '${s.absentRate}%',
        icon: Icons.cancel_outlined,
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
        childAspectRatio: isMobile ? 1.4 : 1.8,
      ),
      itemBuilder: (context, index) {
        final stat = stats[index];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: stat.background,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(stat.icon, color: stat.color, size: 28),
              const SizedBox(height: 8),
              Text(
                stat.value,
                style: TextStyle(
                  color: stat.color,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                stat.title,
                textAlign: TextAlign.center,
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

  Widget _buildWeeklyChart(bool isDark) {
    final values = _summary!.weeklyAttendance;
    const labels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

    return _ReportPanel(
      isDark: isDark,
      title: 'Tỷ lệ điểm danh theo tuần',
      child: SizedBox(
        height: 240,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(
            values.length,
            (index) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '${(values[index] * 100).round()}%',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: values[index],
                          widthFactor: 0.55,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF1F5EA8),
                              borderRadius: BorderRadius.circular(7),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(labels[index], style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChart(bool isDark) {
    final s = _summary!;
    return _ReportPanel(
      isDark: isDark,
      title: 'Tổng quan trạng thái',
      child: Column(
        children: [
          const SizedBox(height: 8),
          SizedBox(
            width: 165,
            height: 165,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: s.presentRate / 100.0,
                  strokeWidth: 24,
                  backgroundColor: const Color(0xFFE5E7EB),
                  color: const Color(0xFF16A34A),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${s.presentRate}%',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Text('Có mặt', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _Legend(color: const Color(0xFF16A34A), text: 'Có mặt', value: '${s.presentRate}%'),
          _Legend(color: const Color(0xFFD97706), text: 'Muộn', value: '${s.lateRate}%'),
          _Legend(color: const Color(0xFFDC2626), text: 'Vắng', value: '${s.absentRate}%'),
        ],
      ),
    );
  }

  Widget _buildClassReport(bool isDark, bool isMobile) {
    final data = _summary!.classReports;

    return _ReportPanel(
      isDark: isDark,
      title: 'Chi tiết theo lớp',
      child: isMobile
          ? Column(
              children: data.map((item) {
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF25364E)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['name']!,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item['code']!,
                        style: const TextStyle(color: Color(0xFF1F5EA8)),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${item['students']} sinh viên',
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Có mặt: ${item['present']} | Vắng: ${item['absent']} | Muộn: ${item['late']}',
                        style: const TextStyle(
                          color: Color(0xFF16A34A),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            )
          : Column(
              children: [
                const Row(
                  children: [
                    Expanded(flex: 2, child: Text('MÃ LỚP', style: _reportHeaderStyle)),
                    Expanded(flex: 3, child: Text('MÔN HỌC', style: _reportHeaderStyle)),
                    Expanded(flex: 2, child: Text('SĨ SỐ', style: _reportHeaderStyle)),
                    Expanded(flex: 2, child: Text('CÓ MẶT', style: _reportHeaderStyle)),
                    Expanded(flex: 2, child: Text('VẮNG', style: _reportHeaderStyle)),
                    Expanded(flex: 2, child: Text('MUỘN', style: _reportHeaderStyle)),
                  ],
                ),
                const Divider(height: 28),
                ...data.map(
                  (item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            item['code'].toString(),
                            style: const TextStyle(
                              color: Color(0xFF1F5EA8),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Expanded(flex: 3, child: Text(item['name'].toString())),
                        Expanded(flex: 2, child: Text(item['students'].toString())),
                        Expanded(flex: 2, child: Text(item['present'].toString(), style: const TextStyle(color: Color(0xFF16A34A)))),
                        Expanded(flex: 2, child: Text(item['absent'].toString(), style: const TextStyle(color: Color(0xFFDC2626)))),
                        Expanded(flex: 2, child: Text(item['late'].toString(), style: const TextStyle(color: Color(0xFFD97706)))),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _ReportStat {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final Color background;

  const _ReportStat({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.background,
  });
}

class _ReportPanel extends StatelessWidget {
  final bool isDark;
  final String title;
  final Widget child;

  const _ReportPanel({
    required this.isDark,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String text;
  final String value;

  const _Legend({required this.color, required this.text, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 9),
          Expanded(child: Text(text)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

const _reportHeaderStyle = TextStyle(
  color: Colors.grey,
  fontSize: 12,
  fontWeight: FontWeight.w700,
);
