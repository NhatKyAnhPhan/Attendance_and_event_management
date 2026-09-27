import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../controllers/admin_classes_controller.dart';
import '../../controllers/auth_controller.dart';
import '../../core/constants/role.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/models/class_model.dart';

class ClassesPage extends StatelessWidget {
  const ClassesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(AdminClassesController());
    final canManage = Get.find<AuthController>().role.value == Role.admin;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);

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
                    'Quản lý lớp học',
                    style: AppTextStyles.displayLg(c.foreground),
                  ),
                ),
                if (canManage)
                  FilledButton.icon(
                    onPressed: () => _showClassDialog(context, controller),
                    icon: const Icon(Icons.add),
                    label: const Text('Tạo lớp'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (controller.error.value.isNotEmpty)
              Text(
                controller.error.value,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (controller.items.isEmpty && controller.error.value.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(child: Text('Chưa có lớp học nào.')),
              ),
            ...controller.items.map(
              (item) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  onTap: () => _showClassDetails(context, item),
                  title: Text(item.name),
                  subtitle: Text(
                    '${item.code}  |  ${item.lecturerName}\n'
                    '${item.semester} · ${item.schoolYear}\n'
                    '${_periodLabel(item)}',
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${item.studentCount} SV'),
                      if (canManage)
                        PopupMenuButton<String>(
                          tooltip: 'Thao tác lớp',
                          onSelected: (action) {
                            if (action == 'edit') {
                              _showClassDialog(context, controller, item: item);
                            } else if (action == 'delete') {
                              _confirmDelete(context, controller, item);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text('Chỉnh sửa'),
                            ),
                            PopupMenuItem(value: 'delete', child: Text('Xóa')),
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

  Future<void> _showClassDetails(BuildContext context, ClassModel item) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mã lớp: ${item.code}'),
            Text('Giảng viên: ${item.lecturerName}'),
            Text('Học kỳ: ${item.semester}'),
            Text('Năm học: ${item.schoolYear}'),
            Text('Bắt đầu: ${_formatClassDate(item.startDate)}'),
            Text('Kết thúc: ${_formatClassDate(item.endDate)}'),
            Text('Sĩ số: ${item.studentCount}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Future<void> _showClassDialog(
    BuildContext context,
    AdminClassesController controller, {
    ClassModel? item,
  }) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: item?.name ?? '');
    final semesterController = TextEditingController(
      text: item?.semester ?? '',
    );
    final yearController = TextEditingController(text: item?.schoolYear ?? '');
    DateTime? startDate = item?.startDate;
    DateTime? endDate = item?.endDate;
    String? lecturerId = item?.lecturerId.isEmpty == true
        ? null
        : item?.lecturerId;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(item == null ? 'Tạo lớp' : 'Chỉnh sửa lớp'),
          content: SizedBox(
            width: 440,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Tên lớp'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Vui lòng nhập tên lớp'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: semesterController,
                      decoration: const InputDecoration(labelText: 'Học kỳ'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: yearController,
                      decoration: const InputDecoration(labelText: 'Năm học'),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Ngày bắt đầu học kỳ'),
                      subtitle: Text(_formatClassDate(startDate)),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: () async {
                        final selected = await _pickClassDate(
                          context,
                          startDate,
                        );
                        if (!context.mounted) return;
                        if (selected != null) {
                          if (endDate != null && endDate!.isBefore(selected)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Ngày bắt đầu không được sau ngày kết thúc.',
                                ),
                              ),
                            );
                            return;
                          }
                          setState(() => startDate = selected);
                        }
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Ngày kết thúc học kỳ'),
                      subtitle: Text(_formatClassDate(endDate)),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: () async {
                        final selected = await _pickClassDate(context, endDate);
                        if (!context.mounted) return;
                        if (selected != null) {
                          if (startDate != null &&
                              selected.isBefore(startDate!)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Ngày kết thúc phải bằng hoặc sau ngày bắt đầu.',
                                ),
                              ),
                            );
                            return;
                          }
                          setState(() => endDate = selected);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: lecturerId,
                      decoration: const InputDecoration(
                        labelText: 'Giảng viên',
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('Chưa phân công'),
                        ),
                        ...controller.lecturers.map(
                          (lecturer) => DropdownMenuItem<String>(
                            value: lecturer.id,
                            child: Text(lecturer.name),
                          ),
                        ),
                      ],
                      onChanged: (value) => setState(() => lecturerId = value),
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
                if (!formKey.currentState!.validate()) return;
                if (startDate == null || endDate == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Vui lòng chọn ngày bắt đầu và kết thúc.'),
                    ),
                  );
                  return;
                }
                if (!isValidClassDateRange(startDate!, endDate!)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Ngày kết thúc phải bằng hoặc sau ngày bắt đầu.',
                      ),
                    ),
                  );
                  return;
                }
                try {
                  final name = nameController.text.trim();
                  final semester = semesterController.text.trim();
                  final schoolYear = yearController.text.trim();
                  if (item == null) {
                    await controller.createClass(
                      name: name,
                      semester: semester,
                      schoolYear: schoolYear,
                      lecturerId: lecturerId,
                      startDate: startDate!,
                      endDate: endDate!,
                    );
                  } else {
                    await controller.updateClass(
                      id: item.id,
                      name: name,
                      semester: semester,
                      schoolYear: schoolYear,
                      lecturerId: lecturerId,
                      startDate: startDate!,
                      endDate: endDate!,
                    );
                  }
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                } catch (exception) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(exception.toString())),
                    );
                  }
                }
              },
              child: Text(item == null ? 'Lưu' : 'Cập nhật'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    semesterController.dispose();
    yearController.dispose();
  }

  Future<DateTime?> _pickClassDate(
    BuildContext context,
    DateTime? initialDate,
  ) async {
    final initial = initialDate ?? DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: DateUtils.dateOnly(initial),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    return selected == null ? null : DateUtils.dateOnly(selected);
  }

  static String _formatClassDate(DateTime? date) =>
      date == null ? 'Chưa thiết lập' : DateFormat('dd/MM/yyyy').format(date);

  static String _periodLabel(ClassModel item) =>
      '${_formatClassDate(item.startDate)} - ${_formatClassDate(item.endDate)}';

  Future<void> _confirmDelete(
    BuildContext context,
    AdminClassesController controller,
    ClassModel item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa lớp học?'),
        content: Text('Bạn có chắc muốn xóa "${item.name}" không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await controller.deleteClass(item.id);
    } catch (exception) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    }
  }
}
