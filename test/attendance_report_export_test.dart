import 'package:attendance_and_event_management/core/utils/attendance_report_export.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exports summary and daily attendance rows to separate sheets', () {
    final bytes = buildAttendanceReportWorkbook(
      total: 12,
      present: 8,
      late: 2,
      absent: 2,
      excused: 1,
      dailyItems: [
        {
          'date': '2026-10-22',
          'present': 3,
          'late': 1,
          'absent': 0,
          'excused': 1,
        },
      ],
    );

    final workbook = Excel.decodeBytes(bytes);
    final summary = workbook.tables['Tong quan']!;
    final daily = workbook.tables['Chi tiet theo ngay']!;

    expect(summary.rows, hasLength(7));
    expect(
      summary.rows[1][0]?.value,
      isA<TextCellValue>().having(
        (cell) => cell.value.toString(),
        'value',
        'Tổng kết quả',
      ),
    );
    expect(summary.rows[1][1]?.value, const IntCellValue(12));
    expect(summary.rows[2][1]?.value, const IntCellValue(8));
    expect(summary.rows[3][1]?.value, const IntCellValue(2));
    expect(summary.rows[4][1]?.value, const IntCellValue(2));
    expect(summary.rows[5][1]?.value, const IntCellValue(1));
    expect(
      summary.rows[6][1]?.value,
      isA<TextCellValue>().having(
        (cell) => cell.value.toString(),
        'scope',
        contains('7 ngày gần nhất'),
      ),
    );
    expect(daily.rows, hasLength(2));
    expect(
      daily.rows[1][0]?.value,
      isA<TextCellValue>().having(
        (cell) => cell.value.toString(),
        'value',
        '2026-10-22',
      ),
    );
    expect(daily.rows[1][1]?.value, const IntCellValue(3));
    expect(daily.rows[1][4]?.value, const IntCellValue(1));
  });
}
