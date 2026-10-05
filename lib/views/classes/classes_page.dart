import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/admin_classes_controller.dart';
import '../../controllers/auth_controller.dart';
import '../../core/constants/role.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/excel_file_decoder.dart';
import '../../core/utils/semester.dart';
import '../../data/models/class_model.dart';
import '../../widgets/student_roster_list.dart';
import '../../widgets/app_search_field.dart';

class ClassesPage extends StatefulWidget {
  const ClassesPage({super.key});

  @override
  State<ClassesPage> createState() => _ClassesPageState();
}

class _ClassesPageState extends State<ClassesPage> {
  String _query = '';
  bool _showArchived = false;
  final Set<String> _importingClassIds = {};

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
      final query = _query.trim().toLowerCase();
      final filteredItems = controller.items.where((item) {
        if (item.isArchived != _showArchived) return false;
        return [
          item.id,
          item.code,
          item.name,
          item.lecturerName,
          item.semester,
          item.startTime,
          item.subjectCode,
          item.room,
          item.schedule,
        ].any((value) => value.toLowerCase().contains(query));
      }).toList();
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
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Lớp đang mở'),
                  selected: !_showArchived,
                  onSelected: (_) => setState(() => _showArchived = false),
                ),
                ChoiceChip(
                  label: const Text('Lớp đã đóng / quá 1 năm'),
                  selected: _showArchived,
                  onSelected: (_) => setState(() => _showArchived = true),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AppSearchField(
              colors: c,
              hintText: 'Tìm tên lớp, mã lớp, giảng viên...',
              onChanged: (value) => setState(() => _query = value),
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
            if (controller.items.isNotEmpty && filteredItems.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(
                  child: Text('Không có lớp học phù hợp trong mục này.'),
                ),
              ),
            ...filteredItems.map(
              (item) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  onTap: () => _showClassDetails(context, controller, item),
                  title: Text(item.name),
                  subtitle: Text(
                    '${item.code}  |  ${item.lecturerName}\n'
                    '${item.semester} · ${_dateTimeLabel(item.startTime)}\n'
                    '${item.subjectCode} · ${item.majorName} · Khóa ${item.cohortCode}'
                    '${item.isArchived ? '\n${item.isClosed ? 'Đã đóng' : 'Đã mở quá 1 năm'}' : ''}',
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${item.studentCount} SV'),
                      if (_importingClassIds.contains(item.id))
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else if (canManage)
                        PopupMenuButton<String>(
                          tooltip: 'Thao tác lớp',
                          onSelected: (action) {
                            if (action == 'edit') {
                              _showClassDialog(context, controller, item: item);
                            } else if (action == 'delete') {
                              _confirmDelete(context, controller, item);
                            } else if (action == 'close') {
                              _confirmClose(context, controller, item);
                            } else if (action == 'import') {
                              _importStudentsFromExcel(
                                context,
                                controller,
                                item,
                              );
                            }
                          },
                          itemBuilder: (context) => [
                            if (!item.isArchived) ...[
                              const PopupMenuItem(
                                value: 'import',
                                child: Text('Nhập sinh viên từ Excel'),
                              ),
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Chỉnh sửa'),
                              ),
                              const PopupMenuItem(
                                value: 'close',
                                child: Text('Đóng lớp'),
                              ),
                            ],
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

  Future<void> _importStudentsFromExcel(
    BuildContext context,
    AdminClassesController controller,
    ClassModel item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Định dạng file Excel'),
        content: const Text(
          'Chọn file .xlsx có tiêu đề cột MSSV, Mã SV hoặc Mã sinh viên ở dòng đầu. '
          'Nếu mã sinh viên có số 0 ở đầu, hãy định dạng cột đó là Văn bản trong Excel.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Chọn file'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    FilePickerResult? selection;
    try {
      selection = await FilePicker.pickFiles(
        dialogTitle: 'Chọn Excel có cột MSSV hoặc Mã sinh viên',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        allowMultiple: false,
        withData: true,
      );
    } on Exception catch (exception) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thể mở file Excel: $exception')),
      );
      return;
    }
    if (selection == null || selection.files.isEmpty || !context.mounted) {
      return;
    }

    final file = selection.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không đọc được nội dung file Excel.')),
      );
      return;
    }

    try {
      if (!context.mounted) return;
      setState(() => _importingClassIds.add(item.id));

      final workbook = decodeExcelWorkbook(bytes);
      if (workbook.tables.isEmpty) {
        throw const FormatException('File Excel không có trang tính dữ liệu.');
      }
      final rows = workbook.tables.values.first.rows;
      if (rows.isEmpty) {
        throw const FormatException('Trang tính Excel không có dữ liệu.');
      }

      final header = rows.first.map(_excelCellText).toList();
      final idColumn = header.indexWhere(_isStudentIdHeader);
      if (idColumn < 0) {
        throw const FormatException(
          'Cột mã sinh viên cần có tiêu đề MSSV, Mã SV hoặc Mã sinh viên.',
        );
      }

      final uniqueIds = <String>{};
      final studentIds = <String>[];
      var duplicateRows = 0;
      for (final row in rows.skip(1)) {
        if (idColumn >= row.length) continue;
        final studentId = _excelCellText(row[idColumn]).trim();
        if (studentId.isEmpty) continue;
        if (uniqueIds.add(studentId.toUpperCase())) {
          studentIds.add(studentId);
        } else {
          duplicateRows++;
        }
      }
      if (studentIds.isEmpty) {
        throw const FormatException(
          'Không tìm thấy mã sinh viên nào trong file Excel.',
        );
      }
      if (studentIds.length > 2000) {
        throw const FormatException(
          'Mỗi lần chỉ có thể nhập tối đa 2.000 sinh viên.',
        );
      }

      final result = await controller.importStudents(
        classId: item.id,
        studentIds: studentIds,
      );
      if (!context.mounted) return;

      final details = <String>[
        'Đã thêm: ${result.importedCount} sinh viên.',
        'Đã có trong lớp: ${result.alreadyMemberCount} sinh viên.',
        if (duplicateRows > 0) 'Mã trùng trong file: $duplicateRows dòng.',
        if (result.unknownStudentIds.isNotEmpty)
          'Không tìm thấy trong hệ thống (${result.unknownStudentIds.length}): '
              '${result.unknownStudentIds.take(10).join(', ')}'
              '${result.unknownStudentIds.length > 10 ? ', ...' : ''}',
      ];
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Kết quả nhập sinh viên · ${item.code}'),
          content: Text(details.join('\n')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
    } on FormatException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message.toString())));
    } catch (exception) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(exception.toString())));
    } finally {
      if (mounted) setState(() => _importingClassIds.remove(item.id));
    }
  }

  static String _excelCellText(Data? cell) {
    final value = cell?.value;
    return switch (value) {
      TextCellValue(:final value) =>
        value.text ??
            value.children?.map((span) => span.text ?? '').join() ??
            '',
      _ => value?.toString() ?? '',
    };
  }

  static bool _isStudentIdHeader(String header) {
    final normalized = header.toLowerCase().replaceAll(RegExp(r'[\s_.-]'), '');
    return const {
      'mssv',
      'masv',
      'mãsv',
      'mãsinhviên',
      'studentid',
      'studentcode',
    }.contains(normalized);
  }

  Future<void> _showClassDetails(
    BuildContext context,
    AdminClassesController controller,
    ClassModel item,
  ) async {
    final students = controller.getClassStudents(item.id);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final colors = AppColors.of(
          Theme.of(dialogContext).brightness == Brightness.dark,
        );
        return AlertDialog(
          title: Text(item.name),
          content: SizedBox(
            width: 680,
            height: MediaQuery.sizeOf(dialogContext).height * 0.72,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 190,
                  child: Scrollbar(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        Text('Mã lớp: ${item.code}'),
                        Text('Giảng viên: ${item.lecturerName}'),
                        Text('Học kỳ: ${item.semester}'),
                        Text(
                          'Thời gian bắt đầu: ${_dateTimeLabel(item.startTime)}',
                        ),
                        Text('Môn học: ${item.subjectCode}'),
                        Text('Bộ môn: ${item.majorName}'),
                        Text('Khóa: ${item.cohortCode}'),
                        Text('Trạng thái: ${item.status}'),
                        Text('Sĩ số: ${item.studentCount}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Danh sách sinh viên (${item.studentCount})',
                  style: Theme.of(dialogContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: FutureBuilder(
                    future: students,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Không tải được danh sách sinh viên: ${snapshot.error}',
                            textAlign: TextAlign.center,
                          ),
                        );
                      }
                      return StudentRosterList(
                        students: snapshot.data ?? const [],
                        mutedColor: colors.mutedForeground,
                        dividerColor: colors.border,
                        emptyMessage: 'Lớp chưa có sinh viên.',
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Đóng'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showClassDialog(
    BuildContext context,
    AdminClassesController controller, {
    ClassModel? item,
  }) async {
    await controller.loadClassOptions();
    if (!context.mounted) return;
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: item?.name ?? '');
    ClassSubjectOption? selectedSubject;
    for (final subject in controller.subjects) {
      if (subject.id == item?.subjectId) {
        selectedSubject = subject;
        break;
      }
    }
    String? cohortCode = item?.cohortCode.isNotEmpty == true
        ? item!.cohortCode
        : null;
    DateTime? startTime = DateTime.tryParse(item?.startTime ?? '')?.toLocal();
    String? lecturerId = item?.lecturerId.isEmpty == true
        ? null
        : item?.lecturerId;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(item == null ? 'Tạo lớp' : 'Chỉnh sửa lớp'),
            content: SizedBox(
              width: 440,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (item == null)
                        DropdownButtonFormField<ClassSubjectOption>(
                          initialValue: selectedSubject,
                          decoration: const InputDecoration(
                            labelText: 'Môn học',
                          ),
                          items: controller.subjects
                              .map(
                                (subject) =>
                                    DropdownMenuItem<ClassSubjectOption>(
                                      value: subject,
                                      child: Text(
                                        '${subject.code} · ${subject.name}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                              )
                              .toList(),
                          onChanged: (value) => setState(() {
                            selectedSubject = value;
                            if (value != null) {
                              nameController.text = value.name;
                            }
                          }),
                          validator: (value) =>
                              value == null ? 'Vui lòng chọn môn học' : null,
                        )
                      else
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Môn học',
                          ),
                          child: Text(
                            '${item.subjectCode} · ${selectedSubject?.name ?? item.name}',
                          ),
                        ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Tên lớp học phần',
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Vui lòng nhập tên lớp'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      InputDecorator(
                        decoration: const InputDecoration(labelText: 'Bộ môn'),
                        child: Text(
                          selectedSubject?.majorName ?? item?.majorName ?? '',
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (item == null)
                        DropdownButtonFormField<String>(
                          initialValue: cohortCode,
                          decoration: const InputDecoration(
                            labelText: 'Khóa sinh viên',
                          ),
                          items: controller.cohorts
                              .map(
                                (cohort) => DropdownMenuItem<String>(
                                  value: cohort.code,
                                  child: Text(cohort.code),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setState(() => cohortCode = value),
                          validator: (value) => value == null
                              ? 'Vui lòng chọn khóa sinh viên'
                              : null,
                        )
                      else
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Khóa sinh viên',
                          ),
                          child: Text(item.cohortCode),
                        ),
                      const SizedBox(height: 12),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Thời gian bắt đầu'),
                        subtitle: Text(
                          startTime == null
                              ? 'Chưa chọn'
                              : '${_dateTimeLabel(startTime!.toIso8601String())}'
                                    '\nHọc kỳ tự động: ${semesterForDate(startTime!)}',
                        ),
                        trailing: const Icon(Icons.calendar_month_outlined),
                        onTap: () async {
                          final selected = await _pickStartTime(
                            context,
                            startTime,
                          );
                          if (!context.mounted || selected == null) return;
                          setState(() {
                            startTime = selected;
                          });
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
                        onChanged: (value) =>
                            setState(() => lecturerId = value),
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
                  if (startTime == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Vui lòng chọn thời gian bắt đầu.'),
                      ),
                    );
                    return;
                  }
                  try {
                    if (item == null) {
                      await controller.createClass(
                        name: nameController.text.trim(),
                        subjectId: selectedSubject!.id,
                        cohortCode: cohortCode!,
                        semester: semesterForDate(startTime!),
                        startTime: _formatDateTime(startTime!),
                        lecturerId: lecturerId,
                      );
                    } else {
                      await controller.updateClass(
                        id: item.id,
                        name: nameController.text.trim(),
                        semester: semesterForDate(startTime!),
                        startTime: _formatDateTime(startTime!),
                        lecturerId: lecturerId,
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
          );
        },
      ),
    );
    nameController.dispose();
  }

  Future<DateTime?> _pickStartTime(
    BuildContext context,
    DateTime? initialDateTime,
  ) async {
    final now = DateTime.now();
    final initial = initialDateTime ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: DateUtils.dateOnly(initial),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      helpText: 'Chọn ngày bắt đầu',
    );
    if (date == null || !context.mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDateTime ?? now),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  static String _formatDateTime(DateTime value) {
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)} '
        '${twoDigits(value.hour)}:${twoDigits(value.minute)}:00';
  }

  static String _dateTimeLabel(String value) {
    final dateTime = DateTime.tryParse(value)?.toLocal();
    if (dateTime == null) return value;
    return _formatDateTime(dateTime).substring(0, 16);
  }

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
    if (confirmed != true || !context.mounted) return;
    try {
      await controller.deleteClass(item.id);
    } catch (exception) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    }
  }

  Future<void> _confirmClose(
    BuildContext context,
    AdminClassesController controller,
    ClassModel item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Đóng lớp học?'),
        content: Text(
          'Lớp "${item.name}" sẽ được đưa vào mục đã đóng. '
          'Bạn vẫn có thể xem chi tiết và xóa lớp.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Đóng lớp'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await controller.closeClass(item.id);
    } catch (exception) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    }
  }
}
