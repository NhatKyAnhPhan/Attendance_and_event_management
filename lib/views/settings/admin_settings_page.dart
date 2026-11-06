import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/theme_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/api/api_client.dart';
import '../../data/api/endpoints.dart';

class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({super.key});

  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  final _client = ApiClient();
  final _gpsController = TextEditingController();
  final _lockController = TextEditingController();
  final _qrController = TextEditingController();
  final _attendanceThresholdController = TextEditingController();
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _events = [];
  String _scopeType = 'global';
  String _scopeId = '';
  bool _inheritGps = false;
  bool _inheritLock = false;
  bool _inheritQr = false;
  bool _inheritAttendanceThreshold = false;
  bool _loading = true;
  bool _saving = false;
  bool _allowEarlyAttendance = false;
  bool _updatingEarlyAttendance = false;
  String? _error;

  bool get _isSpecificScope => _scopeType == 'class' || _scopeType == 'event';
  bool get _isClassScope =>
      _scopeType == 'class' || _scopeType == 'all_classes';

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  @override
  void dispose() {
    _gpsController.dispose();
    _lockController.dispose();
    _qrController.dispose();
    _attendanceThresholdController.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    try {
      final body = await _client.get(ApiEndpoints.adminParameterOptions);
      if (!mounted) return;
      setState(() {
        _classes = _mapList(body['classes']);
        _events = _mapList(body['events']);
      });
      await _loadConfiguration();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> _mapList(dynamic value) => value is List
      ? value.map((item) => Map<String, dynamic>.from(item as Map)).toList()
      : [];

  Future<void> _loadConfiguration() async {
    if (_isSpecificScope && _scopeId.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final query = _isSpecificScope
          ? '?scopeType=$_scopeType&scopeId=${Uri.encodeQueryComponent(_scopeId)}'
          : '?scopeType=$_scopeType';
      final body = await _client.get('${ApiEndpoints.adminParameters}$query');
      if (!mounted) return;
      final overrides = Map<String, dynamic>.from(body['overrides'] as Map);
      final effective = Map<String, dynamic>.from(body['effective'] as Map);
      final global = Map<String, dynamic>.from(body['global'] as Map);
      setState(() {
        _allowEarlyAttendance = global['allowEarlyAttendance'] == true;
        _inheritGps =
            _scopeType != 'global' && overrides['gpsRadiusMeters'] == null;
        _inheritLock =
            _scopeType != 'global' &&
            overrides['eventRegistrationLockHours'] == null;
        _inheritQr =
            _scopeType != 'global' && overrides['qrDurationMinutes'] == null;
        _inheritAttendanceThreshold =
            _scopeType != 'global' &&
            overrides['attendanceThresholdPercent'] == null;
        _gpsController.text =
            (overrides['gpsRadiusMeters'] ?? effective['gpsRadiusMeters'])
                .toString();
        _lockController.text =
            (overrides['eventRegistrationLockHours'] ??
                    effective['eventRegistrationLockHours'])
                .toString();
        _qrController.text =
            (overrides['qrDurationMinutes'] ?? effective['qrDurationMinutes'])
                .toString();
        _attendanceThresholdController.text =
            (overrides['attendanceThresholdPercent'] ??
                    effective['attendanceThresholdPercent'])
                .toString();
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final gps = int.tryParse(_gpsController.text.trim());
    final lock = int.tryParse(_lockController.text.trim());
    final qr = int.tryParse(_qrController.text.trim());
    final attendanceThreshold = int.tryParse(
      _attendanceThresholdController.text.trim(),
    );
    if (gps == null ||
        qr == null ||
        attendanceThreshold == null ||
        (!_isClassScope && lock == null)) {
      _showMessage('Vui lòng nhập tham số bằng số nguyên.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _client.put(
        ApiEndpoints.adminParameters,
        data: {
          'scopeType': _scopeType,
          if (_isSpecificScope) 'scopeId': _scopeId,
          'gpsRadiusMeters': _scopeType != 'global' && _inheritGps ? null : gps,
          'eventRegistrationLockHours': _isClassScope
              ? null
              : _scopeType != 'global' && _inheritLock
              ? null
              : lock,
          'qrDurationMinutes': _scopeType != 'global' && _inheritQr ? null : qr,
          'attendanceThresholdPercent':
              _scopeType != 'global' && _inheritAttendanceThreshold
              ? null
              : attendanceThreshold,
        },
      );
      await _loadConfiguration();
      if (!mounted) return;
      _showMessage('Đã lưu tham số cấu hình.');
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setEarlyAttendance(bool enabled) async {
    setState(() => _updatingEarlyAttendance = true);
    try {
      final body = await _client.put(
        ApiEndpoints.adminEarlyAttendance,
        data: {'allowEarlyAttendance': enabled},
      );
      if (!mounted) return;
      setState(
        () => _allowEarlyAttendance = body['allowEarlyAttendance'] == true,
      );
      _showMessage(
        enabled
            ? 'Đã cho phép mở phiên và điểm danh sự kiện trước giờ bắt đầu trên toàn hệ thống.'
            : 'Đã tắt quyền mở phiên và điểm danh sự kiện trước giờ bắt đầu.',
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _updatingEarlyAttendance = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _changeScopeType(String? value) {
    if (value == null) return;
    setState(() {
      _scopeType = value;
      final options = value == 'class' ? _classes : _events;
      _scopeId = (value != 'class' && value != 'event') || options.isEmpty
          ? ''
          : options.first['id']?.toString() ?? '';
    });
    _loadConfiguration();
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
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cài đặt',
                style: AppTextStyles.displayLg(colors.foreground),
              ),
              const SizedBox(height: 5),
              Text(
                'Quản lý giao diện và tham số vận hành.',
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
                title: 'Tham số hệ thống',
                icon: Icons.tune_rounded,
                child: _buildParameters(colors),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildParameters(AppColors colors) {
    if (_loading && _classes.isEmpty && _events.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }
    final options = _scopeType == 'class'
        ? _classes
        : _scopeType == 'event'
        ? _events
        : <Map<String, dynamic>>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _allowEarlyAttendance,
          onChanged: _loading || _updatingEarlyAttendance
              ? null
              : _setEarlyAttendance,
          title: Text(
            'Cho phép mở phiên và điểm danh sự kiện trước giờ bắt đầu',
            style: AppTextStyles.bodyMd(colors.foreground),
          ),
          subtitle: Text(
            'Cho phép ban tổ chức mở phiên sớm và sinh viên điểm danh sự kiện trước giờ bắt đầu. Áp dụng toàn hệ thống; phù hợp khi demo.',
            style: AppTextStyles.bodySm(colors.mutedForeground),
          ),
          secondary: _updatingEarlyAttendance
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.schedule_outlined, color: colors.primary),
        ),
        const Divider(),
        const SizedBox(height: 8),
        Text(
          'Chọn toàn hệ thống, toàn bộ lớp/sự kiện hoặc cấu hình riêng. Cấu hình riêng được ưu tiên hơn phạm vi rộng.',
          style: AppTextStyles.bodySm(colors.mutedForeground),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          value: _scopeType,
          decoration: const InputDecoration(labelText: 'Phạm vi cài đặt'),
          items: const [
            DropdownMenuItem(value: 'global', child: Text('Toàn hệ thống')),
            DropdownMenuItem(
              value: 'all_classes',
              child: Text('Toàn bộ lớp học phần'),
            ),
            DropdownMenuItem(value: 'class', child: Text('Một lớp học phần')),
            DropdownMenuItem(
              value: 'all_events',
              child: Text('Toàn bộ sự kiện'),
            ),
            DropdownMenuItem(value: 'event', child: Text('Một sự kiện')),
          ],
          onChanged: _changeScopeType,
        ),
        if (_isSpecificScope) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _scopeId.isEmpty ? null : _scopeId,
            decoration: InputDecoration(
              labelText: _scopeType == 'class' ? 'Lớp học phần' : 'Sự kiện',
            ),
            items: options.map((item) {
              final id = item['id'].toString();
              final details = _scopeType == 'class'
                  ? item['subjectName']?.toString()
                  : item['startTime']?.toString();
              return DropdownMenuItem(
                value: id,
                child: Text(
                  '${item['name'] ?? id}${details == null || details.isEmpty ? '' : ' · $details'}',
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: (value) {
              setState(() => _scopeId = value ?? '');
              _loadConfiguration();
            },
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: AppTextStyles.bodySm(Colors.red.shade700)),
        ],
        if (_loading) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
        ],
        const SizedBox(height: 16),
        _parameterField(
          colors,
          label: 'GPS điểm danh',
          unit: 'mét',
          controller: _gpsController,
          inherited: _inheritGps,
          onInheritanceChanged: _scopeType == 'global'
              ? null
              : (value) => setState(() => _inheritGps = value),
          minimum: 10,
          maximum: 5000,
        ),
        if (!_isClassScope) ...[
          const SizedBox(height: 10),
          _parameterField(
            colors,
            label: 'Khóa đăng ký trước khi sự kiện bắt đầu',
            unit: 'giờ',
            controller: _lockController,
            inherited: _inheritLock,
            onInheritanceChanged: _scopeType == 'global'
                ? null
                : (value) => setState(() => _inheritLock = value),
            minimum: 0,
            maximum: 720,
          ),
        ],
        const SizedBox(height: 10),
        _parameterField(
          colors,
          label: 'Thời gian QR có hiệu lực',
          unit: 'phút',
          controller: _qrController,
          inherited: _inheritQr,
          onInheritanceChanged: _scopeType == 'global'
              ? null
              : (value) => setState(() => _inheritQr = value),
          minimum: 1,
          maximum: 180,
        ),
        const SizedBox(height: 10),
        _parameterField(
          colors,
          label: 'Tỷ lệ điểm danh tối thiểu để đạt',
          unit: '%',
          controller: _attendanceThresholdController,
          inherited: _inheritAttendanceThreshold,
          onInheritanceChanged: _scopeType == 'global'
              ? null
              : (value) => setState(() => _inheritAttendanceThreshold = value),
          minimum: 0,
          maximum: 100,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Có mặt và đi trễ được tính là tham dự; buổi vắng có phép vẫn tính là vắng.',
            style: AppTextStyles.bodySm(colors.mutedForeground),
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed:
                _loading || _saving || (_isSpecificScope && _scopeId.isEmpty)
                ? null
                : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Đang lưu...' : 'Lưu tham số'),
          ),
        ),
      ],
    );
  }

  Widget _parameterField(
    AppColors colors, {
    required String label,
    required String unit,
    required TextEditingController controller,
    required bool inherited,
    required ValueChanged<bool>? onInheritanceChanged,
    required int minimum,
    required int maximum,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.bodyMd(colors.foreground),
              ),
            ),
            SizedBox(
              width: 150,
              child: TextFormField(
                controller: controller,
                enabled: onInheritanceChanged == null || !inherited,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  suffixText: unit,
                  helperText: '$minimum–$maximum',
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        if (onInheritanceChanged != null)
          CheckboxListTile(
            value: inherited,
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              'Dùng tham số từ phạm vi rộng hơn',
              style: AppTextStyles.bodyXs(colors.mutedForeground),
            ),
            onChanged: (value) => onInheritanceChanged(value ?? false),
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
}
