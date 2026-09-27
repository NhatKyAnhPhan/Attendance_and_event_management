import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

class StudentProfilePage extends StatelessWidget {
  const StudentProfilePage({super.key});

  /// Hiển thị thông tin tài khoản đã xác thực từ backend.
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);
    final auth = Get.find<AuthController>();
    final user = auth.currentUser.value ?? const <String, dynamic>{};
    final name = user['name']?.toString() ?? 'Người dùng';
    final code = user['id']?.toString() ?? '';
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();

    final info = [
      ['Email', user['email']?.toString() ?? ''],
      ['Chuyên ngành', user['major']?.toString() ?? ''],
      ['Lớp', user['className']?.toString() ?? ''],
      ['Vai trò', user['role']?.toString() ?? ''],
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
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  initials,
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w800,
                    fontSize: 26,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                name,
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
              ),
              Text(
                '$code · ${user['role'] ?? ''}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: c.card,
                  border: Border.all(color: c.border),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: info.asMap().entries.map((e) {
                    final isLast = e.key == info.length - 1;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: isLast
                              ? BorderSide.none
                              : BorderSide(color: c.border),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            e.value[0],
                            style: AppTextStyles.bodySm(c.mutedForeground),
                          ),
                          Text(
                            e.value[1],
                            style: AppTextStyles.bodySm(c.foreground)
                                .copyWith(fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
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
