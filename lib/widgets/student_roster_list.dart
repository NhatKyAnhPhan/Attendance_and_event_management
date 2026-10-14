import 'package:flutter/material.dart';

import '../core/theme/app_text_styles.dart';
import '../data/models/student_roster_entry.dart';

class StudentRosterList extends StatefulWidget {
  final List<StudentRosterEntry> students;
  final Color mutedColor;
  final Color dividerColor;
  final String emptyMessage;

  const StudentRosterList({
    super.key,
    required this.students,
    required this.mutedColor,
    required this.dividerColor,
    required this.emptyMessage,
  });

  @override
  State<StudentRosterList> createState() => _StudentRosterListState();
}

class _StudentRosterListState extends State<StudentRosterList> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = theme.colorScheme.surface;
    final primary = theme.colorScheme.primary;

    if (widget.students.isEmpty) {
      return Center(
        child: Text(
          widget.emptyMessage,
          style: AppTextStyles.bodySm(widget.mutedColor),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.only(right: 10),
        itemCount: widget.students.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final student = widget.students[index];
          return Container(
            decoration: BoxDecoration(
              color: cardColor,
              border: Border.all(color: widget.dividerColor),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 6,
              ),
              leading: CircleAvatar(
                backgroundColor: primary.withValues(alpha: 0.1),
                foregroundColor: primary,
                child: Text(
                  student.studentName.isEmpty
                      ? '?'
                      : student.studentName.characters.first.toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              title: Text(
                student.studentName.isEmpty
                    ? student.studentId
                    : student.studentName,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  [
                    student.studentId,
                    if (student.email.isNotEmpty) student.email,
                    if (student.dateLabel.isNotEmpty) student.dateLabel,
                  ].join(' · '),
                  style: AppTextStyles.bodyXs(widget.mutedColor),
                ),
              ),
              trailing:
                  student.status.isEmpty && student.attendanceStatus.isEmpty
                  ? null
                  : Wrap(
                      direction: Axis.vertical,
                      spacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.end,
                      children: [
                        if (student.status.isNotEmpty)
                          _statusChip(
                            student.status,
                            primary,
                            primary.withValues(alpha: 0.09),
                          ),
                        if (student.attendanceStatus.isNotEmpty)
                          _statusChip(
                            student.attendanceStatus,
                            student.attendanceStatus == 'Đã điểm danh QR'
                                ? primary
                                : widget.mutedColor,
                            student.attendanceStatus == 'Đã điểm danh QR'
                                ? primary.withValues(alpha: 0.09)
                                : widget.dividerColor.withValues(alpha: 0.45),
                          ),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }

  Widget _statusChip(String label, Color foreground, Color background) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTextStyles.bodyXs(foreground)
            .copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}
