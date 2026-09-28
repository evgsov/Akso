import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/drawing_legend.dart';
import 'package:akso/domain/models/drawing_sheet.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/enums/sheet_format_type.dart';
import 'package:akso/domain/models/sheet_format.dart';
import 'package:akso/data/services/pdf_export_service.dart';

void main() {
  group('PdfExportService', () {
    test('generates valid PDF bytes with A3 dimensions and %PDF header', () async {
      final sheet = DrawingSheet.createDefault(id: 's1', name: 'Лист 1: В1', sheetNumber: 1);
      final network = PipingNetwork();
      final bytes = await PdfExportService.generateSheetPdf(sheet: sheet, network: network);
      expect(bytes, isNotEmpty);
      expect(bytes.sublist(0, 4), equals([0x25, 0x50, 0x44, 0x46])); // %PDF
    });

    test('generates PDF for A4 portrait sheet with network content, callouts, and legend', () async {
      final network = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      network.nodes[n1.id] = n1;
      network.nodes[n2.id] = n2;
      final seg = PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 50, systemId: 'sys_1');
      network.segments[seg.id] = seg;
      network.callouts['c1'] = Callout(
        id: 'c1',
        targetType: CalloutTargetType.segment,
        targetId: 's1',
        customText: 'Труба 57х3.5',
        customBottomText: 'L=2.0 м',
        shelfDirection: ShelfDirection.left,
      );
      network.callouts['c2'] = Callout(
        id: 'c2',
        targetType: CalloutTargetType.node,
        targetId: 'n1',
        arrowOnNode: true,
        shelfDirection: ShelfDirection.right,
      );

      final sheet = DrawingSheet.createDefault(id: 's2', name: 'Лист 2: А4', sheetNumber: 2).copyWith(
        format: const SheetFormat(type: SheetFormatType.a4, orientation: SheetOrientation.portrait),
        technicalRequirements: const TechnicalRequirements(
          text: '1. Сварные швы по ГОСТ 16037-80.\n2. Испытать давлением Рисп = 1.25 Рраб.',
        ),
        legend: const DrawingLegend(
          isVisible: true,
          xMm: 20,
          yMm: 20,
          items: [
            LegendItem(id: 'l1', type: LegendItemType.dimension, label: 'Длина трубы'),
            LegendItem(id: 'l2', type: LegendItemType.elevation, label: 'Отметка уровня'),
          ],
        ),
      );

      final bytes = await PdfExportService.generateSheetPdf(sheet: sheet, network: network);
      expect(bytes, isNotEmpty);
      expect(bytes.sublist(0, 4), equals([0x25, 0x50, 0x44, 0x46]));
    });
  });
}

