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
          (header) =>
              targetIdHeaders.map(_normalizeHeader).contains(header),
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

List<ExcelEventImportRow> extractEventsFromWorkbook(Excel workbook) {
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

  for (var index = headerIndex + 1; index < rows.length; index++) {
    final row = rows[index];
    final sourceId = _cellTextAt(row, idColumn).trim();
    final name = _cellTextAt(row, nameColumn).trim();
    if (sourceId.isEmpty && name.isEmpty) continue;
    if (sourceId.isEmpty || name.isEmpty) {
      throw FormatException(
        'Thiếu mã hoặc tên sự kiện ở dòng ${index + 1} của file Excel.',
      );
    }
    final eventDate = _excelDateAt(row, dateColumn);
    if (eventDate == null) {
      throw FormatException(
        'Thiếu ngày tổ chức của sự kiện "$name" ở dòng ${index + 1}.',
      );
    }
    final organizerName = _cellTextAt(row, organizerColumn).trim();
    final location = _cellTextAt(row, locationColumn).trim();
    if (organizerName.isEmpty || location.isEmpty) {
      throw FormatException(
        'Thiếu đơn vị tổ chức hoặc địa điểm của sự kiện "$name".',
      );
    }

    events.add((
      sourceId: sourceId,
      name: name,
      organizerName: organizerName,
      location: location,
      eventDate: eventDate,
      startMinutes: _excelTimeMinutesAt(row, startColumn),
      endMinutes: _excelTimeMinutesAt(row, endColumn),
      description: _cellTextAt(row, descriptionColumn).trim(),
    ));
  }

  if (events.isEmpty) {
    throw const FormatException('Không tìm thấy sự kiện nào trong file Excel.');
  }
  return events;
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

int _findHeader(List<String> headers, Set<String> candidates) =>
    headers.indexWhere(
      (header) => candidates.map(_normalizeHeader).contains(header),
    );

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
  return parsed == null ? null : DateTime(parsed.year, parsed.month, parsed.day);
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
