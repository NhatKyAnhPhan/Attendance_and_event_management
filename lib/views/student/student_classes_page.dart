import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/classes_controller.dart';
import '../../controllers/events_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/models/student_summaries.dart';
import 'student_class_details_page.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/statistics_charts.dart';
import '../../widgets/student_form_dialogs.dart';

Future<void> _showClassFeedbackDialog(
  BuildContext context,
  ClassesController classesController,
  EventsController eventsController,
  String classId,
) async {
  await showStudentFeedbackDialog(
    context: context,
    eventsController: eventsController,
    classesController: classesController,
    initialTarget: StudentFeedbackTarget.classSection,
    initialItemId: classId,
  );
}

class StudentClassesPage extends StatefulWidget {
  const StudentClassesPage({super.key});

  @override
  State<StudentClassesPage> createState() => _StudentClassesPageState();
}

class _StudentClassesPageState extends State<StudentClassesPage> {
  String _query = '';

  /// Hiển thị lớp và kết quả điểm danh lấy từ API sinh viên.
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);
    final controller = Get.put(ClassesController());
    final eventsController = Get.isRegistered<EventsController>()
        ? Get.find<EventsController>()
        : Get.put(EventsController());

    return Obx(() {
      final classes = controller.items;
      final query = _query.trim().toLowerCase();
      final filteredClasses = classes.where((cls) {
        return [
          cls.id,
          cls.name,
          cls.lecturer,
          cls.time,
          cls.room,
        ].any((value) => value.toLowerCase().contains(query));
      }).toList();
      final hasAttendanceData = filteredClasses.any(
        (cls) => cls.present + cls.late + cls.absent > 0,
      );
      if (controller.loading.value && classes.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (controller.error.value.isNotEmpty && classes.isEmpty) {
        return Center(child: Text(controller.error.value));
      }
      return RefreshIndicator(
        onRefresh: controller.load,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
              decoration: BoxDecoration(
                color: c.card,
                border: Border(bottom: BorderSide(color: c.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Lớp học của tôi',
                    style: AppTextStyles.displayLg(c.foreground)
                        .copyWith(fontSize: 22),
                  ),
                  Text(
                    '${filteredClasses.length} lớp trong dữ liệu của bạn',
                    style: AppTextStyles.bodySm(c.mutedForeground),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: AppSearchField(
                colors: c,
                hintText: 'Tìm tên lớp, mã lớp, giảng viên...',
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            if (hasAttendanceData)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: StatisticsBarChart(
                  title: 'Kết quả điểm danh theo lớp',
                  colors: c,
                  categories: filteredClasses.map((cls) => cls.id).toList(),
                  series: [
                    StatisticsChartSeries(
                      label: 'Có mặt',
                      color: c.success,
                      values: filteredClasses
                          .map((cls) => cls.present)
                          .toList(),
                    ),
                    StatisticsChartSeries(
                      label: 'Muộn',
                      color: c.warning,
                      values: filteredClasses.map((cls) => cls.late).toList(),
                    ),
                    StatisticsChartSeries(
                      label: 'Vắng',
                      color: c.danger,
                      values: filteredClasses.map((cls) => cls.absent).toList(),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: filteredClasses.isEmpty
                    ? [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Text(
                            classes.isEmpty
                                ? 'Bạn chưa có lớp học.'
                                : 'Không tìm thấy lớp học phù hợp.',
                            style: AppTextStyles.bodySm(c.mutedForeground),
                          ),
                        ),
                      ]
                    : filteredClasses
                          .map(
                            (cls) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _ClassCard(
                                cls: cls,
                                c: c,
                                onTap: () => Get.to(
                                  () =>
                                      StudentClassDetailsPage(classId: cls.id),
                                ),
                                onFeedback: () => _showClassFeedbackDialog(
                                  context,
                                  controller,
                                  eventsController,
                                  cls.id,
                                ),
                                onRating: () => showStudentRatingDialog(
                                  context: context,
                                  eventsController: eventsController,
                                  classesController: controller,
                                  initialTarget:
                                      StudentFeedbackTarget.classSection,
                                  initialItemId: cls.id,
                                ),
                              ),
                            ),
                          )
                          .toList(),
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _ClassCard extends StatelessWidget {
  final StudentClassSummary cls;
  final AppColors c;
  final VoidCallback onTap;
  final VoidCallback onFeedback;
  final VoidCallback onRating;
  const _ClassCard({
    required this.cls,
    required this.c,
    required this.onTap,
    required this.onFeedback,
    required this.onRating,
  });

  @override
  Widget build(BuildContext context) {
    final stats = [
      {'v': '${cls.present}', 'l': 'Có mặt', 'c': const Color(0xFF16A34A)},
      {'v': '${cls.late}', 'l': 'Muộn', 'c': const Color(0xFFD97706)},
      {'v': '${cls.absent}', 'l': 'Vắng', 'c': const Color(0xFFDC2626)},
      {'v': '${cls.rate}%', 'l': 'Tỷ lệ', 'c': c.primary},
    ];

    return Material(
      color: c.card,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth <= 400;
                    final info = Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: c.secondary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                cls.id,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.mono(
                                  c.primary,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            cls.name,
                            maxLines: narrow ? 3 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.displaySm(c.foreground),
                          ),
                          Text(
                            cls.lecturer,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodyXs(c.mutedForeground),
                          ),
                          if (cls.time.isNotEmpty || cls.room.isNotEmpty)
                            Text(
                              '${cls.time}'
                              '${cls.time.isNotEmpty && cls.room.isNotEmpty ? ' · ' : ''}'
                              '${cls.room.isEmpty ? '' : 'Phòng ${cls.room}'}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodyXs(c.mutedForeground),
                            ),
                          if (cls.credits > 0 || cls.capacity > 0)
                            Text(
                              '${cls.credits} tín chỉ · ${cls.studentCount}/${cls.capacity} sinh viên',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodyXs(c.mutedForeground),
                            ),
                        ],
                      ),
                    );
                    final actions = Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      alignment: WrapAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: onFeedback,
                          icon: const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 18,
                          ),
                          label: const Text('Phản hồi'),
                        ),
                        TextButton.icon(
                          onPressed: onRating,
                          icon: const Icon(
                            Icons.star_outline_rounded,
                            size: 18,
                          ),
                          label: const Text('Đánh giá'),
                        ),
                      ],
                    );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: const Color(0xFFDBEAFE),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.menu_book,
                                color: Color(0xFF1E56A0),
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            info,
                            if (!narrow) ...[
                              const SizedBox(width: 8),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 220,
                                ),
                                child: actions,
                              ),
                            ],
                          ],
                        ),
                        if (narrow) ...[
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: actions,
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: c.border)),
                ),
                child: Row(
                  children: List.generate(stats.length, (i) {
                    final s = stats[i];
                    return Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          border: Border(
                            right: i < stats.length - 1
                                ? BorderSide(color: c.border)
                                : BorderSide.none,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              s['v'] as String,
                              style: TextStyle(
                                fontFamily: 'Nunito',
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                color: s['c'] as Color,
                              ),
                            ),
                            Text(
                              s['l'] as String,
                              style: AppTextStyles.bodyXs(c.mutedForeground)
                                  .copyWith(fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
