import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:attendance_and_event_management/core/utils/attendance_report_export.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exports one row per student with attendance counts', () {
    final bytes = buildAttendanceReportWorkbook(
      className: 'Lập trình ứng dụng',
      sessionCount: 14,
      students: [
        {
          'studentId': 'SV001',
          'studentName': 'Nguyễn An',
          'totalSessions': 14,
          'present': 8,
          'late': 2,
          'absent': 3,
          'excused': 1,
        },
      ],
    );
    final workbook = Excel.decodeBytes(bytes);
    expect(workbook.tables.keys, ['Danh sach sinh vien']);
    final rows = workbook.tables['Danh sach sinh vien']!.rows;

    expect(rows, hasLength(5));
    expect(rows[0][0]?.value, TextCellValue('BÁO CÁO ĐIỂM DANH'));
    expect(rows[1][0]?.value, TextCellValue('Lớp học phần'));
    expect(rows[1][1]?.value, TextCellValue('Lập trình ứng dụng'));
    expect(rows[2][1]?.value, const IntCellValue(14));
    expect(rows[3][0]?.value, TextCellValue('STT'));
    expect(rows[4][1]?.value, TextCellValue('SV001'));
    expect(rows[4][2]?.value, TextCellValue('Nguyễn An'));
    expect(rows[4][3]?.value, const IntCellValue(14));
    expect(rows[4][4]?.value, const IntCellValue(8));
    expect(rows[4][5]?.value, const IntCellValue(2));
    expect(rows[4][6]?.value, const IntCellValue(3));
    expect(rows[4][7]?.value, const IntCellValue(1));
  });

  test('keeps worksheet elements in Excel-compatible order', () {
    final bytes = buildAttendanceReportWorkbook(
      className: 'Lập trình ứng dụng',
      sessionCount: 14,
      students: const [],
    );
    final archive = ZipDecoder().decodeBytes(bytes);
    final worksheet = archive.findFile('xl/worksheets/sheet1.xml');

    expect(worksheet, isNotNull);
    final xml = utf8.decode(worksheet!.content as List<int>);
    expect(xml, isNot(contains('<sheetFormatPr')));
    expect(
      xml.indexOf('<dimension'),
      lessThan(xml.indexOf('<sheetViews>')),
    );
    expect(
      xml.indexOf('<sheetViews>'),
      lessThan(xml.indexOf('<cols>')),
    );
    expect(
      xml.indexOf('<cols>'),
      lessThan(xml.indexOf('<sheetData>')),
    );
  });
}
