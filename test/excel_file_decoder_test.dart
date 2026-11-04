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

  test('groups roster rows by their event or class code', () {
    final workbook = Excel.createExcel();
    final sheet = workbook.tables['Sheet1']!;
    sheet.appendRow([
      TextCellValue('MSSV'),
      TextCellValue('TenLop'),
      TextCellValue('MaLop'),
    ]);
    sheet.appendRow([
      TextCellValue('001234'),
      TextCellValue('Lập trình Web'),
      const IntCellValue(20260910),
    ]);
    sheet.appendRow([
      TextCellValue('001234'),
      TextCellValue('Lập trình Web'),
      const IntCellValue(20260910),
    ]);
    sheet.appendRow([
      TextCellValue('005678'),
      TextCellValue('Thực hành Lập trình Web'),
      const IntCellValue(20260911),
    ]);

    final groups = extractStudentRosterGroups(
      workbook,
      targetIdHeaders: const {'MaLop'},
      targetNameHeaders: const {'TenLop'},
    );

    expect(groups, hasLength(2));
    expect(groups[0].targetId, '20260910');
    expect(groups[0].targetName, 'Lập trình Web');
    expect(groups[0].studentIds, ['001234']);
    expect(groups[0].duplicateRows, 1);
    expect(groups[1].studentIds, ['005678']);
  });

  test('extracts event rows including Excel date and time cells', () {
    final workbook = Excel.createExcel();
    final sheet = workbook.tables['Sheet1']!;
    sheet.appendRow([
      TextCellValue('MaSuKien'),
      TextCellValue('TenSuKien'),
      TextCellValue('DonViToChuc'),
      TextCellValue('DiaDiem'),
      TextCellValue('NgayToChuc'),
      TextCellValue('GioBatDau'),
      TextCellValue('GioKetThuc'),
      TextCellValue('MoTa'),
    ]);
    sheet.appendRow([
      TextCellValue('SK2026004'),
      TextCellValue('FAIR 2026'),
      TextCellValue('Khoa Công nghệ thông tin'),
      TextCellValue('HUIT'),
      const DateCellValue(year: 2026, month: 10, day: 8),
      const TimeCellValue(hour: 8, minute: 30),
      const TimeCellValue(hour: 12),
      TextCellValue('Hội nghị khoa học.'),
    ]);
    sheet.appendRow([TextCellValue('SK2026005')]);

    final result = extractEventsFromWorkbook(workbook);

    expect(result.events, hasLength(1));
    expect(result.warnings, hasLength(1));
    expect(result.warnings.single, contains('tên sự kiện'));
    expect(result.events.single.sourceId, 'SK2026004');
    expect(result.events.single.name, 'FAIR 2026');
    expect(result.events.single.eventDate, DateTime(2026, 10, 8));
    expect(result.events.single.startMinutes, 510);
    expect(result.events.single.endMinutes, 720);
  });

  test('extracts units and user accounts from the named master-data sheets', () {
    final workbook = Excel.createExcel();
    workbook.rename('Sheet1', 'DonVi');
    workbook['DonVi'].appendRow([
      TextCellValue('MaDV'),
      TextCellValue('TenDV'),
      TextCellValue('MaNhanVienPhuTrach'),
    ]);
    workbook['DonVi'].appendRow([
      TextCellValue('DV01'),
      TextCellValue('Khoa Công nghệ thông tin'),
      TextCellValue('NV001'),
    ]);
    workbook['NguoiDung'].appendRow([
      TextCellValue('MaND'),
      TextCellValue('HoTen'),
      TextCellValue('Email'),
      TextCellValue('MatKhau'),
      TextCellValue('VaiTro'),
      TextCellValue('Lop'),
      TextCellValue('ChuyenNganh'),
    ]);
    workbook['NguoiDung'].appendRow([
      TextCellValue('SV001'),
      TextCellValue('Nguyễn An'),
      TextCellValue('an@example.com'),
      TextCellValue('password123'),
      TextCellValue('Sinh viên'),
      TextCellValue('12A'),
      TextCellValue('Công nghệ thông tin'),
    ]);

    final result = extractAdminMasterDataFromWorkbook(workbook);

    expect(result.units, hasLength(1));
    expect(result.units.single['id'], 'DV01');
    expect(result.units.single['managerId'], 'NV001');
    expect(result.users, hasLength(1));
    expect(result.users.single['id'], 'SV001');
    expect(result.users.single['className'], '12A');
    expect(result.warnings, isEmpty);
  });
}
