import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/classes_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/mock/student_mock_data.dart';

class StudentClassesPage extends StatelessWidget {
  const StudentClassesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);
    final controller = Get.put(ClassesController());

    return Obx(() {
      final classes = controller.items;
      if (controller.loading.value && classes.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (controller.error.value.isNotEmpty && classes.isEmpty) {
        return Center(child: Text(controller.error.value));
      }
      return ListView(
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
                  'HK2 2024–2025 · ${classes.length} lớp',
                  style: AppTextStyles.bodySm(c.mutedForeground),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: classes
                  .map(
                    (cls) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ClassCard(cls: cls, c: c),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      );
    });
  }
}

class _ClassCard extends StatelessWidget {
  final StudentClassSummary cls;
  final AppColors c;
  const _ClassCard({required this.cls, required this.c});

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
                    ],
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
