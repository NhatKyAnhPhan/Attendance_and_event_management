import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/auth_controller.dart';
import '../../data/models/class_model.dart';
import '../../data/models/class_stats_model.dart';
import '../../data/repositories/class_repository.dart';
import '../../services/class_service.dart';
import 'widgets/class_form_dialog.dart';
import 'lecturer_class_detail_page.dart';

class LecturerClassesPage extends StatefulWidget {
  const LecturerClassesPage({super.key});

  @override
  State<LecturerClassesPage> createState() => _LecturerClassesPageState();
}

class _LecturerClassesPageState extends State<LecturerClassesPage> {
  final TextEditingController _searchController = TextEditingController();

  String _keyword = '';
  String _semester = 'Tất cả học kỳ';

  List<ClassWithStats> _classes = [];
  bool _isLoading = true;

  late final ClassService _classService;

  @override
  void initState() {
    super.initState();
    // Khởi tạo Service với Mock Repository
    _classService = ClassService(MockClassRepository());
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final auth = Get.find<AuthController>();
      final identifier = auth.currentUser.value?.email ?? '';

      // Gọi service (sau này sẽ chọc xuống REST API qua ApiClassRepository)
      final data = await _classService.getClassesForLecturer(identifier);
      if (mounted) {
        setState(() {
          _classes = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<ClassWithStats> get _filteredClasses {
    return _classes.where((item) {
      final c = item.classData;
      final text = '${c.code} ${c.name} ${c.lecturerName}'.toLowerCase();

      final matchKeyword =
          _keyword.isEmpty || text.contains(_keyword.toLowerCase());

      final matchSemester =
          _semester == 'Tất cả học kỳ' || c.semester.contains(_semester);

      return matchKeyword && matchSemester;
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Color _attendanceColor(int rate) {
    if (rate >= 85) return const Color(0xFF16A34A);
    if (rate >= 75) return const Color(0xFFD97706);
    return const Color(0xFFDC2626);
  }

  void _openDetail(ClassModel c) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => LecturerClassDetailPage(classModel: c),
      ),
    );
  }

  Future<void> _editClass(ClassModel c) async {
    final result = await showDialog<ClassModel>(
      context: context,
      builder: (ctx) => ClassFormDialog(initialClass: c),
    );
    if (result != null) {
      await _classService.updateClass(result);
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã cập nhật lớp thành công')),
        );
      }
    }
  }

  Future<void> _deleteClass(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: const Text('Bạn có chắc chắn muốn xóa lớp học này không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Xóa', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _classService.deleteClass(id);
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã xóa lớp học')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 700;

        return SingleChildScrollView(
          padding: EdgeInsets.all(isMobile ? 16 : 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTitle(isMobile),
              const SizedBox(height: 24),

              _buildFilters(context, isDark, isMobile),

              const SizedBox(height: 20),

              if (_isLoading)
                const Center(child: Padding(
                  padding: EdgeInsets.all(40.0),
                  child: CircularProgressIndicator(),
                ))
              else if (isMobile)
                _buildMobileList(isDark)
              else
                _buildDesktopTable(isDark),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTitle(bool isMobile) {
    if (isMobile) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quản lý lớp học',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 4),
          Text(
            '2 lớp học — Học kỳ 1/2026-2027',
            style: TextStyle(color: Colors.grey),
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
                'Quản lý lớp học',
                style: TextStyle(fontSize: 27, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 4),
              Text(
                '2 lớp học — Học kỳ 1/2026-2027',
                style: TextStyle(color: Colors.grey, fontSize: 15),
              ),
            ],
          ),
        ),

        ElevatedButton.icon(
          onPressed: () async {
            final result = await showDialog<ClassModel>(
              context: context,
              builder: (ctx) => const ClassFormDialog(),
            );
            if (result != null) {
              await _classService.createClass(result);
              _loadData();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã thêm lớp thành công')),
                );
              }
            }
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
            'Tạo lớp học',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildFilters(BuildContext context, bool isDark, bool isMobile) {
    final background = isDark ? const Color(0xFF1E2A3D) : Colors.white;

    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE5E7EB);

    final searchField = TextField(
      controller: _searchController,
      onChanged: (value) {
        setState(() {
          _keyword = value;
        });
      },
      decoration: InputDecoration(
        hintText: 'Tìm theo tên, mã lớp, giảng viên...',
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: isDark ? const Color(0xFF25364E) : const Color(0xFFF3F6FA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );

    final semesterDropdown = DropdownButtonFormField<String>(
      value: _semester,
      items: const [
        DropdownMenuItem(value: 'Tất cả học kỳ', child: Text('Tất cả học kỳ')),
        DropdownMenuItem(value: 'Học kỳ 1', child: Text('Học kỳ 1')),
        DropdownMenuItem(value: 'Học kỳ 2', child: Text('Học kỳ 2')),
      ],
      onChanged: (value) {
        if (value == null) return;

        setState(() {
          _semester = value;
        });
      },
      decoration: InputDecoration(
        filled: true,
        fillColor: isDark ? const Color(0xFF25364E) : const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderColor),
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: isMobile
          ? Column(
              children: [
                searchField,
                const SizedBox(height: 12),
                semesterDropdown,
              ],
            )
          : Row(
              children: [
                Expanded(flex: 3, child: searchField),
                const SizedBox(width: 14),
                SizedBox(width: 210, child: semesterDropdown),
                const SizedBox(width: 14),
                OutlinedButton.icon(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 18,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.filter_alt_outlined),
                  label: const Text('Lọc'),
                ),
              ],
            ),
    );
  }

  Widget _buildDesktopTable(bool isDark) {
    final classes = _filteredClasses;

    final background = isDark ? const Color(0xFF1E2A3D) : Colors.white;

    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE5E7EB);

    return Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            color: isDark ? const Color(0xFF25364E) : const Color(0xFFF1F5F9),
            child: const Row(
              children: [
                Expanded(flex: 2, child: Text('MÃ LỚP', style: _headerStyle)),
                Expanded(
                  flex: 4,
                  child: Text('TÊN MÔN HỌC', style: _headerStyle),
                ),
                Expanded(
                  flex: 3,
                  child: Text('GIẢNG VIÊN', style: _headerStyle),
                ),
                Expanded(
                  flex: 2,
                  child: Text('SINH VIÊN', style: _headerStyle),
                ),
                Expanded(flex: 3, child: Text('TIẾN ĐỘ', style: _headerStyle)),
                Expanded(
                  flex: 3,
                  child: Text('TỶ LỆ ĐIỂM DANH', style: _headerStyle),
                ),
                SizedBox(width: 30),
              ],
            ),
          ),

          if (classes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Text('Không tìm thấy lớp học phù hợp.'),
            ),

          ...classes.map(
            (item) => _DesktopClassRow(
              item: item,
              attendanceColor: _attendanceColor(item.stats.attendancePercentage),
              borderColor: borderColor,
              onEdit: () => _editClass(item.classData),
              onDelete: () => _deleteClass(item.classData.id),
              onTap: () => _openDetail(item.classData),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileList(bool isDark) {
    final classes = _filteredClasses;

    if (classes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Text('Không tìm thấy lớp học phù hợp.'),
        ),
      );
    }

    return Column(
      children: classes.map((item) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _MobileClassCard(
            item: item,
            attendanceColor: _attendanceColor(item.stats.attendancePercentage),
            onEdit: () => _editClass(item.classData),
            onDelete: () => _deleteClass(item.classData.id),
            onTap: () => _openDetail(item.classData),
          ),
        );
      }).toList(),
    );
  }
}

const _headerStyle = TextStyle(
  color: Colors.grey,
  fontSize: 12,
  fontWeight: FontWeight.w700,
);

class _DesktopClassRow extends StatelessWidget {
  final ClassWithStats item;
  final Color attendanceColor;
  final Color borderColor;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _DesktopClassRow({
    required this.item,
    required this.attendanceColor,
    required this.borderColor,
    required this.onEdit,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = item.classData;
    final s = item.stats;
    
    final completed = s.completed;
    final total = s.total;
    final progress = total > 0 ? completed / total : 0.0;
    final attendance = s.attendancePercentage;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: borderColor)),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                c.code,
                style: const TextStyle(
                  color: Color(0xFF1F5EA8),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),

            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    c.semester,
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            ),

            Expanded(flex: 3, child: Text(c.lecturerName)),

            Expanded(
              flex: 2,
              child: Row(
                children: [
                  const Icon(
                    Icons.people_outline,
                    size: 17,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 6),
                  Text('${c.studentCount}'),
                ],
              ),
            ),

            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.only(right: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$completed/$total buổi',
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 7),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 5,
                      borderRadius: BorderRadius.circular(8),
                      backgroundColor: const Color(0xFFE2E8F0),
                      color: const Color(0xFF1F5EA8),
                    ),
                  ],
                ),
              ),
            ),

            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: attendance / 100,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(8),
                      backgroundColor: const Color(0xFFE2E8F0),
                      color: attendanceColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '$attendance%',
                    style: TextStyle(
                      color: attendanceColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 14),

            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.grey),
              onSelected: (value) {
                if (value == 'edit') onEdit();
                if (value == 'delete') onDelete();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Text('Sửa lớp học'),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Xóa lớp học', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileClassCard extends StatelessWidget {
  final ClassWithStats item;
  final Color attendanceColor;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _MobileClassCard({
    required this.item,
    required this.attendanceColor,
    required this.onEdit,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final c = item.classData;
    final s = item.stats;

    final completed = s.completed;
    final total = s.total;
    final attendance = s.attendancePercentage;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
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
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF1FF),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    c.code,
                    style: const TextStyle(
                      color: Color(0xFF1F5EA8),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),

                const Spacer(),

                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.grey),
                  padding: EdgeInsets.zero,
                  onSelected: (value) {
                    if (value == 'edit') onEdit();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('Sửa lớp học'),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Xóa lớp', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 14),

            Text(
              c.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),

            const SizedBox(height: 5),

            Text(
              c.semester,
              style: const TextStyle(color: Colors.grey),
            ),

            const SizedBox(height: 14),

            Row(
              children: [
                const Icon(Icons.person_outline, size: 18, color: Colors.grey),
                const SizedBox(width: 6),
                Expanded(child: Text(c.lecturerName)),
              ],
            ),

            const SizedBox(height: 8),

            Row(
              children: [
                const Icon(Icons.people_outline, size: 18, color: Colors.grey),
                const SizedBox(width: 6),
                Text('${c.studentCount} sinh viên'),

                const Spacer(),

                Text(
                  '$completed/$total buổi',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),

            const SizedBox(height: 16),

            Row(
              children: [
                const Text(
                  'Tỷ lệ điểm danh',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),

                const Spacer(),

                Text(
                  '$attendance%',
                  style: TextStyle(
                    color: attendanceColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            LinearProgressIndicator(
              value: attendance / 100,
              minHeight: 7,
              borderRadius: BorderRadius.circular(10),
              backgroundColor: const Color(0xFFE2E8F0),
              color: attendanceColor,
            ),
          ],
        ),
      ),
    );
  }
}
