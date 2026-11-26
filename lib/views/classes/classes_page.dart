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
import '../../widgets/total_count_card.dart';

class ClassesPage extends StatefulWidget {
  const ClassesPage({super.key});

  @override
  State<ClassesPage> createState() => _ClassesPageState();
}

class _ClassesPageState extends State<ClassesPage> {
  String _query = '';
  bool _showArchived = false;
  bool _showFilters = false;
  String? _cohortFilter;
  String? _lecturerFilter;
  String? _subjectFilter;
  final Set<String> _importingClassIds = {};

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(AdminClassesController());
    final role = Get.find<AuthController>().role.value;
    final canManage = role == Role.admin;
    final canImportStudents = canManage;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);

    return Obx(() {
      if (controller.loading.value && controller.items.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      final query = _query.trim().toLowerCase();
      final auth = Get.find<AuthController>();
      final lecturerId = auth.currentUser.value?['id']?.toString();
      final visibleItems = controller.items.where((item) =>
          role != Role.lecturer ||
          (lecturerId != null && item.lecturerId == lecturerId));
      final cohorts = visibleItems.map((item) => item.cohortCode).where((v) => v.isNotEmpty).toSet().toList()..sort();
      final lecturers = {for (final item in visibleItems) if (item.lecturerId.isNotEmpty) item.lecturerId: item.lecturerName.isEmpty ? item.lecturerId : item.lecturerName};
      final subjects = {for (final item in visibleItems) if ((item.subjectId.isNotEmpty ? item.subjectId : item.subjectCode).isNotEmpty) (item.subjectId.isNotEmpty ? item.subjectId : item.subjectCode): item.subjectName.isEmpty ? item.subjectCode : item.subjectName};
      final filteredItems = controller.items.where((item) {
        if (role == Role.lecturer &&
            (lecturerId == null || item.lecturerId != lecturerId)) {
          return false;
        }
        if (item.isArchived != _showArchived) return false;
        if (_cohortFilter != null && item.cohortCode != _cohortFilter) return false;
        if (_lecturerFilter != null && item.lecturerId != _lecturerFilter) return false;
        if (_subjectFilter != null && (item.subjectId.isNotEmpty ? item.subjectId : item.subjectCode) != _subjectFilter) return false;
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: MediaQuery.sizeOf(context).width > 800
                      ? MediaQuery.sizeOf(context).width - 360
                      : MediaQuery.sizeOf(context).width - 56,
                  child: Text(
                    'Quản lý lớp học',
                    style: AppTextStyles.displayLg(c.foreground),
                  ),
                ),
                if (canImportStudents)
                  OutlinedButton.icon(
                    onPressed: _importingClassIds.contains('__excel__')
                        ? null
                        : () => _importRosterFromExcel(context, controller),
                    icon: _importingClassIds.contains('__excel__')
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file_outlined),
                    label: Text(
                      _importingClassIds.contains('__excel__')
                          ? 'Đang nhập...'
                          : 'Nhập sinh viên Excel',
                    ),
                  ),
                if (canManage)
                  OutlinedButton.icon(
                    onPressed: _importingClassIds.contains('__create_classes__')
                        ? null
                        : () => _importClassesFromExcel(context, controller),
                    icon: _importingClassIds.contains('__create_classes__')
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.library_add_outlined),
                    label: Text(
                      _importingClassIds.contains('__create_classes__')
                          ? 'Đang tạo lớp...'
                          : 'Tạo lớp Excel',
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
                  selectedColor: c.secondary,
                  side: BorderSide(
                    color: !_showArchived ? c.primary : c.border,
                  ),
                  labelStyle: TextStyle(
                    color: !_showArchived
                        ? c.secondaryForeground
                        : c.mutedForeground,
                    fontWeight: !_showArchived
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  onSelected: (_) => setState(() => _showArchived = false),
                ),
                ChoiceChip(
                  label: const Text('Lớp đã đóng / quá 1 năm'),
                  selected: _showArchived,
                  selectedColor: c.secondary,
                  side: BorderSide(color: _showArchived ? c.primary : c.border),
                  labelStyle: TextStyle(
                    color: _showArchived
                        ? c.secondaryForeground
                        : c.mutedForeground,
                    fontWeight: _showArchived
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
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
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _showFilters = !_showFilters),
                icon: const Icon(Icons.filter_list),
                label: Text(_showFilters ? 'Ẩn bộ lọc' : 'Bộ lọc'),
              ),
            ),
            if (_showFilters) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _classFilterDropdown('Khóa', 'Tất cả khóa', _cohortFilter, cohorts, (v) => setState(() => _cohortFilter = v)),
                _classFilterDropdown('Giảng viên', 'Tất cả giảng viên', _lecturerFilter, lecturers.keys.toList()..sort(), (v) => setState(() => _lecturerFilter = v), labels: lecturers),
                _classFilterDropdown('Môn học', 'Tất cả môn học', _subjectFilter, subjects.keys.toList()..sort(), (v) => setState(() => _subjectFilter = v), labels: subjects),
              ],
            ),
            ],
            const SizedBox(height: 12),
            TotalCountCard(
              label: 'Số lớp đang hiển thị',
              count: filteredItems.length,
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
                margin: const EdgeInsets.only(bottom: 14),
                elevation: 2,
                color: c.card,
                shadowColor: Colors.black.withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: c.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _showClassDetails(context, controller, item),
                  hoverColor: c.primary.withValues(alpha: 0.035),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 680;
                        final content = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              style: AppTextStyles.displayMd(c.foreground),
                            ),
                            const SizedBox(height: 7),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  item.code,
                                  style: AppTextStyles.mono(c.primary),
                                ),
                                Text('•', style: TextStyle(color: c.border)),
                                Text(
                                  item.lecturerName,
                                  style: AppTextStyles.bodySm(c.foreground),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _classMetaLine(
                              c,
                              Icons.calendar_today_outlined,
                              '${item.semester} · ${_dateTimeLabel(item.startTime)}',
                            ),
                            const SizedBox(height: 7),
                            _classMetaLine(
                              c,
                              Icons.menu_book_outlined,
                              '${item.subjectCode} · ${item.majorName} · Khóa ${item.cohortCode}',
                            ),
                            const SizedBox(height: 7),
                            _classMetaLine(
                              c,
                              Icons.school_outlined,
                              '${item.credits} tín chỉ'
                              '${item.isArchived ? ' · ${item.isClosed ? 'Đã đóng' : 'Đã mở quá 1 năm'}' : ''}',
                            ),
                          ],
                        );
                        final actions = Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: c.secondary,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${item.studentCount}/${item.capacity} SV',
                                style: AppTextStyles.bodyXs(
                                  c.secondaryForeground,
                                ).copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (_importingClassIds.contains(item.id))
                              const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            else if (canImportStudents)
                              PopupMenuButton<String>(
                                tooltip: 'Thao tác lớp',
                                onSelected: (action) {
                                  if (action == 'edit') {
                                    _showClassDialog(
                                      context,
                                      controller,
                                      item: item,
                                    );
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
                        );
                        if (compact) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Align(
                                alignment: Alignment.centerRight,
                                child: actions,
                              ),
                              content,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: content),
                            const SizedBox(width: 16),
                            actions,
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _classFilterDropdown(
    String label,
    String allLabel,
    String? value,
    List<String> options,
    ValueChanged<String?> onChanged, {
    Map<String, String> labels = const {},
  }) {
    return SizedBox(
      width: 220,
      child: DropdownButtonFormField<String>(
        value: value != null && options.contains(value) ? value : '',
        isExpanded: true,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        items: [
          DropdownMenuItem<String>(value: '', child: Text(allLabel)),
          ...options.map((option) => DropdownMenuItem<String>(
                value: option,
                child: Text(labels[option] ?? option, overflow: TextOverflow.ellipsis),
              )),
        ],
        onChanged: (next) => onChanged(next == null || next.isEmpty ? null : next),
      ),
    );
  }

  Widget _classMetaLine(AppColors colors, IconData icon, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: colors.mutedForeground),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: AppTextStyles.bodySm(colors.mutedForeground),
          ),
        ),
      ],
    );
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

      final parsed = extractStudentIdsFromWorkbook(decodeExcelWorkbook(bytes));
      final studentIds = parsed.studentIds;
      final duplicateRows = parsed.duplicateRows;
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
      final confirmed = await _confirmExcelImport(
        context,
        title: 'Xác nhận import sinh viên vào lớp',
        subtitle:
            '${item.name} (${item.code}) · ${studentIds.length} sinh viên.',
        lines: [studentIds.join(', ')],
      );
      if (confirmed != true || !context.mounted) return;

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
      await _showExcelError(context, error.message.toString());
    } catch (exception) {
      if (!context.mounted) return;
      await _showExcelError(context, exception.toString());
    } finally {
      if (mounted) setState(() => _importingClassIds.remove(item.id));
    }
  }

  Future<void> _importClassesFromExcel(
    BuildContext context,
    AdminClassesController controller,
  ) async {
    await Future.wait([
      controller.loadClassOptions(),
      controller.loadLecturers(),
    ]);
    if (!context.mounted) return;

    FilePickerResult? selection;
    try {
      selection = await FilePicker.pickFiles(
        dialogTitle: 'Chọn file Excel chứa dữ liệu lớp',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        allowMultiple: false,
        withData: true,
      );
    } on Exception catch (exception) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể mở file Excel: $exception')),
        );
      }
      return;
    }
    if (selection == null || selection.files.isEmpty || !context.mounted) {
      return;
    }
    final bytes = selection.files.single.bytes;
    if (bytes == null || bytes.isEmpty) {
      await _showExcelError(context, 'Không đọc được nội dung file Excel.');
      return;
    }

    setState(() => _importingClassIds.add('__create_classes__'));
    try {
      final rows = extractClassCreationRows(decodeExcelWorkbook(bytes));
      final preview = rows.map((row) {
        final subjects = controller.subjects.where(
          (subject) =>
              subject.id.toUpperCase() == row.subjectId.toUpperCase() ||
              subject.code.toUpperCase() == row.subjectId.toUpperCase(),
        );
        final subject = subjects.length == 1 ? subjects.single : null;
        final cohortExists = controller.cohorts.any(
          (cohort) => cohort.code.toUpperCase() == row.cohortCode.toUpperCase(),
        );
        final lecturerExists = row.lecturerId.isEmpty ||
            controller.lecturers.any(
              (lecturer) =>
                  lecturer.id.toUpperCase() == row.lecturerId.toUpperCase(),
            );
        final issue = subject == null
            ? (subjects.isEmpty ? 'Không tìm thấy mã môn học' : 'Mã môn học bị trùng')
            : !cohortExists
            ? 'Không tìm thấy mã khóa sinh viên'
            : !lecturerExists
            ? 'Không tìm thấy mã giảng viên'
            : null;
        return (row: row, subject: subject, issue: issue);
      }).toList();
      final validRows = preview.where((entry) => entry.issue == null).toList();
      if (validRows.isEmpty) {
        await _showExcelError(
          context,
          'Không có dòng lớp hợp lệ. Kiểm tra mã môn, mã khóa và mã giảng viên.',
        );
        return;
      }
      final confirmed = await _confirmExcelImport(
        context,
        title: 'Xác nhận tạo lớp từ Excel',
        subtitle:
            '${validRows.length} lớp sẽ được tạo; ${preview.length - validRows.length} dòng sẽ bị bỏ qua.',
        lines: preview.map((entry) {
          final row = entry.row;
          final status = entry.issue == null ? '' : ' - Bỏ qua: ${entry.issue}';
          return '${row.name} | ${row.subjectId} | khóa ${row.cohortCode}\n'
              '${row.startTime.toIso8601String().replaceFirst('T', ' ')} | ${row.capacity} sinh viên | '
              '${row.semester.isEmpty ? semesterForDate(row.startTime) : row.semester}$status';
        }).toList(),
      );
      if (confirmed != true || !context.mounted) return;

      var createdCount = 0;
      var failedCount = 0;
      for (final entry in validRows) {
        final row = entry.row;
        try {
          await controller.createClass(
            name: row.name,
            subjectId: entry.subject!.id,
            cohortCode: row.cohortCode,
            semester: row.semester.isEmpty
                ? semesterForDate(row.startTime)
                : row.semester,
            startTime: _formatDateTime(row.startTime),
            lecturerId: row.lecturerId.isEmpty ? null : row.lecturerId,
            capacity: row.capacity,
            reloadAfterCreate: false,
          );
          createdCount++;
        } catch (_) {
          failedCount++;
        }
      }
      if (createdCount > 0) await controller.load();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Đã tạo $createdCount lớp; $failedCount lớp tạo không thành công.',
            ),
          ),
        );
      }
    } on FormatException catch (exception) {
      if (context.mounted) {
        await _showExcelError(context, exception.message.toString());
      }
    } catch (exception) {
      if (context.mounted) await _showExcelError(context, exception.toString());
    } finally {
      if (mounted) {
        setState(() => _importingClassIds.remove('__create_classes__'));
      }
    }
  }
  Future<void> _importRosterFromExcel(
    BuildContext context,
    AdminClassesController controller,
  ) async {
    FilePickerResult? selection;
    try {
      selection = await FilePicker.pickFiles(
        dialogTitle: 'Chọn file Excel có cột MSSV và MaLop',
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

    final bytes = selection.files.single.bytes;
    if (bytes == null || bytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không đọc được nội dung file Excel.')),
      );
      return;
    }

    setState(() => _importingClassIds.add('__excel__'));
    try {
      final groups = extractStudentRosterGroups(
        decodeExcelWorkbook(bytes),
        targetIdHeaders: const {'MaLop', 'Mã lớp', 'classId', 'classCode'},
        targetNameHeaders: const {'TenLop', 'Tên lớp', 'className'},
      );
      final preview = groups.map((group) {
        final matchingClasses = controller.items.where(
          (item) =>
              item.id.toUpperCase() == group.targetId.toUpperCase() ||
              item.code.toUpperCase() == group.targetId.toUpperCase(),
        );
        final item = matchingClasses.length == 1
            ? matchingClasses.single
            : null;
        final issue = matchingClasses.isEmpty
            ? 'không tìm thấy lớp'
            : matchingClasses.length > 1
            ? 'mã lớp bị trùng'
            : item!.isArchived
            ? 'lớp đã đóng/lưu trữ'
            : group.studentIds.length > 2000
            ? 'vượt giới hạn 2.000 sinh viên'
            : null;
        return (
          group: group,
          item: item,
          issue: issue,
        );
      }).toList();
      final confirmed = await _confirmExcelImport(
        context,
        title: 'Xác nhận thêm sinh viên vào lớp',
        subtitle:
            '${groups.length} lớp, ${groups.fold<int>(0, (total, group) => total + group.studentIds.length)} mã sinh viên trong file.',
        lines: preview.map((entry) {
          final group = entry.group;
          final target = entry.item?.name ??
              (group.targetName.isNotEmpty
                  ? group.targetName
                  : group.targetId);
          final status = entry.issue == null ? '' : ' — Bỏ qua: ${entry.issue}';
          return '$target (${group.targetId}) — ${group.studentIds.length} sinh viên$status\n'
              '${group.studentIds.join(', ')}';
        }).toList(),
      );
      if (confirmed != true || !context.mounted) return;
      var importedCount = 0;
      var alreadyMemberCount = 0;
      var unknownStudentCount = 0;
      var duplicateRows = 0;
      final skipped = <String>[];

      for (final group in groups) {
        final matchingClasses = controller.items.where(
          (item) =>
              item.id.toUpperCase() == group.targetId.toUpperCase() ||
              item.code.toUpperCase() == group.targetId.toUpperCase(),
        );
        if (matchingClasses.isEmpty) {
          skipped.add(
            '${group.targetName.isEmpty ? group.targetId : group.targetName} '
            '(${group.targetId}): không có trong danh sách lớp bạn phụ trách.',
          );
          continue;
        }
        if (matchingClasses.length > 1) {
          skipped.add(
            '${group.targetName.isEmpty ? group.targetId : group.targetName} '
            '(${group.targetId}): mã lớp bị trùng trong hệ thống.',
          );
          continue;
        }
        final item = matchingClasses.first;
        if (item.isArchived) {
          skipped.add('${item.name} (${item.code}): lớp đã đóng/lưu trữ.');
          continue;
        }
        if (group.studentIds.length > 2000) {
          skipped.add(
            '${item.name} (${item.code}): vượt giới hạn 2.000 sinh viên.',
          );
          continue;
        }

        try {
          final result = await controller.importStudents(
            classId: item.id,
            studentIds: group.studentIds,
          );
          importedCount += result.importedCount;
          alreadyMemberCount += result.alreadyMemberCount;
          unknownStudentCount += result.unknownStudentIds.length;
          duplicateRows += group.duplicateRows;
        } catch (exception) {
          skipped.add('${item.name} (${item.code}): $exception');
        }
      }

      await controller.load();
      if (!context.mounted) return;
      final details = <String>[
        'Đã thêm: $importedCount sinh viên.',
        'Đã có trong lớp: $alreadyMemberCount sinh viên.',
        if (unknownStudentCount > 0)
          'Không tìm thấy $unknownStudentCount mã sinh viên trong hệ thống.',
        if (duplicateRows > 0)
          'Mã sinh viên trùng trong file: $duplicateRows dòng.',
        if (skipped.isNotEmpty) ...[
          'Không nhập được ${skipped.length} lớp:',
          ...skipped.take(10),
          if (skipped.length > 10) '... và ${skipped.length - 10} lớp khác.',
        ],
      ];
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Kết quả nhập sinh viên'),
          content: SingleChildScrollView(child: Text(details.join('\n'))),
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
      await _showExcelError(context, error.message.toString());
    } catch (exception) {
      if (!context.mounted) return;
      await _showExcelError(context, exception.toString());
    } finally {
      if (mounted) setState(() => _importingClassIds.remove('__excel__'));
    }
  }

  Future<bool?> _confirmExcelImport(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<String> lines,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(subtitle),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(lines.join('\n\n')),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Xác nhận nhập'),
          ),
        ],
      ),
    );
  }

  Future<void> _showExcelError(BuildContext context, String message) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Không thể nhập file Excel'),
        content: SingleChildScrollView(child: SelectableText(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
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
        final viewport = MediaQuery.sizeOf(dialogContext);
        final compact = viewport.width <= 700;
        return AlertDialog(
          insetPadding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 40,
            vertical: compact ? 12 : 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          surfaceTintColor: Colors.transparent,
          titlePadding: EdgeInsets.fromLTRB(
            compact ? 16 : 24,
            compact ? 16 : 22,
            compact ? 16 : 24,
            0,
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.secondary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.school_outlined,
                  color: colors.secondaryForeground,
                ),
              ),
              SizedBox(width: compact ? 10 : 14),
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.displayMd(colors.foreground)
                      .copyWith(fontSize: compact ? 18 : null),
                ),
              ),
            ],
          ),
          contentPadding: EdgeInsets.fromLTRB(
            compact ? 16 : 24,
            18,
            compact ? 16 : 24,
            8,
          ),
          content: SizedBox(
            width: compact ? (viewport.width - 56).clamp(240.0, 760.0) : 760,
            height: viewport.height * (compact ? 0.58 : 0.74),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 6,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.muted.withValues(alpha: 0.55),
                      border: Border.all(color: colors.border),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: SingleChildScrollView(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final twoColumns = constraints.maxWidth >= 600;
                          final tileWidth = twoColumns
                              ? (constraints.maxWidth - 12) / 2
                              : constraints.maxWidth;
                          return Wrap(
                            spacing: 12,
                            runSpacing: 14,
                            children: [
                              _classInfoTile(
                                colors,
                                Icons.tag_outlined,
                                'Mã lớp',
                                item.code,
                                width: tileWidth,
                              ),
                              _classInfoTile(
                                colors,
                                Icons.person_outline_rounded,
                                'Giảng viên',
                                item.lecturerName,
                                width: tileWidth,
                              ),
                              _classInfoTile(
                                colors,
                                Icons.calendar_month_outlined,
                                'Học kỳ',
                                item.semester,
                                width: tileWidth,
                              ),
                              _classInfoTile(
                                colors,
                                Icons.schedule_outlined,
                                'Thời gian bắt đầu',
                                _dateTimeLabel(item.startTime),
                                width: tileWidth,
                              ),
                              _classInfoTile(
                                colors,
                                Icons.menu_book_outlined,
                                'Môn học',
                                item.subjectCode,
                                width: tileWidth,
                              ),
                              _classInfoTile(
                                colors,
                                Icons.account_balance_outlined,
                                'Bộ môn',
                                item.majorName,
                                width: tileWidth,
                              ),
                              _classInfoTile(
                                colors,
                                Icons.groups_outlined,
                                'Khóa',
                                item.cohortCode,
                                width: tileWidth,
                              ),
                              _classInfoTile(
                                colors,
                                Icons.info_outline_rounded,
                                'Trạng thái',
                                item.status,
                                width: tileWidth,
                                badge: true,
                              ),
                              _classInfoTile(
                                colors,
                                Icons.people_outline_rounded,
                                'Sĩ số',
                                '${item.studentCount}',
                                width: tileWidth,
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
                SizedBox(height: compact ? 12 : 18),
                Row(
                  children: [
                    Icon(
                      Icons.people_alt_outlined,
                      size: compact ? 18 : 20,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Danh sách sinh viên (${item.studentCount})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.displaySm(colors.foreground)
                            .copyWith(fontSize: compact ? 16 : null),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  flex: 4,
                  child: FutureBuilder(
                    future: students,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
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
          actionsPadding: EdgeInsets.fromLTRB(
            compact ? 16 : 24,
            8,
            compact ? 16 : 24,
            compact ? 12 : 18,
          ),
          actions: [
            FilledButton.tonal(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Đóng'),
            ),
          ],
        );
      },
    );
  }

  Widget _classInfoTile(
    AppColors colors,
    IconData icon,
    String label,
    String value, {
    required double width,
    bool badge = false,
  }) {
    final valueWidget = badge
        ? Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: colors.secondary,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                value,
                style: AppTextStyles.bodyXs(colors.secondaryForeground)
                    .copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          )
        : Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySm(colors.foreground)
                .copyWith(fontWeight: FontWeight.w600),
          );
    return SizedBox(
      width: width,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colors.primary),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.bodyXs(colors.mutedForeground),
                ),
                const SizedBox(height: 3),
                valueWidget,
              ],
            ),
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
    final hostContext = context;
    await controller.loadClassOptions();
    if (!hostContext.mounted) return;
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: item?.name ?? '');
    final capacityController = TextEditingController(
      text: item?.capacity.toString() ?? '50',
    );
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
      context: hostContext,
      builder: (dialogContext) => StatefulBuilder(
        builder: (modalContext, setModalState) {
          final colors = AppColors.of(
            Theme.of(modalContext).brightness == Brightness.dark,
          );
          Widget enrollmentFields() {
            final capacityField = TextFormField(
              controller: capacityController,
              keyboardType: TextInputType.number,
              decoration: _classInputDecoration(
                colors,
                'Sĩ số tối đa',
              ).copyWith(suffixText: 'sinh viên'),
              validator: (value) {
                final capacity = int.tryParse(value?.trim() ?? '');
                if (capacity == null || capacity < 1) {
                  return 'Nhập số lượng sinh viên lớn hơn 0.';
                }
                return null;
              },
            );
            final cohortField = item == null
                ? DropdownButtonFormField<String>(
                    initialValue: cohortCode,
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(12),
                    decoration: _classInputDecoration(colors, 'Khóa sinh viên'),
                    items: controller.cohorts
                        .map(
                          (cohort) => DropdownMenuItem<String>(
                            value: cohort.code,
                            child: Text(cohort.code),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setModalState(() => cohortCode = value),
                    validator: (value) =>
                        value == null ? 'Vui lòng chọn khóa sinh viên' : null,
                  )
                : InputDecorator(
                    decoration: _classInputDecoration(colors, 'Khóa sinh viên'),
                    child: Text(item.cohortCode),
                  );
            final isWide = MediaQuery.sizeOf(modalContext).width >= 720;
            if (!isWide) {
              return Column(
                children: [
                  capacityField,
                  const SizedBox(height: 12),
                  cohortField,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: capacityField),
                const SizedBox(width: 12),
                Expanded(child: cohortField),
              ],
            );
          }

          return AlertDialog(
            scrollable: true,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 16,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            surfaceTintColor: Colors.transparent,
            titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.secondary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.add_business_outlined,
                    color: colors.secondaryForeground,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    item == null ? 'Tạo lớp' : 'Chỉnh sửa lớp',
                    style: AppTextStyles.displayMd(colors.foreground),
                  ),
                ),
              ],
            ),
            contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
            content: SizedBox(
              width: 650,
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _classFormSection(
                      colors,
                      Icons.menu_book_outlined,
                      'Thông tin môn/lớp',
                      [
                        if (item == null)
                          DropdownButtonFormField<ClassSubjectOption>(
                            initialValue: selectedSubject,
                            isExpanded: true,
                            isDense: false,
                            itemHeight: 72,
                            menuMaxHeight: 360,
                            borderRadius: BorderRadius.circular(12),
                            decoration: _classInputDecoration(colors, 'Môn học')
                                .copyWith(
                                  constraints: const BoxConstraints(
                                    minHeight: 76,
                                  ),
                                  contentPadding: const EdgeInsets.fromLTRB(
                                    14,
                                    18,
                                    14,
                                    12,
                                  ),
                                ),
                            items: controller.subjects
                                .map(
                                  (subject) =>
                                      DropdownMenuItem<ClassSubjectOption>(
                                        value: subject,
                                        child: _classSubjectOption(
                                          colors,
                                          subject,
                                        ),
                                      ),
                                )
                                .toList(),
                            selectedItemBuilder: (context) => controller
                                .subjects
                                .map(
                                  (subject) =>
                                      _classSubjectOption(colors, subject),
                                )
                                .toList(),
                            onChanged: (value) => setModalState(() {
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
                            decoration: _classInputDecoration(
                              colors,
                              'Môn học',
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  selectedSubject?.name ?? item.name,
                                  style: AppTextStyles.bodySm(colors.foreground)
                                      .copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${item.subjectCode} · ${item.credits} tín chỉ',
                                  style: AppTextStyles.bodyXs(
                                    colors.mutedForeground,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (item == null && selectedSubject != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Môn học có ${selectedSubject!.credits} tín chỉ.',
                                style: AppTextStyles.bodyXs(
                                  colors.mutedForeground,
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: nameController,
                          decoration: _classInputDecoration(
                            colors,
                            'Tên lớp học phần',
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Vui lòng nhập tên lớp'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        InputDecorator(
                          decoration: _classInputDecoration(colors, 'Bộ môn'),
                          child: Text(
                            selectedSubject?.majorName ?? item?.majorName ?? '',
                            style: AppTextStyles.bodySm(colors.foreground),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _classFormSection(
                      colors,
                      Icons.groups_outlined,
                      'Thông tin tuyển sinh',
                      [enrollmentFields()],
                    ),
                    const SizedBox(height: 16),
                    _classFormSection(
                      colors,
                      Icons.assignment_ind_outlined,
                      'Phân công & thời gian',
                      [
                        _classDateField(
                          colors,
                          startTime == null
                              ? 'Chưa chọn'
                              : '${_dateTimeLabel(startTime!.toIso8601String())}'
                                    '\nHọc kỳ tự động: ${semesterForDate(startTime!)}',
                          () async {
                            final selected = await _pickStartTime(
                              modalContext,
                              startTime,
                            );
                            if (!dialogContext.mounted || selected == null) {
                              return;
                            }
                            setModalState(() {
                              startTime = selected;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: lecturerId,
                          isExpanded: true,
                          borderRadius: BorderRadius.circular(12),
                          decoration: _classInputDecoration(
                            colors,
                            'Giảng viên',
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
                              setModalState(() => lecturerId = value),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
            actionsAlignment: MainAxisAlignment.end,
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Hủy'),
              ),
              FilledButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  if (startTime == null) {
                    ScaffoldMessenger.of(hostContext).showSnackBar(
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
                        capacity: int.parse(capacityController.text.trim()),
                      );
                    } else {
                      await controller.updateClass(
                        id: item.id,
                        name: nameController.text.trim(),
                        semester: semesterForDate(startTime!),
                        startTime: _formatDateTime(startTime!),
                        lecturerId: lecturerId,
                        capacity: int.parse(capacityController.text.trim()),
                      );
                    }
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  } catch (exception) {
                    if (hostContext.mounted) {
                      ScaffoldMessenger.of(hostContext).showSnackBar(
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
    capacityController.dispose();
  }

  static Widget _classFormSection(
    AppColors colors,
    IconData icon,
    String title,
    List<Widget> children,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 19, color: colors.primary),
              const SizedBox(width: 8),
              Text(title, style: AppTextStyles.displaySm(colors.foreground)),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  static Widget _classSubjectOption(
    AppColors colors,
    ClassSubjectOption subject,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          subject.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.bodySm(colors.foreground)
              .copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 3),
        Text(
          '${subject.code} · ${subject.credits} tín chỉ',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.bodyXs(colors.mutedForeground),
        ),
      ],
    );
  }

  static InputDecoration _classInputDecoration(AppColors colors, String label) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(11),
      borderSide: BorderSide(color: colors.border),
    );
    return InputDecoration(
      labelText: label,
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: BorderSide(color: colors.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  static Widget _classDateField(
    AppColors colors,
    String value,
    VoidCallback onTap,
  ) {
    return Material(
      color: colors.muted.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Thời gian bắt đầu',
                      style: AppTextStyles.bodyXs(colors.mutedForeground),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: AppTextStyles.bodySm(colors.foreground)
                          .copyWith(height: 1.4, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.calendar_month_outlined, color: colors.primary),
            ],
          ),
        ),
      ),
    );
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    }
  }
}
