import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/classes_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/api/api_client.dart';
import '../../data/models/student_summaries.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/statistics_charts.dart';

Future<void> _showClassFeedbackDialog(
  BuildContext context,
  ClassesController controller,
  String classId,
) async {
  final formKey = GlobalKey<FormState>();
  final commentController = TextEditingController();
  var rating = 5;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Phản hồi và đánh giá lớp học'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    5,
                    (index) => IconButton(
                      tooltip: '${index + 1} sao',
                      onPressed: () => setState(() => rating = index + 1),
                      icon: Icon(
                        index < rating ? Icons.star : Icons.star_border,
                        color: const Color(0xFFF59E0B),
                      ),
                    ),
                  ),
                ),
                TextFormField(
                  controller: commentController,
                  maxLines: 4,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Nội dung phản hồi',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Vui lòng nhập nội dung phản hồi.'
                      : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              try {
                await controller.submitFeedback(
                  classId: classId,
                  rating: rating,
                  comment: commentController.text.trim(),
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Đã gửi đánh giá lớp học.')),
                  );
                }
              } on ApiException catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(error.message)),
                  );
                }
              }
            },
            child: const Text('Gửi'),
          ),
        ],
      ),
    ),
  );
  commentController.dispose();
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
                    values: filteredClasses.map((cls) => cls.present).toList(),
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
                              onFeedback: () => _showClassFeedbackDialog(
                                context,
                                controller,
                                cls.id,
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
  final VoidCallback onFeedback;
  const _ClassCard({
    required this.cls,
    required this.c,
    required this.onFeedback,
  });

  @override
  Widget build(BuildContext context) {
    final stats = [
      {'v': '${cls.present}', 'l': 'Có mặt', 'c': const Color(0xFF16A34A)},
      {'v': '${cls.late}', 'l': 'Muộn', 'c': const Color(0xFFD97706)},
      {'v': '${cls.absent}', 'l': 'Vắng', 'c': const Color(0xFFDC2626)},
      {'v': '${cls.rate}%', 'l': 'Tỷ lệ', 'c': c.primary},
    ];

    return Container(
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
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
                          style: AppTextStyles.mono(c.primary, fontSize: 11),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        cls.name,
                        style: AppTextStyles.displaySm(c.foreground),
                      ),
                      Text(
                        cls.lecturer,
                        style: AppTextStyles.bodyXs(c.mutedForeground),
                      ),
                      Text(
                        '${cls.time} · Phòng ${cls.room}',
                        style: AppTextStyles.bodyXs(c.mutedForeground),
                      ),
                      if (cls.credits > 0 || cls.capacity > 0)
                        Text(
                          '${cls.credits} tín chỉ · ${cls.studentCount}/${cls.capacity} sinh viên',
                          style: AppTextStyles.bodyXs(c.mutedForeground),
                        ),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 4),
                    child: TextButton.icon(
                      onPressed: onFeedback,
                      icon: const Icon(Icons.rate_review_outlined),
                      label: const Text('Phản hồi / đánh giá'),
                    ),
                  ),
                ),
              ],
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
    );
  }
}
