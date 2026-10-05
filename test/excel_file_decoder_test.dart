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
}
