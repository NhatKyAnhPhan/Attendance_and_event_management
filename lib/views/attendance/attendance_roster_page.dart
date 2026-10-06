import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/api/api_client.dart';
import '../../data/api/endpoints.dart';
import '../../widgets/app_badge.dart';

class AttendanceRosterPage extends StatefulWidget {
  final String sessionId;
  final String title;

  /// Tạo trang danh sách điểm danh cho một phiên cụ thể.
  const AttendanceRosterPage({
    super.key,
    required this.sessionId,
    required this.title,
  });

  /// Tạo state quản lý danh sách và thao tác điểm danh thủ công.
  @override
  State<AttendanceRosterPage> createState() => _AttendanceRosterPageState();
}

class _AttendanceRosterPageState extends State<AttendanceRosterPage> {
  final _client = ApiClient();
  final _searchController = TextEditingController();
  Timer? _refreshTimer;
  List<Map<String, dynamic>> _students = [];
  Map<String, dynamic>? _session;
  bool _loading = true;
  bool _saving = false;
  bool _requestInProgress = false;
  String? _error;
  String _query = '';

  /// Tải danh sách lần đầu và bắt đầu đồng bộ định kỳ với máy chủ.
  @override
  void initState() {
    super.initState();
    _loadRoster();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _loadRoster(silent: true),
    );
  }

  /// Dừng đồng bộ và giải phóng bộ điều khiển khi rời trang.
  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Tải lại trạng thái sinh viên và thông tin phiên từ API.
  Future<void> _loadRoster({bool silent = false}) async {
    if (_requestInProgress) return;
    _requestInProgress = true;
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final response = await _client.get(
        ApiEndpoints.attendanceSessionStudents(widget.sessionId),
      );
      final items = response['items'];
      if (!mounted) return;
      final session = Map<String, dynamic>.from(response['session'] as Map);
      setState(() {
        _session = session;
        _students = items is List
            ? items.whereType<Map>().map(Map<String, dynamic>.from).toList()
            : <Map<String, dynamic>>[];
        _loading = false;
        _error = null;
      });
      if (session['canEdit'] != true) _refreshTimer?.cancel();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    } finally {
      _requestInProgress = false;
    }
  }

  /// Lưu trạng thái thủ công của sinh viên rồi làm mới danh sách.
  Future<void> _setStatus(
    Map<String, dynamic> student,
    String status,
  ) async {
    final studentId = student['studentId']?.toString() ?? '';
    if (_saving || studentId.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _client.post(
        '${ApiEndpoints.attendanceSessionStudents(widget.sessionId)}/${Uri.encodeComponent(studentId)}',
        data: {'status': status},
      );
      await _loadRoster();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã cập nhật điểm danh thủ công.')),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Mở lựa chọn trạng thái điểm danh cho sinh viên đã chọn.
  Future<void> _showStatusPicker(Map<String, dynamic> student) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                'Chọn trạng thái điểm danh',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Có mặt'),
              onTap: () => Navigator.pop(context, 'present'),
            ),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Đi trễ'),
              onTap: () => Navigator.pop(context, 'late'),
            ),
            ListTile(
              leading: const Icon(Icons.cancel_outlined),
              title: const Text('Vắng mặt'),
              onTap: () => Navigator.pop(context, 'absent'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (result != null) await _setStatus(student, result);
  }

  /// Đếm số sinh viên có một trạng thái điểm danh cụ thể.
  static int _count(List<Map<String, dynamic>> students, String status) =>
      students
          .where(
            (student) =>
                (student['attendanceStatus']?.toString() ?? '') == status,
          )
          .length;

  /// Ánh xạ trạng thái từ API sang màu badge của giao diện.
  static BadgeStatus _badgeStatus(String? status) {
    switch (status) {
      case 'Có mặt':
        return BadgeStatus.present;
      case 'Đi trễ':
        return BadgeStatus.late;
      case 'Vắng mặt':
        return BadgeStatus.absent;
      default:
        return BadgeStatus.pending;
    }
  }

  /// Hiển thị danh sách, bộ lọc, trạng thái cập nhật và thao tác thủ công.
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(Theme.of(context).brightness == Brightness.dark);
    final filteredStudents = _students.where((student) {
      final query = _query.trim().toLowerCase();
      return query.isEmpty ||
          '${student['studentName']} ${student['studentId']} ${student['email']}'
              .toLowerCase()
              .contains(query);
    }).toList();
    final canEdit = _session?['canEdit'] == true;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Làm mới danh sách',
            onPressed: _loading ? null : _loadRoster,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading && _session == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadRoster,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  if (_session != null) ...[
                    Text(
                      _session!['sessionName']?.toString().isNotEmpty == true
                          ? _session!['sessionName'].toString()
                          : widget.title,
                      style: AppTextStyles.displaySm(c.foreground),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_session!['classId'] ?? ''} · ${_session!['className'] ?? ''}',
                      style: AppTextStyles.bodySm(c.mutedForeground),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _CountChip(
                          label: 'Có mặt',
                          count: _count(_students, 'Có mặt'),
                          status: BadgeStatus.present,
                        ),
                        _CountChip(
                          label: 'Đi trễ',
                          count: _count(_students, 'Đi trễ'),
                          status: BadgeStatus.late,
                        ),
                        _CountChip(
                          label: 'Vắng mặt',
                          count: _count(_students, 'Vắng mặt'),
                          status: BadgeStatus.absent,
                        ),
                        _CountChip(
                          label: 'Chưa ghi nhận',
                          count: _count(_students, ''),
                          status: BadgeStatus.pending,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          canEdit ? Icons.sync : Icons.lock_outline,
                          size: 16,
                          color: canEdit ? c.success : c.mutedForeground,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            canEdit
                                ? 'Tự cập nhật mỗi 3 giây · Phiên đang mở'
                                : 'Phiên đã đóng · Chỉ xem danh sách',
                            style: AppTextStyles.bodyXs(c.mutedForeground),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: c.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(color: c.danger),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Tìm tên hoặc mã sinh viên',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                              icon: const Icon(Icons.close),
                            ),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                  const SizedBox(height: 12),
                  if (_loading && _session != null)
                    const LinearProgressIndicator(),
                  if (filteredStudents.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 36),
                      child: Center(
                        child: Text(
                          _students.isEmpty
                              ? 'Lớp chưa có sinh viên trong danh sách.'
                              : 'Không tìm thấy sinh viên phù hợp.',
                          style: AppTextStyles.bodySm(c.mutedForeground),
                        ),
                      ),
                    )
                  else
                    ...filteredStudents.map((student) {
                      final status =
                          student['attendanceStatus']?.toString() ?? '';
                      final name =
                          student['studentName']?.toString().trim() ?? '';
                      final checkedInAt = DateTime.tryParse(
                        student['checkedInAt']?.toString() ?? '',
                      );
                      final subtitle = [
                        student['studentId']?.toString() ?? '',
                        if (checkedInAt != null)
                          DateFormat('HH:mm:ss').format(checkedInAt.toLocal()),
                      ].where((value) => value.isNotEmpty).join(' · ');
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                child: Text(
                                  name.isEmpty
                                      ? '?'
                                      : name.characters.first.toUpperCase(),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name.isEmpty ? 'Sinh viên' : name,
                                      style: AppTextStyles.bodyMd(c.foreground),
                                    ),
                                    Text(
                                      subtitle,
                                      style: AppTextStyles.bodyXs(
                                        c.mutedForeground,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (status.isEmpty)
                                const AppBadge(
                                  label: 'Chưa điểm danh',
                                  status: BadgeStatus.pending,
                                )
                              else
                                AppBadge(
                                  label: status,
                                  status: _badgeStatus(status),
                                ),
                              if (canEdit) ...[
                                const SizedBox(width: 4),
                                IconButton(
                                  tooltip: status.isEmpty
                                      ? 'Điểm danh thủ công'
                                      : 'Điều chỉnh trạng thái',
                                  onPressed: _saving
                                      ? null
                                      : () => _showStatusPicker(student),
                                  icon: const Icon(Icons.edit_note),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final String label;
  final int count;
  final BadgeStatus status;

  /// Tạo nhãn tóm tắt cho một nhóm trạng thái điểm danh.
  const _CountChip({
    required this.label,
    required this.count,
    required this.status,
  });

  /// Hiển thị số lượng sinh viên theo trạng thái.
  @override
  Widget build(BuildContext context) {
    return AppBadge(label: '$label: $count', status: status);
  }
}
