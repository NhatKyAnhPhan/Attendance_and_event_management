import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/organizer_events_controller.dart';
import '../../core/constants/role.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/api/api_client.dart';
import '../../widgets/statistics_charts.dart';
import 'student_attendance_detail_page.dart';

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
  String? _selectedEventId;
  Map<String, dynamic>? _selectedEventDetails;

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
      final status = event['status']?.toString().toLowerCase() ?? '';
      final endTime = _parseDate(event['endTime']);
      final isOpen = !const {'đã đóng', 'đã kết thúc', 'closed', 'ended'}
              .contains(status) &&
          (endTime == null || endTime.isAfter(DateTime.now()));
      final searchable = [
        event['id'],
        event['name'],
        event['location'],
      ].join(' ').toLowerCase();
      return isOpen && (query.isEmpty || searchable.contains(query));
    }).toList();

    final selectedEventSummary = _selectedEventId == null
        ? null
        : events.cast<Map<String, dynamic>?>().firstWhere(
            (event) => event?['id']?.toString() == _selectedEventId,
            orElse: () => null,
          );
    final selectedEvent = selectedEventSummary == null
        ? null
        : {...selectedEventSummary, ...?_selectedEventDetails};
    final summaryEvents = selectedEvent == null ? events : [selectedEvent];
    final registeredCount = summaryEvents.fold<int>(
      0,
      (total, event) => total + _count(event['registeredCount']),
    );
    final checkedInCount = summaryEvents.fold<int>(
      0,
      (total, event) => total + _count(event['checkedInCount']),
    );
    final absentCount = summaryEvents.fold<int>(
      0,
      (total, event) => total + _count(event['absentCount']),
    );
    final pendingCount = summaryEvents.fold<int>(
      0,
      (total, event) => total + _count(event['pendingCount']),
    );

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
          'Chọn sự kiện đang mở để xem chi tiết và kết quả điểm danh.',
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
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 900;
              final eventList = _buildEventList(
                events,
                colors,
                selectedEvent?['id']?.toString(),
              );
              final overview = _buildEventOverview(
                colors,
                summaryEvents,
                registeredCount,
                checkedInCount,
                absentCount,
                pendingCount,
                selectedEvent,
              );
              if (!isWide) {
                return Column(
                  children: [eventList, const SizedBox(height: 16), overview],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 44, child: eventList),
                  const SizedBox(width: 16),
                  Expanded(flex: 56, child: overview),
                ],
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildEventList(
    List<Map<String, dynamic>> events,
    AppColors colors,
    String? selectedEventId,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Danh sách sự kiện',
                  style: AppTextStyles.displaySm(colors.foreground),
                ),
              ),
              TextButton.icon(
                onPressed: selectedEventId == null
                    ? null
                    : () => setState(() => _selectedEventId = null),
                icon: const Icon(Icons.analytics_outlined),
                label: const Text('Xem tổng hợp'),
              ),
            ],
          ),
          ...events.map(
            (event) => _EventAttendanceCard(
              event: event,
              colors: colors,
              selected: event['id']?.toString() == selectedEventId,
              onTap: () => _selectEvent(event),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectEvent(Map<String, dynamic> event) async {
    final eventId = event['id']?.toString() ?? '';
    setState(() {
      _selectedEventId = eventId;
      _selectedEventDetails = null;
    });
    try {
      final details = await Get.put(OrganizerEventsController())
          .getEventDetails(eventId);
      if (!mounted || _selectedEventId != eventId) return;
      setState(() => _selectedEventDetails = details);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không tải được chi tiết sự kiện: $error')),
      );
    }
  }

  Widget _buildEventOverview(
    AppColors colors,
    List<Map<String, dynamic>> events,
    int registeredCount,
    int checkedInCount,
    int absentCount,
    int pendingCount,
    Map<String, dynamic>? selectedEvent,
  ) {
    final title = selectedEvent?['name']?.toString().trim().isNotEmpty == true
        ? selectedEvent!['name'].toString()
        : 'Tổng hợp tất cả sự kiện';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: AppTextStyles.displaySm(colors.foreground)),
        if (selectedEvent != null) ...[
          const SizedBox(height: 8),
          Text(
            selectedEvent['description']?.toString().trim().isNotEmpty == true
                ? selectedEvent['description'].toString()
                : 'Chưa có mô tả cho sự kiện này.',
            style: AppTextStyles.bodySm(colors.mutedForeground),
          ),
          if ((selectedEvent['location']?.toString() ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Địa điểm: ${selectedEvent['location']}'),
            ),
          if (Get.find<AuthController>().canManageEvents)
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => _createEventQr(selectedEvent),
                icon: const Icon(Icons.qr_code_2),
                label: const Text('Tạo mã QR điểm danh'),
              ),
            ),
        ],
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) => GridView.count(
            crossAxisCount: constraints.maxWidth >= 760
                ? 4
                : constraints.maxWidth >= 400
                ? 2
                : 1,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            mainAxisExtent: 88,
            children: [
              _EventSummaryCard(
                title: selectedEvent == null ? 'Sự kiện' : 'Đăng ký',
                value: selectedEvent == null
                    ? '${events.length}'
                    : '$registeredCount',
                color: colors.primary,
                background: colors.secondary,
              ),
              _EventSummaryCard(
                title: 'Đã điểm danh',
                value: '$checkedInCount',
                color: colors.success,
                background: const Color(0xFFDCFCE7),
              ),
              _EventSummaryCard(
                title: 'Vắng mặt',
                value: '$absentCount',
                color: colors.danger,
                background: const Color(0xFFFEE2E2),
              ),
              _EventSummaryCard(
                title: 'Chờ điểm danh',
                value: '$pendingCount',
                color: colors.warning,
                background: const Color(0xFFFEF3C7),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        StatisticsDonutChart(
          title: 'Phân bổ điểm danh',
          colors: colors,
          data: [
            StatisticsChartDatum(
              label: 'Đã điểm danh',
              value: checkedInCount,
              color: colors.success,
            ),
            StatisticsChartDatum(
              label: 'Vắng mặt',
              value: absentCount,
              color: colors.danger,
            ),
            StatisticsChartDatum(
              label: 'Chờ điểm danh',
              value: pendingCount,
              color: colors.warning,
            ),
          ],
        ),
        if (selectedEvent != null) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      _EventAttendanceRosterPage(event: selectedEvent),
                ),
              ),
              icon: const Icon(Icons.groups_outlined),
              label: const Text('Danh sách sinh viên'),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _createEventQr(Map<String, dynamic> event) async {
    final eventId = event['id']?.toString() ?? '';
    try {
      final controller = Get.put(OrganizerEventsController());
      final details = await controller.getEventDetails(eventId);
      final hasPeriods = details['attendancePeriods'] is List &&
          (details['attendancePeriods'] as List).isNotEmpty;
      final periods = (details['attendancePeriods'] as List? ?? const [])
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .where((period) {
            final end = _parseDate(period['endTime']);
            return end != null && end.isAfter(DateTime.now());
          })
          .toList();
      if (hasPeriods && periods.isEmpty) {
        throw Exception('Tất cả khung điểm danh của sự kiện đã kết thúc.');
      }
      Map<String, dynamic>? period;
      if (periods.length == 1) {
        period = periods.first;
      } else if (periods.length > 1) {
        period = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Chọn khung điểm danh'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: periods.map((item) => ListTile(
                title: Text(item['name']?.toString() ?? 'Khung điểm danh'),
                subtitle: Text('${DateFormat('dd/MM HH:mm').format(_parseDate(item['startTime'])!.toLocal())} – ${DateFormat('dd/MM HH:mm').format(_parseDate(item['endTime'])!.toLocal())}'),
                onTap: () => Navigator.pop(dialogContext, item),
              )).toList(),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Hủy'))],
          ),
        );
        if (period == null || !mounted) return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Hãy bật dịch vụ vị trí trên thiết bị.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw Exception('Cần cấp quyền vị trí để tạo mã QR điểm danh.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final result = await controller.createAttendanceQr(
        eventId,
        latitude: position.latitude,
        longitude: position.longitude,
        periodId: period?['id']?.toString(),
      );
      final qr = result['qr']?.toString() ?? '';
      final sessionId = result['sessionId']?.toString() ?? '';
      if (qr.isEmpty || sessionId.isEmpty) throw Exception('Máy chủ không trả về mã QR hợp lệ.');
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(period?['name']?.toString() ?? 'QR điểm danh sự kiện'),
          content: SizedBox(
            width: 300,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(event['name']?.toString() ?? 'Sự kiện', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              QrImageView(data: qr, size: 250),
              const Text('Sinh viên quét mã trên ứng dụng để ghi nhận điểm danh.', textAlign: TextAlign.center),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Đóng')),
            FilledButton.icon(
              onPressed: () async {
                try {
                  await controller.closeAttendanceSession(eventId, sessionId);
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã tắt mã QR.')));
                } catch (error) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không thể tắt mã QR: $error')));
                }
              },
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('Tắt mã QR'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không tạo được mã QR: $error')));
    }
  }

  static int _count(dynamic value) =>
      int.tryParse(value?.toString() ?? '') ?? 0;
}

class _EventAttendanceCard extends StatelessWidget {
  const _EventAttendanceCard({
    required this.event,
    required this.colors,
    required this.selected,
    required this.onTap,
  });

  final Map<String, dynamic> event;
  final AppColors colors;
  final bool selected;
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
      color: selected ? colors.secondary : colors.card,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppColors.radius),
        side: BorderSide(color: selected ? colors.primary : colors.border),
      ),
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
                  Icon(
                    selected ? Icons.check_circle : Icons.chevron_right,
                    color: selected ? colors.primary : null,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                details,
                style: AppTextStyles.bodySm(colors.mutedForeground),
              ),
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
                    label: 'Đã điểm danh',
                    count: checkedInCount,
                    color: colors.success,
                  ),
                  _CountPill(
                    label: 'Vắng mặt',
                    count: _count(event['absentCount']),
                    color: colors.danger,
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
  final ScrollController _pageScrollController = ScrollController();
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
    _pageScrollController.dispose();
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
      ].join(' ').toLowerCase();
      return query.isEmpty || searchable.contains(query);
    }).toList();
    final checkedIn = _students
        .where(
          (student) => (student['attendanceStatus']?.toString() ?? '')
              .startsWith('Đã điểm danh'),
        )
        .length;
    final canViewStudentDetails =
        Get.find<AuthController>().role.value != Role.student;
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
        child: Scrollbar(
          controller: _pageScrollController,
          thumbVisibility: true,
          interactive: true,
          child: ListView(
            controller: _pageScrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${_students.length} sinh viên đăng ký · $checkedIn đã điểm danh · '
                '${_countStatus(_students, 'Vắng mặt')} vắng mặt',
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
                  final attendanceStatus =
                      student['attendanceStatus']?.toString() ??
                      'Chưa điểm danh';
                  final isCheckedIn = attendanceStatus.startsWith(
                    'Đã điểm danh',
                  );
                  final subtitle = [
                    studentId,
                    attendanceStatus,
                    if (checkedAt != null)
                      'Điểm danh lúc ${DateFormat('dd/MM/yyyy HH:mm').format(checkedAt.toLocal())}',
                  ].where((item) => item.isNotEmpty).join(' · ');

                  return Card(
                    color: colors.card,
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          name.isEmpty
                              ? '?'
                              : name.characters.first.toUpperCase(),
                        ),
                      ),
                      title: Text(name.isEmpty ? 'Sinh viên' : name),
                      subtitle: Text(subtitle),
                      onTap: canViewStudentDetails
                          ? () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => StudentAttendanceDetailPage(
                                  student: student,
                                  contextTitle: eventName,
                                ),
                              ),
                            )
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isCheckedIn ? Icons.check_circle : Icons.schedule,
                            color: isCheckedIn
                                ? colors.success
                                : colors.mutedForeground,
                          ),
                          if (canViewStudentDetails)
                            Icon(Icons.chevron_right, color: colors.primary),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EventSummaryCard extends StatelessWidget {
  const _EventSummaryCard({
    required this.title,
    required this.value,
    required this.color,
    required this.background,
  });

  final String title;
  final String value;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: AppTextStyles.bodySm(color)),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppTextStyles.displayLg(color).copyWith(fontSize: 22),
          ),
        ],
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
  return DateTime.tryParse(
    text.contains('T') ? text : text.replaceFirst(' ', 'T'),
  );
}

int _count(dynamic value) => int.tryParse(value?.toString() ?? '') ?? 0;

int _countStatus(List<Map<String, dynamic>> students, String status) => students
    .where((student) => student['attendanceStatus']?.toString() == status)
    .length;
