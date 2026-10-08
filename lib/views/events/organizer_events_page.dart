import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/organizer_events_controller.dart';
import '../../core/constants/role.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/models/event_model.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/student_roster_list.dart';

class OrganizerEventsPage extends StatefulWidget {
  const OrganizerEventsPage({super.key});

  @override
  State<OrganizerEventsPage> createState() => _OrganizerEventsPageState();
}

class _OrganizerEventsPageState extends State<OrganizerEventsPage> {
  String _query = '';
  bool _showArchived = false;
  bool _sendingCertificates = false;

  // Hiển thị danh sách sự kiện cùng các thao tác theo vai trò.
  @override
  Widget build(BuildContext context) {
    final controller = Get.put(OrganizerEventsController());
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = AppColors.of(isDark);

    // Theo dõi trạng thái controller để hiển thị tải, lỗi và danh sách sự kiện.
    return Obx(() {
      controller.statusRefreshTick.value;
      final auth = Get.find<AuthController>();
      final canManageEvents = auth.canManageEvents;
      final canDeleteEvents = auth.role.value == Role.admin;
      final query = _query.trim().toLowerCase();
      final filteredItems = controller.items.where((event) {
        if (event.isArchived != _showArchived) return false;
        return [
          event.id,
          event.name,
          event.location,
          event.status,
          event.organizerId,
        ].any((value) => value.toLowerCase().contains(query));
      }).toList();
      if (controller.loading.value && controller.items.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      return RefreshIndicator(
        onRefresh: controller.load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Quản lý sự kiện',
                    style: AppTextStyles.displayLg(colors.foreground),
                  ),
                ),
                if (canManageEvents)
                  FilledButton.icon(
                    onPressed: () async {
                      await controller.loadUnits();
                      if (!context.mounted) return;
                      if (controller.unitsError.value.isNotEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(controller.unitsError.value)),
                        );
                      }
                      await _showEventDialog(context, controller);
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Tạo sự kiện'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Sự kiện đang mở'),
                  selected: !_showArchived,
                  onSelected: (_) => setState(() => _showArchived = false),
                ),
                ChoiceChip(
                  label: const Text('Sự kiện đã đóng / quá 1 năm'),
                  selected: _showArchived,
                  onSelected: (_) => setState(() => _showArchived = true),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AppSearchField(
              colors: colors,
              hintText: 'Tìm tên sự kiện, địa điểm, trạng thái...',
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 16),
            if (controller.error.value.isNotEmpty)
              _ErrorBanner(message: controller.error.value),
            if (controller.items.isEmpty && controller.error.value.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(child: Text('Chưa có sự kiện nào.')),
              ),
            if (controller.items.isNotEmpty && filteredItems.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(
                  child: Text('Không có sự kiện phù hợp trong mục này.'),
                ),
              ),
            ...filteredItems.map(
              (event) => Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  onTap: () => _showEventDetails(context, controller, event),
                  title: Text(
                    event.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${event.location}\n'
                      '${DateFormat('dd/MM/yyyy HH:mm').format(event.startTime)} - '
                      '${DateFormat('HH:mm').format(event.endTime)}\n'
                      'Đăng ký: ${event.registeredCount}/${event.capacity}'
                      '${event.isArchived ? '\n${event.isClosed ? 'Đã đóng' : 'Đã diễn ra quá 1 năm'}' : ''}',
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Chip(label: Text(event.status)),
                      if (canManageEvents || canDeleteEvents)
                        PopupMenuButton<String>(
                          tooltip: 'Thao tác sự kiện',
                          onSelected: (action) {
                            if (action == 'edit') {
                              _showEventDialog(
                                context,
                                controller,
                                event: event,
                              );
                            } else if (action == 'delete') {
                              _confirmDelete(context, controller, event);
                            } else if (action == 'close') {
                              _confirmClose(context, controller, event);
                            }
                          },
                          itemBuilder: (context) => [
                            if (canManageEvents && _canEditEvent(event))
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Chỉnh sửa'),
                              ),
                            if (canManageEvents && !event.isArchived)
                              const PopupMenuItem(
                                value: 'close',
                                child: Text('Đóng sự kiện'),
                              ),
                            if (canDeleteEvents)
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Xóa'),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  // Hiển thị thông tin chi tiết của một sự kiện.
  Future<void> _showEventDetails(
    BuildContext context,
    OrganizerEventsController controller,
    OrganizerEventSummary event,
  ) async {
    final detailsFuture = controller.getEventDetails(event.id);
    final studentsFuture = controller.getEventStudents(event.id);
    final colors = AppColors.of(
      Theme.of(context).brightness == Brightness.dark,
    );
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(event.name),
        content: SizedBox(
          width: 700,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.72,
            ),
            child: FutureBuilder<Map<String, dynamic>>(
              future: detailsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Không tải được chi tiết: ${snapshot.error}'),
                  );
                }

                final details = snapshot.data ?? const <String, dynamic>{};
                final benefits = details['benefits'] is List
                    ? (details['benefits'] as List).whereType<Map>().toList()
                    : const <Map>[];
                final rules = details['rules'] is List
                    ? (details['rules'] as List).whereType<Map>().toList()
                    : const <Map>[];
                final description = details['description']?.toString().trim();

                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _detailSection('Thông tin sự kiện', [
                        _detailRow('Mã sự kiện', event.id),
                        _detailRow('Trạng thái', event.status),
                        _detailRow(
                          'Đơn vị tổ chức',
                          details['organizerName']?.toString() ??
                              event.organizerId,
                        ),
                        _detailRow(
                          'Thời gian bắt đầu',
                          DateFormat('dd/MM/yyyy HH:mm')
                              .format(event.startTime),
                        ),
                        _detailRow(
                          'Thời gian kết thúc',
                          DateFormat('dd/MM/yyyy HH:mm').format(event.endTime),
                        ),
                        _detailRow('Địa điểm', event.location),
                        _detailRow(
                          'Số lượng đăng ký',
                          '${details['registeredCount'] ?? event.registeredCount}/${details['capacity'] ?? event.capacity}',
                        ),
                      ]),
                      const SizedBox(height: 16),
                      _detailSection('Mô tả', [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 160),
                          child: Scrollbar(
                            child: SingleChildScrollView(
                              child: Text(
                                description == null || description.isEmpty
                                    ? 'Chưa có mô tả cho sự kiện này.'
                                    : description,
                              ),
                            ),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      _detailSection(
                        'Quyền lợi',
                        benefits.isEmpty
                            ? [const Text('Chưa có thông tin quyền lợi.')]
                            : benefits.map((benefit) {
                                final type = benefit['type']?.toString();
                                final points = benefit['points'];
                                final content = benefit['content']?.toString();
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(
                                    [
                                      if (type != null && type.isNotEmpty) type,
                                      if (points != null) '$points điểm',
                                      if (content != null && content.isNotEmpty)
                                        content,
                                    ].join(' · '),
                                  ),
                                );
                              }).toList(),
                      ),
                      const SizedBox(height: 16),
                      _detailSection(
                        'Nội quy',
                        rules.isEmpty
                            ? [const Text('Chưa có nội quy cho sự kiện này.')]
                            : rules.map((rule) {
                                final order = rule['sortOrder']?.toString();
                                final text = rule['text']?.toString() ?? '';
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(
                                    order == null ? text : '$order. $text',
                                  ),
                                );
                              }).toList(),
                      ),
                      const SizedBox(height: 16),
                      _detailSection(
                        'Danh sách sinh viên đăng ký '
                        '(${event.registeredCount})',
                        [
                          SizedBox(
                            height: 260,
                            child: FutureBuilder(
                              future: studentsFuture,
                              builder: (context, studentSnapshot) {
                                if (studentSnapshot.connectionState !=
                                    ConnectionState.done) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }
                                if (studentSnapshot.hasError) {
                                  return Center(
                                    child: Text(
                                      'Không tải được danh sách sinh viên: '
                                      '${studentSnapshot.error}',
                                      textAlign: TextAlign.center,
                                    ),
                                  );
                                }
                                return StudentRosterList(
                                  students: studentSnapshot.data ?? const [],
                                  mutedColor: colors.mutedForeground,
                                  dividerColor: colors.border,
                                  emptyMessage:
                                      'Chưa có sinh viên đăng ký sự kiện.',
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        actions: [
          if (Get.find<AuthController>().canManageEvents &&
              !event.isClosed &&
              event.endTime.isAfter(DateTime.now()))
            TextButton.icon(
              onPressed: () =>
                  _showEventAttendanceQr(dialogContext, controller, event),
              icon: const Icon(Icons.qr_code_2),
              label: const Text('QR điểm danh'),
            ),
          if (Get.find<AuthController>().canManageEvents &&
              event.endTime.isBefore(DateTime.now()))
            TextButton.icon(
              onPressed: _sendingCertificates
                  ? null
                  : () => _confirmSendCertificates(
                      dialogContext,
                      controller,
                      event,
                    ),
              icon: const Icon(Icons.email_outlined),
              label: Text(
                _sendingCertificates ? 'Đang gửi...' : 'Gửi chứng nhận',
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEventAttendanceQr(
    BuildContext context,
    OrganizerEventsController controller,
    OrganizerEventSummary event,
  ) async {
    try {
      final qr = await controller.createAttendanceQr(event.id);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('QR điểm danh sự kiện'),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(event.name, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                QrImageView(data: qr, size: 250),
                Text(
                  'Mã QR có hiệu lực đến ${DateFormat('dd/MM/yyyy HH:mm').format(event.endTime)}.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Không tạo được QR: $error')));
    }
  }

  Future<void> _confirmSendCertificates(
    BuildContext context,
    OrganizerEventsController controller,
    OrganizerEventSummary event,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gửi chứng nhận qua email?'),
        content: Text(
          'Chứng nhận PDF sẽ chỉ gửi cho sinh viên đã điểm danh QR '
          'sự kiện “${event.name}”.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Gửi'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    setState(() => _sendingCertificates = true);
    try {
      final result = await controller.sendCertificates(event.id);
      if (!context.mounted) return;
      final sent = result['sent'] as int? ?? 0;
      final failures = result['failures'] is List
          ? (result['failures'] as List)
                .whereType<Map>()
                .map((item) => item['message']?.toString() ?? '')
                .where((message) => message.isNotEmpty)
                .toList()
          : const <String>[];
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Kết quả gửi chứng nhận'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Gửi thành công: $sent'),
                  Text('Gửi thất bại: ${failures.length}'),
                  for (final failure in failures)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(failure),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không gửi được chứng nhận: $error')),
      );
    } finally {
      if (mounted) setState(() => _sendingCertificates = false);
    }
  }

  static Widget _detailSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  static Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(child: Text(value.isEmpty ? 'Chưa cập nhật' : value)),
        ],
      ),
    );
  }

  // Mở biểu mẫu tạo mới hoặc cập nhật sự kiện hợp lệ.
  Future<void> _showEventDialog(
    BuildContext context,
    OrganizerEventsController controller, {
    OrganizerEventSummary? event,
  }) async {
    // Dùng chung biểu mẫu cho cả thao tác tạo mới và cập nhật sự kiện.
    final isEditing = event != null;
    if (event != null && !_canEditEvent(event)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sự kiện đã kết thúc hoặc đã bắt đầu quá 1 ngày.'),
        ),
      );
      return;
    }
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: event?.name ?? '');
    final locationController = TextEditingController(
      text: event?.location ?? '',
    );
    final capacityController = TextEditingController(
      text: event?.capacity.toString() ?? '100',
    );
    final organizerController = TextEditingController(
      text: event?.organizerId ?? '',
    );
    String? selectedOrganizerId = event?.organizerId;
    DateTime startTime =
        event?.startTime ?? DateTime.now().add(const Duration(days: 1));
    DateTime endTime =
        event?.endTime ?? DateTime.now().add(const Duration(days: 1, hours: 2));

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(isEditing ? 'Chỉnh sửa sự kiện' : 'Tạo sự kiện'),
          content: SizedBox(
            width: 480,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _field(nameController, 'Tên sự kiện'),
                    _unitField(
                      controller.units,
                      selectedOrganizerId,
                      organizerController,
                      (value) => setState(() => selectedOrganizerId = value),
                    ),
                    _field(locationController, 'Địa điểm'),
                    _field(capacityController, 'Số lượng tối đa', number: true),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Bắt đầu'),
                      subtitle: Text(
                        DateFormat('dd/MM/yyyy HH:mm').format(startTime),
                      ),
                      onTap: () async {
                        final selected = await _pickDateTime(
                          context,
                          startTime,
                        );
                        if (!context.mounted) return;
                        if (selected != null) {
                          if (!endTime.isAfter(selected)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Thời gian bắt đầu phải trước thời gian kết thúc.',
                                ),
                              ),
                            );
                            return;
                          }
                          setState(() => startTime = selected);
                        }
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Kết thúc'),
                      subtitle: Text(
                        DateFormat('dd/MM/yyyy HH:mm').format(endTime),
                      ),
                      onTap: () async {
                        final selected = await _pickDateTime(context, endTime);
                        if (!context.mounted) return;
                        if (selected != null) {
                          if (!selected.isAfter(startTime)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Thời gian kết thúc phải sau thời gian bắt đầu.',
                                ),
                              ),
                            );
                            return;
                          }
                          setState(() => endTime = selected);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () async {
                final timeError = _eventTimeError(
                  startTime,
                  endTime,
                  isEditing,
                );
                if (!formKey.currentState!.validate() || timeError != null) {
                  if (context.mounted && timeError != null) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(timeError)));
                  }
                  return;
                }
                try {
                  final eventName = nameController.text.trim();
                  final organizerId = selectedOrganizerId?.trim() ?? '';
                  final location = locationController.text.trim();
                  final capacity = int.parse(capacityController.text.trim());
                  if (isEditing) {
                    await controller.updateEvent(
                      id: event.id,
                      name: eventName,
                      organizerId: organizerId,
                      startTime: startTime,
                      endTime: endTime,
                      location: location,
                      capacity: capacity,
                    );
                  } else {
                    await controller.createEvent(
                      name: eventName,
                      organizerId: organizerId,
                      startTime: startTime,
                      endTime: endTime,
                      location: location,
                      capacity: capacity,
                    );
                  }
                } catch (exception) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(exception.toString())),
                    );
                  }
                  return;
                }
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: Text(isEditing ? 'Cập nhật' : 'Lưu'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    locationController.dispose();
    capacityController.dispose();
    organizerController.dispose();
  }

  // Trả về lỗi nếu khoảng thời gian tạo hoặc sửa không hợp lệ.
  static String? _eventTimeError(
    DateTime startTime,
    DateTime endTime,
    bool isEditing,
  ) {
    final now = DateTime.now();
    if (!endTime.isAfter(startTime)) {
      return 'Thời gian kết thúc phải sau thời gian bắt đầu.';
    }
    if (endTime.difference(startTime) > const Duration(days: 1)) {
      return 'Thời lượng sự kiện không được quá 1 ngày.';
    }
    if (!isEditing && !startTime.isAfter(now)) {
      return 'Sự kiện mới phải bắt đầu trong tương lai.';
    }
    if (isEditing && !endTime.isAfter(now)) {
      return 'Không thể chỉnh sửa sự kiện đã kết thúc.';
    }
    return null;
  }

  // Kiểm tra sự kiện chưa kết thúc, chưa quá một ngày và không kéo dài quá 24 giờ.
  static bool _canEditEvent(OrganizerEventSummary event) {
    final now = DateTime.now();
    return !event.isArchived &&
        event.endTime.isAfter(now) &&
        now.difference(event.startTime) <= const Duration(days: 1) &&
        event.endTime.difference(event.startTime) <= const Duration(days: 1);
  }

  // Tạo ô nhập liệu và xác thực dữ liệu cơ bản của sự kiện.
  static Widget _field(
    TextEditingController controller,
    String label, {
    bool number = false,
    bool readOnly = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        readOnly: readOnly,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Vui lòng nhập $label';
          }
          if (number && (int.tryParse(value.trim()) ?? 0) <= 0) {
            return '$label phải là số nguyên dương';
          }
          return null;
        },
      ),
    );
  }

  // Hiển thị ô tìm kiếm và chọn đơn vị tổ chức.
  static Widget _unitField(
    List<OrganizerUnit> units,
    String? value,
    TextEditingController controller,
    ValueChanged<String?> onChanged,
  ) {
    // Cho phép tìm mã hoặc tên đơn vị và chọn từ danh sách gợi ý.
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FormField<String>(
        initialValue: value ?? '',
        validator: (selected) => selected == null || selected.trim().isEmpty
            ? 'Vui lòng nhập mã đơn vị tổ chức'
            : null,
        builder: (field) => Autocomplete<OrganizerUnit>(
          displayStringForOption: (unit) => unit.id,
          initialValue: TextEditingValue(text: value ?? ''),
          optionsBuilder: (textEditingValue) {
            final query = textEditingValue.text.trim().toLowerCase();
            if (query.isEmpty) return units;
            return units.where(
              (unit) =>
                  unit.id.toLowerCase().contains(query) ||
                  unit.name.toLowerCase().contains(query),
            );
          },
          onSelected: (unit) {
            controller.text = unit.id;
            field.didChange(unit.id);
            onChanged(unit.id);
          },
          optionsViewBuilder: (context, onSelected, options) => Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final unit = options.elementAt(index);
                    return ListTile(
                      title: Text(unit.id),
                      subtitle: Text(unit.name),
                      onTap: () => onSelected(unit),
                    );
                  },
                ),
              ),
            ),
          ),
          fieldViewBuilder: (context, textController, focusNode, onSubmitted) {
            controller.value = textController.value;
            return TextFormField(
              controller: textController,
              focusNode: focusNode,
              onChanged: (text) {
                controller.value = textController.value;
                field.didChange(text);
                onChanged(text.trim().isEmpty ? null : text.trim());
              },
              onFieldSubmitted: (_) => onSubmitted(),
              decoration: InputDecoration(
                labelText: 'Mã đơn vị tổ chức',
                hintText: 'Nhập mã, ví dụ: DVK',
                border: const OutlineInputBorder(),
                errorText: field.errorText,
                suffixIcon: IconButton(
                  tooltip: 'Xem danh sách đơn vị',
                  icon: const Icon(Icons.arrow_drop_down),
                  onPressed: focusNode.requestFocus,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // Yêu cầu xác nhận trước khi xóa sự kiện.
  Future<void> _confirmDelete(
    BuildContext context,
    OrganizerEventsController controller,
    OrganizerEventSummary event,
  ) async {
    // Chỉ gửi yêu cầu xóa sau khi người dùng xác nhận.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa sự kiện?'),
        content: Text('Bạn có chắc muốn xóa "${event.name}" không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await controller.deleteEvent(event.id);
    } catch (exception) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    }
  }

  Future<void> _confirmClose(
    BuildContext context,
    OrganizerEventsController controller,
    OrganizerEventSummary event,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Đóng sự kiện?'),
        content: Text(
          'Sự kiện "${event.name}" sẽ được đưa vào mục đã đóng. '
          'Bạn vẫn có thể xem chi tiết và xóa sự kiện.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Đóng sự kiện'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await controller.closeEvent(event.id);
    } catch (exception) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    }
  }

  // Chọn ngày và giờ cho một mốc thời gian sự kiện.
  static Future<DateTime?> _pickDateTime(
    BuildContext context,
    DateTime initial,
  ) async {
    // Cho phép chọn ngày cũ khi sửa sự kiện đã diễn ra.
    final today = DateUtils.dateOnly(DateTime.now());
    final initialDate = DateUtils.dateOnly(initial);
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: initialDate.isBefore(today) ? initialDate : today,
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date == null || !context.mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  // Hiển thị thông báo lỗi tải dữ liệu.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}
