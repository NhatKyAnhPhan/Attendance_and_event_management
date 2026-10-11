import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../controllers/auth_controller.dart';
import '../../../core/constants/role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/api/api_client.dart';
import '../../../data/repositories/profile_repository.dart';
import 'profile_info_section.dart';

class ProfileContactEditor extends StatefulWidget {
  const ProfileContactEditor({
    super.key,
    required this.colors,
    required this.readOnlyItems,
    required this.email,
    required this.phone,
    required this.address,
    required this.allowEditing,
    this.allowEditingPersonalDetails = false,
    this.birthDate = 'Chưa cập nhật',
    this.gender = 'Chưa cập nhật',
    this.hometown = 'Chưa cập nhật',
  });

  final AppColors colors;
  final List<ProfileInfoItem> readOnlyItems;
  final String email;
  final String phone;
  final String address;
  final bool allowEditing;
  final bool allowEditingPersonalDetails;
  final String birthDate;
  final String gender;
  final String hometown;

  @override
  State<ProfileContactEditor> createState() => _ProfileContactEditorState();
}

class _ProfileContactEditorState extends State<ProfileContactEditor> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _birthDateController = TextEditingController();
  final _hometownController = TextEditingController();
  final _repository = ProfileRepository();
  String _gender = '';
  bool _editing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _resetFields();
  }

  @override
  void didUpdateWidget(covariant ProfileContactEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing
        && (oldWidget.email != widget.email
            || oldWidget.phone != widget.phone
            || oldWidget.address != widget.address
            || oldWidget.birthDate != widget.birthDate
            || oldWidget.gender != widget.gender
            || oldWidget.hometown != widget.hometown)) {
      _resetFields();
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _birthDateController.dispose();
    _hometownController.dispose();
    super.dispose();
  }

  void _resetFields() {
    _emailController.text = widget.email == 'Chưa cập nhật' ? '' : widget.email;
    _phoneController.text = widget.phone == 'Chưa cập nhật' ? '' : widget.phone;
    _addressController.text =
        widget.address == 'Chưa cập nhật' ? '' : widget.address;
    _birthDateController.text = _dateForInput(widget.birthDate);
    _gender = const {'Nam', 'Nữ', 'Khác'}.contains(widget.gender)
        ? widget.gender
        : '';
    _hometownController.text =
        widget.hometown == 'Chưa cập nhật' ? '' : widget.hometown;
  }

  void _cancel() {
    _resetFields();
    setState(() => _editing = false);
  }

  static String _dateForInput(String value) {
    if (value == 'Chưa cập nhật' || value.trim().isEmpty) return '';
    final parts = value.split('/');
    if (parts.length == 3) {
      return '${parts[2]}-${parts[1].padLeft(2, '0')}-${parts[0].padLeft(2, '0')}';
    }
    return value;
  }

  Future<void> _pickBirthDate() async {
    final initial = DateTime.tryParse(_birthDateController.text)
        ?? DateTime(DateTime.now().year - 18);
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      helpText: 'Chọn ngày sinh',
    );
    if (selected == null || !mounted) return;
    final month = selected.month.toString().padLeft(2, '0');
    final day = selected.day.toString().padLeft(2, '0');
    _birthDateController.text = '${selected.year}-$month-$day';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final updated = await _repository.updateContact(
        email: _emailController.text,
        phone: widget.allowEditingPersonalDetails
            ? _phoneController.text
            : null,
        address: widget.allowEditingPersonalDetails
            ? _addressController.text
            : null,
        birthDate: widget.allowEditingPersonalDetails
            ? _birthDateController.text
            : null,
        gender: widget.allowEditingPersonalDetails ? _gender : null,
        hometown: widget.allowEditingPersonalDetails
            ? _hometownController.text
            : null,
      );
      final auth = Get.find<AuthController>();
      final merged = <String, dynamic>{...?auth.currentUser.value, ...updated};
      auth.currentUser.value = merged;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('currentUser', jsonEncode(merged));
      if (!mounted) return;
      setState(() => _editing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cập nhật thông tin thành công')),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showChangePassword() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ChangePasswordDialog(repository: _repository),
    );
    if (changed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đổi mật khẩu thành công')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = Get.find<AuthController>().role.value;
    final canEditEmail = widget.allowEditing || role == Role.lecturer;
    final canChangePassword = role == Role.student
        || role == Role.lecturer
        || role == Role.organizer;
    final contactItems = [
      ProfileInfoItem(
        icon: Icons.phone_outlined,
        label: 'Số điện thoại',
        value: widget.phone,
      ),
      ProfileInfoItem(
        icon: Icons.email_outlined,
        label: 'Email',
        value: widget.email,
      ),
      ProfileInfoItem(
        icon: Icons.location_on_outlined,
        label: 'Địa chỉ hiện tại',
        value: widget.address,
      ),
    ];
    final readOnlyContactItems = [
      contactItems.first,
      contactItems.last,
    ];
    final personalReadOnlyItems = widget.allowEditingPersonalDetails
        ? widget.readOnlyItems
              .where(
                (item) => !const {'Ngày sinh', 'Giới tính', 'Quê quán'}
                    .contains(item.label),
              )
              .toList()
        : widget.readOnlyItems;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProfileInfoSection(
          title: 'Thông tin cá nhân',
          colors: widget.colors,
          items: _editing
              ? [
                  ...personalReadOnlyItems,
                  ...(widget.allowEditingPersonalDetails
                      ? [contactItems[1]]
                      : readOnlyContactItems),
                ]
              : [...widget.readOnlyItems, ...contactItems],
        ),
        if (_editing) ...[
          const SizedBox(height: 12),
          Form(
            key: _formKey,
            child: TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                final email = value?.trim() ?? '';
                if (email.isEmpty) return 'Vui lòng nhập email.';
                if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
                  return 'Email không đúng định dạng.';
                }
                if (email.length > 150) {
                  return 'Email không được vượt quá 150 ký tự.';
                }
                return null;
              },
            ),
          ),
          if (widget.allowEditingPersonalDetails) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Số điện thoại',
                prefixIcon: Icon(Icons.phone_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _addressController,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Địa chỉ hiện tại',
                prefixIcon: Icon(Icons.location_on_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _birthDateController,
              readOnly: true,
              onTap: _pickBirthDate,
              decoration: const InputDecoration(
                labelText: 'Ngày sinh',
                prefixIcon: Icon(Icons.cake_outlined),
                suffixIcon: Icon(Icons.calendar_month_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _gender,
              decoration: const InputDecoration(
                labelText: 'Giới tính',
                prefixIcon: Icon(Icons.wc_outlined),
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: '', child: Text('Chưa cung cấp')),
                DropdownMenuItem(value: 'Nam', child: Text('Nam')),
                DropdownMenuItem(value: 'Nữ', child: Text('Nữ')),
                DropdownMenuItem(value: 'Khác', child: Text('Khác')),
              ],
              onChanged: (value) => setState(() => _gender = value ?? ''),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _hometownController,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Quê quán',
                prefixIcon: Icon(Icons.home_outlined),
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (!widget.allowEditingPersonalDetails)
            Text(
              'Số điện thoại và địa chỉ hiện tại đang chỉ đọc.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: widget.colors.mutedForeground),
            ),
        ],
        if (canEditEmail || canChangePassword) ...[
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: _editing
                ? [
                    OutlinedButton(
                      onPressed: _saving ? null : _cancel,
                      child: const Text('Hủy'),
                    ),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Lưu thay đổi'),
                    ),
                  ]
                : [
                    if (canEditEmail)
                      OutlinedButton.icon(
                        onPressed: () => setState(() => _editing = true),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Chỉnh sửa thông tin'),
                      ),
                    if (canChangePassword)
                      OutlinedButton.icon(
                        onPressed: _showChangePassword,
                        icon: const Icon(Icons.lock_reset_outlined),
                        label: const Text('Đổi mật khẩu'),
                      ),
                  ],
          ),
        ],
      ],
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.repository});

  final ProfileRepository repository;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _saving = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    try {
      await widget.repository.changePassword(
        currentPassword: _currentPasswordController.text,
        newPassword: _newPasswordController.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Đổi mật khẩu'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _currentPasswordController,
                obscureText: _obscurePassword,
                autofillHints: const [AutofillHints.password],
                decoration: const InputDecoration(
                  labelText: 'Mật khẩu hiện tại',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.isEmpty
                    ? 'Vui lòng nhập mật khẩu hiện tại.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _newPasswordController,
                obscureText: _obscurePassword,
                autofillHints: const [AutofillHints.newPassword],
                decoration: const InputDecoration(
                  labelText: 'Mật khẩu mới',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final password = value ?? '';
                  if (password.length < 8) {
                    return 'Mật khẩu mới phải có ít nhất 8 ký tự.';
                  }
                  if (utf8.encode(password).length > 72) {
                    return 'Mật khẩu mới không được vượt quá 72 byte.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _obscurePassword,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: 'Xác nhận mật khẩu mới',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                    onPressed: () => setState(
                      () => _obscurePassword = !_obscurePassword,
                    ),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) => value != _newPasswordController.text
                    ? 'Xác nhận mật khẩu không khớp.'
                    : null,
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Đổi mật khẩu'),
        ),
      ],
    );
  }
}