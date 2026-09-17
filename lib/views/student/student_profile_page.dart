import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/auth_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

class StudentProfilePage extends StatelessWidget {
  const StudentProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);

    // TODO: thay bằng dữ liệu thật từ UserRepository khi có API.
    const info = [
      ['Email', '21it042@huit.edu.vn'],
      ['Khoa', 'Công nghệ Thông tin'],
      ['Lớp', '21CNTT3'],
      ['Năm học', '2021–2025'],
    ];

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 48, 16, 24),
          color: c.primary,
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
                child: const Text('PD',
                    style: TextStyle(color: Colors.white, fontFamily: 'Nunito', fontWeight: FontWeight.w800, fontSize: 26)),
              ),
              const SizedBox(height: 12),
              const Text('Phạm Văn Dũng',
                  style: TextStyle(color: Colors.white, fontFamily: 'Nunito', fontWeight: FontWeight.w800, fontSize: 20)),
              const Text('21IT042 · Sinh viên', style: TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(color: c.card, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(10)),
                child: Column(
                  children: info.asMap().entries.map((e) {
                    final isLast = e.key == info.length - 1;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(bottom: isLast ? BorderSide.none : BorderSide(color: c.border)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(e.value[0], style: AppTextStyles.bodySm(c.mutedForeground)),
                          Text(e.value[1], style: AppTextStyles.bodySm(c.foreground).copyWith(fontWeight: FontWeight.w500)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: c.card, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(10)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Thành tích', style: AppTextStyles.displaySm(c.foreground)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.emoji_events, color: Color(0xFFD97706), size: 22),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('2 chứng chỉ', style: AppTextStyles.displayXs(c.foreground).copyWith(fontSize: 14)),
                            Text('Sự kiện đã hoàn thành', style: AppTextStyles.bodyXs(c.mutedForeground)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton(
                  onPressed: () => Get.find<AuthController>().logout(),
                  child: Text('Đăng xuất', style: TextStyle(color: c.danger)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}