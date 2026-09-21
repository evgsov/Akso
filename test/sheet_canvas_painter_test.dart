import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/enums/sheet_format_type.dart';
import 'package:akso/domain/models/drawing_sheet.dart';
import 'package:akso/domain/models/title_block_data.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/drawing_legend.dart';
import 'package:akso/domain/models/linear_dimension.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/ui/canvas/input_controller.dart';
import 'package:akso/ui/canvas/sheet_canvas_painter.dart';

void main() {
  group('SheetCanvasPainter', () {
    test('renders sheet paper, margins, title block, and clipped viewport without throwing', () {
      final network = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      network.nodes[n1.id] = n1;
      network.nodes[n2.id] = n2;
      network.segments['s1'] = PipeSegment(
        id: 's1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        dn: 50,
        systemId: 'sys_b1',
      );

      final sheet = DrawingSheet.createDefault(
        id: 's1',
        name: 'Лист 1: В1',
        sheetNumber: 1,
        formatType: SheetFormatType.a3,
        orientation: SheetOrientation.landscape,
      ).copyWith(
        titleBlockData: const TitleBlockData(
          projectName: 'КС Южная',
          buildingName: 'Цех очистки газа',
          drawingTitle: 'Схема технологических трубопроводов В1',
          documentCode: '04-2026-ТХ.ИС',
          organization: 'ООО НефтеГазМонтаж',
          stage: 'И',
          sheetNumber: 1,
          totalSheets: 1,
          topRightCorner: TopRightCornerBlock(
            mode: TopRightCornerMode.actAttachment,
            text: 'Приложение №1 к Акту освидетельствования скрытых работ №42',
          ),
        ),
        technicalRequirements: const TechnicalRequirements(
          text: '1. Сварка по ГОСТ 16037-80.\n2. Гидравлическое испытание давлением 1.6 МПа.',
          xMm: 230.0,
          yMm: 180.0,
          widthMm: 185.0,
        ),
      );

      final painter = SheetCanvasPainter(
        sheet: sheet,
        network: network,
        sheetZoom: 1.5, // 1.5 px per mm
        sheetPan: const Offset(50, 50),
        isViewportFocused: false,
      );

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 1200, 900));
      painter.paint(canvas, const Size(1200, 900));
      final picture = recorder.endRecording();

      expect(picture, isNotNull);
    });

    test('highlights viewport when isViewportFocused is true', () {
      final sheet = DrawingSheet.createDefault(id: 's2', name: 'Лист 2', sheetNumber: 2);
      final network = PipingNetwork();
      final painter = SheetCanvasPainter(
        sheet: sheet,
        network: network,
        sheetZoom: 1.0,
        sheetPan: Offset.zero,
        isViewportFocused: true,
      );

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 1000, 800));
      expect(() => painter.paint(canvas, const Size(1000, 800)), returnsNormally);
      recorder.endRecording();
    });

    test('renders callouts, dimensions, legend, and active block grips without throwing', () {
      final network = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      network.nodes[n1.id] = n1;
      network.nodes[n2.id] = n2;
      network.segments['s1'] = PipeSegment(
        id: 's1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        dn: 50,
        systemId: 'sys_b1',
      );
      network.callouts['c1'] = const Callout(
        id: 'c1',
        targetId: 's1',
        targetType: CalloutTargetType.segment,
        customText: 'В1 ⌀57х3.5',
      );
      network.dimensions['d1'] = LinearDimension(
        id: 'd1',
        startPoint: n1,
        endPoint: n2,
      );

      final sheet = DrawingSheet.createDefault(id: 's3', name: 'Лист 3', sheetNumber: 3).copyWith(
        legend: DrawingLegend.createDefault(),
        technicalRequirements: const TechnicalRequirements(text: '1. ТТ тест.'),
      );

      for (final block in ['viewport', 'notes', 'act', 'legend']) {
        final painter = SheetCanvasPainter(
          sheet: sheet,
          network: network,
          sheetZoom: 1.0,
          sheetPan: Offset.zero,
          isViewportFocused: false,
          selectedSheetBlock: block,
        );

        final recorder = PictureRecorder();
        final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 1000, 800));
        expect(() => painter.paint(canvas, const Size(1000, 800)), returnsNormally);
        recorder.endRecording();
      }
    });

    test('PipingInputController manages sheets, viewport focus, and auto-fit', () {
      final controller = PipingInputController();
      expect(controller.isModelSpaceActive, isTrue);
      expect(controller.sheets, isEmpty);

      // Add a sheet
      final sheet1 = controller.addSheet(name: 'Лист 1: В1');
      expect(controller.sheets.length, equals(1));
      expect(controller.activeSheetId, equals(sheet1.id));
      expect(controller.isModelSpaceActive, isFalse);
      expect(controller.activeSheet?.name, equals('Лист 1: В1'));

      // Add second sheet
      final sheet2 = controller.addSheet(name: 'Лист 2: Т3');
      expect(controller.sheets.length, equals(2));
      expect(controller.activeSheetId, equals(sheet2.id));

      // Switch back to sheet 1
      controller.selectSheet(sheet1.id);
      expect(controller.activeSheetId, equals(sheet1.id));

      // Viewport focus toggle
      expect(controller.isViewportFocused, isFalse);
      controller.toggleViewportFocus();
      expect(controller.isViewportFocused, isTrue);

      // Panning and zooming in focused viewport
      final prevScale = controller.activeSheet!.viewport.viewScale;
      controller.zoom(1.5, const Offset(100, 100));
      expect(controller.activeSheet!.viewport.viewScale, greaterThan(prevScale));

      // Unfocus and test sheet pan / zoom
      controller.toggleViewportFocus();
      expect(controller.isViewportFocused, isFalse);
      final prevSheetZoom = controller.sheetZoom;
      controller.zoom(1.2, const Offset(200, 200));
      expect(controller.sheetZoom, greaterThan(prevSheetZoom));

      // Auto-fit active sheet viewport
      controller.network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      controller.network.nodes['n2'] = const Node3D(id: 'n2', x: 3000, y: 0, z: 0);
      controller.network.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 50, systemId: 'sys_b1');
      controller.autoFitActiveSheetViewport();
      expect(controller.activeSheet!.viewport.viewScale, greaterThan(0.0));

      // Switch to model space
      controller.selectModelSpace();
      expect(controller.isModelSpaceActive, isTrue);
      expect(controller.activeSheetId, isNull);

      // Remove sheet
      controller.removeSheet(sheet1.id);
      expect(controller.sheets.length, equals(1));
      expect(controller.sheets.first.id, equals(sheet2.id));
    });
  });
}
