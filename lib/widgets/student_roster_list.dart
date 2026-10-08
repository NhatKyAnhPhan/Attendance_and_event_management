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
        padding: const EdgeInsets.only(right: 12),
        itemCount: widget.students.length,
        separatorBuilder: (_, _) =>
            Divider(height: 1, color: widget.dividerColor),
        itemBuilder: (context, index) {
          final student = widget.students[index];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: CircleAvatar(
              child: Text(
                student.studentName.isEmpty
                    ? '?'
                    : student.studentName.characters.first.toUpperCase(),
              ),
            ),
            title: Text(
              student.studentName.isEmpty
                  ? student.studentId
                  : student.studentName,
            ),
            subtitle: Text(
              [
                student.studentId,
                if (student.email.isNotEmpty) student.email,
                if (student.dateLabel.isNotEmpty) student.dateLabel,
              ].join(' · '),
              style: AppTextStyles.bodyXs(widget.mutedColor),
            ),
            trailing: student.status.isEmpty && student.attendanceStatus.isEmpty
                ? null
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (student.status.isNotEmpty)
                        Text(
                          student.status,
                          style: AppTextStyles.bodyXs(widget.mutedColor),
                        ),
                      if (student.attendanceStatus.isNotEmpty)
                        Text(
                          student.attendanceStatus,
                          style: AppTextStyles.bodyXs(
                            student.attendanceStatus == 'Đã điểm danh QR'
                                ? Theme.of(context).colorScheme.primary
                                : widget.mutedColor,
                          ),
                        ),
                    ],
                  ),
          );
        },
      ),
    );
  }
}
