import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/events_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/mock/student_mock_data.dart';
import '../../widgets/app_badge.dart';

class StudentEventsPage extends StatelessWidget {
  const StudentEventsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);
    final controller = Get.put(EventsController());

    return Obx(() {
      final events = controller.items;
      if (controller.loading.value && events.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (controller.error.value.isNotEmpty && events.isEmpty) {
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
                  'Sự kiện',
                  style: AppTextStyles.displayLg(c.foreground)
                      .copyWith(fontSize: 22),
                ),
                Text(
                  'Khám phá & đăng ký sự kiện',
                  style: AppTextStyles.bodySm(c.mutedForeground),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                ...events.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _EventCard(
                      event: e,
                      c: c,
                      onRegister: () => controller.register(e.id),
                    ),
                  ),
                ),
                _SearchMoreCard(c: c),
              ],
            ),
          ),
        ],
      );
    });
  }
}

class _EventCard extends StatelessWidget {
  final StudentEventSummary event;
  final AppColors c;
  final Future<void> Function() onRegister;
  const _EventCard({
    required this.event,
    required this.c,
    required this.onRegister,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3E8FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.event,
                  color: Color(0xFF7C3AED),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.name,
                      style: AppTextStyles.displaySm(c.foreground),
                    ),
                    Text(
                      '${event.date} · ${event.org}',
                      style: AppTextStyles.bodyXs(c.mutedForeground),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              event.registered
                  ? const AppBadge(
                      label: 'Đã đăng ký',
                      status: BadgeStatus.present,
                    )
                  : const AppBadge(
                      label: 'Chưa đăng ký',
                      status: BadgeStatus.pending,
                    ),
              const Spacer(),
              event.registered
                  ? OutlinedButton(
                      onPressed: () {},
                      child: const Text('Xem chi tiết'),
                    )
                  : ElevatedButton(
                      onPressed: onRegister,
                      child: const Text('Đăng ký ngay'),
                    ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchMoreCard extends StatelessWidget {
  final AppColors c;
  const _SearchMoreCard({required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          const Text('🔍', style: TextStyle(fontSize: 32)),
          const SizedBox(height: 8),
          Text(
            'Khám phá thêm sự kiện',
            style: AppTextStyles.displayXs(c.foreground).copyWith(fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            'Tìm kiếm sự kiện theo tên, mã hoặc ngày',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySm(c.mutedForeground),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () {},
            child: const Text('Tìm kiếm sự kiện'),
          ),
        ],
      ),
    );
  }
}
