import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../controllers/theme_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/api/api_client.dart';

class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({super.key});

  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  static const _apiUrlKey = 'apiBaseUrl';

  late final TextEditingController _urlController;
  bool _isChecking = false;
  bool? _isConnected;
  String? _connectionMessage;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: ApiClient.baseUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _saveApiUrl() async {
    final uri = Uri.tryParse(_urlController.text.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        !{'http', 'https'}.contains(uri.scheme)) {
      setState(() {
        _isConnected = false;
        _connectionMessage = 'Nhập địa chỉ máy chủ HTTP hoặc HTTPS hợp lệ.';
      });
      return;
    }

    final baseUrl = _urlController.text.trim().replaceFirst(RegExp(r'/+$'), '');
    ApiClient.configureBaseUrl(baseUrl);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiUrlKey, baseUrl);
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
      _connectionMessage = null;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = AppColors.of(isDark);
    final theme = Get.find<ThemeController>();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cài đặt',
                style: AppTextStyles.displayLg(colors.foreground),
              ),
              const SizedBox(height: 5),
              Text(
                'Tùy chỉnh giao diện và kết nối hệ thống.',
                style: AppTextStyles.bodySm(colors.mutedForeground),
              ),
              const SizedBox(height: 24),
              _section(
                colors,
                title: 'Giao diện',
                icon: Icons.palette_outlined,
                child: Obx(
                  () => SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: theme.isDark.value,
                    onChanged: (_) => theme.toggle(),
                    secondary: Icon(
                      theme.isDark.value
                          ? Icons.dark_mode_outlined
                          : Icons.light_mode_outlined,
                      color: colors.primary,
                    ),
                    title: Text(
                      'Chế độ tối',
                      style: AppTextStyles.bodyMd(colors.foreground),
                    ),
                    subtitle: Text(
                      'Áp dụng trên toàn bộ ứng dụng.',
                      style: AppTextStyles.bodySm(colors.mutedForeground),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _section(
                colors,
                title: 'Kết nối máy chủ',
                icon: Icons.dns_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _urlController,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        labelText: 'Địa chỉ API',
                        hintText: 'http://192.168.1.10:3000',
                        prefixIcon: const Icon(Icons.link),
                        filled: true,
                        fillColor: colors.background,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: colors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: colors.border),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: _isChecking ? null : _checkConnection,
                          icon: _isChecking
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.sync, size: 18),
                          label: Text(
                            _isChecking ? 'Đang kiểm tra' : 'Kiểm tra kết nối',
                          ),
                        ),
                        if (_connectionMessage != null)
                          _connectionStatus(colors),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _section(
    AppColors colors, {
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: colors.primary),
              const SizedBox(width: 10),
              Text(title, style: AppTextStyles.displaySm(colors.foreground)),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _connectionStatus(AppColors colors) {
    final connected = _isConnected == true;
    final color = connected ? colors.success : colors.danger;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          connected ? Icons.check_circle_outline : Icons.error_outline,
          size: 18,
          color: color,
        ),
        const SizedBox(width: 6),
        Text(_connectionMessage!, style: AppTextStyles.bodySm(color)),
      ],
    );
  }
}
