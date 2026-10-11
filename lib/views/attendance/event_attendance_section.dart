import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/api/api_client.dart';

class EventAttendanceSection extends StatefulWidget {
  const EventAttendanceSection({super.key});

  @override
  EventAttendanceSectionState createState() => EventAttendanceSectionState();
}

class EventAttendanceSectionState extends State<EventAttendanceSection> {
  final ApiClient _client = ApiClient();
  final TextEditingController _searchController = TextEditingController();
  Timer? _refreshTimer;
  List<Map<String, dynamic>> _events = [];
  bool _loading = true;
  bool _requestInProgress = false;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    load();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => load(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> load({bool silent = false}) async {
    if (_requestInProgress) return;
    _requestInProgress = true;
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final response = await _client.get('/api/organizer/events');
      final items = response['items'];
      if (items is! List) {
        throw const ApiException('Danh sách sự kiện trả về không hợp lệ.');
      }
      if (!mounted) return;
      setState(() {
        _events = items
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList();
        _loading = false;
        _error = null;
      });
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

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(
      Theme.of(context).brightness == Brightness.dark,
    );
    final query = _query.trim().toLowerCase();
    final events = _events.where((event) {
      final searchable = [
        event['id'],
        event['name'],
        event['location'],
      ].join(' ').toLowerCase();
      return query.isEmpty || searchable.contains(query);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Điểm danh sự kiện',
                style: AppTextStyles.displaySm(colors.foreground),
              ),
            ),
            IconButton(
              tooltip: 'Làm mới danh sách sự kiện',
              onPressed: _loading ? null : load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        Text(
          'Chọn sự kiện để xem danh sách đăng ký và trạng thái quét QR.',
          style: AppTextStyles.bodySm(colors.mutedForeground),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _searchController,
          onChanged: (value) => setState(() => _query = value),
          decoration: InputDecoration(
            hintText: 'Tìm tên hoặc mã sự kiện',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Xóa nội dung tìm kiếm',
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                    icon: const Icon(Icons.close),
                  ),
            border: const OutlineInputBorder(),
          ),
        ),
        if (_loading && _events.isEmpty) ...[
          const SizedBox(height: 24),
          const Center(child: CircularProgressIndicator()),
        ] else if (_error != null) ...[
          const SizedBox(height: 16),
          _MessageCard(message: _error!, colors: colors, isError: true),
        ] else if (events.isEmpty) ...[
          const SizedBox(height: 16),
          _MessageCard(
            message: _events.isEmpty
                ? 'Đơn vị của bạn chưa có sự kiện.'
                : 'Không tìm thấy sự kiện phù hợp.',
            colors: colors,
          ),
        ] else ...[
          if (_loading) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 12),
          ...events.map(
            (event) => _EventAttendanceCard(
              event: event,
              colors: colors,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _EventAttendanceRosterPage(event: event),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _EventAttendanceCard extends StatelessWidget {
  const _EventAttendanceCard({
    required this.event,
    required this.colors,
    required this.onTap,
  });

  final Map<String, dynamic> event;
  final AppColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final startTime = _parseDate(event['startTime']);
    final details = [
      event['id']?.toString() ?? '',
      if (startTime != null)
        DateFormat('dd/MM/yyyy HH:mm').format(startTime.toLocal()),
      event['location']?.toString() ?? '',
    ].where((item) => item.isNotEmpty).join(' · ');
    final registeredCount = _count(event['registeredCount']);
    final checkedInCount = _count(event['checkedInCount']);

    return Card(
      color: colors.card,
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppColors.radius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.event_available_outlined, color: colors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      event['name']?.toString().trim().isNotEmpty == true
                          ? event['name'].toString()
                          : 'Sự kiện',
                      style: AppTextStyles.displaySm(colors.foreground),
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 6),
              Text(details, style: AppTextStyles.bodySm(colors.mutedForeground)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _CountPill(
                    label: 'Đã đăng ký',
                    count: registeredCount,
                    color: colors.primary,
                  ),
                  _CountPill(
                    label: 'Đã điểm danh QR',
                    count: checkedInCount,
                    color: colors.success,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventAttendanceRosterPage extends StatefulWidget {
  const _EventAttendanceRosterPage({required this.event});

  final Map<String, dynamic> event;

  @override
  State<_EventAttendanceRosterPage> createState() =>
      _EventAttendanceRosterPageState();
}

class _EventAttendanceRosterPageState
    extends State<_EventAttendanceRosterPage> {
  final ApiClient _client = ApiClient();
  final TextEditingController _searchController = TextEditingController();
  Timer? _refreshTimer;
  List<Map<String, dynamic>> _students = [];
  bool _loading = true;
  bool _requestInProgress = false;
  String? _error;
  String _query = '';

  String get _eventId => widget.event['id']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    _loadStudents();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _loadStudents(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadStudents({bool silent = false}) async {
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
        '/api/organizer/events/${Uri.encodeComponent(_eventId)}/students',
      );
      final items = response['items'];
      if (items is! List) {
        throw const ApiException('Danh sách điểm danh trả về không hợp lệ.');
      }
      if (!mounted) return;
      setState(() {
        _students = items
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList();
        _loading = false;
        _error = null;
      });
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

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(
      Theme.of(context).brightness == Brightness.dark,
    );
    final query = _query.trim().toLowerCase();
    final students = _students.where((student) {
      final searchable = [
        student['studentName'],
        student['studentId'],
        student['email'],
      ].join(' ').toLowerCase();
      return query.isEmpty || searchable.contains(query);
    }).toList();
    final checkedIn = _students
        .where((student) => student['attendanceStatus'] == 'Đã điểm danh QR')
        .length;
    final eventName = widget.event['name']?.toString() ?? 'Sự kiện';

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(eventName),
        actions: [
          IconButton(
            tooltip: 'Làm mới danh sách',
            onPressed: _loading ? null : _loadStudents,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadStudents,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '${_students.length} sinh viên đăng ký · $checkedIn đã điểm danh QR',
              style: AppTextStyles.bodySm(colors.mutedForeground),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Tìm tên hoặc mã sinh viên',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Xóa nội dung tìm kiếm',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
            if (_loading && _students.isEmpty) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
            ] else if (_error != null) ...[
              const SizedBox(height: 16),
              _MessageCard(message: _error!, colors: colors, isError: true),
            ] else if (students.isEmpty) ...[
              const SizedBox(height: 16),
              _MessageCard(
                message: _students.isEmpty
                    ? 'Sự kiện chưa có sinh viên đăng ký.'
                    : 'Không tìm thấy sinh viên phù hợp.',
                colors: colors,
              ),
            ] else ...[
              if (_loading) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
              ],
              const SizedBox(height: 12),
              ...students.map((student) {
                final name = student['studentName']?.toString().trim() ?? '';
                final studentId = student['studentId']?.toString() ?? '';
                final checkedAt = _parseDate(student['checkedInAt']);
                final isCheckedIn =
                    student['attendanceStatus'] == 'Đã điểm danh QR';
                final subtitle = [
                  studentId,
                  if (checkedAt != null)
                    'Quét lúc ${DateFormat('dd/MM/yyyy HH:mm').format(checkedAt.toLocal())}',
                ].where((item) => item.isNotEmpty).join(' · ');

                return Card(
                  color: colors.card,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(
                        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                      ),
                    ),
                    title: Text(name.isEmpty ? 'Sinh viên' : name),
                    subtitle: Text(subtitle),
                    trailing: Icon(
                      isCheckedIn ? Icons.check_circle : Icons.schedule,
                      color: isCheckedIn
                          ? colors.success
                          : colors.mutedForeground,
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.message,
    required this.colors,
    this.isError = false,
  });

  final String message;
  final AppColors colors;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? colors.danger : colors.mutedForeground;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(AppColors.radius),
      ),
      child: Text(message, style: TextStyle(color: color)),
    );
  }
}

DateTime? _parseDate(dynamic value) {
  final text = value?.toString();
  if (text == null || text.isEmpty) return null;
  return DateTime.tryParse(text.contains('T') ? text : text.replaceFirst(' ', 'T'));
}

int _count(dynamic value) => int.tryParse(value?.toString() ?? '') ?? 0;
