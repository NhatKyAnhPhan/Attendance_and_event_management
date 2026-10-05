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
