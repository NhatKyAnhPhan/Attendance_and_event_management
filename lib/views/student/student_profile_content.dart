import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/theme_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../data/api/api_client.dart';
import '../lecturer_profile/profile_view_model.dart';
import '../lecturer_profile/widgets/profile_contact_editor.dart';
import '../lecturer_profile/widgets/profile_info_section.dart';

class StudentProfileContent extends StatefulWidget {
  const StudentProfileContent({super.key});

  @override
  State<StudentProfileContent> createState() => _StudentProfileContentState();
}

class _StudentProfileContentState extends State<StudentProfileContent> {
  final TextEditingController _apiUrlController = TextEditingController();
  bool _isChecking = false;
  bool? _isConnected;
  String? _connectionMessage;

  @override
  void initState() {
    super.initState();
    _loadApiUrl();
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadApiUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('apiBaseUrl') ?? ApiClient.baseUrl;
    if (!mounted) return;
    _apiUrlController.text = savedUrl;
  }

  Future<void> _saveApiUrl() async {
    final rawUrl = _apiUrlController.text.trim();
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || !uri.hasAuthority || !{'http', 'https'}.contains(uri.scheme)) {
      setState(() {
        _isConnected = false;
        _connectionMessage = 'Nhập địa chỉ máy chủ HTTP hoặc HTTPS hợp lệ.';
      });
      return;
    }

    final baseUrl = rawUrl.replaceFirst(RegExp(r'/+$'), '');
    ApiClient.configureBaseUrl(baseUrl);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('apiBaseUrl', baseUrl);
    if (!mounted) return;
    setState(() {
      _isConnected = null;
      _connectionMessage = 'Đã lưu địa chỉ máy chủ.';
    });
  }

  Future<void> _checkConnection() async {
    await _saveApiUrl();
    if (!mounted || _isConnected == false) return;

    setState(() {
      _isChecking = true;
      _connectionMessage = 'Đang kiểm tra kết nối...';
    });

    try {
      final result = await ApiClient().get('/health');
      final connected =
          result['ok'] == true && result['database']?.toString() == 'connected';
      if (!mounted) return;
      setState(() {
        _isConnected = connected;
        _connectionMessage = connected
            ? 'Máy chủ và cơ sở dữ liệu đang hoạt động.'
            : 'Máy chủ phản hồi nhưng cơ sở dữ liệu chưa kết nối.';
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isConnected = false;
        _connectionMessage = error.message;
      });
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(
      Theme.of(context).brightness == Brightness.dark,
    );
    final auth = Get.find<AuthController>();
    final theme = Get.find<ThemeController>();

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
            allowEditingPersonalDetails: true,
            birthDate: profile.birthDate,
            gender: profile.gender,
            hometown: profile.hometown,
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
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(AppColors.radiusLg),
              border: Border.all(color: colors.border),
            ),
            child: Obx(
              () => SwitchListTile(
                value: theme.isDark.value,
                onChanged: (_) => theme.toggle(),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppColors.radiusLg),
                ),
                secondary: Icon(
                  theme.isDark.value
                      ? Icons.dark_mode_outlined
                      : Icons.light_mode_outlined,
                  color: colors.primary,
                ),
                title: Text(
                  'Giao diện tối',
                  style: TextStyle(
                    color: colors.foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(AppColors.radiusLg),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.dns_outlined, color: colors.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Máy chủ API',
                      style: TextStyle(
                        color: colors.foreground,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _apiUrlController,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    hintText: 'http://192.168.1.20:3000',
                    prefixIcon: const Icon(Icons.link),
                    filled: true,
                    fillColor: colors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: colors.border),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isChecking ? null : _checkConnection,
                        icon: _isChecking
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.sync),
                        label: const Text('Kiểm tra'),
                      ),
                    ),
                  ],
                ),
                if (_connectionMessage != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (_isConnected == true)
                        Icon(Icons.check_circle, color: colors.success)
                      else if (_isConnected == false)
                        Icon(Icons.error_outline, color: colors.danger)
                      else
                        Icon(Icons.info_outline, color: colors.info),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _connectionMessage!,
                          style: TextStyle(
                            color: _isConnected == false
                                ? colors.danger
                                : _isConnected == true
                                    ? colors.success
                                    : colors.foreground,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
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