import 'package:flutter/material.dart';
import '../../data/models/class_model.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/student_repository.dart';
import '../../services/student_service.dart';

class LecturerClassDetailPage extends StatefulWidget {
  final ClassModel classModel;

  const LecturerClassDetailPage({super.key, required this.classModel});

  @override
  State<LecturerClassDetailPage> createState() => _LecturerClassDetailPageState();
}

class _LecturerClassDetailPageState extends State<LecturerClassDetailPage> {
  final TextEditingController _searchController = TextEditingController();
  String _keyword = '';
  List<UserModel> _students = [];
  bool _isLoading = true;

  late final StudentService _studentService;

  @override
  void initState() {
    super.initState();
    _studentService = StudentService(MockStudentRepository());
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final data = await _studentService.getStudentsByClass(widget.classModel.id);
      if (mounted) {
        setState(() {
          _students = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<UserModel> get _filteredStudents {
    if (_keyword.isEmpty) return _students;
    return _students.where((s) {
      final text = '${s.code} ${s.name} ${s.email}'.toLowerCase();
      return text.contains(_keyword.toLowerCase());
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.classModel;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chi tiết lớp học'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${c.code} - ${c.name}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Học kỳ: ${c.semester}'),
            Text('Loại: ${c.type.label}'),
            Text('Phòng: ${c.room}'),
            Text('Lịch học: ${c.schedule}'),
            const SizedBox(height: 16),
            const Text(
              'Danh sách sinh viên',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Tìm sinh viên...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (val) => setState(() => _keyword = val),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredStudents.isEmpty
                      ? const Center(child: Text('Không có sinh viên nào'))
                      : ListView.builder(
                          itemCount: _filteredStudents.length,
                          itemBuilder: (ctx, i) {
                            final s = _filteredStudents[i];
                            return ListTile(
                              leading: CircleAvatar(child: Text(s.name[0])),
                              title: Text(s.name),
                              subtitle: Text('${s.code} - ${s.email}'),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
