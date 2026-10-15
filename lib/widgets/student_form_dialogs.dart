import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/auth_controller.dart';
import '../controllers/classes_controller.dart';
import '../controllers/events_controller.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../data/api/api_client.dart';
import '../data/models/student_summaries.dart';
import '../data/repositories/profile_repository.dart';

enum StudentFeedbackTarget { event, classSection }

String _studentCode() {
  if (!Get.isRegistered<AuthController>()) return '';
  final user = Get.find<AuthController>().currentUser.value ?? const {};
  for (final key in const ['id', 'studentCode', 'studentId', 'Masv']) {
    final value = user[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return '';
}

String _eventSubtitle(StudentEventSummary event) {
  final place = event.location.trim().isEmpty ? event.org : event.location;
  final start = event.startTime;
  final end = event.endTime;
  if (start == null) {
    return [place, event.date].where((e) => e.isNotEmpty).join(' · ');
  }
  final date = DateFormat('dd/MM/yyyy HH:mm').format(start);
  final endText = end == null ? '' : ' - ${DateFormat('HH:mm').format(end)}';
  return [place, '$date$endText'].where((e) => e.isNotEmpty).join(' · ');
}

Future<void> showStudentRegistrationDialog({
  required BuildContext context,
  required List<StudentEventSummary> events,
  required Future<bool> Function(StudentEventSummary event) onSubmit,
  String? initialEventId,
}) async {
  final available = events
      .where((event) => !event.registered && !event.isEnded)
      .toList();
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .42),
    builder: (_) => _StudentRegistrationDialog(
      events: available,
      initialEventId: initialEventId,
      onSubmit: onSubmit,
    ),
  );
}

class _StudentRegistrationDialog extends StatefulWidget {
  const _StudentRegistrationDialog({
    required this.events,
    required this.initialEventId,
    required this.onSubmit,
  });

  final List<StudentEventSummary> events;
  final String? initialEventId;
  final Future<bool> Function(StudentEventSummary event) onSubmit;

  @override
  State<_StudentRegistrationDialog> createState() =>
      _StudentRegistrationDialogState();
}

class _StudentRegistrationDialogState
    extends State<_StudentRegistrationDialog> {
  final _studentFormKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _profileRepository = ProfileRepository();

  StudentEventSummary? _selectedEvent;
  Map<String, dynamic>? _eventDetails;
  String? _detailsError;
  String? _submitError;
  String _originalEmail = '';
  String _originalPhone = '';
  String _originalAddress = '';
  int _step = 0;
  int _detailsRequest = 0;
  bool _loadingDetails = false;
  bool _submitting = false;

  AuthController? get _authController =>
      Get.isRegistered<AuthController>() ? Get.find<AuthController>() : null;

  EventsController? get _eventsController =>
      Get.isRegistered<EventsController>()
      ? Get.find<EventsController>()
      : null;

  Map<String, dynamic> get _user =>
      _authController?.currentUser.value ?? const <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    for (final event in widget.events) {
      if (event.id == widget.initialEventId) {
        _selectedEvent = event;
        break;
      }
    }
    _originalEmail = _userValue(const ['email']);
    _originalPhone = _userValue(const ['phone']);
    _originalAddress = _userValue(const ['address', 'currentAddress']);
    _emailController.text = _originalEmail;
    _phoneController.text = _originalPhone;
    _addressController.text = _originalAddress;
    if (_selectedEvent != null) _loadEventDetails(_selectedEvent!);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  String _userValue(List<String> keys) {
    for (final key in keys) {
      final value = _user[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  Future<void> _loadEventDetails(StudentEventSummary event) async {
    final controller = _eventsController;
    final request = ++_detailsRequest;
    setState(() {
      _loadingDetails = true;
      _detailsError = null;
      _eventDetails = null;
    });
    if (controller == null) {
      setState(() {
        _loadingDetails = false;
        _detailsError = 'Không thể tải chi tiết sự kiện.';
      });
      return;
    }
    try {
      final details = await controller.getDetails(event.id);
      if (!mounted || request != _detailsRequest) return;
      setState(() {
        _eventDetails = details;
        _loadingDetails = false;
      });
    } catch (error) {
      if (!mounted || request != _detailsRequest) return;
      setState(() {
        _detailsError = error is ApiException
            ? error.message
            : 'Không tải được chi tiết sự kiện.';
        _loadingDetails = false;
      });
    }
  }

  void _selectEvent(StudentEventSummary? event) {
    if (event == null || event.id == _selectedEvent?.id) return;
    setState(() {
      _selectedEvent = event;
      _submitError = null;
    });
    _loadEventDetails(event);
  }

  void _continue() {
    if (_selectedEvent == null) {
      setState(() => _detailsError = 'Vui lòng chọn sự kiện');
      return;
    }
    if (_loadingDetails || _eventDetails == null || _detailsError != null) {
      return;
    }
    setState(() {
      _step = 1;
      _submitError = null;
    });
  }

  Future<void> _submit() async {
    if (!_studentFormKey.currentState!.validate() || _selectedEvent == null) {
      return;
    }
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    var shouldClose = false;
    try {
      final email = _emailController.text.trim();
      final phone = _phoneController.text.trim();
      final address = _addressController.text.trim();
      final profileChanged =
          email != _originalEmail ||
          phone != _originalPhone ||
          address != _originalAddress;
      if (profileChanged) {
        final updated = await _profileRepository.updateContact(
          email: email,
          phone: phone,
          address: address,
        );
        if (!mounted) return;
        final authController = _authController;
        if (authController != null) {
          final merged = <String, dynamic>{
            ...?authController.currentUser.value,
            ...updated,
          };
          authController.currentUser.value = merged;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('currentUser', jsonEncode(merged));
          if (!mounted) return;
        }
        _originalEmail = email;
        _originalPhone = phone;
        _originalAddress = address;
      }
      final success = await widget.onSubmit(_selectedEvent!);
      if (!mounted) return;
      shouldClose = success;
    } on ApiException catch (error) {
      if (mounted) setState(() => _submitError = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _submitError = 'Không thể hoàn tất đăng ký sự kiện.');
      }
    } finally {
      if (mounted && !shouldClose) setState(() => _submitting = false);
    }
    if (shouldClose && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(Theme.of(context).brightness == Brightness.dark);
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 620;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 28,
        vertical: compact ? 12 : 24,
      ),
      backgroundColor: c.card,
      surfaceTintColor: Colors.transparent,
      elevation: 18,
      shadowColor: Colors.black.withValues(alpha: .16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 740,
          maxHeight: size.height * (compact ? .94 : .90),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(c, compact),
            Divider(height: 1, color: c.border),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  compact ? 16 : 24,
                  20,
                  compact ? 16 : 24,
                  24,
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _step == 0
                      ? _buildEventStep(c, compact)
                      : _buildStudentStep(c, compact),
                ),
              ),
            ),
            Divider(height: 1, color: c.border),
            _buildFooter(c, compact),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppColors c, bool compact) => Padding(
    padding: EdgeInsets.fromLTRB(compact ? 16 : 24, 18, 12, 16),
    child: Column(
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: c.secondary,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                Icons.event_available_outlined,
                color: c.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                'Đăng ký sự kiện',
                style: AppTextStyles.displaySm(c.foreground)
                    .copyWith(fontSize: compact ? 19 : 21),
              ),
            ),
            IconButton(
              tooltip: 'Đóng',
              onPressed: _submitting ? null : () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _WizardProgress(step: _step, compact: compact),
      ],
    ),
  );

  Widget _buildEventStep(AppColors c, bool compact) => Column(
    key: const ValueKey('event-step'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Bước 1/2 — Thông tin sự kiện',
        style: AppTextStyles.displayXs(c.foreground),
      ),
      const SizedBox(height: 18),
      const _FieldLabel('Sự kiện', required: true),
      DropdownButtonFormField<StudentEventSummary>(
        initialValue: _selectedEvent,
        isExpanded: true,
        itemHeight: 64,
        menuMaxHeight: 360,
        borderRadius: BorderRadius.circular(14),
        decoration: _inputDecoration('Chọn sự kiện').copyWith(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 8,
          ),
          prefixIcon: const Icon(Icons.event_outlined, size: 20),
        ),
        selectedItemBuilder: (context) => widget.events
            .map(
              (event) => Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  event.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySm(c.foreground),
                ),
              ),
            )
            .toList(),
        items: widget.events
            .map(
              (event) => DropdownMenuItem(
                value: event,
                child: _OptionText(
                  title: event.name,
                  subtitle: _eventSubtitle(event),
                ),
              ),
            )
            .toList(),
        onChanged: _submitting ? null : _selectEvent,
      ),
      if (widget.events.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Hiện không có sự kiện phù hợp để đăng ký.',
            style: AppTextStyles.bodyXs(c.mutedForeground),
          ),
        ),
      const SizedBox(height: 18),
      if (_loadingDetails)
        _LoadingEventCard(c)
      else if (_detailsError != null)
        _ErrorEventCard(
          message: _detailsError!,
          onRetry: _selectedEvent == null
              ? null
              : () => _loadEventDetails(_selectedEvent!),
        )
      else if (_selectedEvent != null && _eventDetails != null)
        _EventRegistrationDetails(
          event: _selectedEvent!,
          details: _eventDetails!,
          compact: compact,
        ),
    ],
  );

  Widget _buildStudentStep(AppColors c, bool compact) {
    final studentCode = _studentCode();
    final name = _userValue(const ['name', 'fullName', 'hoTen']);
    final className = _userValue(const ['className']);
    final major = _userValue(const ['major']);
    return Form(
      key: _studentFormKey,
      child: Column(
        key: const ValueKey('student-step'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bước 2/2 — Thông tin sinh viên',
            style: AppTextStyles.displayXs(c.foreground),
          ),
          const SizedBox(height: 18),
          _RegistrationField(
            label: 'MSSV',
            value: studentCode,
            required: true,
            readOnly: true,
            icon: Icons.badge_outlined,
            validator: (_) =>
                studentCode.isEmpty ? 'Không tìm thấy mã sinh viên' : null,
          ),
          const SizedBox(height: 14),
          _RegistrationField(
            label: 'Họ tên',
            value: name,
            required: true,
            readOnly: true,
            icon: Icons.person_outline_rounded,
            validator: (_) => name.isEmpty ? 'Không tìm thấy họ tên' : null,
          ),
          const SizedBox(height: 14),
          _RegistrationField(
            label: 'Email',
            controller: _emailController,
            required: true,
            enabled: !_submitting,
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              final email = value?.trim() ?? '';
              if (email.isEmpty) return 'Vui lòng nhập email';
              if (email.length > 150 ||
                  !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
                return 'Email không hợp lệ';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          _RegistrationField(
            label: 'Số điện thoại',
            controller: _phoneController,
            enabled: !_submitting,
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            validator: (value) {
              final phone = value?.trim() ?? '';
              if (phone.isNotEmpty &&
                  (phone.length > 15 ||
                      !RegExp(r'^[0-9+()\-\s]+$').hasMatch(phone))) {
                return 'Số điện thoại không hợp lệ';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          _RegistrationField(
            label: 'Địa chỉ',
            controller: _addressController,
            enabled: !_submitting,
            icon: Icons.home_outlined,
            maxLength: 200,
            maxLines: compact ? 2 : 3,
            validator: (value) => (value?.trim().length ?? 0) > 200
                ? 'Địa chỉ không được vượt quá 200 ký tự'
                : null,
          ),
          const SizedBox(height: 14),
          _RegistrationField(
            label: 'Lớp',
            value: className,
            readOnly: true,
            icon: Icons.groups_outlined,
          ),
          const SizedBox(height: 14),
          _RegistrationField(
            label: 'Chuyên ngành',
            value: major,
            readOnly: true,
            icon: Icons.school_outlined,
          ),
          const SizedBox(height: 18),
          const _InfoBox(
            text: 'Thông tin được lấy từ hồ sơ sinh viên hiện tại. Các thay đổi hợp lệ sẽ được cập nhật vào hồ sơ trước khi đăng ký.',
          ),
          if (_submitError != null) ...[
            const SizedBox(height: 12),
            Text(_submitError!, style: AppTextStyles.bodySm(c.danger)),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter(AppColors c, bool compact) {
    final secondary = _step == 1
        ? OutlinedButton.icon(
            onPressed: _submitting ? null : () => setState(() => _step = 0),
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('Quay lại'),
          )
        : OutlinedButton(
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
            child: const Text('Hủy'),
          );
    final primary = FilledButton.icon(
      onPressed: _submitting
          ? null
          : _step == 0
          ? (_selectedEvent != null &&
                    _eventDetails != null &&
                    !_loadingDetails &&
                    _detailsError == null
                ? _continue
                : null)
          : _submit,
      icon: _submitting
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(
              _step == 0 ? Icons.arrow_forward_rounded : Icons.check_rounded,
            ),
      label: Text(_step == 0 ? 'Tiếp tục' : 'Xác nhận đăng ký'),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 24,
        14,
        compact ? 16 : 24,
        18,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 380) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [primary, const SizedBox(height: 8), secondary],
            );
          }
          return Row(children: [secondary, const Spacer(), primary]);
        },
      ),
    );
  }
}

class _WizardProgress extends StatelessWidget {
  const _WizardProgress({required this.step, required this.compact});
  final int step;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(Theme.of(context).brightness == Brightness.dark);
    Widget marker(int index, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: step >= index ? c.primary : c.muted,
            shape: BoxShape.circle,
            border: Border.all(color: step >= index ? c.primary : c.border),
          ),
          child: Text(
            '${index + 1}',
            style: AppTextStyles.bodyXs(
              step >= index ? c.primaryForeground : c.mutedForeground,
            ).copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        if (!compact) ...[
          const SizedBox(width: 8),
          Text(
            label,
            style: AppTextStyles.bodySm(
              step >= index ? c.primary : c.mutedForeground,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ],
    );
    return Row(
      children: [
        marker(0, 'Thông tin sự kiện'),
        Expanded(
          child: Container(
            height: 2,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            color: step == 1 ? c.primary : c.border,
          ),
        ),
        marker(1, 'Thông tin sinh viên'),
      ],
    );
  }
}

class _LoadingEventCard extends StatelessWidget {
  const _LoadingEventCard(this.c);
  final AppColors c;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: c.muted.withValues(alpha: .55),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: c.border),
    ),
    child: const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 12),
        Text('Đang tải chi tiết sự kiện...'),
      ],
    ),
  );
}

class _ErrorEventCard extends StatelessWidget {
  const _ErrorEventCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(Theme.of(context).brightness == Brightness.dark);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.danger.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.danger.withValues(alpha: .25)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: c.danger),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: AppTextStyles.bodySm(c.danger))),
          if (onRetry != null)
            IconButton(
              tooltip: 'Tải lại',
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
    );
  }
}

class _EventRegistrationDetails extends StatelessWidget {
  const _EventRegistrationDetails({
    required this.event,
    required this.details,
    required this.compact,
  });
  final StudentEventSummary event;
  final Map<String, dynamic> details;
  final bool compact;

  String _text(String key, String fallback) {
    final value = details[key]?.toString().trim() ?? '';
    return value.isEmpty ? fallback : value;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(Theme.of(context).brightness == Brightness.dark);
    final start =
        DateTime.tryParse(details['startTime']?.toString() ?? '')?.toLocal() ??
        event.startTime;
    final end =
        DateTime.tryParse(details['endTime']?.toString() ?? '')?.toLocal() ??
        event.endTime;
    final capacity =
        num.tryParse(details['capacity']?.toString() ?? '')?.round() ?? 0;
    final registered =
        num.tryParse(details['registeredCount']?.toString() ?? '')?.round() ??
        0;
    final benefits = (details['benefits'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final rules = (details['rules'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final status = event.eventStatus.isNotEmpty
        ? event.eventStatus
        : _text('status', 'Chưa cập nhật');
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 16 : 20),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .035),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _text('name', event.name),
            style: AppTextStyles.displayXs(c.foreground),
          ),
          const SizedBox(height: 12),
          _DetailLine(label: 'Mã sự kiện', value: event.id),
          _DetailLine(
            label: 'Đơn vị tổ chức',
            value: _text('organizerName', event.org),
          ),
          const SizedBox(height: 10),
          _ResponsiveDetailGrid(
            compact: compact,
            children: [
              _DetailTile(
                icon: Icons.calendar_today_outlined,
                label: 'Thời gian bắt đầu',
                value: start == null
                    ? 'Chưa cập nhật'
                    : DateFormat('dd/MM/yyyy HH:mm').format(start),
              ),
              _DetailTile(
                icon: Icons.event_busy_outlined,
                label: 'Thời gian kết thúc',
                value: end == null
                    ? 'Chưa cập nhật'
                    : DateFormat('dd/MM/yyyy HH:mm').format(end),
              ),
              _DetailTile(
                icon: Icons.location_on_outlined,
                label: 'Địa điểm',
                value: _text(
                  'location',
                  event.location.isEmpty ? 'Chưa cập nhật' : event.location,
                ),
              ),
              _DetailTile(
                icon: Icons.groups_outlined,
                label: 'Số lượng đăng ký',
                value: capacity > 0
                    ? '$registered / $capacity sinh viên'
                    : '$registered sinh viên',
              ),
              _DetailTile(
                icon: Icons.info_outline_rounded,
                label: 'Trạng thái',
                value: status,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _TextSection(
            title: 'Mô tả',
            text: _text('description', 'Chưa có mô tả cho sự kiện này.'),
          ),
          const SizedBox(height: 14),
          _ListSection(
            title: 'Quyền lợi',
            emptyText: 'Chưa có thông tin quyền lợi.',
            items: benefits.map((benefit) {
              final points =
                  num.tryParse(benefit['points']?.toString() ?? '')?.round() ??
                  0;
              final content = benefit['content']?.toString().trim() ?? '';
              final type = benefit['type']?.toString().trim() ?? 'Quyền lợi';
              return '$type${points > 0 ? ' · $points điểm' : ''}'
                  '${content.isEmpty ? '' : ': $content'}';
            }).toList(),
          ),
          const SizedBox(height: 14),
          _ListSection(
            title: 'Nội quy',
            emptyText: 'Chưa có nội quy.',
            items: rules
                .map((rule) => rule['text']?.toString().trim() ?? '')
                .where((text) => text.isNotEmpty)
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _ResponsiveDetailGrid extends StatelessWidget {
  const _ResponsiveDetailGrid({required this.compact, required this.children});
  final bool compact;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Column(
        children: children
            .map(
              (child) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: child,
              ),
            )
            .toList(),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: children
              .map((child) => SizedBox(width: width, child: child))
              .toList(),
        );
      },
    );
  }
}

class _DetailTile extends StatelessWidget {
  const _DetailTile({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(Theme.of(context).brightness == Brightness.dark);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: c.primary, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.bodyXs(c.mutedForeground)),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: AppTextStyles.bodySm(c.foreground)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(Theme.of(context).brightness == Brightness.dark);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(
        TextSpan(
          text: '$label: ',
          style: AppTextStyles.bodySm(c.mutedForeground),
          children: [
            TextSpan(
              text: value,
              style: AppTextStyles.bodySm(c.foreground)
                  .copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _TextSection extends StatelessWidget {
  const _TextSection({required this.title, required this.text});
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(Theme.of(context).brightness == Brightness.dark);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTextStyles.bodySm(c.foreground)
              .copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          text,
          style: AppTextStyles.bodySm(c.foreground).copyWith(height: 1.5),
        ),
      ],
    );
  }
}

class _ListSection extends StatelessWidget {
  const _ListSection({
    required this.title,
    required this.emptyText,
    required this.items,
  });
  final String title;
  final String emptyText;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(Theme.of(context).brightness == Brightness.dark);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTextStyles.bodySm(c.foreground)
              .copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        if (items.isEmpty)
          Text(emptyText, style: AppTextStyles.bodySm(c.mutedForeground))
        else
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: c.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      item,
                      style: AppTextStyles.bodySm(c.foreground)
                          .copyWith(height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _RegistrationField extends StatelessWidget {
  const _RegistrationField({
    required this.label,
    required this.icon,
    this.controller,
    this.value,
    this.required = false,
    this.readOnly = false,
    this.enabled = true,
    this.keyboardType,
    this.maxLines = 1,
    this.maxLength,
    this.validator,
  });
  final String label;
  final IconData icon;
  final TextEditingController? controller;
  final String? value;
  final bool required;
  final bool readOnly;
  final bool enabled;
  final TextInputType? keyboardType;
  final int maxLines;
  final int? maxLength;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(Theme.of(context).brightness == Brightness.dark);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label, required: required),
        TextFormField(
          controller: controller,
          initialValue: controller == null ? value : null,
          readOnly: readOnly,
          enabled: enabled,
          keyboardType: keyboardType,
          maxLines: maxLines,
          maxLength: maxLength,
          decoration: _inputDecoration(label).copyWith(
            filled: readOnly,
            fillColor: readOnly ? c.muted.withValues(alpha: .7) : null,
            prefixIcon: Icon(icon, size: 20),
          ),
          validator: validator,
        ),
      ],
    );
  }
}

Future<void> showStudentFeedbackDialog({
  required BuildContext context,
  required EventsController eventsController,
  required ClassesController classesController,
  StudentFeedbackTarget initialTarget = StudentFeedbackTarget.event,
  String? initialItemId,
}) => _showFeedbackOrRatingDialog(
  context: context,
  eventsController: eventsController,
  classesController: classesController,
  initialTarget: initialTarget,
  initialItemId: initialItemId,
  isRating: false,
);

Future<void> showStudentRatingDialog({
  required BuildContext context,
  required EventsController eventsController,
  required ClassesController classesController,
  StudentFeedbackTarget initialTarget = StudentFeedbackTarget.event,
  String? initialItemId,
}) => _showFeedbackOrRatingDialog(
  context: context,
  eventsController: eventsController,
  classesController: classesController,
  initialTarget: initialTarget,
  initialItemId: initialItemId,
  isRating: true,
);

Future<void> _showFeedbackOrRatingDialog({
  required BuildContext context,
  required EventsController eventsController,
  required ClassesController classesController,
  required StudentFeedbackTarget initialTarget,
  required String? initialItemId,
  required bool isRating,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .42),
    builder: (_) => _FeedbackOrRatingDialog(
      eventsController: eventsController,
      classesController: classesController,
      initialTarget: initialTarget,
      initialItemId: initialItemId,
      isRating: isRating,
      messenger: messenger,
    ),
  );
}

class _FeedbackOrRatingDialog extends StatefulWidget {
  const _FeedbackOrRatingDialog({
    required this.eventsController,
    required this.classesController,
    required this.initialTarget,
    required this.initialItemId,
    required this.isRating,
    required this.messenger,
  });

  final EventsController eventsController;
  final ClassesController classesController;
  final StudentFeedbackTarget initialTarget;
  final String? initialItemId;
  final bool isRating;
  final ScaffoldMessengerState? messenger;

  @override
  State<_FeedbackOrRatingDialog> createState() =>
      _FeedbackOrRatingDialogState();
}

class _FeedbackOrRatingDialogState extends State<_FeedbackOrRatingDialog> {
  final _formKey = GlobalKey<FormState>();
  final _commentController = TextEditingController();
  late StudentFeedbackTarget _target;
  String? _selectedId;
  int _rating = 0;
  bool _submitting = false;
  bool _showHistory = false;
  bool _loadingHistory = false;
  bool _historyLoaded = false;
  String? _historyError;
  List<Map<String, dynamic>> _historyItems = const [];

  bool get _isEvent => _target == StudentFeedbackTarget.event;

  @override
  void initState() {
    super.initState();
    _target = widget.initialTarget;
    _selectedId = widget.initialItemId;
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final comment = _commentController.text.trim();
      if (_isEvent) {
        if (widget.isRating) {
          await widget.eventsController.submitRating(
            eventId: _selectedId!,
            rating: _rating,
            comment: comment,
          );
        } else {
          await widget.eventsController.submitComment(
            eventId: _selectedId!,
            comment: comment,
          );
        }
        await widget.eventsController.load();
      } else {
        if (widget.isRating) {
          await widget.classesController.submitRating(
            classId: _selectedId!,
            rating: _rating,
            comment: comment,
          );
        } else {
          await widget.classesController.submitComment(
            classId: _selectedId!,
            comment: comment,
          );
        }
        await widget.classesController.load();
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      if (widget.messenger?.mounted ?? false) {
        widget.messenger!.showSnackBar(
          SnackBar(
            content: Text(
              widget.isRating ? 'Đã gửi đánh giá.' : 'Đã gửi phản hồi.',
            ),
          ),
        );
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      if (widget.messenger?.mounted ?? false) {
        widget.messenger!.showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      if (widget.messenger?.mounted ?? false) {
        widget.messenger!.showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loadingHistory = true;
      _historyError = null;
    });
    try {
      final data = await widget.eventsController.getMyFeedback();
      if (!mounted) return;
      final rawItems = data[widget.isRating ? 'ratingItems' : 'feedbackItems'];
      setState(() {
        _historyItems = rawItems is List
            ? rawItems
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList()
            : const [];
        _historyLoaded = true;
        _loadingHistory = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _historyError = error.message;
        _loadingHistory = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _historyError = 'Không thể tải lịch sử đã gửi.';
        _loadingHistory = false;
      });
    }
  }

  void _changeView(bool showComposer) {
    if (_submitting) return;
    setState(() => _showHistory = !showComposer);
    if (!showComposer && !_historyLoaded && !_loadingHistory) {
      _loadHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = widget.eventsController.items
        .where((event) => event.registered && event.isEnded)
        .toList();
    final classes = widget.classesController.items;
    final validIds = _isEvent
        ? events.map((event) => event.id)
        : classes.map((item) => item.id);
    if (!validIds.contains(_selectedId)) _selectedId = null;

    return _StudentDialogShell(
      icon: widget.isRating
          ? Icons.star_outline_rounded
          : Icons.chat_bubble_outline_rounded,
      iconColor: widget.isRating ? const Color(0xFFD97706) : null,
      iconBackground: widget.isRating ? const Color(0xFFFFF7E6) : null,
      title: widget.isRating
          ? 'Đánh giá ${_isEvent ? 'sự kiện' : 'lớp học phần'}'
          : 'Gửi phản hồi',
      subtitle: widget.isRating
          ? 'Hãy đánh giá và chia sẻ cảm nhận của bạn'
          : 'Chia sẻ ý kiến, góp ý của bạn về sự kiện hoặc lớp học',
      primaryLabel: widget.isRating ? 'Gửi đánh giá' : 'Gửi phản hồi',
      submitting: _submitting,
      onPrimary: _submit,
      showPrimary: !_showHistory,
      cancelLabel: _showHistory ? 'Đóng' : 'Hủy',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SegmentedChoice(
            firstLabel: widget.isRating ? 'Gửi đánh giá' : 'Gửi phản hồi',
            secondLabel: widget.isRating
                ? 'Đánh giá đã gửi'
                : 'Phản hồi đã gửi',
            firstSelected: !_showHistory,
            onChanged: _changeView,
          ),
          const SizedBox(height: 20),
          if (_showHistory)
            _FeedbackHistoryView(
              isRating: widget.isRating,
              loading: _loadingHistory,
              error: _historyError,
              items: _historyItems,
              onRetry: _loadHistory,
            )
          else
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SegmentedChoice(
                    firstLabel: widget.isRating
                        ? 'Đánh giá sự kiện'
                        : 'Phản hồi về sự kiện',
                    secondLabel: widget.isRating
                        ? 'Đánh giá lớp học phần'
                        : 'Phản hồi về lớp học phần',
                    firstSelected: _isEvent,
                    onChanged: _submitting
                        ? null
                        : (first) => setState(() {
                            _target = first
                                ? StudentFeedbackTarget.event
                                : StudentFeedbackTarget.classSection;
                            _selectedId = null;
                          }),
                  ),
                  const SizedBox(height: 18),
                  _FieldLabel(
                    _isEvent ? 'Sự kiện' : 'Lớp học phần',
                    required: true,
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedId,
                    isExpanded: true,
                    isDense: false,
                    itemHeight: 64,
                    menuMaxHeight: 360,
                    borderRadius: BorderRadius.circular(14),
                    decoration: _inputDecoration(
                      _isEvent ? 'Chọn sự kiện' : 'Chọn lớp học phần',
                    ),
                    selectedItemBuilder: (context) =>
                        (_isEvent
                                ? events.map((event) => event.name)
                                : classes.map((item) => item.name))
                            .map(
                              (name) => Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                    items: _isEvent
                        ? events
                              .map(
                                (event) => DropdownMenuItem(
                                  value: event.id,
                                  child: _OptionText(
                                    title: event.name,
                                    subtitle: _eventSubtitle(event),
                                  ),
                                ),
                              )
                              .toList()
                        : classes
                              .map(
                                (item) => DropdownMenuItem(
                                  value: item.id,
                                  child: _OptionText(
                                    title: item.name,
                                    subtitle: '${item.id} · ${item.lecturer}',
                                  ),
                                ),
                              )
                              .toList(),
                    onChanged: _submitting
                        ? null
                        : (value) => setState(() => _selectedId = value),
                    validator: (value) => value == null
                        ? 'Vui lòng chọn ${_isEvent ? 'sự kiện' : 'lớp học phần'}'
                        : null,
                  ),
                  const SizedBox(height: 18),
                  const _StudentCodeField(),
                  if (widget.isRating) ...[
                    const SizedBox(height: 18),
                    const _FieldLabel('Số sao', required: true),
                    FormField<int>(
                      validator: (_) =>
                          _rating == 0 ? 'Vui lòng chọn số sao' : null,
                      builder: (field) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 3,
                            children: List.generate(
                              5,
                              (index) => IconButton(
                                tooltip: '${index + 1} sao',
                                visualDensity: VisualDensity.compact,
                                onPressed: _submitting
                                    ? null
                                    : () {
                                        setState(() => _rating = index + 1);
                                        field.didChange(_rating);
                                      },
                                iconSize: 32,
                                color: const Color(0xFFF59E0B),
                                icon: Icon(
                                  index < _rating
                                      ? Icons.star_rounded
                                      : Icons.star_border_rounded,
                                ),
                              ),
                            ),
                          ),
                          Text(
                            'Chọn số sao từ 1 đến 5',
                            style: AppTextStyles.bodyXs(
                              AppColors.light.mutedForeground,
                            ),
                          ),
                          if (field.hasError) ...[
                            const SizedBox(height: 6),
                            Text(
                              field.errorText!,
                              style: const TextStyle(
                                color: Color(0xFFDC2626),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  _FieldLabel(
                    widget.isRating ? 'Nội dung đánh giá' : 'Nội dung phản hồi',
                    required: !widget.isRating,
                  ),
                  TextFormField(
                    controller: _commentController,
                    enabled: !_submitting,
                    minLines: 4,
                    maxLines: 6,
                    maxLength: 1000,
                    decoration: _inputDecoration(
                      widget.isRating
                          ? 'Chia sẻ thêm cảm nhận của bạn (không bắt buộc)...'
                          : 'Nhập nội dung phản hồi của bạn...',
                    ).copyWith(alignLabelWithHint: true),
                    validator: (value) {
                      if (!widget.isRating &&
                          (value == null || value.trim().isEmpty)) {
                        return 'Vui lòng nhập nội dung phản hồi';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _FeedbackHistoryView extends StatelessWidget {
  const _FeedbackHistoryView({
    required this.isRating,
    required this.loading,
    required this.error,
    required this.items,
    required this.onRetry,
  });

  final bool isRating;
  final bool loading;
  final String? error;
  final List<Map<String, dynamic>> items;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(Theme.of(context).brightness == Brightness.dark);
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (error != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: c.danger.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.danger.withValues(alpha: .24)),
        ),
        child: Column(
          children: [
            Icon(Icons.error_outline_rounded, color: c.danger),
            const SizedBox(height: 8),
            Text(
              error!,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySm(c.danger),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Tải lại'),
            ),
          ],
        ),
      );
    }
    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 42),
        decoration: BoxDecoration(
          color: c.muted.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.border),
        ),
        child: Column(
          children: [
            Icon(
              isRating
                  ? Icons.star_outline_rounded
                  : Icons.chat_bubble_outline_rounded,
              color: c.mutedForeground,
              size: 30,
            ),
            const SizedBox(height: 10),
            Text(
              isRating
                  ? 'Chưa có đánh giá đã gửi.'
                  : 'Chưa có phản hồi đã gửi.',
              style: AppTextStyles.bodySm(c.mutedForeground),
            ),
          ],
        ),
      );
    }
    return Column(
      children: items
          .map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _FeedbackHistoryCard(item: item, isRating: isRating),
            ),
          )
          .toList(),
    );
  }
}

class _FeedbackHistoryCard extends StatelessWidget {
  const _FeedbackHistoryCard({required this.item, required this.isRating});

  final Map<String, dynamic> item;
  final bool isRating;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(Theme.of(context).brightness == Brightness.dark);
    final targetType = item['targetType']?.toString() ?? '';
    final targetLabel = targetType == 'event' ? 'Sự kiện' : 'Lớp học phần';
    final fallbackId = targetType == 'event'
        ? item['eventId']?.toString() ?? ''
        : item['classId']?.toString() ?? '';
    final targetName = item['targetName']?.toString().trim() ?? '';
    final content = item['content']?.toString().trim() ?? '';
    final createdAt = DateTime.tryParse(item['createdAt']?.toString() ?? '')
        ?.toLocal();
    final rating =
        num.tryParse(item['rating']?.toString() ?? '')?.round().clamp(0, 5) ??
        0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .035),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isRating ? const Color(0xFFFFF7E6) : c.secondary,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  isRating
                      ? Icons.star_outline_rounded
                      : Icons.chat_bubble_outline_rounded,
                  color: isRating ? const Color(0xFFD97706) : c.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  targetName.isEmpty ? fallbackId : targetName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMd(c.foreground)
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: c.secondary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  targetLabel,
                  style: AppTextStyles.bodyXs(c.primary)
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (isRating) ...[
            const SizedBox(height: 12),
            Row(
              children: List.generate(
                5,
                (index) => Icon(
                  index < rating
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  size: 20,
                  color: const Color(0xFFF59E0B),
                ),
              ),
            ),
          ],
          if (content.isNotEmpty) ...[
            const SizedBox(height: 11),
            Text(
              content,
              style: AppTextStyles.bodySm(c.foreground).copyWith(height: 1.45),
            ),
          ],
          const SizedBox(height: 11),
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 16, color: c.mutedForeground),
              const SizedBox(width: 6),
              Text(
                createdAt == null
                    ? 'Chưa cập nhật'
                    : DateFormat('dd/MM/yyyy HH:mm').format(createdAt),
                style: AppTextStyles.bodyXs(c.mutedForeground),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StudentDialogShell extends StatelessWidget {
  const _StudentDialogShell({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    required this.onPrimary,
    required this.submitting,
    required this.child,
    this.iconColor,
    this.iconBackground,
    this.showPrimary = true,
    this.cancelLabel = 'Hủy',
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String primaryLabel;
  final Future<void> Function() onPrimary;
  final bool submitting;
  final Widget child;
  final Color? iconColor;
  final Color? iconBackground;
  final bool showPrimary;
  final String cancelLabel;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(Theme.of(context).brightness == Brightness.dark);
    final width = MediaQuery.sizeOf(context).width;
    final compact = width <= 430;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact
            ? 12
            : width < 640
            ? 16
            : 32,
        vertical: compact ? 12 : 24,
      ),
      backgroundColor: c.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 18,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 16 : 24,
                compact ? 16 : 22,
                compact ? 8 : 16,
                16,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: iconBackground ?? c.secondary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: iconColor ?? c.primary, size: 23),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.displaySm(c.foreground)
                              .copyWith(fontSize: compact ? 19 : 21),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: compact ? 3 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodySm(c.mutedForeground),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Đóng',
                    onPressed: submitting ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: c.border),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(compact ? 16 : 24),
                child: child,
              ),
            ),
            Divider(height: 1, color: c.border),
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 16 : 24,
                14,
                compact ? 16 : 24,
                compact ? 16 : 20,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final cancel = OutlinedButton(
                    onPressed: submitting ? null : () => Navigator.pop(context),
                    child: Text(cancelLabel),
                  );
                  final primary = FilledButton.icon(
                    onPressed: submitting ? null : onPrimary,
                    icon: submitting
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded, size: 18),
                    label: Text(primaryLabel),
                  );
                  if (showPrimary && constraints.maxWidth < 300) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [primary, const SizedBox(height: 8), cancel],
                    );
                  }
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      cancel,
                      if (showPrimary) ...[
                        const SizedBox(width: 12),
                        Flexible(child: primary),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {this.required = false});
  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(Theme.of(context).brightness == Brightness.dark);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text.rich(
        TextSpan(
          text: text,
          style: AppTextStyles.bodySm(c.foreground)
              .copyWith(fontWeight: FontWeight.w700),
          children: required
              ? const [
                  TextSpan(
                    text: ' *',
                    style: TextStyle(color: Color(0xFFDC2626)),
                  ),
                ]
              : const [],
        ),
      ),
    );
  }
}

class _StudentCodeField extends StatelessWidget {
  const _StudentCodeField();

  @override
  Widget build(BuildContext context) {
    final code = _studentCode();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel('Mã sinh viên', required: true),
        TextFormField(
          initialValue: code,
          readOnly: true,
          decoration: _inputDecoration('Mã sinh viên').copyWith(
            filled: true,
            fillColor: AppColors.of(
              Theme.of(context).brightness == Brightness.dark,
            ).muted,
            prefixIcon: const Icon(Icons.badge_outlined, size: 20),
          ),
          validator: (_) => code.isEmpty ? 'Không tìm thấy mã sinh viên' : null,
        ),
      ],
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFEFF6FF),
      border: Border.all(color: const Color(0xFFBFDBFE)),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.info_outline_rounded,
          color: Color(0xFF1E56A0),
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Color(0xFF1E3A5F), height: 1.45),
          ),
        ),
      ],
    ),
  );
}

class _SegmentedChoice extends StatelessWidget {
  const _SegmentedChoice({
    required this.firstLabel,
    required this.secondLabel,
    required this.firstSelected,
    required this.onChanged,
  });
  final String firstLabel;
  final String secondLabel;
  final bool firstSelected;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(Theme.of(context).brightness == Brightness.dark);
    Widget option(String label, bool first) => Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onChanged == null ? null : () => onChanged!(first),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          decoration: BoxDecoration(
            color: firstSelected == first ? c.card : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: firstSelected == first
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .08),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodyXs(
              firstSelected == first ? c.primary : c.mutedForeground,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [option(firstLabel, true), option(secondLabel, false)],
      ),
    );
  }
}

class _OptionText extends StatelessWidget {
  const _OptionText({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(Theme.of(context).brightness == Brightness.dark);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.bodySm(c.foreground),
        ),
        if (subtitle.isNotEmpty)
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodyXs(c.mutedForeground),
          ),
      ],
    );
  }
}

InputDecoration _inputDecoration(String hint) => InputDecoration(
  hintText: hint,
  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: Color(0xFF1E56A0), width: 1.5),
  ),
);
