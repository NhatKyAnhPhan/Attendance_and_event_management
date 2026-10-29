import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:attendance_and_event_management/core/utils/excel_file_decoder.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes workbooks with absolute worksheet relationship targets', () {
    final sourceWorkbook = Excel.createExcel();
    final sourceBytes = sourceWorkbook.encode()!;
    final archive = ZipDecoder().decodeBytes(sourceBytes);
    final relationships = archive.findFile('xl/_rels/workbook.xml.rels')!;
    final xml = utf8.decode(relationships.content as List<int>);
    final absoluteTargetXml = xml.replaceFirst(
      'Target="worksheets/sheet1.xml"',
      'Target="/xl/worksheets/sheet1.xml"',
    );
    final relationshipIndex = archive.files.indexOf(relationships);
    final absoluteTargetBytes = utf8.encode(absoluteTargetXml);
    archive[relationshipIndex] = ArchiveFile(
      relationships.name,
      absoluteTargetBytes.length,
      absoluteTargetBytes,
    );

    final absoluteTargetWorkbook = ZipEncoder().encode(archive)!;
    final decodedWorkbook = decodeExcelWorkbook(absoluteTargetWorkbook);

    expect(decodedWorkbook.tables, contains('Sheet1'));
  });

  test('extracts numeric and text student IDs below the labeled header', () {
    final workbook = Excel.createExcel();
    final sheet = workbook.tables['Sheet1']!;
    sheet.appendRow([TextCellValue('Danh sách sinh viên')]);
    sheet.appendRow([TextCellValue('Họ tên'), TextCellValue('MSSV')]);
    sheet.appendRow([TextCellValue('Nguyễn An'), const IntCellValue(123456)]);
    sheet.appendRow([TextCellValue('Trần Bình'), TextCellValue('001234')]);
    sheet.appendRow([TextCellValue('Nguyễn An'), const IntCellValue(123456)]);

    final result = extractStudentIdsFromWorkbook(workbook);

    expect(result.studentIds, ['123456', '001234']);
    expect(result.duplicateRows, 1);
  });
}
