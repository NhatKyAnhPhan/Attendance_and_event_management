import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../controllers/organizer_events_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/models/event_model.dart';

class OrganizerEventsPage extends StatelessWidget {
  const OrganizerEventsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(OrganizerEventsController());
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = AppColors.of(isDark);

    return Obx(() {
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
                FilledButton.icon(
                  onPressed: () async {
                    await controller.loadUnits();
                    if (!context.mounted) return;
                    if (controller.unitsError.value.isNotEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${controller.unitsError.value} Bạn vẫn có thể nhập mã thủ công.',
                          ),
                        ),
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
            if (controller.error.value.isNotEmpty)
              _ErrorBanner(message: controller.error.value),
            if (controller.items.isEmpty && controller.error.value.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(child: Text('Chưa có sự kiện nào.')),
              ),
            ...controller.items.map(
              (event) => Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  title: Text(
                    event.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${event.id}  |  ${event.location}\n'
                      '${DateFormat('dd/MM/yyyy HH:mm').format(event.startTime)} - '
                      '${DateFormat('HH:mm').format(event.endTime)}\n'
                      'Đăng ký: ${event.registeredCount}/${event.capacity}',
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Chip(label: Text(event.status)),
                      IconButton(
                        tooltip: 'Chỉnh sửa sự kiện',
                        onPressed: () =>
                            _showEventDialog(context, controller, event: event),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Xóa sự kiện',
                        onPressed: () =>
                            _confirmDelete(context, controller, event),
                        icon: const Icon(Icons.delete_outline),
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

  Future<void> _showEventDialog(
    BuildContext context,
    OrganizerEventsController controller, {
    OrganizerEventSummary? event,
  }) async {
    final isEditing = event != null;
    final formKey = GlobalKey<FormState>();
    final idController = TextEditingController(text: event?.id ?? '');
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
                    _field(idController, 'Mã sự kiện', readOnly: isEditing),
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
                        if (selected != null) {
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
                        if (selected != null) {
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
                if (!formKey.currentState!.validate() ||
                    !endTime.isAfter(startTime)) {
                  if (context.mounted && !endTime.isAfter(startTime)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Thời gian kết thúc phải sau thời gian bắt đầu.',
                        ),
                      ),
                    );
                  }
                  return;
                }
                try {
                  final eventId = idController.text.trim();
                  final eventName = nameController.text.trim();
                  final organizerId = selectedOrganizerId?.trim() ?? '';
                  final location = locationController.text.trim();
                  final capacity = int.parse(capacityController.text.trim());
                  if (isEditing) {
                    await controller.updateEvent(
                      id: eventId,
                      name: eventName,
                      organizerId: organizerId,
                      startTime: startTime,
                      endTime: endTime,
                      location: location,
                      capacity: capacity,
                    );
                  } else {
                    await controller.createEvent(
                      id: eventId,
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
    idController.dispose();
    nameController.dispose();
    locationController.dispose();
    capacityController.dispose();
    organizerController.dispose();
  }

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

  static Widget _unitField(
    List<OrganizerUnit> units,
    String? value,
    TextEditingController controller,
    ValueChanged<String?> onChanged,
  ) {
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

  Future<void> _confirmDelete(
    BuildContext context,
    OrganizerEventsController controller,
    OrganizerEventSummary event,
  ) async {
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    }
  }

  static Future<DateTime?> _pickDateTime(
    BuildContext context,
    DateTime initial,
  ) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now(),
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
