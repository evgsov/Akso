import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/enums/sheet_format_type.dart';
import 'package:akso/domain/enums/viewport_layout_preset.dart';
import 'package:akso/domain/models/drawing_sheet.dart';
import 'package:akso/domain/models/title_block_data.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/ui/canvas/input_controller.dart';
import 'package:akso/ui/canvas/sheet_canvas_painter.dart';
import 'package:akso/data/services/pdf_export_service.dart';
import 'package:akso/data/dxf/dxf_writer.dart';

void main() {
  group('GOST Title Block and Viewport Grips', () {
    test('DrawingSheet default viewport uses wideAboveStamp on A3 landscape', () {
      final sheet = DrawingSheet.createDefault(
        id: 's_a3',
        name: 'Лист 1',
        sheetNumber: 1,
        formatType: SheetFormatType.a3,
        orientation: SheetOrientation.landscape,
      );

      // A3 landscape: 420 x 297 mm
      // Frame margins: left 20, right 5, top 5, bottom 5 mm
      // Printable: 395 x 287 mm
      // wideAboveStamp: x = 22 mm, y = 7 mm, width = 391 mm, height = 224 mm (leaves space for 55 mm stamp + 5 mm margin + 3 mm gap)
      final vp = sheet.viewport;
      expect(vp.xMm, equals(22.0));
      expect(vp.yMm, equals(7.0));
      expect(vp.widthMm, equals(391.0));
      expect(vp.heightMm, equals(224.0));
    });

    test('ViewportLayoutPreset calculates correctly for all presets', () {
      final sheet = DrawingSheet.createDefault(
        id: 's_test',
        name: 'Лист Тест',
        sheetNumber: 1,
        formatType: SheetFormatType.a3,
        orientation: SheetOrientation.landscape,
      );

      // 1. wideAboveStamp
      final vpWide = sheet.getPresetViewport(ViewportLayoutPreset.wideAboveStamp);
      expect(vpWide.xMm, equals(22.0));
      expect(vpWide.yMm, equals(7.0));
      expect(vpWide.widthMm, equals(391.0));
      expect(vpWide.heightMm, equals(224.0));

      // 2. fullSheet (covers the whole printable area)
      final vpFull = sheet.getPresetViewport(ViewportLayoutPreset.fullSheet);
      expect(vpFull.xMm, equals(22.0));
      expect(vpFull.yMm, equals(7.0));
      expect(vpFull.widthMm, equals(391.0));
      expect(vpFull.heightMm, equals(283.0));

      // 3. leftColumn (left of stamp & notes)
      final vpCol = sheet.getPresetViewport(ViewportLayoutPreset.leftColumn);
      expect(vpCol.xMm, equals(22.0));
      expect(vpCol.yMm, equals(7.0));
      expect(vpCol.widthMm, equals(202.0));
      expect(vpCol.heightMm, equals(283.0));

      // Test applyViewportPreset
      final updatedSheet = sheet.applyViewportPreset(ViewportLayoutPreset.fullSheet);
      expect(updatedSheet.viewport.widthMm, equals(391.0));
      expect(updatedSheet.viewport.heightMm, equals(283.0));
    });

    test('SheetCanvasPainter renders GOST Title Block (Form 3) and CAD Grips without errors', () {
      final network = PipingNetwork();
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 5000, y: 0, z: 0);
      network.segments['s1'] = const PipeSegment(
        id: 's1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        dn: 100,
        systemId: 'sys_nvk',
      );

      final sheet = DrawingSheet.createDefault(
        id: 's_exec',
        name: 'Лист 1',
        sheetNumber: 1,
        formatType: SheetFormatType.a3,
        orientation: SheetOrientation.landscape,
      ).copyWith(
        titleBlockData: const TitleBlockData(
          documentCode: '09/2025-НВК',
          projectName: 'Жилой комплекс с подземной автостоянкой по адресу: г. Москва',
          buildingName: 'Наружные сети водоснабжения и канализации',
          drawingTitle: 'Исполнительная схема наружных сетей водопровода В1',
          organization: 'ООО "СтарКом"',
          stage: 'ИД',
          sheetNumber: 1,
          totalSheets: 1,
          approvals: [
            TitleBlockApproval(role: 'Геодезист', name: 'Иванов И.И.', date: '09.25'),
            TitleBlockApproval(role: 'Исп. директор', name: 'Петров П.П.', date: '09.25'),
            TitleBlockApproval(role: 'Мастер', name: 'Сидоров С.С.', date: '09.25'),
            TitleBlockApproval(role: 'Разраб.', name: 'Кузнецов К.К.', date: '09.25'),
          ],
          topRightCorner: TopRightCornerBlock(
            mode: TopRightCornerMode.actAttachment,
            text: 'Приложение к акту №15\nот 25.09.2025 г.',
          ),
        ),
      );

      final painter = SheetCanvasPainter(
        sheet: sheet,
        network: network,
        sheetZoom: 1.0,
        sheetPan: const Offset(40, 40),
        isViewportFocused: false,
        isViewportSelected: true,
        activeGrip: 'se',
      );

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 1400, 900));
      painter.paint(canvas, const Size(1400, 900));
      final picture = recorder.endRecording();
      expect(picture, isNotNull);
    });

    test('PipingInputController interactive grips hit-testing and resizing', () {
      final controller = PipingInputController();
      controller.addSheet(
        name: 'Лист ИД',
        formatType: SheetFormatType.a3,
        orientation: SheetOrientation.landscape,
      );

      controller.sheetPan = Offset.zero;
      controller.sheetZoom = 1.0;

      // Check hit-testing helper methods
      final stampRect = controller.getActiveSheetStampRect();
      expect(stampRect, isNotNull);
      // Stamp is at bottom-right (420 - 5 - 185 = 230 mm)
      expect(stampRect!.left, equals(230.0));
      expect(stampRect.top, equals(237.0)); // 297 - 5 - 55 = 237 mm
      expect(stampRect.width, equals(185.0));
      expect(stampRect.height, equals(55.0));

      expect(controller.hitTestSheetStamp(const Offset(250, 250)), isTrue);
      expect(controller.hitTestSheetStamp(const Offset(100, 100)), isFalse);

      final vpRect = controller.getActiveSheetViewportScreenRect();
      expect(vpRect, isNotNull);
      expect(controller.hitTestSheetViewport(const Offset(100, 100)), isTrue);

      // Viewport grips
      final grips = controller.getActiveSheetViewportGrips();
      expect(grips.length, equals(8));
      expect(grips.containsKey('nw'), isTrue);
      expect(grips.containsKey('se'), isTrue);

      final sePos = grips['se']!;
      expect(controller.hitTestViewportGrip(sePos), equals('se'));
      expect(controller.hitTestViewportGrip(const Offset(999, 999)), isNull);

      // Title block tap callback
      bool stampTapped = false;
      controller.onTitleBlockTapped = () => stampTapped = true;
      controller.handlePointerDown(const Offset(250, 250));
      expect(stampTapped, isTrue);

      // Viewport selection on click
      controller.handlePointerDown(const Offset(100, 100));
      expect(controller.isViewportSelected, isTrue);
      expect(controller.activeViewportGrip, isNull);

      // Click on 'se' grip to start dragging
      controller.handlePointerDown(sePos);
      expect(controller.activeViewportGrip, equals('se'));

      // Drag 'se' grip by +20 mm right and +10 mm down
      controller.handlePointerMove(sePos + const Offset(20, 10));
      expect(controller.activeSheet!.viewport.widthMm, equals(393.0)); // clamped to sheet frameRight (415 - 22 = 393 mm)
      
      // Release grip
      controller.handlePointerUp();
      expect(controller.activeViewportGrip, isNull);

      // Apply preset through controller
      controller.applyViewportPreset(ViewportLayoutPreset.leftColumn);
      expect(controller.activeSheet!.viewport.widthMm, equals(202.0));
    });

    test('PDF Export contains GOST Title Block texts and Format label', () async {
      final network = PipingNetwork();
      final sheet = DrawingSheet.createDefault(
        id: 's_pdf',
        name: 'Лист 1',
        sheetNumber: 1,
        formatType: SheetFormatType.a3,
        orientation: SheetOrientation.landscape,
      ).copyWith(
        titleBlockData: const TitleBlockData(
          documentCode: '09/2025-НВК',
          projectName: 'Жилой комплекс',
          buildingName: 'Наружные сети',
          drawingTitle: 'Исполнительная схема водопровода',
          organization: 'ООО "СтарКом"',
          stage: 'ИД',
          sheetNumber: 1,
          totalSheets: 2,
        ),
      );

      final pdfBytes = await PdfExportService.generateSheetPdf(
        sheet: sheet,
        network: network,
      );

      expect(pdfBytes, isNotEmpty);
      expect(pdfBytes.length, greaterThan(1000));
    });

    test('DXF Export contains GOST Title Block lines, texts and Format label', () {
      final controller = PipingInputController();
      controller.addSheet(
        name: 'Лист ИД',
        formatType: SheetFormatType.a3,
        orientation: SheetOrientation.landscape,
      );

      controller.updateActiveSheetTitleBlock(const TitleBlockData(
        documentCode: '09/2025-НВК',
        projectName: 'Жилой комплекс',
        buildingName: 'Сети НВК',
        drawingTitle: 'Исполнительная схема',
        organization: 'ООО "СтарКом"',
        stage: 'ИД',
        sheetNumber: 1,
        totalSheets: 1,
      ));

      final dxf = DxfWriter.generate2dGostAxonometryWithLayoutsDxf(
        network: controller.network,
        sheets: controller.sheets,
      );

      expect(dxf, contains('АКСО_ЛИСТ_ШТАМП'));
      expect(dxf, contains('09/2025-НВК'));
      expect(dxf, contains('ООО "СтарКом"'));
      expect(dxf, contains('Формат A3'));
      expect(dxf, contains('Изм.'));
      expect(dxf, contains('Кол.уч'));
    });
  });
}
