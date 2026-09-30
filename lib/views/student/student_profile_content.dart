import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../core/theme/app_colors.dart';
import '../lecturer_profile/profile_view_model.dart';
import '../lecturer_profile/widgets/profile_contact_editor.dart';
import '../lecturer_profile/widgets/profile_info_section.dart';

class StudentProfileContent extends StatelessWidget {
  const StudentProfileContent({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(
      Theme.of(context).brightness == Brightness.dark,
    );
    final auth = Get.find<AuthController>();

    return Obx(() {
      final user = auth.currentUser.value ?? const <String, dynamic>{};
      final profile = ProfileViewModel.fromSession(
        user: user,
        role: auth.role.value,
      );
      final name = _value(user, const ['name', 'fullName', 'hoTen']);
      final code = _value(user, const ['id', 'studentCode']);

      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StudentSummary(
            colors: colors,
            name: name,
            code: code,
            role: profile.roleLabel,
            initials: profile.initials,
          ),
          const SizedBox(height: 16),
          ProfileContactEditor(
            colors: colors,
            email: profile.email,
            phone: profile.phone,
            address: profile.currentAddress,
            allowEditing: true,
            readOnlyItems: [
              ProfileInfoItem(
                icon: Icons.person_outline,
                label: 'Họ tên',
                value: name,
              ),
              ProfileInfoItem(
                icon: Icons.badge_outlined,
                label: 'Mã sinh viên',
                value: code,
              ),
              ProfileInfoItem(
                icon: Icons.cake_outlined,
                label: 'Ngày sinh',
                value: profile.birthDate,
              ),
              ProfileInfoItem(
                icon: Icons.wc_outlined,
                label: 'Giới tính',
                value: profile.gender,
              ),
              ProfileInfoItem(
                icon: Icons.home_outlined,
                label: 'Quê quán',
                value: profile.hometown,
              ),
            ],
          ),
          const SizedBox(height: 16),
          ProfileInfoSection(
            title: 'Thông tin học tập',
            colors: colors,
            items: [
              ProfileInfoItem(
                icon: Icons.groups_outlined,
                label: 'Lớp',
                value: _value(user, const ['className']),
              ),
              ProfileInfoItem(
                icon: Icons.menu_book_outlined,
                label: 'Chuyên ngành',
                value: _value(user, const ['major']),
              ),
              ProfileInfoItem(
                icon: Icons.school_outlined,
                label: 'Khoa / Trường',
                value: profile.unit,
              ),
            ],
          ),
          const SizedBox(height: 16),
          ProfileInfoSection(
            title: 'Thông tin tài khoản',
            colors: colors,
            items: [
              ProfileInfoItem(
                icon: Icons.admin_panel_settings_outlined,
                label: 'Vai trò',
                value: profile.roleLabel,
              ),
              ProfileInfoItem(
                icon: Icons.verified_user_outlined,
                label: 'Trạng thái tài khoản',
                value: profile.accountStatus,
              ),
            ],
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: auth.logout,
            child: Text('Đăng xuất', style: TextStyle(color: colors.danger)),
          ),
        ],
      );
    });
  }

  static String _value(Map<String, dynamic> user, List<String> keys) {
    for (final key in keys) {
      final value = user[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return ProfileViewModel.unavailable;
  }
}

class _StudentSummary extends StatelessWidget {
  const _StudentSummary({
    required this.colors,
    required this.name,
    required this.code,
    required this.role,
    required this.initials,
  });

  final AppColors colors;
  final String name;
  final String code;
  final String role;
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: BorderRadius.circular(AppColors.radiusLg),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            child: Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$code · $role',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}