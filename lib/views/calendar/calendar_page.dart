import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/role.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/models/calendar_model.dart';
import '../../data/models/event_model.dart';
import '../../data/models/student_summaries.dart';
import '../../data/repositories/class_repository.dart';
import '../../data/repositories/event_repository.dart';

enum _CalendarView { day, week, month }

class CalendarPage extends StatefulWidget {
  final Role role;
  final void Function({required bool isEvent}) onOpenAttendance;

  const CalendarPage({
    super.key,
    required this.role,
    required this.onOpenAttendance,
  });

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  final ClassRepository _classRepository = ClassRepository();
  final EventRepository _eventRepository = EventRepository();
  final List<CalendarClass> _classes = [];
  final List<_CalendarEntry> _events = [];
  DateTime _selectedDate = DateUtils.dateOnly(DateTime.now());
  _CalendarView _view = _CalendarView.week;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final classes = <CalendarClass>[];
      final events = <_CalendarEntry>[];

      if (widget.role == Role.organizer) {
        final organizerEvents = await _eventRepository.getOrganizerEvents();
        events.addAll(organizerEvents.map(_organizerEventEntry));
      } else {
        final results = await Future.wait([
          _classRepository.getCalendarClasses(),
          _eventRepository.getEvents(),
        ]);
        classes.addAll(results[0] as List<CalendarClass>);
        final registeredEvents = results[1] as List<StudentEventSummary>;
        events.addAll(
          registeredEvents
              .where((event) => event.registered)
              .map(_studentEventEntry),
        );
      }

      if (!mounted) return;
      setState(() {
        _classes
          ..clear()
          ..addAll(classes);
        _events
          ..clear()
          ..addAll(events);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _classes.clear();
        _events.clear();
        _error = error.toString();
        _loading = false;
      });
    }
  }

  _CalendarEntry _studentEventEntry(StudentEventSummary event) =>
      _CalendarEntry(
        id: event.id,
        title: event.name,
        start: event.startTime ?? DateTime.tryParse(event.date)?.toLocal(),
        end: event.endTime,
        location: event.location,
        organizer: event.org,
        isEvent: true,
      );

  _CalendarEntry _organizerEventEntry(OrganizerEventSummary event) =>
      _CalendarEntry(
        id: event.id,
        title: event.name,
        start: event.startTime,
        end: event.endTime,
        location: event.location,
        organizer: event.organizerId,
        isEvent: true,
      );

  List<_CalendarEntry> _entriesOn(DateTime date) {
    final entries = _events
        .where((entry) => entry.start != null && _sameDate(entry.start!, date))
        .toList();
    for (final classItem in _classes) {
      for (final schedule in classItem.schedules) {
        if (schedule.weekday != date.weekday) continue;
        final day = DateUtils.dateOnly(date);
        if (schedule.startsOn != null && day.isBefore(schedule.startsOn!)) {
          continue;
        }
        if (schedule.endsOn != null && day.isAfter(schedule.endsOn!)) {
          continue;
        }
        final startTime = _parseTime(schedule.startTime);
        if (startTime == null) continue;
        final endTime = _parseTime(schedule.endTime);
        entries.add(
          _CalendarEntry(
            id: classItem.id,
            title: classItem.name,
            start: DateTime(
              date.year,
              date.month,
              date.day,
              startTime.$1,
              startTime.$2,
            ),
            end: endTime == null
                ? null
                : DateTime(
                    date.year,
                    date.month,
                    date.day,
                    endTime.$1,
                    endTime.$2,
                  ),
            location: schedule.room,
            subtitle: classItem.subjectName,
            organizer: classItem.lecturerName,
            isEvent: false,
          ),
        );
      }
    }
    entries.sort((a, b) => a.start!.compareTo(b.start!));
    return entries;
  }

  static (int, int)? _parseTime(String value) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(value.trim());
    if (match == null) return null;
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return null;
    }
    return (hour, minute);
  }

  static bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _weekdayShort(int weekday) => switch (weekday) {
    1 => 'T2',
    2 => 'T3',
    3 => 'T4',
    4 => 'T5',
    5 => 'T6',
    6 => 'T7',
    7 => 'CN',
    _ => '',
  };

  static String _weekdayLong(int weekday) => switch (weekday) {
    1 => 'Thứ 2',
    2 => 'Thứ 3',
    3 => 'Thứ 4',
    4 => 'Thứ 5',
    5 => 'Thứ 6',
    6 => 'Thứ 7',
    7 => 'Chủ nhật',
    _ => '',
  };

  void _changePeriod(int amount) {
    final days = _view == _CalendarView.day ? amount : amount * 7;
    setState(() {
      _selectedDate = DateUtils.dateOnly(
        _selectedDate.add(Duration(days: days)),
      );
    });
  }

  Future<void> _chooseMonth() async {
    var year = _selectedDate.year;
    final selectedMonth = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              IconButton(
                tooltip: 'Năm trước',
                onPressed: () => setDialogState(() => year--),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '$year',
                    style: AppTextStyles.displaySm(
                      AppColors.of(
                        Theme.of(context).brightness == Brightness.dark,
                      ).foreground,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Năm sau',
                onPressed: () => setDialogState(() => year++),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          content: SizedBox(
            width: 300,
            child: GridView.count(
              shrinkWrap: true,
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.8,
              children: List.generate(12, (index) {
                final month = index + 1;
                return OutlinedButton(
                  onPressed: () => Navigator.pop(dialogContext, month),
                  child: Text('Tháng $month'),
                );
              }),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Hủy'),
            ),
          ],
        ),
      ),
    );
    if (selectedMonth == null || !mounted) return;
    setState(() {
      _selectedDate = DateTime(year, selectedMonth, 1);
      _view = _CalendarView.month;
    });
  }

  Future<void> _showDetails(_CalendarEntry entry) async {
    final colors = AppColors.of(
      Theme.of(context).brightness == Brightness.dark,
    );
    final isStudent = widget.role == Role.student;
    final detailFuture = entry.isEvent
        ? _eventRepository.getEventDetails(entry.id)
        : null;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.card,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.72,
        child: FutureBuilder<Map<String, dynamic>>(
          future: detailFuture,
          builder: (context, snapshot) {
            final details = snapshot.data;
            final title = details?['name']?.toString() ?? entry.title;
            final description = details?['description']?.toString() ?? '';
            final organizer =
                details?['organizerName']?.toString() ?? entry.organizer;
            final location = details?['location']?.toString() ?? entry.location;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                Row(
                  children: [
                    Icon(
                      entry.isEvent
                          ? Icons.event_available_outlined
                          : Icons.menu_book_outlined,
                      color: entry.isEvent ? colors.warning : colors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        entry.isEvent ? 'Sự kiện' : 'Lớp học',
                        style: AppTextStyles.bodySm(colors.mutedForeground),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Đóng chi tiết',
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(title, style: AppTextStyles.displayLg(colors.foreground)),
                if (entry.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    entry.subtitle,
                    style: AppTextStyles.bodySm(colors.mutedForeground),
                  ),
                ],
                if (entry.isEvent &&
                    snapshot.connectionState != ConnectionState.done) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                ],
                if (entry.isEvent && snapshot.hasError) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Không tải được mô tả sự kiện: ${snapshot.error}',
                    style: AppTextStyles.bodySm(colors.danger),
                  ),
                ],
                if (description.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    description,
                    style: AppTextStyles.bodySm(colors.foreground)
                        .copyWith(height: 1.5),
                  ),
                ],
                const SizedBox(height: 18),
                _DetailLine(
                  icon: Icons.schedule_outlined,
                  label: 'Thời gian',
                  value: _formatTime(entry),
                  colors: colors,
                ),
                _DetailLine(
                  icon: Icons.location_on_outlined,
                  label: 'Địa điểm',
                  value: location.trim().isEmpty ? 'Chưa cập nhật' : location,
                  colors: colors,
                ),
                _DetailLine(
                  icon: entry.isEvent
                      ? Icons.apartment_outlined
                      : Icons.person_outline,
                  label: entry.isEvent ? 'Đơn vị tổ chức' : 'Giảng viên',
                  value: organizer.trim().isEmpty ? 'Chưa cập nhật' : organizer,
                  colors: colors,
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      widget.onOpenAttendance(isEvent: entry.isEvent);
                    },
                    icon: const Icon(Icons.qr_code_scanner),
                    label: Text(isStudent ? 'Điểm danh' : 'Mở điểm danh'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _formatTime(_CalendarEntry entry) {
    final start = entry.start;
    if (start == null) return 'Chưa cập nhật';
    final date = DateFormat('dd/MM/yyyy').format(start);
    final time = DateFormat('HH:mm').format(start);
    final end = entry.end;
    return end == null
        ? '$date · $time'
        : '$date · $time–${DateFormat('HH:mm').format(end)}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(
      Theme.of(context).brightness == Brightness.dark,
    );
    final selectedEntries = _entriesOn(_selectedDate);
    final weekDates = _weekDates;
    return RefreshIndicator(
      onRefresh: _load,
      child: LayoutBuilder(
        builder: (context, constraints) => Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: constraints.maxWidth > 900 ? 900 : constraints.maxWidth,
            ),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Lịch học / lịch sự kiện',
                        style: AppTextStyles.displayLg(colors.foreground),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Tải lại lịch',
                      onPressed: _loading ? null : _load,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildCalendarControls(colors),
                const SizedBox(height: 12),
                if (_view == _CalendarView.month) ...[
                  _buildMonthCalendar(colors),
                  const SizedBox(height: 16),
                ] else if (_view == _CalendarView.week) ...[
                  _buildWeekSelector(colors, weekDates),
                  const SizedBox(height: 16),
                ],
                _buildSelectedDayHeading(colors, selectedEntries.length),
                const SizedBox(height: 10),
                if (_loading && _classes.isEmpty && _events.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  _buildError(colors)
                else if (selectedEntries.isEmpty)
                  _buildEmpty(colors)
                else
                  ...selectedEntries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _EntryCard(
                        entry: entry,
                        colors: colors,
                        onTap: () => _showDetails(entry),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<DateTime> get _weekDates {
    final monday = DateUtils.dateOnly(
      _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1)),
    );
    return List.generate(7, (index) => monday.add(Duration(days: index)));
  }

  Widget _buildCalendarControls(AppColors colors) => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _chooseMonth,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        'Tháng ${_selectedDate.month}, ${_selectedDate.year}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.displaySm(colors.foreground),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_drop_down, color: colors.mutedForeground),
                  ],
                ),
              ),
            ),
          ),
          SegmentedButton<_CalendarView>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _CalendarView.day, label: Text('Ngày')),
              ButtonSegment(value: _CalendarView.week, label: Text('Tuần')),
              ButtonSegment(value: _CalendarView.month, label: Text('Tháng')),
            ],
            selected: {_view},
            onSelectionChanged: (selection) {
              setState(() => _view = selection.first);
            },
          ),
        ],
      ),
      _buildPeriodNavigation(colors),
    ],
  );

  Widget _buildPeriodNavigation(AppColors colors) {
    final dates = _weekDates;
    final title = _view == _CalendarView.day
        ? '${_weekdayLong(_selectedDate.weekday)}, '
              '${DateFormat('dd/MM/yyyy').format(_selectedDate)}'
        : '${DateFormat('dd/MM').format(dates.first)}'
              ' – ${DateFormat('dd/MM/yyyy').format(dates.last)}';
    return Row(
      children: [
        IconButton(
          tooltip: _view == _CalendarView.day ? 'Ngày trước' : 'Tuần trước',
          visualDensity: VisualDensity.compact,
          onPressed: () => _changePeriod(-1),
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Center(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySm(colors.mutedForeground),
            ),
          ),
        ),
        TextButton(
          onPressed: () => setState(
            () => _selectedDate = DateUtils.dateOnly(DateTime.now()),
          ),
          child: const Text('Hôm nay'),
        ),
        IconButton(
          tooltip: _view == _CalendarView.day ? 'Ngày sau' : 'Tuần sau',
          visualDensity: VisualDensity.compact,
          onPressed: () => _changePeriod(1),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  Widget _buildWeekSelector(AppColors colors, List<DateTime> dates) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: colors.card,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: dates.map((date) {
            final selected = _sameDate(date, _selectedDate);
            final entries = _entriesOn(date);
            return Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _selectedDate = date),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      Text(
                        _weekdayShort(date.weekday),
                        style: AppTextStyles.bodyXs(
                          date.weekday >= 6
                              ? colors.danger
                              : colors.mutedForeground,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 34,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected ? colors.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Text(
                          '${date.day}',
                          style: AppTextStyles.bodySm(
                            selected
                                ? colors.primaryForeground
                                : colors.foreground,
                          ).copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (entries.isNotEmpty)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: entries.take(3).map((entry) {
                            return Container(
                              width: 4,
                              height: 4,
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              decoration: BoxDecoration(
                                color: entry.isEvent
                                    ? colors.warning
                                    : colors.success,
                                shape: BoxShape.circle,
                              ),
                            );
                          }).toList(),
                        )
                      else
                        const SizedBox(height: 4),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      );

  Widget _buildSelectedDayHeading(AppColors colors, int count) => Row(
    children: [
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: colors.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${_weekdayLong(_selectedDate.weekday)}, '
            '${DateFormat('dd/MM').format(_selectedDate)}',
            style: AppTextStyles.bodySm(colors.primaryForeground)
                .copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ),
      const SizedBox(width: 10),
      Text('$count buổi', style: AppTextStyles.bodySm(colors.mutedForeground)),
    ],
  );

  Widget _buildMonthCalendar(AppColors colors) {
    final firstDay = DateTime(_selectedDate.year, _selectedDate.month);
    final offset = firstDay.weekday - 1;
    final dayCount = DateUtils.getDaysInMonth(
      _selectedDate.year,
      _selectedDate.month,
    );
    final cellCount = ((offset + dayCount + 6) ~/ 7) * 7;
    final rowCount = cellCount ~/ 7;
    const weekdays = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Center(
                  child: Text(
                    'Tháng ${_selectedDate.month}, ${_selectedDate.year}',
                    style: AppTextStyles.displaySm(colors.foreground),
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  final today = DateUtils.dateOnly(DateTime.now());
                  setState(() {
                    _selectedDate = today;
                  });
                },
                child: const Text('Hôm nay'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: weekdays
                .map(
                  (day) => Expanded(
                    child: Center(
                      child: Text(
                        day,
                        style: AppTextStyles.bodyXs(colors.mutedForeground),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: rowCount * 42,
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cellCount,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
                mainAxisExtent: 40,
              ),
              itemBuilder: (context, index) {
                final dayNumber = index - offset + 1;
                if (dayNumber < 1 || dayNumber > dayCount) {
                  return const SizedBox.shrink();
                }
                final date = DateTime(
                  _selectedDate.year,
                  _selectedDate.month,
                  dayNumber,
                );
                final entries = _entriesOn(date);
                final selected = _sameDate(date, _selectedDate);
                final today = _sameDate(date, DateTime.now());
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => _selectedDate = date),
                  child: Container(
                    decoration: BoxDecoration(
                      color: selected ? colors.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: today && !selected
                          ? Border.all(color: colors.primary)
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$dayNumber',
                          style: AppTextStyles.bodySm(
                            selected
                                ? colors.primaryForeground
                                : colors.foreground,
                          ).copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        if (entries.isNotEmpty)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: entries.take(3).map((entry) {
                              final color = entry.isEvent
                                  ? colors.warning
                                  : selected
                                  ? colors.primaryForeground
                                  : colors.success;
                              return Container(
                                width: 4,
                                height: 4,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                              );
                            }).toList(),
                          )
                        else
                          const SizedBox(height: 4),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _LegendDot(color: colors.primary, label: 'Lớp học'),
              const SizedBox(width: 18),
              _LegendDot(color: colors.warning, label: 'Sự kiện'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildError(AppColors colors) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: colors.card,
      border: Border.all(color: colors.border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        Text(
          'Không tải được lịch: $_error',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySm(colors.danger),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Thử lại'),
        ),
      ],
    ),
  );

  Widget _buildEmpty(AppColors colors) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: colors.card,
      border: Border.all(color: colors.border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        Icon(
          Icons.event_busy_outlined,
          size: 30,
          color: colors.mutedForeground,
        ),
        const SizedBox(height: 8),
        Text(
          'Không có lịch trong ngày này.',
          style: AppTextStyles.bodySm(colors.mutedForeground),
        ),
      ],
    ),
  );
}

class _CalendarEntry {
  final String id;
  final String title;
  final DateTime? start;
  final DateTime? end;
  final String location;
  final String subtitle;
  final String organizer;
  final bool isEvent;

  const _CalendarEntry({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    required this.location,
    this.subtitle = '',
    required this.organizer,
    required this.isEvent,
  });
}

class _EntryCard extends StatelessWidget {
  final _CalendarEntry entry;
  final AppColors colors;
  final VoidCallback onTap;

  const _EntryCard({
    required this.entry,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = entry.isEvent ? colors.warning : colors.success;
    final start = entry.start;
    final end = entry.end;
    final time = start == null
        ? 'Chưa cập nhật'
        : '${DateFormat('HH:mm').format(start)}'
              '${end == null ? '' : ' – ${DateFormat('HH:mm').format(end)}'}';
    final details = entry.isEvent
        ? [
            ('Thời gian', time),
            ('Địa điểm', entry.location),
            ('Đơn vị', entry.organizer),
          ]
        : [
            ('Thời gian', time),
            ('Phòng', entry.location),
            ('Giảng viên', entry.organizer),
          ];
    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(
                  width: 6,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.displaySm(colors.foreground),
                      ),
                      if (entry.subtitle.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          entry.subtitle,
                          style: AppTextStyles.bodyXs(colors.mutedForeground),
                        ),
                      ],
                      const SizedBox(height: 8),
                      ...details
                          .where((detail) => detail.$2.trim().isNotEmpty)
                          .map(
                            (detail) => Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 86,
                                    child: Text(
                                      '${detail.$1}:',
                                      style: AppTextStyles.bodySm(
                                        colors.mutedForeground,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      detail.$2,
                                      style: AppTextStyles.bodySm(
                                        colors.foreground,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, color: colors.mutedForeground),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final AppColors colors;

  const _DetailLine({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: colors.primary),
        const SizedBox(width: 10),
        SizedBox(
          width: 94,
          child: Text(
            label,
            style: AppTextStyles.bodySm(colors.mutedForeground),
          ),
        ),
        Expanded(
          child: Text(value, style: AppTextStyles.bodySm(colors.foreground)),
        ),
      ],
    ),
  );
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: AppTextStyles.bodyXs(
          AppColors.of(Theme.of(context).brightness == Brightness.dark)
              .mutedForeground,
        ),
      ),
    ],
  );
}
