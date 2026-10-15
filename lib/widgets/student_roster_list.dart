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
        padding: EdgeInsets.only(
          right: 10,
          bottom: 8 + MediaQuery.paddingOf(context).bottom,
        ),
        itemCount: widget.students.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final student = widget.students[index];
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cardColor,
              border: Border.all(color: widget.dividerColor),
              borderRadius: BorderRadius.circular(12),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth <= 430;
                final hasStatus =
                    student.status.isNotEmpty ||
                    student.attendanceStatus.isNotEmpty;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 21,
                          backgroundColor: primary.withValues(alpha: 0.1),
                          foregroundColor: primary,
                          child: Text(
                            student.studentName.isEmpty
                                ? '?'
                                : student.studentName.characters.first
                                      .toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.w700),
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
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                student.studentId,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.bodyXs(widget.mutedColor),
                              ),
                              if (student.email.isNotEmpty)
                                Text(
                                  student.email,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.bodyXs(
                                    widget.mutedColor,
                                  ),
                                ),
                              if (student.dateLabel.isNotEmpty)
                                Text(
                                  student.dateLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.bodyXs(
                                    widget.mutedColor,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (hasStatus && !narrow) ...[
                          const SizedBox(width: 10),
                          Flexible(child: _statusWrap(student, primary)),
                        ],
                      ],
                    ),
                    if (hasStatus && narrow) ...[
                      const SizedBox(height: 9),
                      Padding(
                        padding: const EdgeInsets.only(left: 54),
                        child: _statusWrap(student, primary),
                      ),
                    ],
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _statusWrap(StudentRosterEntry student, Color primary) {
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: 6,
        runSpacing: 5,
        alignment: WrapAlignment.end,
        children: [
          if (student.status.isNotEmpty)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth),
              child: _statusChip(
                student.status,
                primary,
                primary.withValues(alpha: 0.09),
              ),
            ),
          if (student.attendanceStatus.isNotEmpty)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth),
              child: _statusChip(
                student.attendanceStatus,
                student.attendanceStatus == 'Đã điểm danh QR'
                    ? primary
                    : widget.mutedColor,
                student.attendanceStatus == 'Đã điểm danh QR'
                    ? primary.withValues(alpha: 0.09)
                    : widget.dividerColor.withValues(alpha: 0.45),
              ),
            ),
        ],
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
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.bodyXs(foreground)
            .copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}
