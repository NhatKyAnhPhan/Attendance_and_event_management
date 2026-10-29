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

bool _isStudentIdHeader(String header) {
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
