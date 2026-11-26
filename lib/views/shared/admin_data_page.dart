import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/api/api_client.dart';
import '../../core/utils/excel_file_decoder.dart';
import '../../widgets/app_search_field.dart';

class AdminDataPage extends StatefulWidget {
  final String title;
  final String endpoint;
  final List<String> columns;

  const AdminDataPage({
    super.key,
    required this.title,
    required this.endpoint,
    required this.columns,
  });

  @override
  State<AdminDataPage> createState() => _AdminDataPageState();
}

class _AdminDataPageState extends State<AdminDataPage> {
  late Future<Map<String, dynamic>> _dataFuture;
  String _query = '';
  String _userRoleFilter = 'all';
  bool _importingMasterData = false;

  @override
  void initState() {
    super.initState();
    _dataFuture = ApiClient().get(widget.endpoint);
  }

  @override
  void didUpdateWidget(covariant AdminDataPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.endpoint != widget.endpoint) {
      _query = '';
      _userRoleFilter = 'all';
      _dataFuture = ApiClient().get(widget.endpoint);
    }
  }

  String? get _masterDataKind => widget.endpoint.endsWith('/units')
      ? 'units'
      : widget.endpoint.endsWith('/users')
      ? 'users'
      : null;

  bool get _supportsMasterDataImport => _masterDataKind != null;

  String _userCategory(Object? rawRole) {
    final role = (rawRole ?? '').toString().trim().toLowerCase()
        .replaceAll('_', ' ')
        .replaceAll('-', ' ');
    if (role == 'sinh viên' || role == 'student') return 'student';
    if (role == 'giảng viên' || role == 'lecturer' || role == 'teacher') {
      return 'lecturer';
    }
    if ({'cán bộ', 'nhân viên', 'employee', 'staff', 'organizer',
      'event organizer', 'ban tổ chức'}.contains(role)) {
      return 'employee';
    }
    return 'other';
  }

  Future<void> _downloadMasterDataTemplate() async {
    try {
      final workbook = Excel.createExcel();
      final isUnits = _masterDataKind == 'units';
      final sheetName = isUnits ? 'DonVi' : 'NguoiDung';
      workbook.rename('Sheet1', sheetName);
      workbook[sheetName].appendRow(
        isUnits
            ? [
                TextCellValue('MaDV'),
                TextCellValue('TenDV'),
                TextCellValue('MaNhanVienPhuTrach'),
              ]
            : [
                TextCellValue('MaND'),
                TextCellValue('HoTen'),
                TextCellValue('Email'),
                TextCellValue('MatKhau'),
                TextCellValue('VaiTro'),
                TextCellValue('TrangThai'),
                TextCellValue('SDT'),
                TextCellValue('DiaChi'),
                TextCellValue('NgaySinh'),
                TextCellValue('GioiTinh'),
                TextCellValue('QueQuan'),
                TextCellValue('Lop'),
                TextCellValue('MaKhoa'),
                TextCellValue('ChuyenNganh'),
                TextCellValue('BoMon'),
                TextCellValue('ChucVu'),
              ],
      );
      final instructions = isUnits
          ? [
              'Sheet DonVi: MaDV và TenDV bắt buộc; MaNhanVienPhuTrach có thể để trống.',
              'Định dạng MaDV và MaNhanVienPhuTrach là Văn bản để giữ số 0 ở đầu.',
              'Mã đơn vị phải chưa tồn tại trong hệ thống.',
            ]
          : [
              'Sheet NguoiDung: MaND, HoTen, Email, MatKhau và VaiTro bắt buộc.',
              'VaiTro hợp lệ: Sinh viên, Giảng viên, Cán bộ. Không hỗ trợ tạo tài khoản Admin.',
              'Sinh viên cần Lop và ChuyenNganh; MaKhoa có thể để trống nếu Lop bắt đầu bằng mã khóa (ví dụ 26DHKTPM01). Giảng viên cần BoMon; Cán bộ cần ChucVu.',
              'MatKhau tối thiểu 8 ký tự; mật khẩu được mã hóa trước khi lưu. Trạng thái trống mặc định là Đang hoạt động.',
              'Định dạng MaND là Văn bản để giữ số 0 ở đầu. NgaySinh dùng dạng YYYY-MM-DD.',
              'Mã tài khoản và email phải chưa tồn tại trong hệ thống.',
            ];
      for (final instruction in instructions) {
        workbook['HuongDan'].appendRow([TextCellValue(instruction)]);
      }
      final bytes = workbook.encode();
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Không tạo được nội dung file mẫu.');
      }
      final savedPath = await FilePicker.saveFile(
        dialogTitle: 'Lưu mẫu import ${isUnits ? 'đơn vị' : 'người dùng'}',
        fileName: isUnits
            ? 'Mau_import_don_vi.xlsx'
            : 'Mau_import_nguoi_dung.xlsx',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        bytes: Uint8List.fromList(bytes),
      );
      if (!mounted || savedPath == null) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Đã lưu file mẫu: $savedPath')));
    } on Exception catch (exception) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thể tạo file mẫu Excel: $exception')),
      );
    }
  }

  Future<void> _importMasterData() async {
    FilePickerResult? selection;
    try {
      selection = await FilePicker.pickFiles(
        dialogTitle:
            'Chọn file Excel ${_masterDataKind == 'units' ? 'đơn vị' : 'người dùng'}',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        allowMultiple: false,
        withData: true,
      );
    } on Exception catch (exception) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thể mở file Excel: $exception')),
      );
      return;
    }
    if (selection == null || selection.files.isEmpty || !mounted) return;
    final bytes = selection.files.single.bytes;
    if (bytes == null || bytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không đọc được nội dung file Excel.')),
      );
      return;
    }

    try {
      final parsed = extractAdminMasterDataFromWorkbook(
        decodeExcelWorkbook(bytes),
      );
      final isUnits = _masterDataKind == 'units';
      final selected = (
        units: isUnits ? parsed.units : <Map<String, String>>[],
        users: isUnits ? <Map<String, String>>[] : parsed.users,
        warnings: parsed.warnings,
      );
      if (selected.units.isEmpty && selected.users.isEmpty) {
        throw FormatException(
          isUnits
              ? 'Không tìm thấy đơn vị hợp lệ trong sheet DonVi.'
              : 'Không tìm thấy tài khoản hợp lệ trong sheet NguoiDung.',
        );
      }
      final confirmed = await _confirmMasterDataImport(selected);
      if (confirmed != true || !mounted) return;

      setState(() => _importingMasterData = true);
      final result = await ApiClient().post(
        '/api/admin/master-data/import',
        data: {'units': parsed.units, 'users': parsed.users},
      );
      if (!mounted) return;
      setState(() {
        _dataFuture = ApiClient().get(widget.endpoint);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isUnits
                ? 'Đã thêm ${result['importedUnits'] ?? 0} đơn vị.'
                : 'Đã thêm ${result['importedUsers'] ?? 0} tài khoản.',
          ),
        ),
      );
    } on FormatException catch (exception) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(exception.message)));
    } on Exception catch (exception) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thể nhập dữ liệu Excel: $exception')),
      );
    } finally {
      if (mounted) setState(() => _importingMasterData = false);
    }
  }

  Future<bool?> _confirmMasterDataImport(ExcelMasterDataImport parsed) {
    final preview = <String>[
      for (final unit in parsed.units)
        'Đơn vị: ${unit['name']} · ${unit['id']} · '
            'Phụ trách: ${unit['managerId']!.isEmpty ? 'chưa phân công' : unit['managerId']}',
      for (final user in parsed.users)
        'Tài khoản: ${user['name']} · ${user['id']} · '
            '${user['email']} · ${user['role']}',
    ];
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'Xác nhận import ${parsed.units.isNotEmpty ? 'đơn vị' : 'người dùng'}',
        ),
        content: SizedBox(
          width: 560,
          height: 440,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                parsed.units.isNotEmpty
                    ? '${parsed.units.length} đơn vị hợp lệ sẽ được thêm.'
                    : '${parsed.users.length} tài khoản hợp lệ sẽ được thêm.',
              ),
              const SizedBox(height: 8),
              if (parsed.users.isNotEmpty)
                const Text(
                  'Mật khẩu không hiển thị trong bản xem trước và sẽ được mã hóa khi lưu. Không thể tạo tài khoản Admin từ Excel.',
                ),
              if (parsed.warnings.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '${parsed.warnings.length} dòng sẽ bị bỏ qua:',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ...parsed.warnings.take(5).map(Text.new),
                if (parsed.warnings.length > 5)
                  Text('Còn ${parsed.warnings.length - 5} cảnh báo khác.'),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: preview.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(preview[index]),
                  ),
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
            onPressed: _importingMasterData
                ? null
                : () => Navigator.pop(dialogContext, true),
            child: const Text('Xác nhận import'),
          ),
        ],
      ),
    );
  }

  /// Tải bảng dữ liệu thật theo endpoint được chọn.
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);
    return FutureBuilder<Map<String, dynamic>>(
      future: _dataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text(snapshot.error.toString()));
        }
        final rawItems = snapshot.data?['items'];
        final items = rawItems is List
            ? rawItems.whereType<Map>().toList()
            : <Map>[];
        final keys = columnKeys;
        final isUsers = widget.endpoint.endsWith('/users');
        final query = _query.trim().toLowerCase();
        final roleFilteredItems = !isUsers || _userRoleFilter == 'all'
            ? items
            : items.where((item) => _userCategory(item['role']) == _userRoleFilter).toList();
        final filteredItems = roleFilteredItems.where((item) {
          return query.isEmpty ||
              keys.any(
                (key) =>
                    item[key]?.toString().toLowerCase().contains(query) ??
                    false,
              );
        }).toList();
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(widget.title, style: AppTextStyles.displayLg(c.foreground)),
            const SizedBox(height: 16),
            if (_supportsMasterDataImport) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _importingMasterData
                        ? null
                        : _downloadMasterDataTemplate,
                    icon: const Icon(Icons.download_outlined),
                    label: Text(
                      'Tải mẫu ${_masterDataKind == 'units' ? 'đơn vị' : 'người dùng'} Excel',
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _importingMasterData ? null : _importMasterData,
                    icon: const Icon(Icons.upload_file),
                    label: Text(
                      _importingMasterData
                          ? 'Đang nhập...'
                          : 'Import ${_masterDataKind == 'units' ? 'đơn vị' : 'người dùng'} Excel',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _masterDataKind == 'units'
                    ? 'Dùng sheet DonVi với các cột MaDV, TenDV và MaNhanVienPhuTrach (không bắt buộc).'
                    : 'Dùng sheet NguoiDung. Vai trò hợp lệ: Sinh viên, Giảng viên, Cán bộ; không hỗ trợ tạo Admin. Sinh viên cần lớp/chuyên ngành, Giảng viên cần bộ môn, Cán bộ cần chức vụ.',
                style: AppTextStyles.bodyXs(c.mutedForeground),
              ),
              const SizedBox(height: 16),
            ],
            AppSearchField(
              key: ValueKey(widget.endpoint),
              colors: c,
              hintText: 'Tìm trong ${widget.title.toLowerCase()}...',
              onChanged: (value) => setState(() => _query = value),
            ),
            if (isUsers) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: 360,
                child: DropdownButtonFormField<String>(
                  initialValue: _userRoleFilter,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Lọc theo vai trò',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('Tất cả tài khoản')),
                    DropdownMenuItem(value: 'student', child: Text('Sinh viên')),
                    DropdownMenuItem(value: 'lecturer', child: Text('Giảng viên')),
                    DropdownMenuItem(value: 'employee', child: Text('Nhân viên')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _userRoleFilter = value);
                  },
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ('Tổng người dùng', filteredItems.length),
                  ('Sinh viên', filteredItems.where((item) => _userCategory(item['role']) == 'student').length),
                  ('Giảng viên', filteredItems.where((item) => _userCategory(item['role']) == 'lecturer').length),
                  ('Nhân viên', filteredItems.where((item) => _userCategory(item['role']) == 'employee').length),
                  ('Vai trò khác', filteredItems.where((item) => _userCategory(item['role']) == 'other').length),
                ].map((stat) => Container(
                  constraints: const BoxConstraints(minWidth: 118),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: c.card,
                    border: Border.all(color: c.border),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(stat.$1, style: AppTextStyles.bodyXs(c.mutedForeground)),
                      const SizedBox(height: 3),
                      Text('${stat.$2}', style: AppTextStyles.displaySm(c.foreground)),
                    ],
                  ),
                )).toList(),
              ),
            ],
            const SizedBox(height: 16),
            if (filteredItems.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    items.isEmpty
                        ? 'Chưa có dữ liệu.'
                        : 'Không tìm thấy kết quả phù hợp.',
                    style: AppTextStyles.bodySm(c.mutedForeground),
                  ),
                ),
              )
            else
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: c.card,
                  border: Border.all(color: c.border),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: constraints.maxWidth,
                      ),
                      child: DataTable(
                        headingRowHeight: 52,
                        headingRowColor: WidgetStatePropertyAll(
                          c.muted.withValues(alpha: 0.82),
                        ),
                        headingTextStyle: AppTextStyles.label(c.mutedForeground)
                            .copyWith(fontWeight: FontWeight.w700),
                        dataTextStyle: AppTextStyles.bodySm(c.foreground),
                        dividerThickness: 0.8,
                        horizontalMargin: 24,
                        columnSpacing: 44,
                        dataRowMinHeight: 58,
                        dataRowMaxHeight: 66,
                        columns: widget.columns
                            .map((column) => DataColumn(label: Text(column)))
                            .toList(),
                        rows: filteredItems.map((item) {
                          return DataRow(
                            color: WidgetStateProperty.resolveWith((states) {
                              if (states.contains(WidgetState.hovered)) {
                                return c.primary.withValues(alpha: 0.045);
                              }
                              return null;
                            }),
                            mouseCursor: const WidgetStatePropertyAll(
                              SystemMouseCursors.basic,
                            ),
                            cells: widget.columns.map((column) {
                              final key = keys[widget.columns.indexOf(column)];
                              return DataCell(
                                _buildCell(
                                  c,
                                  column,
                                  item[key]?.toString() ?? '',
                                  isUsers,
                                ),
                              );
                            }).toList(),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildCell(
    AppColors colors,
    String column,
    String value,
    bool isUsers,
  ) {
    if (isUsers && (column == 'Vai trò' || column == 'Trạng thái')) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: column == 'Trạng thái'
              ? colors.primary.withValues(alpha: 0.08)
              : colors.secondary,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          value,
          style: AppTextStyles.bodyXs(
            column == 'Trạng thái'
                ? colors.primary
                : colors.secondaryForeground,
          ).copyWith(fontWeight: FontWeight.w700),
        ),
      );
    }
    return Text(
      value,
      style: column == 'Họ tên' && isUsers
          ? AppTextStyles.bodySm(colors.foreground)
                .copyWith(fontWeight: FontWeight.w700)
          : column == 'Email' && isUsers
          ? AppTextStyles.bodySm(colors.mutedForeground)
          : AppTextStyles.bodySm(colors.foreground),
    );
  }

  /// Ánh xạ các cột hiển thị về key JSON từ từng endpoint.
  List<String> get columnKeys {
    if (widget.endpoint.endsWith('/units')) {
      return const ['id', 'name'];
    }
    if (widget.endpoint.endsWith('/users')) {
      return const ['id', 'name', 'email', 'role', 'status'];
    }
    if (widget.endpoint.endsWith('/classes')) {
      return const ['id', 'name', 'lecturerName', 'semester', 'studentCount'];
    }
    return const ['id', 'name', 'location', 'startTime', 'registeredCount'];
  }
}
