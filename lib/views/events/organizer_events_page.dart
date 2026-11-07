import 'package:file_picker/file_picker.dart';
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
import '../../core/utils/date_time_serialization.dart';
import '../../core/utils/excel_file_decoder.dart';
import '../../data/models/event_model.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/student_roster_list.dart';

class OrganizerEventsPage extends StatefulWidget {
  const OrganizerEventsPage({super.key});

  @override
  State<OrganizerEventsPage> createState() => _OrganizerEventsPageState();
}

class _EventBenefitDraft {
  _EventBenefitDraft({
    this.type = 'Khác',
    String points = '0',
    String content = '',
  }) : pointsController = TextEditingController(text: points),
       contentController = TextEditingController(text: content);

  String type;
  final TextEditingController pointsController;
  final TextEditingController contentController;

  Map<String, dynamic> toJson() => {
    'type': type,
    'points': int.parse(pointsController.text.trim()),
    'content': contentController.text.trim(),
  };

  void dispose() {
    pointsController.dispose();
    contentController.dispose();
  }
}

class _AttendancePeriodDraft {
  _AttendancePeriodDraft({
    String name = '',
    required this.startTime,
    required this.endTime,
  }) : nameController = TextEditingController(text: name);

  final TextEditingController nameController;
  DateTime startTime;
  DateTime endTime;

  Map<String, dynamic> toJson() => {
    'name': nameController.text.trim(),
    'startTime': dateTimeToUtcIso8601(startTime),
    'endTime': dateTimeToUtcIso8601(endTime),
  };

  void dispose() => nameController.dispose();
}

List<int> _eventAttendanceThresholdOptions(int periodCount) => periodCount <= 0
    ? [100]
    : List.generate(periodCount, (index) => ((index + 1) * 100) ~/ periodCount);

class _OrganizerEventsPageState extends State<OrganizerEventsPage> {
  String _query = '';
  bool _showArchived = false;
  final Set<String> _selectedClosedEventIds = {};
  bool _sendingCertificates = false;
  bool _issuingCertificatesInApp = false;
  bool _importingEventsFromExcel = false;
  bool _importingStudentsFromExcel = false;
  DateTimeRange? _dateRange;
  final Set<String> _importingEventIds = {};
  final Map<String, String> _activeQrSessionIds = {};

  Future<void> _selectDateRange() async {
    final now = DateTime.now();
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 10),
      initialDateRange: _dateRange ?? DateTimeRange(start: now, end: now),
      helpText: 'Chọn khoảng thời gian diễn ra sự kiện',
      saveText: 'ÁP DỤNG',
    );
    if (selected != null && mounted) {
      setState(() => _dateRange = selected);
    }
  }

  Future<void> _importEventsFromExcel(
    BuildContext context,
    OrganizerEventsController controller,
  ) async {
    FilePickerResult? selection;
    try {
      selection = await FilePicker.pickFiles(
        dialogTitle: 'Chọn file Excel danh sách sự kiện',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        allowMultiple: false,
        withData: true,
      );
    } on Exception catch (exception) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thể mở file Excel: $exception')),
      );
      return;
    }
    if (selection == null || selection.files.isEmpty || !context.mounted) {
      return;
    }
    final bytes = selection.files.single.bytes;
    if (bytes == null || bytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không đọc được nội dung file Excel.')),
      );
      return;
    }

    try {
      final parsedEvents = extractEventsFromWorkbook(
        decodeExcelWorkbook(bytes),
      );
      final events = parsedEvents.events;
      await controller.loadUnits();
      if (!context.mounted) return;
      if (controller.unitsError.value.isNotEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(controller.unitsError.value)));
        return;
      }
      if (controller.units.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tài khoản chưa được phân công đơn vị tổ chức.'),
          ),
        );
        return;
      }
      final unitMappings = <String, OrganizerUnit?>{};
      for (final event in events) {
        final matches = controller.units
            .where(
              (unit) =>
                  _normalizeMatchText(unit.name) ==
                  _normalizeMatchText(event.organizerName),
            )
            .toList();
        unitMappings[event.organizerName] = matches.length == 1
            ? matches.single
            : null;
      }
      final importableEvents = events
          .where((event) => unitMappings[event.organizerName] != null)
          .toList();
      final unmatchedOrganizerNames = unitMappings.entries
          .where((entry) => entry.value == null)
          .map((entry) => entry.key)
          .toSet();
      if (importableEvents.isEmpty) {
        await _showExcelError(
          context,
          'Không có sự kiện nào có đơn vị tổ chức khớp với đơn vị hiện có. '
          'Các tên không khớp: ${unmatchedOrganizerNames.join(', ')}.',
        );
        return;
      }
      final warnings = [
        ...parsedEvents.warnings,
        for (final name in unmatchedOrganizerNames)
          'Không tìm thấy đơn vị "$name" trong hệ thống; sự kiện của đơn vị này sẽ bị bỏ qua.',
      ];
      final confirmed = await _confirmExcelImport(
        context,
        title: 'Xác nhận thêm sự kiện từ Excel',
        subtitle:
            '${importableEvents.length} sự kiện có đơn vị khớp sẽ được thêm; '
            '${events.length - importableEvents.length} sự kiện không khớp sẽ bị bỏ qua.',
        warnings: warnings,
        lines: events.map((event) {
          final unit = unitMappings[event.organizerName];
          return '${event.name} (${event.sourceId})\n'
              '${DateFormat('dd/MM/yyyy').format(event.eventDate)} · '
              '${event.startMinutes == null ? '09:00 mặc định' : _formatMinutes(event.startMinutes!)} · '
              '${event.location} · '
              '${unit?.name ?? 'Không khớp đơn vị: ${event.organizerName} — sẽ bỏ qua'}';
        }).toList(),
      );
      if (confirmed != true || !context.mounted) return;

      setState(() => _importingEventsFromExcel = true);
      var importedCount = 0;
      var existingCount = 0;
      final failures = <String>[];
      for (final event in events) {
        final organizerUnit = unitMappings[event.organizerName];
        if (organizerUnit == null) {
          failures.add(
            '${event.name}: không tìm thấy đơn vị "${event.organizerName}" trong hệ thống.',
          );
          continue;
        }
        final normalizedName = _normalizeMatchText(event.name);
        if (controller.items.any(
          (existing) => _normalizeMatchText(existing.name) == normalizedName,
        )) {
          existingCount++;
          continue;
        }

        final startTime = DateTime(
          event.eventDate.year,
          event.eventDate.month,
          event.eventDate.day,
        ).add(Duration(minutes: event.startMinutes ?? 9 * 60));
        var endTime = event.endMinutes == null
            ? startTime.add(const Duration(hours: 2))
            : DateTime(
                event.eventDate.year,
                event.eventDate.month,
                event.eventDate.day,
              ).add(Duration(minutes: event.endMinutes!));
        if (!endTime.isAfter(startTime)) {
          endTime = endTime.add(const Duration(days: 1));
        }

        try {
          await controller.createEvent(
            sourceId: event.sourceId,
            name: event.name,
            organizerId: organizerUnit.id,
            startTime: startTime,
            endTime: endTime,
            location: event.location,
            capacity: 2000,
            certificateEnabled: false,
            attendanceThresholdPercent: 100,
            description: event.description,
            benefits: const [],
            rules: const [],
            attendancePeriods: const [],
            allowHistoricalImport: true,
          );
          importedCount++;
        } catch (exception) {
          failures.add('${event.name}: $exception');
        }
      }

      if (!context.mounted) return;
      final details = <String>[
        'Đã thêm: $importedCount sự kiện.',
        if (existingCount > 0) 'Đã có sẵn: $existingCount sự kiện.',
        if (failures.isNotEmpty) ...[
          'Không nhập được ${failures.length} sự kiện:',
          ...failures.take(10),
          if (failures.length > 10)
            '... và ${failures.length - 10} sự kiện khác.',
        ],
        'Giờ bắt đầu mặc định là 09:00; nếu thiếu giờ kết thúc, dùng thời lượng 2 giờ. '
            'Sĩ số tối đa mặc định là 2.000.',
      ];
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Kết quả nhập sự kiện'),
          content: SingleChildScrollView(child: Text(details.join('\n\n'))),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
    } on FormatException catch (error) {
      if (!context.mounted) return;
      await _showExcelError(context, error.message.toString());
    } catch (exception) {
      if (!context.mounted) return;
      await _showExcelError(context, exception.toString());
    } finally {
      if (mounted) setState(() => _importingEventsFromExcel = false);
    }
  }

  String _formatMinutes(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';

  Future<bool?> _confirmExcelImport(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<String> lines,
    List<String> warnings = const [],
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(subtitle),
              if (warnings.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer
                        .withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Dòng sẽ bị bỏ qua:\n${warnings.join('\n')}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(child: Text(lines.join('\n\n'))),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Xác nhận nhập'),
          ),
        ],
      ),
    );
  }

  Future<void> _showExcelError(BuildContext context, String message) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Không thể nhập file Excel'),
        content: SingleChildScrollView(child: SelectableText(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Future<void> _importStudentRosterFromExcel(
    BuildContext context,
    OrganizerEventsController controller,
  ) async {
    FilePickerResult? selection;
    try {
      selection = await FilePicker.pickFiles(
        dialogTitle: 'Chọn file Excel có cột MSSV và MaSuKien',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        allowMultiple: false,
        withData: true,
      );
    } on Exception catch (exception) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thể mở file Excel: $exception')),
      );
      return;
    }
    if (selection == null || selection.files.isEmpty || !context.mounted) {
      return;
    }
    final bytes = selection.files.single.bytes;
    if (bytes == null || bytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không đọc được nội dung file Excel.')),
      );
      return;
    }

    setState(() => _importingStudentsFromExcel = true);
    try {
      final groups = extractStudentRosterGroups(
        decodeExcelWorkbook(bytes),
        targetIdHeaders: const {
          'MaSuKien',
          'Mã sự kiện',
          'eventId',
          'eventCode',
        },
        targetNameHeaders: const {'TenSuKien', 'Tên sự kiện', 'eventName'},
      );
      final previewLines = <String>[];
      for (final group in groups) {
        var matches = controller.items
            .where(
              (event) => event.id.toUpperCase() == group.targetId.toUpperCase(),
            )
            .toList();
        if (matches.isEmpty && group.targetName.isNotEmpty) {
          matches = controller.items
              .where(
                (event) =>
                    _normalizeMatchText(event.name) ==
                    _normalizeMatchText(group.targetName),
              )
              .toList();
        }
        final eventName = matches.length == 1
            ? matches.single.name
            : group.targetName.isEmpty
            ? group.targetId
            : group.targetName;
        final issue = matches.isEmpty
            ? ' — Bỏ qua: chưa có sự kiện tương ứng'
            : matches.length > 1
            ? ' — Bỏ qua: mã/tên sự kiện bị trùng'
            : group.studentIds.length > 2000
            ? ' — Bỏ qua: vượt giới hạn 2.000 sinh viên'
            : '';
        previewLines.add(
          '$eventName (${group.targetId}) — ${group.studentIds.length} sinh viên$issue\n'
          '${group.studentIds.join(', ')}',
        );
      }
      final confirmed = await _confirmExcelImport(
        context,
        title: 'Xác nhận import sinh viên',
        subtitle:
            '${groups.length} danh sách, ${groups.fold<int>(0, (total, group) => total + group.studentIds.length)} mã sinh viên được đọc từ file.',
        lines: previewLines,
      );
      if (confirmed != true || !context.mounted) return;
      var importedCount = 0;
      var alreadyRegisteredCount = 0;
      var unknownStudentCount = 0;
      var duplicateRows = 0;
      final skipped = <String>[];
      for (final group in groups) {
        var matches = controller.items
            .where(
              (event) => event.id.toUpperCase() == group.targetId.toUpperCase(),
            )
            .toList();
        if (matches.isEmpty && group.targetName.isNotEmpty) {
          matches = controller.items
              .where(
                (event) =>
                    _normalizeMatchText(event.name) ==
                    _normalizeMatchText(group.targetName),
              )
              .toList();
        }
        if (matches.isEmpty) {
          skipped.add(
            '${group.targetName.isEmpty ? group.targetId : group.targetName} '
            '(${group.targetId}): chưa có sự kiện tương ứng trong hệ thống.',
          );
          continue;
        }
        if (matches.length > 1) {
          skipped.add(
            '${group.targetName.isEmpty ? group.targetId : group.targetName}: '
            'có nhiều sự kiện trùng thông tin.',
          );
          continue;
        }
        final event = matches.first;
        if (group.studentIds.length > 2000) {
          skipped.add('${event.name}: vượt giới hạn 2.000 sinh viên.');
          continue;
        }
        try {
          final result = await controller.importEventStudents(
            eventId: event.id,
            studentIds: group.studentIds,
            allowHistoricalImport: true,
          );
          importedCount += result.importedCount;
          alreadyRegisteredCount += result.alreadyRegisteredCount;
          unknownStudentCount += result.unknownStudentIds.length;
          duplicateRows += group.duplicateRows;
        } catch (exception) {
          skipped.add('${event.name}: $exception');
        }
      }
      await controller.load();
      if (!context.mounted) return;
      final details = <String>[
        'Đã thêm: $importedCount sinh viên.',
        'Đã đăng ký trước đó: $alreadyRegisteredCount sinh viên.',
        if (unknownStudentCount > 0)
          'Không tìm thấy $unknownStudentCount mã sinh viên trong hệ thống.',
        if (duplicateRows > 0)
          'Mã sinh viên trùng trong file: $duplicateRows dòng.',
        if (skipped.isNotEmpty) ...[
          'Không nhập được ${skipped.length} danh sách:',
          ...skipped.take(10),
          if (skipped.length > 10)
            '... và ${skipped.length - 10} danh sách khác.',
        ],
      ];
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Kết quả nhập sinh viên'),
          content: SingleChildScrollView(child: Text(details.join('\n'))),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
    } on FormatException catch (error) {
      if (!context.mounted) return;
      await _showExcelError(context, error.message.toString());
    } catch (exception) {
      if (!context.mounted) return;
      await _showExcelError(context, exception.toString());
    } finally {
      if (mounted) setState(() => _importingStudentsFromExcel = false);
    }
  }

  String _normalizeMatchText(String value) =>
      value.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

  // Hiển thị danh sách sự kiện cùng các thao tác theo vai trò.
  @override
  Widget build(BuildContext context) {
    final controller = Get.put(OrganizerEventsController());
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = AppColors.of(isDark);

    // Theo dõi trạng thái controller để hiển thị tải, lỗi và danh sách sự kiện.
    return Obx(() {
      controller.statusRefreshTick.value;
      final auth = Get.find<AuthController>();
      final canManageEvents = auth.canManageEvents;
      final currentRole = auth.currentUser.value?['role']?.toString() ?? '';
      final canImportExcel =
          auth.role.value == Role.admin ||
          auth.role.value == Role.organizer ||
          RoleX.isEmployee(currentRole);
      final canDeleteEvents = canManageEvents;
      final query = _query.trim().toLowerCase();
      final filteredItems = controller.items.where((event) {
        if (event.isArchived != _showArchived) return false;
        final dateRange = _dateRange;
        if (dateRange != null) {
          final rangeStart = DateTime(
            dateRange.start.year,
            dateRange.start.month,
            dateRange.start.day,
          );
          final rangeEnd = DateTime(
            dateRange.end.year,
            dateRange.end.month,
            dateRange.end.day,
            23,
            59,
            59,
            999,
          );
          if (event.endTime.isBefore(rangeStart) ||
              event.startTime.isAfter(rangeEnd)) {
            return false;
          }
        }
        return [
          event.id,
          event.name,
          event.location,
          event.status,
          event.organizerId,
        ].any((value) => value.toLowerCase().contains(query));
      }).toList()
        ..sort((a, b) {
            int rank(OrganizerEventSummary event) {
              if (event.isClosed) return 4;
              if (event.status == 'Sắp diễn ra') return 0;
              if (event.status == 'Đang diễn ra') return 1;
              return 3;
            }
            final rankOrder = rank(a).compareTo(rank(b));
            if (rankOrder != 0) return rankOrder;
            return a.startTime.compareTo(b.startTime);
          });
      if (controller.loading.value && controller.items.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      return RefreshIndicator(
        onRefresh: controller.load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: MediaQuery.sizeOf(context).width > 800
                      ? MediaQuery.sizeOf(context).width - 560
                      : MediaQuery.sizeOf(context).width - 56,
                  child: Text(
                    'Quản lý sự kiện',
                    style: AppTextStyles.displayLg(colors.foreground),
                  ),
                ),
                if (canImportExcel)
                  OutlinedButton.icon(
                    onPressed:
                        _importingEventsFromExcel || _importingStudentsFromExcel
                        ? null
                        : () => _importEventsFromExcel(context, controller),
                    icon: _importingEventsFromExcel
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file_outlined),
                    label: Text(
                      _importingEventsFromExcel
                          ? 'Đang nhập sự kiện...'
                          : 'Thêm sự kiện Excel',
                    ),
                  ),
                if (canImportExcel)
                  OutlinedButton.icon(
                    onPressed:
                        _importingStudentsFromExcel || _importingEventsFromExcel
                        ? null
                        : () => _importStudentRosterFromExcel(
                            context,
                            controller,
                          ),
                    icon: _importingStudentsFromExcel
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.group_add_outlined),
                    label: Text(
                      _importingStudentsFromExcel
                          ? 'Đang nhập sinh viên...'
                          : 'Thêm sinh viên Excel',
                    ),
                  ),
                if (canManageEvents)
                  FilledButton.icon(
                    onPressed:
                        _importingEventsFromExcel || _importingStudentsFromExcel
                        ? null
                        : () async {
                            await controller.loadUnits();
                            if (!context.mounted) return;
                            if (controller.unitsError.value.isNotEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(controller.unitsError.value),
                                ),
                              );
                            }
                            await _showEventDialog(context, controller);
                          },
                    icon: const Icon(Icons.add),
                    label: const Text('Tạo sự kiện'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Sự kiện đang mở'),
                  selected: !_showArchived,
                  selectedColor: colors.secondary,
                  side: BorderSide(
                    color: !_showArchived ? colors.primary : colors.border,
                  ),
                  labelStyle: TextStyle(
                    color: !_showArchived
                        ? colors.secondaryForeground
                        : colors.mutedForeground,
                    fontWeight: !_showArchived
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  onSelected: (_) => setState(() => _showArchived = false),
                ),
                ChoiceChip(
                  label: const Text('Sự kiện đã đóng'),
                  selected: _showArchived,
                  selectedColor: colors.secondary,
                  side: BorderSide(
                    color: _showArchived ? colors.primary : colors.border,
                  ),
                  labelStyle: TextStyle(
                    color: _showArchived
                        ? colors.secondaryForeground
                        : colors.mutedForeground,
                    fontWeight: _showArchived
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  onSelected: (_) => setState(() => _showArchived = true),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_showArchived && canDeleteEvents && filteredItems.isNotEmpty)
              Wrap(spacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: () => setState(() {
                    if (_selectedClosedEventIds.length == filteredItems.length) {
                      _selectedClosedEventIds.clear();
                    } else {
                      _selectedClosedEventIds
                        ..clear()
                        ..addAll(filteredItems.map((event) => event.id));
                    }
                  }),
                  icon: const Icon(Icons.check_box_outlined),
                  label: Text(_selectedClosedEventIds.length == filteredItems.length ? 'Bỏ chọn tất cả' : 'Chọn tất cả'),
                ),
                FilledButton.icon(
                  onPressed: _selectedClosedEventIds.isEmpty ? null : () => _confirmDeleteSelected(context, controller),
                  icon: const Icon(Icons.delete_outline),
                  label: Text('Xóa đã chọn (${_selectedClosedEventIds.length})'),
                ),
              ]),
            if (_showArchived && canDeleteEvents && filteredItems.isNotEmpty)
              const SizedBox(height: 12),
            AppSearchField(
              colors: colors,
              hintText: 'Tìm tên sự kiện, địa điểm, trạng thái...',
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _selectDateRange,
                  icon: const Icon(Icons.date_range_outlined),
                  label: Text(
                    _dateRange == null
                        ? 'Lọc theo ngày'
                        : '${DateFormat('dd/MM/yyyy').format(_dateRange!.start)}'
                              ' - ${DateFormat('dd/MM/yyyy').format(_dateRange!.end)}',
                  ),
                ),
                if (_dateRange != null)
                  IconButton(
                    tooltip: 'Xóa bộ lọc ngày',
                    onPressed: () => setState(() => _dateRange = null),
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (controller.error.value.isNotEmpty)
              _ErrorBanner(message: controller.error.value),
            if (controller.items.isEmpty && controller.error.value.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(child: Text('Chưa có sự kiện nào.')),
              ),
            if (controller.items.isNotEmpty && filteredItems.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(
                  child: Text('Không có sự kiện phù hợp trong mục này.'),
                ),
              ),
            ...filteredItems.map(
              (event) => Card(
                margin: const EdgeInsets.only(bottom: 14),
                elevation: 2,
                color: colors.card,
                shadowColor: Colors.black.withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: colors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _showEventDetails(context, controller, event),
                  hoverColor: colors.primary.withValues(alpha: 0.035),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (_showArchived && canDeleteEvents)
                          Checkbox(
                            value: _selectedClosedEventIds.contains(event.id),
                            onChanged: (selected) => setState(() {
                              if (selected == true) {
                                _selectedClosedEventIds.add(event.id);
                              } else {
                                _selectedClosedEventIds.remove(event.id);
                              }
                            }),
                          ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                event.name,
                                style: AppTextStyles.displayMd(
                                  colors.foreground,
                                ),
                              ),
                              const SizedBox(height: 10),
                              _eventMetaLine(
                                colors,
                                Icons.location_on_outlined,
                                event.location,
                              ),
                              const SizedBox(height: 7),
                              _eventMetaLine(
                                colors,
                                Icons.calendar_month_outlined,
                                '${DateFormat('dd/MM/yyyy HH:mm').format(event.startTime)} - '
                                '${DateFormat('HH:mm').format(event.endTime)}',
                              ),
                              const SizedBox(height: 7),
                              _eventMetaLine(
                                colors,
                                Icons.people_outline_rounded,
                                'Đăng ký: ${event.registeredCount}/${event.capacity}',
                              ),
                              _eventMetaLine(
                                colors,
                                event.certificateEnabled
                                    ? Icons.verified_outlined
                                    : Icons.verified_user_outlined,
                                event.certificateEnabled
                                    ? 'Có cấp chứng nhận'
                                    : 'Không cấp chứng nhận',
                              ),
                              if (event.isClosed) ...[
                                const SizedBox(height: 7),
                                Text(
                                  event.isClosed
                                      ? 'Đã đóng'
                                      : 'Đã diễn ra quá 1 năm',
                                  style: AppTextStyles.bodyXs(
                                    colors.mutedForeground,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _eventStatusColor(event.status),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            event.status,
                            style: AppTextStyles.bodyXs(
                              Colors.white,
                            ).copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (canManageEvents || canDeleteEvents)
                          PopupMenuButton<String>(
                            tooltip: 'Thao tác sự kiện',
                            onSelected: (action) {
                              if (action == 'edit') {
                                _showEventDialog(
                                  context,
                                  controller,
                                  event: event,
                                );
                              } else if (action == 'delete') {
                                _confirmDelete(context, controller, event);
                              } else if (action == 'close') {
                                _confirmClose(context, controller, event);
                              }
                            },
                            itemBuilder: (context) => [
                              if (canManageEvents && _canEditEvent(event))
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Chỉnh sửa'),
                                ),
                              if (canManageEvents && !event.isArchived)
                                const PopupMenuItem(
                                  value: 'close',
                                  child: Text('Đóng sự kiện'),
                                ),
                              if (canDeleteEvents)
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Xóa'),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  Color _eventStatusColor(String status) => switch (status) {
    'Sắp diễn ra' => Colors.green.shade700,
    'Đang diễn ra' => Colors.amber.shade800,
    'Đã kết thúc' => Colors.red.shade700,
    'Đã đóng' => Colors.red.shade900,
    _ => Colors.blueGrey,
  };

  Future<void> _confirmDeleteSelected(
    BuildContext context,
    OrganizerEventsController controller,
  ) async {
    final ids = _selectedClosedEventIds.toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa sự kiện đã chọn?'),
        content: Text('Bạn có chắc muốn xóa ${ids.length} sự kiện đã đóng không?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Xác nhận xóa')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      for (final id in ids) {
        await controller.deleteEvent(id);
      }
      if (mounted) setState(() => _selectedClosedEventIds.clear());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã xóa ${ids.length} sự kiện.')));
      }
    } catch (exception) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(exception.toString())));
    }
  }

  Widget _eventMetaLine(AppColors colors, IconData icon, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: colors.mutedForeground),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: AppTextStyles.bodySm(colors.mutedForeground),
          ),
        ),
      ],
    );
  }

  // Hiển thị thông tin chi tiết của một sự kiện.
  Future<void> _showEventDetails(
    BuildContext context,
    OrganizerEventsController controller,
    OrganizerEventSummary event,
  ) async {
    final detailsFuture = controller.getEventDetails(event.id);
    final studentsFuture = controller.getEventStudents(event.id);
    final colors = AppColors.of(
      Theme.of(context).brightness == Brightness.dark,
    );
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final compact = viewportWidth <= 430;
    final dialogContentWidth = viewportWidth <= 700
        ? (viewportWidth - (compact ? 56 : 88)).clamp(240.0, 760.0)
        : 760.0;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: compact
              ? 12
              : viewportWidth <= 700
              ? 20
              : 40,
          vertical: compact ? 12 : 24,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        surfaceTintColor: Colors.transparent,
        titlePadding: EdgeInsets.fromLTRB(
          compact ? 16 : 24,
          compact ? 16 : 22,
          compact ? 16 : 24,
          0,
        ),
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(compact ? 8 : 10),
              decoration: BoxDecoration(
                color: colors.secondary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.event_outlined,
                color: colors.secondaryForeground,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                event.name,
                maxLines: compact ? 3 : 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.displayMd(colors.foreground)
                    .copyWith(fontSize: compact ? 18 : null),
              ),
            ),
          ],
        ),
        contentPadding: EdgeInsets.fromLTRB(
          compact ? 16 : 24,
          18,
          compact ? 16 : 24,
          8,
        ),
        content: SizedBox(
          width: dialogContentWidth,
          child: ConstrainedBox(
            constraints: BoxConstraints.tightFor(
              height: viewportHeight * (compact ? 0.68 : 0.72),
            ),
            child: FutureBuilder<Map<String, dynamic>>(
              future: detailsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Không tải được chi tiết: ${snapshot.error}'),
                  );
                }

                final details = snapshot.data ?? const <String, dynamic>{};
                final benefits = details['benefits'] is List
                    ? (details['benefits'] as List).whereType<Map>().toList()
                    : const <Map>[];
                final rules = details['rules'] is List
                    ? (details['rules'] as List).whereType<Map>().toList()
                    : const <Map>[];
                final description = details['description']?.toString().trim();

                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _detailSection(
                        colors,
                        Icons.info_outline_rounded,
                        'Thông tin sự kiện',
                        [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final twoColumns = constraints.maxWidth >= 600;
                              final itemWidth = twoColumns
                                  ? (constraints.maxWidth - 12) / 2
                                  : constraints.maxWidth;
                              return Wrap(
                                spacing: 12,
                                runSpacing: 14,
                                children: [
                                  _eventInfoTile(
                                    colors,
                                    Icons.tag_outlined,
                                    'Mã sự kiện',
                                    event.id,
                                    itemWidth,
                                  ),
                                  _eventInfoTile(
                                    colors,
                                    Icons.check_circle_outline_rounded,
                                    'Trạng thái',
                                    event.status,
                                    itemWidth,
                                    badge: true,
                                  ),
                                  _eventInfoTile(
                                    colors,
                                    Icons.account_balance_outlined,
                                    'Đơn vị tổ chức',
                                    details['organizerName']?.toString() ??
                                        event.organizerId,
                                    itemWidth,
                                  ),
                                  _eventInfoTile(
                                    colors,
                                    Icons.schedule_outlined,
                                    'Thời gian bắt đầu',
                                    DateFormat('dd/MM/yyyy HH:mm')
                                        .format(event.startTime),
                                    itemWidth,
                                  ),
                                  _eventInfoTile(
                                    colors,
                                    Icons.event_available_outlined,
                                    'Thời gian kết thúc',
                                    DateFormat('dd/MM/yyyy HH:mm')
                                        .format(event.endTime),
                                    itemWidth,
                                  ),
                                  _eventInfoTile(
                                    colors,
                                    Icons.location_on_outlined,
                                    'Địa điểm',
                                    event.location,
                                    itemWidth,
                                  ),
                                  _eventInfoTile(
                                    colors,
                                    Icons.people_outline_rounded,
                                    'Số lượng đăng ký',
                                    '${details['registeredCount'] ?? event.registeredCount}/${details['capacity'] ?? event.capacity}',
                                    itemWidth,
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _detailSection(colors, Icons.notes_outlined, 'Mô tả', [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 160),
                          child: Scrollbar(
                            child: SingleChildScrollView(
                              child: Text(
                                description == null || description.isEmpty
                                    ? 'Chưa có mô tả cho sự kiện này.'
                                    : description,
                                style: AppTextStyles.bodySm(colors.foreground)
                                    .copyWith(height: 1.5),
                              ),
                            ),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      _detailSection(
                        colors,
                        Icons.workspace_premium_outlined,
                        'Quyền lợi',
                        benefits.isEmpty
                            ? [const Text('Chưa có thông tin quyền lợi.')]
                            : benefits.map((benefit) {
                                final type = benefit['type']?.toString();
                                final points = benefit['points'];
                                final content = benefit['content']?.toString();
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.muted.withValues(alpha: 0.55),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.check_circle_outline_rounded,
                                        size: 18,
                                        color: colors.primary,
                                      ),
                                      const SizedBox(width: 9),
                                      Expanded(
                                        child: Text(
                                          [
                                            if (type != null && type.isNotEmpty)
                                              type,
                                            if (points != null) '$points điểm',
                                            if (content != null &&
                                                content.isNotEmpty)
                                              content,
                                          ].join(' · '),
                                          style: AppTextStyles.bodySm(
                                            colors.foreground,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                      ),
                      const SizedBox(height: 16),
                      _detailSection(
                        colors,
                        Icons.rule_outlined,
                        'Nội quy',
                        rules.isEmpty
                            ? [const Text('Chưa có nội quy cho sự kiện này.')]
                            : rules.map((rule) {
                                final order = rule['sortOrder']?.toString();
                                final text = rule['text']?.toString() ?? '';
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.muted.withValues(alpha: 0.55),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.shield_outlined,
                                        size: 18,
                                        color: colors.primary,
                                      ),
                                      const SizedBox(width: 9),
                                      Expanded(
                                        child: Text(
                                          order == null
                                              ? text
                                              : '$order. $text',
                                          style: AppTextStyles.bodySm(
                                            colors.foreground,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                      ),
                      const SizedBox(height: 16),
                      _detailSection(
                        colors,
                        Icons.groups_outlined,
                        'Danh sách sinh viên đăng ký '
                        '(${event.registeredCount})',
                        [
                          SizedBox(
                            height: compact ? 320 : 260,
                            child: FutureBuilder(
                              future: studentsFuture,
                              builder: (context, studentSnapshot) {
                                if (studentSnapshot.connectionState !=
                                    ConnectionState.done) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }
                                if (studentSnapshot.hasError) {
                                  return Center(
                                    child: Text(
                                      'Không tải được danh sách sinh viên: '
                                      '${studentSnapshot.error}',
                                      textAlign: TextAlign.center,
                                    ),
                                  );
                                }
                                return StudentRosterList(
                                  students: studentSnapshot.data ?? const [],
                                  mutedColor: colors.mutedForeground,
                                  dividerColor: colors.border,
                                  emptyMessage:
                                      'Chưa có sinh viên đăng ký sự kiện.',
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        actionsPadding: EdgeInsets.fromLTRB(
          compact ? 16 : 24,
          8,
          compact ? 16 : 24,
          compact ? 14 : 18,
        ),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          if ((Get.find<AuthController>().role.value == Role.admin ||
                  Get.find<AuthController>().role.value == Role.organizer ||
                  RoleX.isEmployee(
                    Get.find<AuthController>().currentUser.value?['role']
                            ?.toString() ??
                        '',
                  )) &&
              !event.isClosed &&
              event.endTime.isAfter(DateTime.now()))
            OutlinedButton.icon(
              onPressed: _importingEventIds.contains(event.id)
                  ? null
                  : () => _importEventStudents(context, controller, event),
              icon: const Icon(Icons.upload_file_outlined),
              label: Text(
                _importingEventIds.contains(event.id)
                    ? 'Đang nhập...'
                    : 'Thêm sinh viên',
              ),
            ),
          if (Get.find<AuthController>().canManageEvents &&
              event.certificateEnabled &&
              (event.isClosed || !event.endTime.isAfter(DateTime.now())))
            FilledButton.icon(
              onPressed: _issuingCertificatesInApp
                  ? null
                  : () => _confirmIssueCertificatesInApp(
                      dialogContext,
                      controller,
                      event,
                    ),
              icon: const Icon(Icons.workspace_premium_outlined),
              label: Text(
                _issuingCertificatesInApp ? 'Đang cấp...' : 'Cấp qua app',
              ),
            ),
          if (Get.find<AuthController>().canManageEvents &&
              event.certificateEnabled &&
              (event.isClosed || !event.endTime.isAfter(DateTime.now())))
            FilledButton.icon(
              onPressed: _sendingCertificates
                  ? null
                  : () => _confirmSendCertificates(
                      dialogContext,
                      controller,
                      event,
                    ),
              icon: const Icon(Icons.email_outlined),
              label: Text(
                _sendingCertificates ? 'Đang gửi...' : 'Gửi chứng nhận',
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Future<void> _importEventStudents(
    BuildContext context,
    OrganizerEventsController controller,
    OrganizerEventSummary event,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Định dạng file Excel'),
        content: const Text(
          'Chọn file .xlsx có tiêu đề cột MSSV, Mã SV hoặc Mã sinh viên ở dòng đầu. '
          'Nếu mã sinh viên có số 0 ở đầu, hãy định dạng cột đó là Văn bản trong Excel.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Chọn file'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    FilePickerResult? selection;
    try {
      selection = await FilePicker.pickFiles(
        dialogTitle: 'Chọn Excel có cột MSSV hoặc Mã sinh viên',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        allowMultiple: false,
        withData: true,
      );
    } on Exception catch (exception) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thể mở file Excel: $exception')),
      );
      return;
    }
    if (selection == null || selection.files.isEmpty || !context.mounted) {
      return;
    }

    final bytes = selection.files.single.bytes;
    if (bytes == null || bytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không đọc được nội dung file Excel.')),
      );
      return;
    }

    try {
      setState(() => _importingEventIds.add(event.id));
      final parsed = extractStudentIdsFromWorkbook(decodeExcelWorkbook(bytes));
      final studentIds = parsed.studentIds;
      final duplicateRows = parsed.duplicateRows;
      if (studentIds.isEmpty) {
        throw const FormatException(
          'Không tìm thấy mã sinh viên nào trong file Excel.',
        );
      }
      if (studentIds.length > 2000) {
        throw const FormatException(
          'Mỗi lần chỉ có thể nhập tối đa 2.000 sinh viên.',
        );
      }

      final result = await controller.importEventStudents(
        eventId: event.id,
        studentIds: studentIds,
      );
      await controller.load();
      if (!context.mounted) return;

      final details = <String>[
        'Đã thêm: ${result.importedCount} sinh viên.',
        'Đã đăng ký trước đó: ${result.alreadyRegisteredCount} sinh viên.',
        if (duplicateRows > 0) 'Mã trùng trong file: $duplicateRows dòng.',
        if (result.unknownStudentIds.isNotEmpty)
          'Không tìm thấy trong hệ thống (${result.unknownStudentIds.length}): '
              '${result.unknownStudentIds.take(10).join(', ')}'
              '${result.unknownStudentIds.length > 10 ? ', ...' : ''}',
      ];
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Kết quả nhập sinh viên · ${event.name}'),
          content: Text(details.join('\n')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
    } on FormatException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message.toString())));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thể nhập sinh viên: $error')),
      );
    } finally {
      if (mounted) setState(() => _importingEventIds.remove(event.id));
    }
  }

  Future<void> _showEventAttendanceQr(
    BuildContext context,
    OrganizerEventsController controller,
    OrganizerEventSummary event,
  ) async {
    try {
      final details = await controller.getEventDetails(event.id);
      if (!context.mounted) return;
      final periods = (details['attendancePeriods'] as List? ?? const [])
          .whereType<Map>()
          .map((period) => Map<String, dynamic>.from(period))
          .where((period) {
            final endTime = DateTime.tryParse(
              period['endTime']?.toString() ?? '',
            );
            return endTime != null && endTime.isAfter(DateTime.now());
          })
          .toList();
      String? periodId;
      String? periodName;
      DateTime? periodEndTime;
      if (details['attendancePeriods'] is List &&
          (details['attendancePeriods'] as List).isNotEmpty) {
        if (periods.isEmpty) {
          throw Exception('Tất cả khung điểm danh của sự kiện đã kết thúc.');
        }
        final selectedPeriod = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Chọn khung điểm danh'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: periods.map((period) {
                  final startTime = DateTime.parse(
                    period['startTime'].toString(),
                  );
                  final endTime = DateTime.parse(period['endTime'].toString());
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(period['name'].toString()),
                    subtitle: Text(
                      '${DateFormat('dd/MM HH:mm').format(startTime)} - '
                      '${DateFormat('dd/MM HH:mm').format(endTime)}',
                    ),
                    onTap: () => Navigator.pop(dialogContext, period),
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Hủy'),
              ),
            ],
          ),
        );
        if (selectedPeriod == null || !context.mounted) return;
        periodId = selectedPeriod['id']?.toString();
        periodName = selectedPeriod['name']?.toString();
        periodEndTime = DateTime.parse(selectedPeriod['endTime'].toString());
      }
      final position = await _getCurrentPosition();
      final result = await controller.createAttendanceQr(
        event.id,
        latitude: position.latitude,
        longitude: position.longitude,
        periodId: periodId,
      );
      final qr = result['qr'].toString();
      final radiusMeters = (result['radiusMeters'] as num).toInt();
      final sessionId = result['sessionId'].toString();
      final sessionNumber = (result['sessionNumber'] as num).toInt();
      periodName ??= result['periodName']?.toString();
      periodEndTime ??= event.endTime;
      if (!context.mounted) return;
      setState(() => _activeQrSessionIds[event.id] = sessionId);
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            periodName == null
                ? 'Phiên điểm danh $sessionNumber'
                : '$periodName · Phiên $sessionNumber',
          ),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(event.name, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                QrImageView(data: qr, size: 250),
                Text(
                  periodName == null
                      ? 'Mỗi sinh viên được ghi nhận riêng trong phiên này. '
                            'QR có hiệu lực trong thời gian sự kiện. '
                            'Ẩn mã QR không đóng phiên.'
                      : 'Mỗi sinh viên được ghi nhận riêng trong phiên này. '
                            'QR chỉ hợp lệ trong khung giờ đã chọn. '
                            'Ẩn mã QR không đóng phiên.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Mã QR hết hiệu lực lúc ${DateFormat('dd/MM/yyyy HH:mm').format(periodEndTime!)}.',
                  textAlign: TextAlign.center,
                ),
                if (periodName != null) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Khoảng nghỉ giữa các khung, ví dụ giờ nghỉ trưa, không '
                    'được tính là thời gian điểm danh.',
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 8),
                Text('Phạm vi điểm danh: $radiusMeters m.'),
                if (DateTime.now().isBefore(event.startTime)) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Mã QR chỉ được xác thực trong thời gian sự kiện diễn ra. '
                    'Nếu quét trước giờ bắt đầu, hệ thống sẽ từ chối điểm danh.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Ẩn mã QR'),
            ),
            FilledButton.icon(
              onPressed: () async {
                try {
                  await controller.closeAttendanceSession(event.id, sessionId);
                  if (!context.mounted) return;
                  setState(() => _activeQrSessionIds.remove(event.id));
                  Navigator.pop(dialogContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Đã đóng phiên điểm danh.')),
                  );
                } catch (error) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Không thể đóng phiên: $error')),
                  );
                }
              },
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('Tắt mã QR'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Không tạo được QR: $error')));
    }
  }

  Future<Position> _getCurrentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Hãy bật dịch vụ vị trí trên thiết bị ban tổ chức.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Cần cấp quyền vị trí để tạo QR điểm danh sự kiện.');
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  Future<void> _confirmSendCertificates(
    BuildContext context,
    OrganizerEventsController controller,
    OrganizerEventSummary event,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gửi chứng nhận qua email?'),
        content: Text(
          'Chứng nhận PDF chỉ gửi cho sinh viên đạt tỷ lệ điểm danh tối thiểu '
          'đã cài đặt cho sự kiện “${event.name}”.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Gửi'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    setState(() => _sendingCertificates = true);
    try {
      final result = await controller.sendCertificates(event.id);
      if (!context.mounted) return;
      final sent = result['sent'] as int? ?? 0;
      final skipped = result['skipped'] as int? ?? 0;
      final message = result['message']?.toString();
      final failures = result['failures'] is List
          ? (result['failures'] as List)
                .whereType<Map>()
                .map((item) => item['message']?.toString() ?? '')
                .where((message) => message.isNotEmpty)
                .toList()
          : const <String>[];
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Kết quả gửi chứng nhận'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message != null && message.isNotEmpty)
                    Text(message)
                  else ...[
                    Text('Gửi thành công: $sent'),
                    if (skipped > 0) Text('Đã cấp trước đó: $skipped'),
                    Text('Gửi thất bại: ${failures.length}'),
                  ],
                  for (final failure in failures)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(failure),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không gửi được chứng nhận: $error')),
      );
    } finally {
      if (mounted) setState(() => _sendingCertificates = false);
    }
  }

  Future<void> _confirmIssueCertificatesInApp(
    BuildContext context,
    OrganizerEventsController controller,
    OrganizerEventSummary event,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cấp chứng nhận trong ứng dụng?'),
        content: Text(
          'Chứng nhận sẽ xuất hiện trong ứng dụng của sinh viên đạt tỷ lệ điểm danh tối thiểu đã cài đặt cho sự kiện “${event.name}”. Email sẽ không được gửi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cấp qua app'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    setState(() => _issuingCertificatesInApp = true);
    try {
      final result = await controller.issueCertificatesInApp(event.id);
      if (!context.mounted) return;
      final issued = result['issued'] as int? ?? 0;
      final skipped = result['skipped'] as int? ?? 0;
      final message = result['message']?.toString().trim();
      final failures = result['failures'] is List
          ? (result['failures'] as List)
                .whereType<Map>()
                .map((item) => item['message']?.toString() ?? '')
                .where((message) => message.isNotEmpty)
                .toList()
          : const <String>[];
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Kết quả cấp trong app'),
          content: Text(
            [
              if (message != null && message.isNotEmpty) message,
              'Đã cấp: $issued',
              'Đã có trước đó: $skipped',
              'Thất bại: ${failures.length}',
              if (failures.isNotEmpty) failures.join('\n'),
            ].join('\n'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
      await controller.load();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không cấp được chứng nhận trong app: $error')),
      );
    } finally {
      if (mounted) setState(() => _issuingCertificatesInApp = false);
    }
  }

  static Widget _detailSection(
    AppColors colors,
    IconData icon,
    String title,
    List<Widget> children,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.displaySm(colors.foreground),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  static Widget _eventInfoTile(
    AppColors colors,
    IconData icon,
    String label,
    String value,
    double width, {
    bool badge = false,
  }) {
    final displayValue = value.isEmpty ? 'Chưa cập nhật' : value;
    return SizedBox(
      width: width,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colors.primary),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.bodyXs(colors.mutedForeground),
                ),
                const SizedBox(height: 3),
                if (badge)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colors.secondary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        displayValue,
                        style: AppTextStyles.bodyXs(colors.secondaryForeground)
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  )
                else
                  Text(
                    displayValue,
                    style: AppTextStyles.bodySm(colors.foreground)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Mở biểu mẫu tạo mới hoặc cập nhật sự kiện hợp lệ.
  Future<void> _showEventDialog(
    BuildContext context,
    OrganizerEventsController controller, {
    OrganizerEventSummary? event,
  }) async {
    // Dùng chung biểu mẫu cho cả thao tác tạo mới và cập nhật sự kiện.
    final isEditing = event != null;
    if (event != null && !_canEditEvent(event)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sự kiện đã kết thúc nên không thể chỉnh sửa.'),
        ),
      );
      return;
    }
    Map<String, dynamic> currentDetails = const {};
    if (event != null) {
      try {
        currentDetails = await controller.getEventDetails(event.id);
      } catch (exception) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Không tải được chi tiết sự kiện: $exception'),
            ),
          );
        }
        return;
      }
      if (!context.mounted) return;
    }
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: event?.name ?? '');
    final descriptionController = TextEditingController(
      text: currentDetails['description']?.toString() ?? '',
    );
    final rules = (currentDetails['rules'] as List? ?? const [])
        .whereType<Map>()
        .map((rule) => rule['text']?.toString() ?? '')
        .where((rule) => rule.trim().isNotEmpty)
        .toList();
    final rulesController = TextEditingController(text: rules.join('\n'));
    final benefits = (currentDetails['benefits'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (benefit) => _EventBenefitDraft(
            type: benefit['type']?.toString() ?? 'Khác',
            points: benefit['points']?.toString() ?? '0',
            content: benefit['content']?.toString() ?? '',
          ),
        )
        .toList();
    final locationController = TextEditingController(
      text: event?.location ?? '',
    );
    final capacityController = TextEditingController(
      text: event?.capacity.toString() ?? '100',
    );
    final organizerController = TextEditingController(
      text: event?.organizerId ?? '',
    );
    String? selectedOrganizerId = event?.organizerId;
    DateTime startTime = event?.startTime ?? DateTime.now();
    DateTime endTime =
        event?.endTime ?? DateTime.now().add(const Duration(hours: 2));
    final attendancePeriods =
        (currentDetails['attendancePeriods'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (period) => _AttendancePeriodDraft(
                name: period['name']?.toString() ?? '',
                startTime: DateTime.parse(
                  period['startTime'].toString(),
                ).toLocal(),
                endTime: DateTime.parse(
                  period['endTime'].toString(),
                ).toLocal(),
              ),
            )
            .toList();
    var certificateEnabled =
        currentDetails['certificateEnabled'] == true ||
        currentDetails['certificateEnabled']?.toString() == '1';
    var attendanceThresholdPercent =
        int.tryParse(
          currentDetails['attendanceThresholdPercent']?.toString() ?? '',
        ) ??
        100;
    if (!_eventAttendanceThresholdOptions(attendancePeriods.length)
        .contains(attendanceThresholdPercent)) {
      attendanceThresholdPercent = 100;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          final colors = AppColors.of(
            Theme.of(context).brightness == Brightness.dark,
          );
          final attendanceThresholdOptions = _eventAttendanceThresholdOptions(
            attendancePeriods.length,
          );
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            surfaceTintColor: Colors.transparent,
            titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.secondary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.event_note_outlined,
                    color: colors.secondaryForeground,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    isEditing ? 'Chỉnh sửa sự kiện' : 'Tạo sự kiện',
                    style: AppTextStyles.displayMd(colors.foreground),
                  ),
                ),
              ],
            ),
            contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
            content: SizedBox(
              width: 700,
              height: MediaQuery.sizeOf(dialogContext).height * 0.7,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _eventFormSection(
                        colors,
                        Icons.info_outline_rounded,
                        'Thông tin cơ bản',
                        [
                          _field(nameController, 'Tên sự kiện'),
                          _unitField(
                            controller.units,
                            selectedOrganizerId,
                            organizerController,
                            (value) =>
                                setState(() => selectedOrganizerId = value),
                          ),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final twoColumns = constraints.maxWidth >= 560;
                              final itemWidth = twoColumns
                                  ? (constraints.maxWidth - 12) / 2
                                  : constraints.maxWidth;
                              return Wrap(
                                spacing: 12,
                                children: [
                                  SizedBox(
                                    width: itemWidth,
                                    child: _field(
                                      locationController,
                                      'Địa điểm',
                                    ),
                                  ),
                                  SizedBox(
                                    width: itemWidth,
                                    child: _field(
                                      capacityController,
                                      'Số lượng tối đa',
                                      number: true,
                                    ),
                                  ),
                                  SizedBox(
                                    width: itemWidth,
                                    child: _eventDateTile(
                                      colors,
                                      'Bắt đầu',
                                      DateFormat('dd/MM/yyyy HH:mm')
                                          .format(startTime),
                                      () async {
                                        final selected = await _pickDateTime(
                                          context,
                                          startTime,
                                        );
                                        if (!context.mounted) return;
                                        if (selected != null) {
                                          if (!endTime.isAfter(selected)) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'Thời gian bắt đầu phải trước thời gian kết thúc.',
                                                    ),
                                                  ),
                                                );
                                            return;
                                          }
                                          setState(() => startTime = selected);
                                        }
                                      },
                                    ),
                                  ),
                                  SizedBox(
                                    width: itemWidth,
                                    child: _eventDateTile(
                                      colors,
                                      'Kết thúc',
                                      DateFormat('dd/MM/yyyy HH:mm')
                                          .format(endTime),
                                      () async {
                                        final selected = await _pickDateTime(
                                          context,
                                          endTime,
                                        );
                                        if (!context.mounted) return;
                                        if (selected != null) {
                                          if (!selected.isAfter(startTime)) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'Thời gian kết thúc phải sau thời gian bắt đầu.',
                                                    ),
                                                  ),
                                                );
                                            return;
                                          }
                                          setState(() => endTime = selected);
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: certificateEnabled,
                        onChanged: (value) =>
                            setState(() => certificateEnabled = value ?? false),
                        title: const Text('Cấp chứng nhận cho người tham dự'),
                        subtitle: const Text(
                          'Chỉ bật nếu sự kiện này sẽ phát hành giấy chứng nhận.',
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      const SizedBox(height: 16),
                      _eventFormSection(
                        colors,
                        Icons.schedule_outlined,
                        'Khung điểm danh',
                        [
                          Text(
                            'Tạo các khoảng giờ cần điểm danh. Thời gian nằm '
                            'giữa hai khung (ví dụ nghỉ trưa) sẽ không nhận '
                            'điểm danh. Nếu không thêm khung, QR hoạt động '
                            'trong toàn thời gian sự kiện.',
                            style: AppTextStyles.bodySm(colors.mutedForeground),
                          ),
                          const SizedBox(height: 12),
                          ...attendancePeriods.asMap().entries.map((entry) {
                            final index = entry.key;
                            final period = entry.value;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colors.muted.withValues(alpha: 0.45),
                                border: Border.all(color: colors.border),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          controller: period.nameController,
                                          maxLength: 60,
                                          decoration: _eventInputDecoration(
                                            'Tên khung, ví dụ: Buổi sáng',
                                          ),
                                          validator: (value) =>
                                              attendancePeriods.contains(
                                                    period,
                                                  ) &&
                                                  (value == null ||
                                                      value.trim().isEmpty)
                                              ? 'Nhập tên khung điểm danh'
                                              : null,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Xóa khung điểm danh',
                                        onPressed: () => setState(() {
                                          attendancePeriods
                                              .removeAt(index)
                                              .dispose();
                                          attendanceThresholdPercent = 100;
                                        }),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                    ],
                                  ),
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      final twoColumns =
                                          constraints.maxWidth >= 500;
                                      final itemWidth = twoColumns
                                          ? (constraints.maxWidth - 12) / 2
                                          : constraints.maxWidth;
                                      return Wrap(
                                        spacing: 12,
                                        children: [
                                          SizedBox(
                                            width: itemWidth,
                                            child: _eventDateTile(
                                              colors,
                                              'Bắt đầu khung',
                                              DateFormat('dd/MM/yyyy HH:mm')
                                                  .format(period.startTime),
                                              () async {
                                                final selected =
                                                    await _pickDateTime(
                                                      context,
                                                      period.startTime,
                                                    );
                                                if (selected != null &&
                                                    context.mounted) {
                                                  setState(
                                                    () => period
                                                      ..startTime = selected,
                                                  );
                                                }
                                              },
                                            ),
                                          ),
                                          SizedBox(
                                            width: itemWidth,
                                            child: _eventDateTile(
                                              colors,
                                              'Kết thúc khung',
                                              DateFormat('dd/MM/yyyy HH:mm')
                                                  .format(period.endTime),
                                              () async {
                                                final selected =
                                                    await _pickDateTime(
                                                      context,
                                                      period.endTime,
                                                    );
                                                if (selected != null &&
                                                    context.mounted) {
                                                  setState(
                                                    () =>
                                                        period
                                                          ..endTime = selected,
                                                  );
                                                }
                                              },
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ],
                              ),
                            );
                          }),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => setState(() {
                                attendanceThresholdPercent = 100;
                                final defaultStart = startTime;
                                final defaultEnd =
                                    endTime.isBefore(
                                      startTime.add(const Duration(hours: 2)),
                                    )
                                    ? endTime
                                    : startTime.add(const Duration(hours: 2));
                                attendancePeriods.add(
                                  _AttendancePeriodDraft(
                                    name:
                                        'Buổi ${attendancePeriods.length + 1}',
                                    startTime: defaultStart,
                                    endTime: defaultEnd,
                                  ),
                                );
                              }),
                              icon: const Icon(Icons.add),
                              label: const Text('Thêm khung điểm danh'),
                            ),
                          ),
                          if (certificateEnabled) ...[
                            const SizedBox(height: 12),
                            DropdownButtonFormField<int>(
                              key: ValueKey(attendancePeriods.length),
                              initialValue: attendanceThresholdPercent,
                              decoration: _eventInputDecoration(
                                'Điều kiện điểm danh để đạt chứng nhận',
                              ),
                              items: attendanceThresholdOptions
                                  .map(
                                    (threshold) => DropdownMenuItem(
                                      value: threshold,
                                      child: Text('$threshold%'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) => setState(
                                () => attendanceThresholdPercent = value ?? 100,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Các mức được tính theo số khung điểm danh đã tạo.',
                              style: AppTextStyles.bodySm(
                                colors.mutedForeground,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),
                      _eventFormSection(
                        colors,
                        Icons.notes_outlined,
                        'Nội dung',
                        [
                          TextFormField(
                            controller: descriptionController,
                            maxLength: 1000,
                            maxLines: 4,
                            decoration: _eventInputDecoration(
                              'Nội dung / mô tả sự kiện',
                              alignLabelWithHint: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _eventFormSection(
                        colors,
                        Icons.workspace_premium_outlined,
                        'Quyền lợi',
                        [
                          ...benefits.asMap().entries.map((entry) {
                            final index = entry.key;
                            final benefit = entry.value;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colors.muted.withValues(alpha: 0.45),
                                border: Border.all(color: colors.border),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final compact = constraints.maxWidth < 560;
                                  final typeField =
                                      DropdownButtonFormField<String>(
                                        initialValue: benefit.type,
                                        decoration: _eventInputDecoration(
                                          'Loại',
                                        ),
                                        items:
                                            const [
                                                  'Điểm rèn luyện',
                                                  'Điểm công tác xã hội',
                                                  'Chứng nhận',
                                                  'Khác',
                                                ]
                                                .map(
                                                  (type) => DropdownMenuItem(
                                                    value: type,
                                                    child: Text(
                                                      type,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                )
                                                .toList(),
                                        onChanged: (type) {
                                          if (type != null) {
                                            setState(() => benefit.type = type);
                                          }
                                        },
                                      );
                                  final pointsField = TextFormField(
                                    controller: benefit.pointsController,
                                    keyboardType: TextInputType.number,
                                    decoration: _eventInputDecoration('Điểm'),
                                    validator: (value) {
                                      final points = int.tryParse(
                                        value?.trim() ?? '',
                                      );
                                      return points == null || points < 0
                                          ? 'Số điểm không hợp lệ'
                                          : null;
                                    },
                                  );
                                  final contentField = TextFormField(
                                    controller: benefit.contentController,
                                    maxLength: 500,
                                    decoration: _eventInputDecoration(
                                      'Mô tả quyền lợi',
                                    ),
                                    validator: (value) =>
                                        value == null || value.trim().isEmpty
                                        ? 'Nhập quyền lợi'
                                        : null,
                                  );
                                  final removeButton = IconButton(
                                    tooltip: 'Xóa quyền lợi',
                                    onPressed: () => setState(() {
                                      benefits.removeAt(index).dispose();
                                    }),
                                    icon: const Icon(Icons.delete_outline),
                                  );
                                  if (compact) {
                                    return Column(
                                      children: [
                                        typeField,
                                        const SizedBox(height: 10),
                                        pointsField,
                                        const SizedBox(height: 10),
                                        contentField,
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: removeButton,
                                        ),
                                      ],
                                    );
                                  }
                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(flex: 4, child: typeField),
                                      const SizedBox(width: 10),
                                      SizedBox(width: 86, child: pointsField),
                                      const SizedBox(width: 10),
                                      Expanded(flex: 5, child: contentField),
                                      removeButton,
                                    ],
                                  );
                                },
                              ),
                            );
                          }),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => setState(
                                () => benefits.add(_EventBenefitDraft()),
                              ),
                              icon: const Icon(Icons.add),
                              label: const Text('Thêm quyền lợi'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _eventFormSection(
                        colors,
                        Icons.rule_outlined,
                        'Nội quy',
                        [
                          TextFormField(
                            controller: rulesController,
                            maxLines: 4,
                            maxLength: 3000,
                            decoration: _eventInputDecoration(
                              'Nội quy (mỗi dòng một nội quy)',
                              alignLabelWithHint: true,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
            actionsAlignment: MainAxisAlignment.end,
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Hủy'),
              ),
              FilledButton(
                onPressed: () async {
                  final timeError = _eventTimeError(
                    startTime,
                    endTime,
                    isEditing,
                  );
                  final attendancePeriodError = _attendancePeriodError(
                    attendancePeriods,
                    startTime,
                    endTime,
                  );
                  if (!formKey.currentState!.validate() ||
                      timeError != null ||
                      attendancePeriodError != null) {
                    final validationError = timeError ?? attendancePeriodError;
                    if (context.mounted && validationError != null) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(validationError)));
                    }
                    return;
                  }
                  try {
                    final eventName = nameController.text.trim();
                    final organizerId = selectedOrganizerId?.trim() ?? '';
                    final location = locationController.text.trim();
                    final capacity = int.parse(capacityController.text.trim());
                    final eventBenefits = benefits
                        .map((benefit) => benefit.toJson())
                        .toList();
                    final eventRules = rulesController.text
                        .split('\n')
                        .map((rule) => rule.trim())
                        .where((rule) => rule.isNotEmpty)
                        .toList();
                    final eventAttendancePeriods = attendancePeriods
                        .map((period) => period.toJson())
                        .toList();
                    if (isEditing) {
                      await controller.updateEvent(
                        id: event.id,
                        name: eventName,
                        organizerId: organizerId,
                        startTime: startTime,
                        endTime: endTime,
                        location: location,
                        capacity: capacity,
                        certificateEnabled: certificateEnabled,
                        attendanceThresholdPercent: attendanceThresholdPercent,
                        description: descriptionController.text.trim(),
                        benefits: eventBenefits,
                        rules: eventRules,
                        attendancePeriods: eventAttendancePeriods,
                      );
                    } else {
                      await controller.createEvent(
                        name: eventName,
                        organizerId: organizerId,
                        startTime: startTime,
                        endTime: endTime,
                        location: location,
                        capacity: capacity,
                        certificateEnabled: certificateEnabled,
                        attendanceThresholdPercent: attendanceThresholdPercent,
                        description: descriptionController.text.trim(),
                        benefits: eventBenefits,
                        rules: eventRules,
                        attendancePeriods: eventAttendancePeriods,
                      );
                    }
                  } catch (exception) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(exception.toString())),
                      );
                    }
                    return;
                  }
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
                child: Text(isEditing ? 'Cập nhật' : 'Lưu'),
              ),
            ],
          );
        },
      ),
    );
    nameController.dispose();
    descriptionController.dispose();
    rulesController.dispose();
    for (final benefit in benefits) {
      benefit.dispose();
    }
    for (final period in attendancePeriods) {
      period.dispose();
    }
    locationController.dispose();
    capacityController.dispose();
    organizerController.dispose();
  }

  // Trả về lỗi nếu khoảng thời gian tạo hoặc sửa không hợp lệ.
  static String? _eventTimeError(
    DateTime startTime,
    DateTime endTime,
    bool isEditing,
  ) {
    final now = DateTime.now();
    if (!endTime.isAfter(startTime)) {
      return 'Thời gian kết thúc phải sau thời gian bắt đầu.';
    }
    if (!isEditing && startTime.isBefore(now)) {
      return 'Thời gian bắt đầu không được ở quá khứ.';
    }
    if (isEditing && !endTime.isAfter(now)) {
      return 'Không thể chỉnh sửa sự kiện đã kết thúc.';
    }
    return null;
  }

  static String? _attendancePeriodError(
    List<_AttendancePeriodDraft> periods,
    DateTime eventStart,
    DateTime eventEnd,
  ) {
    if (periods.length > 12) {
      return 'Mỗi sự kiện có thể có tối đa 12 khung điểm danh.';
    }
    final ordered = [...periods]
      ..sort((left, right) => left.startTime.compareTo(right.startTime));
    for (var index = 0; index < ordered.length; index++) {
      final period = ordered[index];
      if (period.nameController.text.trim().isEmpty) {
        return 'Mỗi khung điểm danh cần có tên.';
      }
      if (!period.endTime.isAfter(period.startTime) ||
          period.startTime.isBefore(eventStart) ||
          period.endTime.isAfter(eventEnd)) {
        return 'Khung điểm danh phải nằm trong thời gian sự kiện và có giờ kết thúc sau giờ bắt đầu.';
      }
      if (index > 0 && period.startTime.isBefore(ordered[index - 1].endTime)) {
        return 'Các khung điểm danh không được chồng lấn nhau.';
      }
    }
    return null;
  }

  // Chỉ khóa chỉnh sửa khi sự kiện đã kết thúc hoặc đã lưu trữ.
  static bool _canEditEvent(OrganizerEventSummary event) {
    final now = DateTime.now();
    return !event.isArchived && event.endTime.isAfter(now);
  }

  static Widget _eventFormSection(
    AppColors colors,
    IconData icon,
    String title,
    List<Widget> children,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 19, color: colors.primary),
              const SizedBox(width: 8),
              Text(title, style: AppTextStyles.displaySm(colors.foreground)),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  static Widget _eventDateTile(
    AppColors colors,
    String label,
    String value,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: colors.muted.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 18,
                  color: colors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: AppTextStyles.bodyXs(colors.mutedForeground),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        value,
                        style: AppTextStyles.bodySm(colors.foreground)
                            .copyWith(fontWeight: FontWeight.w600),
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

  static InputDecoration _eventInputDecoration(
    String label, {
    bool alignLabelWithHint = false,
  }) {
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(11));
    return InputDecoration(
      labelText: label,
      alignLabelWithHint: alignLabelWithHint,
      border: border,
      enabledBorder: border,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  // Tạo ô nhập liệu và xác thực dữ liệu cơ bản của sự kiện.
  static Widget _field(
    TextEditingController controller,
    String label, {
    bool number = false,
    bool readOnly = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        readOnly: readOnly,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        decoration: _eventInputDecoration(label),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Vui lòng nhập $label';
          }
          if (number && (int.tryParse(value.trim()) ?? 0) <= 0) {
            return '$label phải là số nguyên dương';
          }
          return null;
        },
      ),
    );
  }

  // Hiển thị ô tìm kiếm và chọn đơn vị tổ chức.
  static Widget _unitField(
    List<OrganizerUnit> units,
    String? value,
    TextEditingController controller,
    ValueChanged<String?> onChanged,
  ) {
    // Cho phép tìm mã hoặc tên đơn vị và chọn từ danh sách gợi ý.
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FormField<String>(
        initialValue: value ?? '',
        validator: (selected) => selected == null || selected.trim().isEmpty
            ? 'Vui lòng nhập mã đơn vị tổ chức'
            : null,
        builder: (field) => Autocomplete<OrganizerUnit>(
          displayStringForOption: (unit) => unit.id,
          initialValue: TextEditingValue(text: value ?? ''),
          optionsBuilder: (textEditingValue) {
            final query = textEditingValue.text.trim().toLowerCase();
            if (query.isEmpty) return units;
            return units.where(
              (unit) =>
                  unit.id.toLowerCase().contains(query) ||
                  unit.name.toLowerCase().contains(query),
            );
          },
          onSelected: (unit) {
            controller.text = unit.id;
            field.didChange(unit.id);
            onChanged(unit.id);
          },
          optionsViewBuilder: (context, onSelected, options) => Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final unit = options.elementAt(index);
                    return ListTile(
                      title: Text(unit.id),
                      subtitle: Text(unit.name),
                      onTap: () => onSelected(unit),
                    );
                  },
                ),
              ),
            ),
          ),
          fieldViewBuilder: (context, textController, focusNode, onSubmitted) {
            controller.value = textController.value;
            return TextFormField(
              controller: textController,
              focusNode: focusNode,
              onChanged: (text) {
                controller.value = textController.value;
                field.didChange(text);
                onChanged(text.trim().isEmpty ? null : text.trim());
              },
              onFieldSubmitted: (_) => onSubmitted(),
              decoration: _eventInputDecoration('Mã đơn vị tổ chức').copyWith(
                hintText: 'Nhập mã, ví dụ: DVK',
                errorText: field.errorText,
                suffixIcon: IconButton(
                  tooltip: 'Xem danh sách đơn vị',
                  icon: const Icon(Icons.arrow_drop_down),
                  onPressed: focusNode.requestFocus,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // Yêu cầu xác nhận trước khi xóa sự kiện.
  Future<void> _confirmDelete(
    BuildContext context,
    OrganizerEventsController controller,
    OrganizerEventSummary event,
  ) async {
    // Chỉ gửi yêu cầu xóa sau khi người dùng xác nhận.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa sự kiện?'),
        content: Text('Bạn có chắc muốn xóa "${event.name}" không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await controller.deleteEvent(event.id);
    } catch (exception) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    }
  }

  Future<void> _confirmClose(
    BuildContext context,
    OrganizerEventsController controller,
    OrganizerEventSummary event,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Đóng sự kiện?'),
        content: Text(
          'Sự kiện "${event.name}" sẽ được đưa vào mục đã đóng. '
          'Bạn vẫn có thể xem chi tiết và xóa sự kiện.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Đóng sự kiện'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await controller.closeEvent(event.id);
    } catch (exception) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    }
  }

  // Chọn ngày và giờ cho một mốc thời gian sự kiện.
  static Future<DateTime?> _pickDateTime(
    BuildContext context,
    DateTime initial,
  ) async {
    // Cho phép chọn ngày cũ khi sửa sự kiện đã diễn ra.
    final today = DateUtils.dateOnly(DateTime.now());
    final initialDate = DateUtils.dateOnly(initial);
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: initialDate.isBefore(today) ? initialDate : today,
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date == null || !context.mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  // Hiển thị thông báo lỗi tải dữ liệu.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}
