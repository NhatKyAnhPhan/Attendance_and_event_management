import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';

Excel decodeExcelWorkbook(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final relationships = archive.findFile('xl/_rels/workbook.xml.rels');
  if (relationships == null) return Excel.decodeBytes(bytes);

  final xml = utf8.decode(relationships.content as List<int>);
  final normalizedXml = xml.replaceAllMapped(
    RegExp(r'''(\bTarget\s*=\s*["'])/xl/([^"']+)(["'])'''),
    (match) => '${match[1]}${match[2]}${match[3]}',
  );
  if (normalizedXml == xml) return Excel.decodeBytes(bytes);

  final relationshipIndex = archive.files.indexOf(relationships);
  final normalizedBytes = utf8.encode(normalizedXml);
  archive[relationshipIndex] = ArchiveFile(
    relationships.name,
    normalizedBytes.length,
    normalizedBytes,
  );

  final normalizedArchive = ZipEncoder().encode(archive);
  if (normalizedArchive == null) {
    throw const FormatException('Không thể đọc cấu trúc file Excel.');
  }
  return Excel.decodeBytes(normalizedArchive);
}

typedef ExcelStudentIds = ({List<String> studentIds, int duplicateRows});

typedef ExcelStudentRosterGroup = ({
  String targetId,
  String targetName,
  List<String> studentIds,
  int duplicateRows,
});

typedef ExcelClassImportRow = ({
  String subjectId,
  String name,
  String cohortCode,
  DateTime startTime,
  int capacity,
  String semester,
  String lecturerId,
});

typedef ExcelEventImportRow = ({
  String sourceId,
  String name,
  String organizerName,
  String location,
  DateTime eventDate,
  int? startMinutes,
  int? endMinutes,
  String description,
});

typedef ExcelEventsImport = ({
  List<ExcelEventImportRow> events,
  List<String> warnings,
});

typedef ExcelMasterDataImport = ({
  List<Map<String, String>> units,
  List<Map<String, String>> users,
  List<String> warnings,
});

ExcelMasterDataImport extractAdminMasterDataFromWorkbook(Excel workbook) {
  final units = <Map<String, String>>[];
  final users = <Map<String, String>>[];
  final warnings = <String>[];
  final unitSheet = workbook.tables['DonVi'];
  final userSheet = workbook.tables['NguoiDung'];

  if (unitSheet == null && userSheet == null) {
    throw const FormatException(
      'File cần có sheet DonVi, NguoiDung hoặc cả hai theo mẫu Excel.',
    );
  }
  if (unitSheet != null) {
    _extractMasterDataSheet(
      unitSheet.rows,
      sheetName: 'DonVi',
      fields: const {
        'id': {'madv', 'maunit', 'unitid', 'unitcode'},
        'name': {'tendv', 'tendonvi', 'unitname', 'name'},
        'managerId': {'manhanvienphutrach', 'manv', 'managerid', 'employeeid'},
      },
      requiredFields: const {'id', 'name'},
      output: units,
      warnings: warnings,
    );
  }
  if (userSheet != null) {
    _extractMasterDataSheet(
      userSheet.rows,
      sheetName: 'NguoiDung',
      fields: const {
        'id': {'mand', 'mataikhoan', 'userid', 'usercode'},
        'name': {'hoten', 'hovaten', 'fullname', 'name'},
        'email': {'email'},
        'password': {'matkhau', 'password'},
        'role': {'vaitro', 'role'},
        'status': {'trangthai', 'trangthaitaikhoan', 'status'},
        'phone': {'sdt', 'sodienthoai', 'phone'},
        'address': {'diachi', 'address'},
        'birthDate': {'ngaysinh', 'birthdate'},
        'gender': {'gioitinh', 'gender'},
        'hometown': {'quequan', 'hometown'},
        'className': {'lop', 'class'},
        'cohortCode': {'makhoa', 'cohort', 'cohortcode'},
        'major': {'chuyennganh', 'major'},
        'subjectDepartment': {'bomon', 'subjectdepartment'},
        'position': {'chucvu', 'position'},
      },
      requiredFields: const {'id', 'name', 'email', 'password', 'role'},
      output: users,
      warnings: warnings,
    );
  }

  if (units.isEmpty && users.isEmpty) {
    throw FormatException(
      warnings.isEmpty
          ? 'Không tìm thấy đơn vị hoặc tài khoản trong file Excel.'
          : warnings.join(' '),
    );
  }
  return (units: units, users: users, warnings: warnings);
}

void _extractMasterDataSheet(
  List<List<Data?>> rows, {
  required String sheetName,
  required Map<String, Set<String>> fields,
  required Set<String> requiredFields,
  required List<Map<String, String>> output,
  required List<String> warnings,
}) {
  final headerIndex = rows.indexWhere((row) {
    final headers = row.map((cell) => _normalizeHeader(_excelCellText(cell)));
    return requiredFields.every(
      (field) => headers.any(fields[field]!.contains),
    );
  });
  if (headerIndex < 0) {
    warnings.add('$sheetName: không tìm thấy hàng tiêu đề hợp lệ.');
    return;
  }

  final headers = rows[headerIndex]
      .map((cell) => _normalizeHeader(_excelCellText(cell)))
      .toList();
  final seenIds = <String>{};
  final seenEmails = <String>{};
  for (var index = headerIndex + 1; index < rows.length; index++) {
    final row = rows[index];
    if (row.every((cell) => _excelCellText(cell).trim().isEmpty)) continue;
    final record = <String, String>{};
    for (final entry in fields.entries) {
      final column = headers.indexWhere(entry.value.contains);
      if (entry.key == 'birthDate') {
        final date = _excelDateAt(row, column);
        record[entry.key] = date == null ? '' : _formatExcelDate(date);
      } else {
        record[entry.key] = _cellTextAt(row, column).trim();
      }
    }
    final missing = requiredFields
        .where((field) => record[field]!.isEmpty)
        .toList();
    if (missing.isNotEmpty) {
      warnings.add(
        '$sheetName dòng ${index + 1}: thiếu ${missing.join(', ')}, sẽ bỏ qua.',
      );
      continue;
    }
    final idKey = record['id']!.toLowerCase();
    if (seenIds.contains(idKey)) {
      warnings.add('$sheetName dòng ${index + 1}: mã bị lặp trong file, sẽ bỏ qua.');
      continue;
    }
    if (sheetName == 'NguoiDung') {
      final role = _canonicalMasterDataRole(record['role']!);
      if (role == null) {
        warnings.add(
          '$sheetName dòng ${index + 1}: vai trò không hợp lệ (không hỗ trợ Admin), sẽ bỏ qua.',
        );
        continue;
      }
      record['role'] = role;
      final email = record['email']!;
      final password = record['password']!;
      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email) ||
          password.length < 8) {
        warnings.add(
          '$sheetName dòng ${index + 1}: email không hợp lệ hoặc mật khẩu ngắn hơn 8 ký tự, sẽ bỏ qua.',
        );
        continue;
      }
      if ((role == 'Sinh viên' &&
              (record['className']!.isEmpty || record['major']!.isEmpty)) ||
          (role == 'Giảng viên' && record['subjectDepartment']!.isEmpty) ||
          (role == 'Cán bộ' && record['position']!.isEmpty)) {
        warnings.add(
          '$sheetName dòng ${index + 1}: thiếu thông tin hồ sơ bắt buộc theo vai trò, sẽ bỏ qua.',
        );
        continue;
      }
      final status = record['status']!.toLowerCase();
      if (status.isNotEmpty &&
          status != 'đang hoạt động' &&
          status != 'đã khóa') {
        warnings.add(
          '$sheetName dòng ${index + 1}: trạng thái không hợp lệ, sẽ bỏ qua.',
        );
        continue;
      }
      final emailKey = email.toLowerCase();
      if (seenEmails.contains(emailKey)) {
        warnings.add(
          '$sheetName dòng ${index + 1}: email bị lặp trong file, sẽ bỏ qua.',
        );
        continue;
      }
      seenEmails.add(emailKey);
    }
    seenIds.add(idKey);
    output.add(record);
  }
}

String? _canonicalMasterDataRole(String role) {
  switch (role.trim().toLowerCase()) {
    case 'sinh viên':
    case 'student':
      return 'Sinh viên';
    case 'giảng viên':
    case 'lecturer':
      return 'Giảng viên';
    case 'cán bộ':
    case 'nhân viên':
    case 'employee':
      return 'Cán bộ';
    default:
      return null;
  }
}

String _formatExcelDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

ExcelStudentIds extractStudentIdsFromWorkbook(Excel workbook) {
  if (workbook.tables.isEmpty) {
    throw const FormatException('File Excel không có trang tính dữ liệu.');
  }
  final rows = workbook.tables.values.first.rows;
  if (rows.isEmpty) {
    throw const FormatException('Trang tính Excel không có dữ liệu.');
  }

  final headerIndex = rows.indexWhere(
    (row) => row.any((cell) => _isStudentIdHeader(_excelCellText(cell))),
  );
  if (headerIndex < 0) {
    throw const FormatException(
      'Cột mã sinh viên cần có tiêu đề MSSV, Mã SV hoặc Mã sinh viên.',
    );
  }
  final idColumn = rows[headerIndex].indexWhere(
    (cell) => _isStudentIdHeader(_excelCellText(cell)),
  );

  final seenIds = <String>{};
  final studentIds = <String>[];
  var duplicateRows = 0;
  for (final row in rows.skip(headerIndex + 1)) {
    if (idColumn >= row.length) continue;
    final studentId = _excelCellText(row[idColumn]).trim();
    if (studentId.isEmpty) continue;
    if (seenIds.add(studentId.toUpperCase())) {
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
  return (studentIds: studentIds, duplicateRows: duplicateRows);
}

List<ExcelStudentRosterGroup> extractStudentRosterGroups(
  Excel workbook, {
  required Set<String> targetIdHeaders,
  required Set<String> targetNameHeaders,
}) {
  final rows = _firstSheetRows(workbook);
  final headerIndex = rows.indexWhere((row) {
    final headers = row.map((cell) => _normalizeHeader(_excelCellText(cell)));
    return headers.any(_isStudentIdHeader) &&
        headers.any(
          (header) => targetIdHeaders.map(_normalizeHeader).contains(header),
        );
  });
  if (headerIndex < 0) {
    throw const FormatException(
      'Không tìm thấy các cột MSSV và mã sự kiện/lớp trong file Excel.',
    );
  }

  final headers = rows[headerIndex]
      .map((cell) => _normalizeHeader(_excelCellText(cell)))
      .toList();
  final studentColumn = headers.indexWhere(_isStudentIdHeader);
  final targetIdColumn = headers.indexWhere(
    (header) => targetIdHeaders.map(_normalizeHeader).contains(header),
  );
  final targetNameColumn = headers.indexWhere(
    (header) => targetNameHeaders.map(_normalizeHeader).contains(header),
  );
  final groupedIds = <String, List<String>>{};
  final groupedNames = <String, String>{};
  final seenIdsByTarget = <String, Set<String>>{};
  final duplicateRowsByTarget = <String, int>{};

  for (var index = headerIndex + 1; index < rows.length; index++) {
    final row = rows[index];
    final studentId = _cellTextAt(row, studentColumn).trim();
    if (studentId.isEmpty) continue;

    final targetId = _cellTextAt(row, targetIdColumn).trim();
    if (targetId.isEmpty) {
      throw FormatException(
        'Thiếu mã sự kiện/lớp ở dòng ${index + 1} của file Excel.',
      );
    }

    final key = targetId.toUpperCase();
    final seenIds = seenIdsByTarget.putIfAbsent(key, () => <String>{});
    if (seenIds.add(studentId.toUpperCase())) {
      groupedIds.putIfAbsent(key, () => <String>[]).add(studentId);
    } else {
      duplicateRowsByTarget.update(
        key,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    if (!groupedNames.containsKey(key)) {
      groupedNames[key] = targetNameColumn < 0
          ? ''
          : _cellTextAt(row, targetNameColumn).trim();
    }
    groupedNames.putIfAbsent('id:$key', () => targetId);
  }

  if (groupedIds.isEmpty) {
    throw const FormatException(
      'Không tìm thấy sinh viên có mã sự kiện/lớp trong file Excel.',
    );
  }

  return groupedIds.entries
      .map(
        (entry) => (
          targetId: groupedNames['id:${entry.key}']!,
          targetName: groupedNames[entry.key] ?? '',
          studentIds: entry.value,
          duplicateRows: duplicateRowsByTarget[entry.key] ?? 0,
        ),
      )
      .toList();
}

List<ExcelClassImportRow> extractClassCreationRows(Excel workbook) {
  final rows = _firstSheetRows(workbook);
  const subjectHeaders = {'mamonhoc', 'subjectid', 'subjectcode'};
  const nameHeaders = {'tenlop', 'tenlophocphan', 'classname'};
  const cohortHeaders = {'makhoasinhvien', 'makhoa', 'cohortcode'};
  const startHeaders = {'ngaygiobatdau', 'thoigianbatdau', 'starttime'};
  const capacityHeaders = {'sisotoida', 'soluongtoida', 'capacity'};
  const semesterHeaders = {'hocky', 'semester'};
  const lecturerHeaders = {'magiangvien', 'lecturerid'};

  final headerIndex = rows.indexWhere((row) {
    final headers = row.map((cell) => _normalizeHeader(_excelCellText(cell)));
    return headers.any(subjectHeaders.contains) &&
        headers.any(nameHeaders.contains) &&
        headers.any(cohortHeaders.contains) &&
        headers.any(startHeaders.contains) &&
        headers.any(capacityHeaders.contains);
  });
  if (headerIndex < 0) {
    throw const FormatException(
      'Thiếu cột bắt buộc: MaMonHoc, TenLop, MaKhoaSinhVien, NgayGioBatDau, SiSoToiDa.',
    );
  }

  final headers = rows[headerIndex]
      .map((cell) => _normalizeHeader(_excelCellText(cell)))
      .toList();
  final subjectColumn = headers.indexWhere(subjectHeaders.contains);
  final nameColumn = headers.indexWhere(nameHeaders.contains);
  final cohortColumn = headers.indexWhere(cohortHeaders.contains);
  final startColumn = headers.indexWhere(startHeaders.contains);
  final capacityColumn = headers.indexWhere(capacityHeaders.contains);
  final semesterColumn = headers.indexWhere(semesterHeaders.contains);
  final lecturerColumn = headers.indexWhere(lecturerHeaders.contains);
  final result = <ExcelClassImportRow>[];

  for (var index = headerIndex + 1; index < rows.length; index++) {
    final row = rows[index];
    if (row.every((cell) => _excelCellText(cell).trim().isEmpty)) continue;
    final rowNumber = index + 1;
    final subjectId = _cellTextAt(row, subjectColumn).trim();
    final name = _cellTextAt(row, nameColumn).trim();
    final cohortCode = _cellTextAt(row, cohortColumn).trim();
    if (subjectId.isEmpty || name.isEmpty || cohortCode.isEmpty) {
      throw FormatException(
        'Thiếu mã môn, tên lớp hoặc mã khóa ở dòng $rowNumber.',
      );
    }

    final startTime = _excelDateTimeAt(row, startColumn);
    if (startTime == null) {
      throw FormatException('Ngày giờ bắt đầu không hợp lệ ở dòng $rowNumber.');
    }
    final capacityText = _cellTextAt(row, capacityColumn).trim();
    final capacity = int.tryParse(capacityText);
    if (capacity == null || capacity < 1) {
      throw FormatException(
        'Sĩ số tối đa phải là số nguyên dương ở dòng $rowNumber.',
      );
    }
    final semester = _cellTextAt(row, semesterColumn).trim().toUpperCase();
    if (semester.isNotEmpty &&
        !const {'HK1', 'HK2', 'HK3'}.contains(semester)) {
      throw FormatException(
        'Học kỳ phải là HK1, HK2 hoặc HK3 ở dòng $rowNumber.',
      );
    }
    result.add((
      subjectId: subjectId,
      name: name,
      cohortCode: cohortCode,
      startTime: startTime,
      capacity: capacity,
      semester: semester,
      lecturerId: _cellTextAt(row, lecturerColumn).trim(),
    ));
  }

  if (result.isEmpty) {
    throw const FormatException('Không tìm thấy dòng lớp nào trong file Excel.');
  }
  if (result.length > 200) {
    throw const FormatException('Mỗi file chỉ được chứa tối đa 200 lớp.');
  }
  return result;
}
ExcelEventsImport extractEventsFromWorkbook(Excel workbook) {
  final rows = _firstSheetRows(workbook);
  const eventIdHeaders = {'masukien', 'mãsựkiện'};
  const eventNameHeaders = {'tensukien', 'tênsựkiện'};
  final headerIndex = rows.indexWhere((row) {
    final headers = row.map((cell) => _normalizeHeader(_excelCellText(cell)));
    return headers.any(eventIdHeaders.contains) &&
        headers.any(eventNameHeaders.contains);
  });
  if (headerIndex < 0) {
    throw const FormatException(
      'Không tìm thấy cột MaSuKien và TenSuKien trong file Excel.',
    );
  }

  final headers = rows[headerIndex]
      .map((cell) => _normalizeHeader(_excelCellText(cell)))
      .toList();
  final idColumn = headers.indexWhere(eventIdHeaders.contains);
  final nameColumn = headers.indexWhere(eventNameHeaders.contains);
  final organizerColumn = _findHeader(headers, const {
    'donvitochuc',
    'đơnvịtổchức',
  });
  final locationColumn = _findHeader(headers, const {'diadiem', 'địađiểm'});
  final dateColumn = _findHeader(headers, const {'ngaytochuc', 'ngàytổchức'});
  final startColumn = _findHeader(headers, const {'giobatdau', 'giờbắtđầu'});
  final endColumn = _findHeader(headers, const {'gioketthuc', 'giờkếtthúc'});
  final descriptionColumn = _findHeader(headers, const {'mota', 'môtả'});
  final events = <ExcelEventImportRow>[];
  final warnings = <String>[];

  for (var index = headerIndex + 1; index < rows.length; index++) {
    final row = rows[index];
    final sourceId = _cellTextAt(row, idColumn).trim();
    final name = _cellTextAt(row, nameColumn).trim();
    if (sourceId.isEmpty && name.isEmpty) continue;
    if (sourceId.isEmpty || name.isEmpty) {
      warnings.add(
        'Dòng ${index + 1}: thiếu ${sourceId.isEmpty ? 'mã sự kiện' : 'tên sự kiện'}, sẽ bỏ qua.',
      );
      continue;
    }
    final eventDate = _excelDateAt(row, dateColumn);
    final organizerName = _cellTextAt(row, organizerColumn).trim();
    final location = _cellTextAt(row, locationColumn).trim();
    final missingFields = <String>[
      if (eventDate == null) 'ngày tổ chức',
      if (organizerName.isEmpty) 'đơn vị tổ chức',
      if (location.isEmpty) 'địa điểm',
    ];
    if (missingFields.isNotEmpty) {
      warnings.add(
        'Dòng ${index + 1} ($name): thiếu ${missingFields.join(', ')}, sẽ bỏ qua.',
      );
      continue;
    }

    events.add((
      sourceId: sourceId,
      name: name,
      organizerName: organizerName,
      location: location,
      eventDate: eventDate!,
      startMinutes: _excelTimeMinutesAt(row, startColumn),
      endMinutes: _excelTimeMinutesAt(row, endColumn),
      description: _cellTextAt(row, descriptionColumn).trim(),
    ));
  }

  if (events.isEmpty) {
    throw FormatException(
      warnings.isEmpty
          ? 'Không tìm thấy sự kiện nào trong file Excel.'
          : 'Không có sự kiện hợp lệ để nhập. ${warnings.join(' ')}',
    );
  }
  return (events: events, warnings: warnings);
}

List<List<Data?>> _firstSheetRows(Excel workbook) {
  if (workbook.tables.isEmpty) {
    throw const FormatException('File Excel không có trang tính dữ liệu.');
  }
  final rows = workbook.tables.values.first.rows;
  if (rows.isEmpty) {
    throw const FormatException('Trang tính Excel không có dữ liệu.');
  }
  return rows;
}

int _findHeader(List<String> headers, Set<String> candidates) => headers
    .indexWhere((header) => candidates.map(_normalizeHeader).contains(header));

String _cellTextAt(List<Data?> row, int column) =>
    column < 0 || column >= row.length ? '' : _excelCellText(row[column]);

DateTime? _excelDateAt(List<Data?> row, int column) {
  if (column < 0 || column >= row.length) return null;
  final value = row[column]?.value;
  if (value is DateCellValue) return value.asDateTimeLocal();
  if (value is DateTimeCellValue) {
    return DateTime(value.year, value.month, value.day);
  }
  final text = _excelCellText(row[column]).trim();
  final parsed = DateTime.tryParse(text);
  return parsed == null
      ? null
      : DateTime(parsed.year, parsed.month, parsed.day);
}

DateTime? _excelDateTimeAt(List<Data?> row, int column) {
  if (column < 0 || column >= row.length) return null;
  final value = row[column]?.value;
  if (value is DateTimeCellValue) {
    return DateTime(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
      value.second,
    );
  }
  if (value is DateCellValue) return value.asDateTimeLocal();
  if (value is DoubleCellValue || value is IntCellValue) {
    final serial = double.tryParse(_excelCellText(row[column]));
    if (serial == null || serial < 1) return null;
    return DateTime(1899, 12, 30).add(
      Duration(seconds: (serial * Duration.secondsPerDay).round()),
    );
  }
  return DateTime.tryParse(_excelCellText(row[column]).trim());
}

int? _excelTimeMinutesAt(List<Data?> row, int column) {
  if (column < 0 || column >= row.length) return null;
  final value = row[column]?.value;
  if (value is TimeCellValue) return value.hour * 60 + value.minute;
  if (value is DateTimeCellValue) return value.hour * 60 + value.minute;
  if (value is DateCellValue) return 0;
  if (value is DoubleCellValue && value.value >= 0 && value.value < 1) {
    return (value.value * 24 * 60).round();
  }
  final text = _excelCellText(row[column]).trim();
  final match = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?$').firstMatch(text);
  if (match != null) {
    final hour = int.parse(match[1]!);
    final minute = int.parse(match[2]!);
    if (hour < 24 && minute < 60) return hour * 60 + minute;
  }
  return null;
}

String _excelCellText(Data? cell) {
  final value = cell?.value;
  return switch (value) {
    TextCellValue(:final value) =>
      value.text ?? value.children?.map((span) => span.text ?? '').join() ?? '',
    IntCellValue(:final value) => value.toString(),
    DoubleCellValue(:final value) =>
      value == value.truncateToDouble()
          ? value.toInt().toString()
          : value.toString(),
    _ => value?.toString() ?? '',
  };
}

String _normalizeHeader(String header) =>
    header.toLowerCase().replaceAll(RegExp(r'[\s_.-]'), '');

bool _isStudentIdHeader(String header) {
  final normalized = _normalizeHeader(header);
  return const {
    'mssv',
    'masv',
    'mãsv',
    'mãsinhviên',
    'studentid',
    'studentcode',
  }.contains(normalized);
}
