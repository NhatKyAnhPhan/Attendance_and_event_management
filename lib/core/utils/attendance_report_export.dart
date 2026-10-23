import 'package:excel/excel.dart';

List<int> buildAttendanceReportWorkbook({
  required int total,
  required int present,
  required int late,
  required int absent,
  required int excused,
  required List<Map<String, dynamic>> dailyItems,
}) {
  final workbook = Excel.createExcel();
  workbook.rename('Sheet1', 'Tong quan');

  final summary = workbook['Tong quan'];
  summary.appendRow([
    TextCellValue('Chỉ số tổng hợp toàn kỳ'),
    TextCellValue('Số lượt'),
  ]);
  summary.appendRow([TextCellValue('Tổng kết quả'), IntCellValue(total)]);
  summary.appendRow([TextCellValue('Có mặt'), IntCellValue(present)]);
  summary.appendRow([TextCellValue('Đi muộn'), IntCellValue(late)]);
  summary.appendRow([TextCellValue('Vắng mặt'), IntCellValue(absent)]);
  summary.appendRow([TextCellValue('Vắng có phép'), IntCellValue(excused)]);
  summary.appendRow([
    TextCellValue('Phạm vi'),
    TextCellValue(
      'Tổng quan toàn kỳ; chi tiết theo ngày trong 7 ngày gần nhất.',
    ),
  ]);

  final daily = workbook['Chi tiet theo ngay'];
  daily.appendRow([
    TextCellValue('Ngày'),
    TextCellValue('Có mặt'),
    TextCellValue('Đi muộn'),
    TextCellValue('Vắng mặt'),
    TextCellValue('Vắng có phép'),
  ]);
  for (final item in dailyItems) {
    daily.appendRow([
      TextCellValue(item['date']?.toString() ?? ''),
      IntCellValue(_reportCount(item['present'])),
      IntCellValue(_reportCount(item['late'])),
      IntCellValue(_reportCount(item['absent'])),
      IntCellValue(_reportCount(item['excused'])),
    ]);
  }

  final bytes = workbook.encode();
  if (bytes == null || bytes.isEmpty) {
    throw StateError('Không thể tạo file Excel báo cáo điểm danh.');
  }
  return bytes;
}

int _reportCount(Object? value) => int.tryParse(value?.toString() ?? '') ?? 0;
