import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../data/api/api_client.dart';
import '../../data/api/endpoints.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../widgets/huit_logo_mark.dart';

/// Tương ứng `type AuthStep` trong AuthPage.tsx
enum _AuthStep { login, forgot, otp, newPassword, success }

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  _AuthStep _step = _AuthStep.login;
  bool _showPw = false;
  bool _loading = false;
  int _resendSeconds = 0;
  Timer? _resendTimer;
  String _error = '';
  String? _resetToken;
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _newPwCtrl = TextEditingController();
  final _confirmPwCtrl = TextEditingController();

  final List<TextEditingController> _otpCtrls = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _otpFocus = List.generate(6, (_) => FocusNode());

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _newPwCtrl.dispose();
    _confirmPwCtrl.dispose();
    _resendTimer?.cancel();
    for (final c in _otpCtrls) {
      c.dispose();
    }
    for (final f in _otpFocus) {
      f.dispose();
    }
    super.dispose();
  }

  // ---------- Handlers (tương ứng handleLogin/handleForgot/handleOtp/handleNewPassword) ----------

  // Kiểm tra biểu mẫu, gọi AuthController và hiển thị lỗi đăng nhập.
  Future<void> _handleLogin() async {
    if (_emailCtrl.text.isEmpty || _passwordCtrl.text.isEmpty) {
      setState(() => _error = 'Vui lòng nhập đầy đủ thông tin.');
      return;
    }
    setState(() {
      _error = '';
      _loading = true;
    });
    try {
      await Get.find<AuthController>().login(
        identifier: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Gửi mã OTP đến email rồi mới mở bước xác nhận.
  Future<void> _handleForgot() async {
    final email = _emailCtrl.text.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _error = 'Vui lòng nhập email hợp lệ.');
      return;
    }
    setState(() {
      _error = '';
      _loading = true;
    });
    try {
      await Get.find<AuthController>().requestPasswordReset(email);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _step = _AuthStep.otp;
      _resetToken = null;
      for (final controller in _otpCtrls) {
        controller.clear();
      }
    });
    _startResendCooldown();
  }

  // Xác minh OTP với backend trước khi cho phép tạo mật khẩu mới.
  Future<void> _handleOtp() async {
    final code = _otpCtrls.map((c) => c.text).join();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Vui lòng nhập đủ 6 chữ số OTP.');
      return;
    }
    setState(() {
      _error = '';
      _loading = true;
    });
    try {
      _resetToken = await Get.find<AuthController>().verifyPasswordResetCode(
        email: _emailCtrl.text.trim(),
        code: code,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _step = _AuthStep.newPassword;
    });
  }

  // Kiểm tra mật khẩu và đổi mật khẩu bằng reset token dùng một lần.
  Future<void> _handleNewPassword() async {
    if (_newPwCtrl.text.length < 8) {
      setState(() => _error = 'Mật khẩu phải có ít nhất 8 ký tự.');
      return;
    }
    if (_newPwCtrl.text != _confirmPwCtrl.text) {
      setState(() => _error = 'Mật khẩu xác nhận không khớp.');
      return;
    }
    setState(() {
      _error = '';
      _loading = true;
    });
    final resetToken = _resetToken;
    if (resetToken == null) {
      setState(() {
        _loading = false;
        _error = 'Mã xác nhận đã hết hạn. Vui lòng yêu cầu mã mới.';
      });
      return;
    }
    try {
      await Get.find<AuthController>().completePasswordReset(
        email: _emailCtrl.text.trim(),
        resetToken: resetToken,
        newPassword: _newPwCtrl.text,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _step = _AuthStep.success;
      _resetToken = null;
    });
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _resendSeconds -= 1;
        if (_resendSeconds <= 0) {
          _resendSeconds = 0;
          timer.cancel();
        }
      });
    });
  }

  // Tự động chuyển focus sang ô OTP kế tiếp sau khi nhập một chữ số.
  void _handleOtpInput(int i, String val) {
    if (val.isNotEmpty && i < 5) {
      _otpFocus[i + 1].requestFocus();
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);

    return Scaffold(
      backgroundColor: c.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final showLeftPanel =
              constraints.maxWidth >=
              900; // tương ứng breakpoint "lg" của Tailwind
          final leftPanelWidth = (constraints.maxWidth * 0.38).clamp(
            360.0,
            560.0,
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showLeftPanel)
                SizedBox(
                  width: leftPanelWidth,
                  child: _LeftPanel(c: c),
                ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!showLeftPanel) _MobileLogo(c: c),
                          _buildStep(c),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStep(AppColors c) {
    switch (_step) {
      case _AuthStep.login:
        return _buildLogin(c);
      case _AuthStep.forgot:
        return _buildForgot(c);
      case _AuthStep.otp:
        return _buildOtp(c);
      case _AuthStep.newPassword:
        return _buildNewPassword(c);
      case _AuthStep.success:
        return _buildSuccess(c);
    }
  }

  Widget _buildLogin(AppColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Đăng nhập', style: AppTextStyles.displayLg(c.foreground)),
        const SizedBox(height: 6),
        Text(
          'Chào mừng trở lại! Vui lòng nhập thông tin đăng nhập.',
          style: AppTextStyles.bodyMd(c.mutedForeground),
        ),
        const SizedBox(height: 24),

        _FieldLabel('Email / Mã số', c: c),
        _AuthTextField(
          controller: _emailCtrl,
          hint: 'email@huit.edu.vn',
          icon: Icons.mail_outline,
          c: c,
        ),
        const SizedBox(height: 16),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _FieldLabel('Mật khẩu', c: c),
            TextButton(
              onPressed: () => setState(() {
                _step = _AuthStep.forgot;
                _error = '';
              }),
              child: Text(
                'Quên mật khẩu?',
                style: AppTextStyles.bodySm(c.primary),
              ),
            ),
          ],
        ),
        _AuthTextField(
          controller: _passwordCtrl,
          hint: '••••••••',
          icon: Icons.lock_outline,
          obscure: !_showPw,
          trailing: IconButton(
            icon: Icon(
              _showPw ? Icons.visibility_off : Icons.visibility,
              size: 18,
              color: c.mutedForeground,
            ),
            onPressed: () => setState(() => _showPw = !_showPw),
          ),
          c: c,
        ),

        if (_error.isNotEmpty) ...[
          const SizedBox(height: 16),
          _ErrorBanner(_error),
        ],

        const SizedBox(height: 20),
        _PrimaryButton(
          label: 'Đăng nhập',
          loading: _loading,
          onPressed: _handleLogin,
          c: c,
        ),
      ],
    );
  }

  Widget _buildForgot(AppColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BackButton(
          label: 'Quay lại đăng nhập',
          c: c,
          onTap: () => setState(() {
            _step = _AuthStep.login;
            _error = '';
          }),
        ),
        const SizedBox(height: 8),
        Text('Quên mật khẩu', style: AppTextStyles.displayLg(c.foreground)),
        const SizedBox(height: 8),
        Text(
          'Nhập email để nhận mã OTP xác thực.',
          style: AppTextStyles.bodyMd(c.mutedForeground),
        ),
        const SizedBox(height: 24),
        _FieldLabel('Email', c: c),
        _AuthTextField(
          controller: _emailCtrl,
          hint: 'email@huit.edu.vn',
          icon: Icons.mail_outline,
          c: c,
        ),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 16),
          _ErrorBanner(_error),
        ],
        const SizedBox(height: 20),
        _PrimaryButton(
          label: 'Gửi mã OTP',
          loading: _loading,
          onPressed: _handleForgot,
          c: c,
        ),
      ],
    );
  }

  Widget _buildOtp(AppColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BackButton(
          label: 'Quay lại',
          c: c,
          onTap: () => setState(() {
            _step = _AuthStep.forgot;
            _error = '';
          }),
        ),
        const SizedBox(height: 8),
        Text('Xác thực OTP', style: AppTextStyles.displayLg(c.foreground)),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(
            style: AppTextStyles.bodyMd(c.mutedForeground),
            children: [
              const TextSpan(text: 'Nhập mã 6 chữ số đã gửi đến '),
              TextSpan(
                text: _emailCtrl.text.isEmpty
                    ? 'email của bạn'
                    : _emailCtrl.text,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: c.foreground,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (i) {
            return Padding(
              padding: EdgeInsets.only(right: i < 5 ? 10 : 0),
              child: SizedBox(
                width: 46,
                height: 54,
                child: TextField(
                  controller: _otpCtrls[i],
                  focusNode: _otpFocus[i],
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  maxLength: 1,
                  style: AppTextStyles.mono(c.foreground, fontSize: 20),
                  decoration: InputDecoration(
                    counterText: '',
                    filled: true,
                    fillColor: c.card,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: c.border),
                    ),
                  ),
                  onChanged: (v) => _handleOtpInput(i, v),
                ),
              ),
            );
          }),
        ),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 8),
          _ErrorBanner(_error),
        ],
        const SizedBox(height: 20),
        _PrimaryButton(
          label: 'Xác nhận',
          loading: _loading,
          onPressed: _handleOtp,
          c: c,
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: _loading || _resendSeconds > 0 ? null : _handleForgot,
            child: Text(
              _resendSeconds > 0
                  ? 'Chưa nhận được mã? Gửi lại (${_resendSeconds}s)'
                  : 'Chưa nhận được mã? Gửi lại',
              style: AppTextStyles.bodySm(c.primary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNewPassword(AppColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Tạo mật khẩu mới', style: AppTextStyles.displayLg(c.foreground)),
        const SizedBox(height: 8),
        Text(
          'Mật khẩu phải có ít nhất 8 ký tự.',
          style: AppTextStyles.bodyMd(c.mutedForeground),
        ),
        const SizedBox(height: 24),
        _FieldLabel('Mật khẩu mới', c: c),
        _AuthTextField(
          controller: _newPwCtrl,
          hint: '••••••••',
          icon: Icons.lock_outline,
          obscure: !_showPw,
          trailing: IconButton(
            icon: Icon(
              _showPw ? Icons.visibility_off : Icons.visibility,
              size: 18,
              color: c.mutedForeground,
            ),
            onPressed: () => setState(() => _showPw = !_showPw),
          ),
          c: c,
        ),
        const SizedBox(height: 16),
        _FieldLabel('Xác nhận mật khẩu', c: c),
        _AuthTextField(
          controller: _confirmPwCtrl,
          hint: '••••••••',
          icon: Icons.lock_outline,
          obscure: true,
          c: c,
        ),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 16),
          _ErrorBanner(_error),
        ],
        const SizedBox(height: 20),
        _PrimaryButton(
          label: 'Đặt mật khẩu mới',
          loading: _loading,
          onPressed: _handleNewPassword,
          c: c,
        ),
      ],
    );
  }

  Widget _buildSuccess(AppColors c) {
    return Column(
      children: [
        const SizedBox(height: 24),
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            color: Color(0xFFDCFCE7),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check, color: Color(0xFF16A34A), size: 36),
        ),
        const SizedBox(height: 24),
        Text('Thành công!', style: AppTextStyles.displayLg(c.foreground)),
        const SizedBox(height: 8),
        Text(
          'Mật khẩu của bạn đã được cập nhật. Vui lòng đăng nhập lại.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMd(c.mutedForeground),
        ),
        const SizedBox(height: 24),
        _PrimaryButton(
          label: 'Về trang đăng nhập',
          loading: false,
          onPressed: () => setState(() {
            _step = _AuthStep.login;
            _error = '';
            _passwordCtrl.clear();
          }),
          c: c,
        ),
      ],
    );
  }
}

// ============ Widget con dùng riêng cho trang này ============
// (Có thể tách ra lib/widgets/ sau nếu app_input.dart/app_button.dart cần dùng lại chỗ khác)

class _LeftPanel extends StatefulWidget {
  final AppColors c;
  const _LeftPanel({required this.c});

  @override
  State<_LeftPanel> createState() => _LeftPanelState();
}

class _LeftPanelState extends State<_LeftPanel> {
  List<Map<String, String>>? _stats;
  String? _statsError;
  bool _loadingStats = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _loadingStats = true;
      _statsError = null;
    });

    try {
      final response = await ApiClient().get(ApiEndpoints.publicStats);
      final stats =
          [
            {'key': 'students', 'label': 'Sinh viên'},
            {'key': 'lecturers', 'label': 'Giảng viên'},
            {'key': 'classes', 'label': 'Lớp học'},
            {'key': 'events', 'label': 'Sự kiện'},
          ].map((item) {
            final value = response[item['key']];
            if (value is! num) {
              throw FormatException('Số liệu ${item['label']} không hợp lệ.');
            }
            return {'n': _formatCount(value.toInt()), 'l': item['label']!};
          }).toList();

      if (!mounted) return;
      setState(() {
        _stats = stats;
        _loadingStats = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _statsError = error.message;
        _loadingStats = false;
      });
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _statsError = error.message;
        _loadingStats = false;
      });
    }
  }

  String _formatCount(int value) {
    final digits = value.toString();
    final formatted = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) {
        formatted.write(',');
      }
      formatted.write(digits[index]);
    }
    return formatted.toString();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return Container(
      padding: const EdgeInsets.all(28),
      color: c.primary,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: const HuitLogoMark(),
                  ),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'HUIT',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'hệ thống điểm danh và quản lý sự kiện',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 32),
            const Text(
              'Hệ thống Quản lý Điểm danh',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w800,
                fontSize: 30,
                height: 1.2,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Quản lý điểm danh lớp học và sự kiện tại trường Đại học Công Thương TP.HCM.',
              style: TextStyle(
                fontSize: 14,
                height: 1.7,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 28),
            if (_loadingStats)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              )
            else if (_statsError != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _statsError!,
                    style: const TextStyle(color: Colors.white),
                  ),
                  TextButton(
                    onPressed: _loadStats,
                    child: const Text(
                      'Thử tải lại',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              )
            else
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.6,
                children: _stats!.map((s) {
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          s['n']!,
                          style: const TextStyle(
                            fontFamily: 'Nunito',
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            fontSize: 22,
                          ),
                        ),
                        Text(
                          s['l']!,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            const SizedBox(height: 20),
            const Text(
              '© 2025 HUIT — Đại Học Công Thương TP.HCM',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileLogo extends StatelessWidget {
  final AppColors c;
  const _MobileLogo({required this.c});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: c.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: const HuitLogoMark(),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'HUIT Điểm Danh',
            style: AppTextStyles.displaySm(c.primary).copyWith(fontSize: 18),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  final AppColors c;
  const _FieldLabel(this.text, {required this.c});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: AppTextStyles.bodySm(c.foreground)
            .copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _AuthTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final Widget? trailing;
  final AppColors c;

  const _AuthTextField({
    required this.controller,
    required this.hint,
    required this.icon,
    required this.c,
    this.obscure = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: AppTextStyles.bodyMd(c.foreground),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 18, color: c.mutedForeground),
        suffixIcon: trailing,
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: Color(0xFF991B1B)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, color: Color(0xFF991B1B)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onPressed;
  final AppColors c;

  const _PrimaryButton({
    required this.label,
    required this.loading,
    required this.onPressed,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        child: loading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: c.primaryForeground,
                ),
              )
            : Text(
                label,
                style: AppTextStyles.button(c.primaryForeground)
                    .copyWith(fontSize: 15),
              ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final String label;
  final AppColors c;
  final VoidCallback onTap;
  const _BackButton({
    required this.label,
    required this.c,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.arrow_back, size: 16, color: c.mutedForeground),
          const SizedBox(width: 8),
          Text(
            label,
            style: AppTextStyles.bodySm(c.mutedForeground)
                .copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
