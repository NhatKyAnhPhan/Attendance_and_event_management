import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/theme_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'profile_view_model.dart';
import 'widgets/profile_contact_editor.dart';
import 'widgets/profile_info_section.dart';

/// Hồ sơ dùng chung cho Giảng viên và Cán bộ đang đăng nhập.
class LecturerProfilePage extends StatelessWidget {
  const LecturerProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();
    final theme = Get.find<ThemeController>();

    return Obx(() {
      final isDark = theme.isDark.value;
      final colors = AppColors.of(isDark);
      final profile = ProfileViewModel.fromSession(
        user: auth.currentUser.value ?? const <String, dynamic>{},
        role: auth.role.value,
      );

      return Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: colors.card,
          foregroundColor: colors.foreground,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            tooltip: 'Quay lại',
            onPressed: Get.back,
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(
            profile.pageTitle,
            style: AppTextStyles.displaySm(colors.foreground),
          ),
          actions: [
            IconButton(
              tooltip: isDark
                  ? 'Chuyển sang giao diện sáng'
                  : 'Chuyển sang giao diện tối',
              onPressed: theme.toggle,
              icon: Icon(
                isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              ),
            ),
            const SizedBox(width: 8),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, color: colors.border),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 720;
                    final summary = _ProfileSummary(
                      profile: profile,
                      colors: colors,
                    );
                    final details = _ProfileDetails(
                      profile: profile,
                      colors: colors,
                    );

                    if (compact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          summary,
                          const SizedBox(height: 16),
                          details,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 280, child: summary),
                        const SizedBox(width: 20),
                        Expanded(child: details),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _ProfileSummary extends StatelessWidget {
  const _ProfileSummary({required this.profile, required this.colors});

  final ProfileViewModel profile;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(AppColors.radiusLg),
      ),
      child: Column(
        children: [
          _ProfileAvatar(profile: profile, colors: colors),
          const SizedBox(height: 16),
          Text(
            profile.name,
            textAlign: TextAlign.center,
            style: AppTextStyles.displayMd(colors.foreground),
          ),
          const SizedBox(height: 6),
          Text(
            profile.code,
            textAlign: TextAlign.center,
            style: AppTextStyles.mono(colors.mutedForeground),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: colors.secondary,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              profile.roleLabel,
              style: AppTextStyles.bodyXs(colors.primary)
                  .copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.profile, required this.colors});

  final ProfileViewModel profile;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      color: colors.primary,
      alignment: Alignment.center,
      child: Text(
        profile.initials,
        style: AppTextStyles.displayLg(Colors.white).copyWith(fontSize: 28),
      ),
    );

    return ClipOval(
      child: SizedBox(
        width: 88,
        height: 88,
        child: profile.avatarUrl == null
            ? fallback
            : Image.network(
                profile.avatarUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

class _ProfileDetails extends StatelessWidget {
  const _ProfileDetails({required this.profile, required this.colors});

  final ProfileViewModel profile;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProfileContactEditor(
          colors: colors,
          email: profile.email,
          phone: profile.phone,
          address: profile.currentAddress,
          allowEditing: !profile.isLecturer,
          readOnlyItems: [
            ProfileInfoItem(
              icon: Icons.person_outline,
              label: 'Họ tên',
              value: profile.name,
            ),
            ProfileInfoItem(
              icon: Icons.badge_outlined,
              label: profile.codeLabel,
              value: profile.code,
            ),
            ProfileInfoItem(
              icon: Icons.cake_outlined,
              label: 'Ngày sinh',
              value: profile.birthDate,
            ),
            ProfileInfoItem(
              icon: Icons.person_outline,
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
          title: 'Thông tin công tác',
          colors: colors,
          items: [
            if (profile.isLecturer)
              ProfileInfoItem(
                icon: Icons.menu_book_outlined,
                label: 'Bộ môn',
                value: profile.subjectDepartment,
              ),
            ProfileInfoItem(
              icon: Icons.apartment_outlined,
              label: profile.isLecturer ? 'Đơn vị / Khoa' : 'Đơn vị',
              value: profile.unit,
            ),
            ProfileInfoItem(
              icon: Icons.work_outline,
              label: 'Chức vụ',
              value: profile.position,
            ),
            if (profile.isLecturer)
              ProfileInfoItem(
                icon: Icons.school_outlined,
                label: 'Học vị / Trình độ',
                value: profile.degree,
              ),
            ProfileInfoItem(
              icon: Icons.event_available_outlined,
              label: 'Ngày bắt đầu công tác',
              value: profile.workStartDate,
            ),
            ProfileInfoItem(
              icon: Icons.timelapse_outlined,
              label: 'Thời gian công tác',
              value: profile.tenure,
            ),
          ],
        ),
        const SizedBox(height: 16),
        ProfileInfoSection(
          title: 'Thông tin tài khoản',
          colors: colors,
          items: [
            ProfileInfoItem(
              icon: Icons.badge_outlined,
              label: profile.codeLabel,
              value: profile.code,
            ),
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
      ],
    );
  }
}