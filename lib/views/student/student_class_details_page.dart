import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/models/student_class_detail.dart';
import '../../data/repositories/class_repository.dart';

class StudentClassDetailsPage extends StatefulWidget {
  final String classId;

  const StudentClassDetailsPage({super.key, required this.classId});

  @override
  State<StudentClassDetailsPage> createState() =>
      _StudentClassDetailsPageState();
}

class _StudentClassDetailsPageState extends State<StudentClassDetailsPage> {
  final ClassRepository _repository = ClassRepository();
  late Future<StudentClassDetail> _detailFuture;

  @override
  void initState() {
    super.initState();
    _detailFuture = _repository.getStudentClassDetail(widget.classId);
  }

  void _reload() {
    setState(() {
      _detailFuture = _repository.getStudentClassDetail(widget.classId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = AppColors.of(isDark);
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Chi tiết lớp học'),
        backgroundColor: colors.card,
        foregroundColor: colors.foreground,
      ),
      body: FutureBuilder<StudentClassDetail>(
        future: _detailFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      snapshot.error?.toString() ??
                          'Không thể tải chi tiết lớp học.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySm(colors.mutedForeground),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Thử lại'),
                    ),
                  ],
                ),
              ),
            );
          }
          return _buildDetails(snapshot.data!, colors);
        },
      ),
    );
  }

  Widget _buildDetails(StudentClassDetail detail, AppColors colors) {
    final semesterLabel = [
      detail.semester,
      detail.academicYear,
    ].where((value) => value.isNotEmpty).join(' · ');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: colors.card,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: colors.secondary,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  detail.id,
                  style: AppTextStyles.mono(colors.primary, fontSize: 12),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                detail.name,
                style: AppTextStyles.displayMd(colors.foreground),
              ),
              if (detail.subjectName.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  detail.subjectName,
                  style: AppTextStyles.bodySm(colors.mutedForeground),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _DetailSection(
          title: 'Thông tin lớp học',
          colors: colors,
          children: [
            _DetailRow(
              icon: Icons.account_balance_outlined,
              label: 'Khoa',
              value: detail.departmentName.isEmpty
                  ? 'Chưa cập nhật'
                  : detail.departmentName,
              colors: colors,
            ),
            _DetailRow(
              icon: Icons.person_outline,
              label: 'Giảng viên',
              value: detail.lecturerName.isEmpty
                  ? 'Chưa phân công'
                  : detail.lecturerName,
              colors: colors,
            ),
            _DetailRow(
              icon: Icons.menu_book_outlined,
              label: 'Môn học',
              value: detail.subjectName.isEmpty
                  ? detail.subjectId
                  : detail.subjectName,
              colors: colors,
            ),
            _DetailRow(
              icon: Icons.calendar_month_outlined,
              label: 'Học kỳ / năm học',
              value: semesterLabel.isEmpty ? 'Chưa cập nhật' : semesterLabel,
              colors: colors,
            ),
            _DetailRow(
              icon: Icons.school_outlined,
              label: 'Tín chỉ',
              value: '${detail.credits}',
              colors: colors,
            ),
            _DetailRow(
              icon: Icons.groups_outlined,
              label: 'Sĩ số',
              value: '${detail.studentCount}/${detail.capacity} sinh viên',
              colors: colors,
            ),
            _DetailRow(
              icon: Icons.info_outline,
              label: 'Trạng thái',
              value: detail.status.isEmpty ? 'Chưa cập nhật' : detail.status,
              colors: colors,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _DetailSection(
          title: 'Lịch học và phòng học',
          colors: colors,
          children: detail.schedules.isEmpty
              ? [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Lớp chưa được xếp lịch học.',
                      style: AppTextStyles.bodySm(colors.mutedForeground),
                    ),
                  ),
                ]
              : detail.schedules
                    .map(
                      (schedule) =>
                          _ScheduleRow(schedule: schedule, colors: colors),
                    )
                    .toList(),
        ),
        const SizedBox(height: 14),
        _DetailSection(
          title: 'Kết quả điểm danh từng buổi',
          colors: colors,
          children: detail.attendanceSessions.isEmpty
              ? [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Chưa có buổi điểm danh nào.',
                      style: AppTextStyles.bodySm(colors.mutedForeground),
                    ),
                  ),
                ]
              : detail.attendanceSessions
                    .map(
                      (session) => _AttendanceSessionRow(
                        session: session,
                        colors: colors,
                      ),
                    )
                    .toList(),
        ),
        const SizedBox(height: 14),
        StudentClassFeedback(classId: detail.id, colors: colors),
        const SizedBox(height: 14),
        _DetailSection(
          title: 'Danh sách sinh viên (${detail.students.length})',
          colors: colors,
          children: detail.students.isEmpty
              ? [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Lớp chưa có sinh viên.',
                      style: AppTextStyles.bodySm(colors.mutedForeground),
                    ),
                  ),
                ]
              : detail.students
                    .map(
                      (student) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: colors.secondary,
                              foregroundColor: colors.primary,
                              child: Text(
                                student.studentName.isEmpty
                                    ? '?'
                                    : student.studentName.characters.first
                                          .toUpperCase(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    student.studentName.isEmpty
                                        ? student.studentId
                                        : student.studentName,
                                    style: AppTextStyles.displayXs(
                                      colors.foreground,
                                    ),
                                  ),
                                  Text(
                                    student.studentId,
                                    style: AppTextStyles.bodyXs(
                                      colors.mutedForeground,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (student.status.isNotEmpty)
                              Text(
                                student.status,
                                style: AppTextStyles.bodyXs(
                                  colors.mutedForeground,
                                ),
                              ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
        ),
      ],
    );
  }
}

class _AttendanceSessionRow extends StatelessWidget {
  final StudentClassAttendance session;
  final AppColors colors;

  const _AttendanceSessionRow({required this.session, required this.colors});

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (session.status) {
      'Có mặt' => colors.success,
      'Đi trễ' => colors.warning,
      'Vắng mặt' => colors.danger,
      _ => colors.primary,
    };
    final details = [
      if (session.startTime.isNotEmpty) session.startTime,
      if (session.checkedInAt.isNotEmpty)
        'Điểm danh lúc ${session.checkedInAt}',
      if (session.method.isNotEmpty) 'Hình thức ${session.method}',
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.fact_check_outlined, size: 20, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.name.isEmpty ? 'Buổi học' : session.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.displayXs(colors.foreground),
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    details.join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyXs(colors.mutedForeground),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              session.status,
              style: AppTextStyles.bodyXs(statusColor)
                  .copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class StudentClassFeedback extends StatefulWidget {
  const StudentClassFeedback({super.key, required this.classId, required this.colors});

  final String classId;
  final AppColors colors;

  @override
  State<StudentClassFeedback> createState() => _StudentClassFeedbackState();
}

class _StudentClassFeedbackState extends State<StudentClassFeedback> {
  final ClassRepository _repository = ClassRepository();
  late Future<Map<String, dynamic>> _feedbackFuture;

  @override
  void initState() {
    super.initState();
    _feedbackFuture = _repository.getClassFeedback(widget.classId);
  }

  void _reload() {
    setState(() => _feedbackFuture = _repository.getClassFeedback(widget.classId));
  }

  Future<void> _openForm({required bool ratingMode}) async {
    final commentController = TextEditingController();
    var rating = 0;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(ratingMode ? 'Đánh giá lớp học' : 'Gửi phản hồi'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (ratingMode) ...[
                const Text('Mức độ hài lòng của bạn'),
                const SizedBox(height: 8),
                Wrap(
                  children: List.generate(5, (index) {
                    final value = index + 1;
                    return IconButton(
                      tooltip: '$value sao',
                      onPressed: () => setDialogState(() => rating = value),
                      icon: Icon(value <= rating ? Icons.star : Icons.star_border, color: Colors.amber),
                    );
                  }),
                ),
              ],
              TextField(
                controller: commentController,
                minLines: 3,
                maxLines: 5,
                maxLength: 2000,
                decoration: InputDecoration(
                  labelText: ratingMode ? 'Nhận xét thêm' : 'Nội dung phản hồi',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Hủy')),
            FilledButton(
              onPressed: () async {
                final comment = commentController.text.trim();
                if (ratingMode && rating == 0) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng chọn số sao.')));
                  return;
                }
                if (!ratingMode && comment.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng nhập nội dung phản hồi.')));
                  return;
                }
                try {
                  if (ratingMode) {
                    await _repository.submitClassRating(classId: widget.classId, rating: rating, comment: comment);
                  } else {
                    await _repository.submitClassComment(classId: widget.classId, comment: comment);
                  }
                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                } catch (error) {
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('Không thể gửi: $error')));
                }
              },
              child: const Text('Gửi'),
            ),
          ],
        ),
      ),
    );
    commentController.dispose();
    if (submitted == true && mounted) {
      _reload();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã gửi ý kiến của bạn.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: c.card, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(14)),
      child: FutureBuilder<Map<String, dynamic>>(
        future: _feedbackFuture,
        builder: (context, snapshot) {
          final data = snapshot.data ?? const <String, dynamic>{};
          final rawItems = data['items'];
          final items = rawItems is List ? rawItems.whereType<Map>().toList() : <Map>[];
          final count = (data['ratingCount'] as num?)?.toInt() ?? 0;
          final average = (data['averageRating'] as num?)?.toDouble() ?? 0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Đánh giá & phản hồi lớp học', style: AppTextStyles.displayXs(c.foreground)),
              const SizedBox(height: 6),
              if (snapshot.connectionState == ConnectionState.waiting)
                const LinearProgressIndicator()
              else if (snapshot.hasError)
                Text('Không tải được đánh giá: ${snapshot.error}', style: AppTextStyles.bodySm(c.danger))
              else ...[
                Text(count > 0 ? '${average.toStringAsFixed(1)} / 5 sao · $count lượt đánh giá' : 'Chưa có lượt đánh giá.', style: AppTextStyles.bodySm(c.mutedForeground)),
                for (final item in items.take(5))
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text('${item['rating'] == null ? '' : '${item['rating']} / 5 ★ · '}${item['comment'] ?? item['content'] ?? ''}', style: AppTextStyles.bodySm(c.foreground)),
                  ),
              ],
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(onPressed: () => _openForm(ratingMode: false), icon: const Icon(Icons.chat_bubble_outline), label: const Text('Gửi phản hồi')),
                OutlinedButton.icon(onPressed: () => _openForm(ratingMode: true), icon: const Icon(Icons.star_outline), label: const Text('Đánh giá')),
                if (snapshot.hasError) IconButton(onPressed: _reload, icon: const Icon(Icons.refresh), tooltip: 'Tải lại'),
              ]),
            ],
          );
        },
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final AppColors colors;
  final List<Widget> children;

  const _DetailSection({
    required this.title,
    required this.colors,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.displaySm(colors.foreground)),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final AppColors colors;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: colors.primary),
          const SizedBox(width: 10),
          SizedBox(
            width: 125,
            child: Text(
              label,
              style: AppTextStyles.bodySm(colors.mutedForeground),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.bodySm(colors.foreground),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  final StudentClassSchedule schedule;
  final AppColors colors;

  const _ScheduleRow({required this.schedule, required this.colors});

  @override
  Widget build(BuildContext context) {
    final dateRange = [
      schedule.startsOn,
      schedule.endsOn,
    ].where((value) => value.isNotEmpty).join(' - ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.schedule_outlined, size: 19, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${schedule.weekdayLabel} · ${schedule.startTime} - ${schedule.endTime}',
                  style: AppTextStyles.bodySm(colors.foreground),
                ),
                const SizedBox(height: 3),
                Text(
                  '${schedule.room.isEmpty ? 'Chưa xếp phòng' : 'Phòng ${schedule.room}'}'
                  '${dateRange.isEmpty ? '' : ' · $dateRange'}',
                  style: AppTextStyles.bodyXs(colors.mutedForeground),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
