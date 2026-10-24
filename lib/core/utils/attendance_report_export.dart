import 'package:excel/excel.dart';

const _tableHeaders = [
  'STT',
  'Mã sinh viên',
  'Họ và tên',
  'Tổng số buổi',
  'Có mặt',
  'Đi muộn',
  'Vắng',
  'Vắng có phép',
];

List<int> buildAttendanceReportWorkbook({
  required String className,
  required int sessionCount,
  required List<Map<String, dynamic>> students,
}) {
  final workbook = Excel.createExcel();
  workbook.rename('Sheet1', 'Danh sach sinh vien');

  final sheet = workbook['Danh sach sinh vien'];
  for (final entry in const <int, double>{
    0: 8,
    1: 18,
    2: 32,
    3: 17,
    4: 13,
    5: 13,
    6: 13,
    7: 18,
  }.entries) {
    sheet.setColumnWidth(entry.key, entry.value);
  }

  sheet.appendRow([
    TextCellValue('BÁO CÁO ĐIỂM DANH'),
  ]);
  sheet.appendRow([
    TextCellValue('Lớp học phần'),
    TextCellValue(className),
  ]);
  sheet.appendRow([
    TextCellValue('Số buổi điểm danh'),
    IntCellValue(sessionCount),
  ]);
  sheet.appendRow(_tableHeaders.map(TextCellValue.new).toList());
  for (var index = 0; index < students.length; index++) {
    final student = students[index];
    sheet.appendRow([
      IntCellValue(index + 1),
      TextCellValue(student['studentId']?.toString() ?? ''),
      TextCellValue(student['studentName']?.toString() ?? ''),
      IntCellValue(_reportCount(student['totalSessions'])),
      IntCellValue(_reportCount(student['present'])),
      IntCellValue(_reportCount(student['late'])),
      IntCellValue(_reportCount(student['absent'])),
      IntCellValue(_reportCount(student['excused'])),
    ]);
  }

  sheet.merge(
    CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
    CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: 0),
    customValue: TextCellValue('BÁO CÁO ĐIỂM DANH'),
  );
  sheet.merge(
    CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1),
    CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: 1),
    customValue: TextCellValue(className),
  );

  final border = Border(
    borderStyle: BorderStyle.Thin,
    borderColorHex: ExcelColor.blueGrey100,
  );
  final titleStyle = CellStyle(
    backgroundColorHex: ExcelColor.blue900,
    fontColorHex: ExcelColor.white,
    fontSize: 18,
    bold: true,
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
  );
  final metadataLabelStyle = CellStyle(
    backgroundColorHex: ExcelColor.blue50,
    fontColorHex: ExcelColor.blue900,
    bold: true,
    verticalAlign: VerticalAlign.Center,
    leftBorder: border,
    rightBorder: border,
    topBorder: border,
    bottomBorder: border,
  );
  final metadataValueStyle = CellStyle(
    fontColorHex: ExcelColor.grey900,
    verticalAlign: VerticalAlign.Center,
    leftBorder: border,
    rightBorder: border,
    topBorder: border,
    bottomBorder: border,
  );
  final headerStyle = CellStyle(
    backgroundColorHex: ExcelColor.blue700,
    fontColorHex: ExcelColor.white,
    fontSize: 11,
    bold: true,
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
    textWrapping: TextWrapping.WrapText,
    leftBorder: border,
    rightBorder: border,
    topBorder: border,
    bottomBorder: border,
  );
  final textCellStyle = CellStyle(
    fontColorHex: ExcelColor.grey900,
    verticalAlign: VerticalAlign.Center,
    leftBorder: border,
    rightBorder: border,
    topBorder: border,
    bottomBorder: border,
  );
  final centeredCellStyle = CellStyle(
    fontColorHex: ExcelColor.grey900,
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
    leftBorder: border,
    rightBorder: border,
    topBorder: border,
    bottomBorder: border,
  );
  final presentCellStyle = _statusCellStyle(ExcelColor.green50, ExcelColor.green800, border);
  final lateCellStyle = _statusCellStyle(ExcelColor.amber50, ExcelColor.amber800, border);
  final absentCellStyle = _statusCellStyle(ExcelColor.red50, ExcelColor.red800, border);
  final excusedCellStyle = _statusCellStyle(ExcelColor.blue50, ExcelColor.blue800, border);

  sheet.setRowHeight(0, 36);
  sheet.setRowHeight(1, 27);
  sheet.setRowHeight(2, 25);
  sheet.setRowHeight(3, 34);
  for (var column = 0; column < _tableHeaders.length; column++) {
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 0))
        .cellStyle = titleStyle;
  }
  for (final rowIndex in [1, 2]) {
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex))
        .cellStyle = metadataLabelStyle;
    for (var column = 1; column < _tableHeaders.length; column++) {
      sheet
          .cell(
            CellIndex.indexByColumnRow(
              columnIndex: column,
              rowIndex: rowIndex,
            ),
          )
          .cellStyle = metadataValueStyle;
    }
  }
  for (var column = 0; column < _tableHeaders.length; column++) {
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 3))
        .cellStyle = headerStyle;
  }
  for (var rowIndex = 4; rowIndex < students.length + 4; rowIndex++) {
    final isAlternate = rowIndex.isOdd;
    sheet.setRowHeight(rowIndex, 24);
    for (var column = 0; column < _tableHeaders.length; column++) {
      final style = switch (column) {
        4 => presentCellStyle,
        5 => lateCellStyle,
        6 => absentCellStyle,
        7 => excusedCellStyle,
        0 || 3 => centeredCellStyle,
        _ => textCellStyle,
      };
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: column, rowIndex: rowIndex),
      );
      cell.cellStyle = isAlternate
          ? style.copyWith(
              backgroundColorHexVal: ExcelColor.grey100,
            )
          : style;
    }
  }
  final bytes = workbook.encode();
  if (bytes == null || bytes.isEmpty) {
    throw StateError('Không thể tạo file Excel báo cáo điểm danh.');
  }
  return bytes;
}

CellStyle _statusCellStyle(
  ExcelColor backgroundColor,
  ExcelColor fontColor,
  Border border,
) {
  return CellStyle(
    backgroundColorHex: backgroundColor,
    fontColorHex: fontColor,
    bold: true,
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
    leftBorder: border,
    rightBorder: border,
    topBorder: border,
    bottomBorder: border,
  );
}

int _reportCount(Object? value) => int.tryParse(value?.toString() ?? '') ?? 0;
