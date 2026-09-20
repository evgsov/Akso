import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/data/services/excel_export_service.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/report_template.dart';

void main() {
  group('ExcelExportService tests', () {
    late PipingNetwork network;

    setUp(() {
      network = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      network.addSegment(PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 100, systemId: '002-ТТ'));
      network.addWeldJoint(segmentId: 's1', ratio: 0.5, stamp: 'А1');
      network.recalculateSpools();
    });

    test('generateExcelBytes produces valid .xlsx for Transneft template', () {
      final template = ReportTemplate.defaultWeldJournalTransneftTemplate;
      final bytes = ExcelExportService.generateExcelBytes(template, network);

      expect(bytes, isNotNull);
      expect(bytes.isNotEmpty, true);

      // Verify that the bytes can be read back by Excel
      final decoded = Excel.decodeBytes(bytes);
      expect(decoded.tables.keys.isNotEmpty, true);

      final sheetName = decoded.tables.keys.first;
      final sheet = decoded.tables[sheetName]!;

      // Since Transneft has group headers, row 0 is group headers, row 1 is column headers, row 2 is data
      expect(sheet.maxRows, greaterThanOrEqualTo(3));

      // Row 1 should have 'Номер стыка'
      final row1Cells = sheet.row(1).map((c) => c?.value?.toString() ?? '').toList();
      expect(row1Cells.any((v) => v.contains('Номер стыка')), true);
      expect(row1Cells.any((v) => v.contains('Тип соединения')), true);

      // Row 2 should contain data for weld joint 'А1'
      final row2Cells = sheet.row(2).map((c) => c?.value?.toString() ?? '').toList();
      expect(row2Cells.any((v) => v.contains('А1')), true);
    });

    test('generateExcelBytes produces valid .xlsx for MTO specification', () {
      final template = ReportTemplate.defaultMtoGostTemplate;
      final bytes = ExcelExportService.generateExcelBytes(template, network);

      expect(bytes.isNotEmpty, true);
      final decoded = Excel.decodeBytes(bytes);
      final sheet = decoded.tables.values.first;

      // Single row header (row 0), data in row 1+
      expect(sheet.maxRows, greaterThanOrEqualTo(2));
      final row0Cells = sheet.row(0).map((c) => c?.value?.toString() ?? '').toList();
      expect(row0Cells.any((v) => v.contains('Наименование')), true);
    });

    test('generateCsvString produces valid semicolon-separated output', () {
      final template = ReportTemplate.defaultWeldJournalGostTemplate;
      final csv = ExcelExportService.generateCsvString(template, network);

      expect(csv.isNotEmpty, true);
      final lines = csv.trim().split('\n');
      expect(lines.length, greaterThanOrEqualTo(2)); // header + at least 1 data row
      expect(lines[0].contains(';'), true);
      expect(lines[0].contains('Номер стыка'), true);
      expect(lines[1].contains('А1'), true);
    });
  });
}
