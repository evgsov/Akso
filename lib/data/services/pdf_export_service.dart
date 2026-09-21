import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/math/axonometry_projector.dart';
import '../../domain/enums/projection_type.dart';
import '../../domain/models/callout.dart';
import '../../domain/models/drawing_sheet.dart';
import '../../domain/models/drawing_style_config.dart';
import '../../domain/models/piping_network.dart';
import '../../domain/models/title_block_data.dart';
import '../../domain/services/viewport_transform_service.dart';
import '../../ui/canvas/painters/callout_painter.dart';

/// Сервис векторной генерации, сохранения и печати чертежей в формате PDF (1:1)
/// по стандартам ГОСТ 21.101-2020 / СПДС.
class PdfExportService {
  /// Генерирует векторный PDF-документ чертежного листа 1:1 со всеми графами штампа,
  /// рамкой 20-5-5-5 мм, техническими требованиями и геометрией трубопроводов.
  static Future<Uint8List> generateSheetPdf({
    required DrawingSheet sheet,
    required PipingNetwork network,
    DrawingStyleConfig styleConfig = const DrawingStyleConfig(),
    ProjectionType projectionType = ProjectionType.gostFrontal45,
  }) async {
    final pdf = pw.Document(
      title: sheet.name,
      author: sheet.titleBlockData.organization,
    );

    final fontRegular = await _loadFont(isBold: false);
    final fontBold = await _loadFont(isBold: true);

    final widthMm = sheet.format.widthMm;
    final heightMm = sheet.format.heightMm;
    const mm = PdfPageFormat.mm;

    final pageFormat = PdfPageFormat(
      widthMm * mm,
      heightMm * mm,
      marginAll: 0,
    );

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) {
          return pw.Stack(
            children: [
              // 1. Векторные линии видового экрана, выносок, размеров, рамки листа и штампа
              pw.CustomPaint(
                size: PdfPoint(pageFormat.width, pageFormat.height),
                painter: (canvas, size) {
                  _drawPdfNetworkInViewport(
                    canvas: canvas,
                    sheet: sheet,
                    network: network,
                    projectionType: projectionType,
                    styleConfig: styleConfig,
                    heightMm: heightMm,
                    mm: mm,
                  );
                  _drawPdfGostFrameAndStampGrid(canvas, sheet, styleConfig, mm);
                },
              ),

              // 2. Текстовые аннотации видового экрана (размерные числа, полки выносок)
              ..._buildViewportAnnotationTexts(
                sheet: sheet,
                network: network,
                projectionType: projectionType,
                fontRegular: fontRegular,
                fontBold: fontBold,
                heightMm: heightMm,
                mm: mm,
              ),

              // 3. Заголовок схемы в левом верхнем углу (как в исполнительных схемах)
              if (sheet.titleBlockData.drawingTitle.isNotEmpty)
                pw.Positioned(
                  left: (sheet.format.frameLeftMm + 5.0) * mm,
                  top: (sheet.format.frameTopMm + 2.5) * mm,
                  child: pw.Text(
                    sheet.titleBlockData.drawingTitle,
                    style: pw.TextStyle(font: fontBold, fontSize: 9.5),
                  ),
                ),

              // 4. Надпись формата листа под штампом за рамкой
              pw.Positioned(
                right: sheet.format.frameRightMm * mm,
                bottom: (sheet.format.frameBottomMm - 4.0) * mm,
                child: pw.Text(
                  'Формат ${sheet.format.type.name.toUpperCase()}',
                  style: pw.TextStyle(font: fontRegular, fontSize: 7),
                ),
              ),

              // 5. Текстовые поля штампа (Форма 3 по ГОСТ 21.101-2020 / СПДС)
              ..._buildTitleBlockTexts(
                sheet: sheet,
                fontRegular: fontRegular,
                fontBold: fontBold,
                mm: mm,
              ),

              // 6. Блок приложения к акту (настраиваемое положение и границы)
              ..._buildTopRightCornerBlock(
                sheet: sheet,
                fontRegular: fontRegular,
                mm: mm,
              ),

              // 7. Технические требования (ТТ) (настраиваемое положение и границы)
              if (sheet.technicalRequirements != null &&
                  sheet.technicalRequirements!.text.isNotEmpty)
                _buildTechnicalRequirements(
                  sheet: sheet,
                  fontRegular: fontRegular,
                  fontBold: fontBold,
                  mm: mm,
                ),

              // 8. Блок «Условные обозначения»
              if (sheet.legend != null && sheet.legend!.isVisible)
                _buildDrawingLegend(
                  sheet: sheet,
                  fontRegular: fontRegular,
                  fontBold: fontBold,
                  mm: mm,
                ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Отрисовка внешней рамки чертежа (ГОСТ 2.104) и сетки штампа (Форма 3 ГОСТ 21.101)
  static void _drawPdfGostFrameAndStampGrid(
    PdfGraphics canvas,
    DrawingSheet sheet,
    DrawingStyleConfig styleConfig,
    double mm,
  ) {
    final widthMm = sheet.format.widthMm;

    final frameLeftMm = sheet.format.frameLeftMm;
    final frameBottomMm = sheet.format.frameBottomMm;
    final printableWidthMm = sheet.format.printableWidthMm;
    final printableHeightMm = sheet.format.printableHeightMm;

    // Внешняя толстая рамка чертежа (20-5-5-5 мм)
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(styleConfig.frameLineWidthMm * mm);
    canvas.drawRect(
      frameLeftMm * mm,
      frameBottomMm * mm,
      printableWidthMm * mm,
      printableHeightMm * mm,
    );
    canvas.strokePath();

    // Штамп Форма 3 (185х55 мм) в правом нижнем углу
    final stampLeftMm = widthMm - sheet.format.frameRightMm - 185.0;
    final stampBottomMm = frameBottomMm;

    // Непрозрачная белая подложка штампа
    canvas.setFillColor(PdfColors.white);
    canvas.drawRect(stampLeftMm * mm, stampBottomMm * mm, 185.0 * mm, 55.0 * mm);
    canvas.fillPath();

    // Внешний контур штампа
    canvas.setLineWidth(styleConfig.stampBorderWidthMm * mm);
    canvas.drawRect(stampLeftMm * mm, stampBottomMm * mm, 185.0 * mm, 55.0 * mm);
    canvas.strokePath();

    // Основной вертикальный разделитель: 65 мм слева (блок согласований/изменений)
    final xApprovalsEndMm = stampLeftMm + 65.0;
    canvas.setLineWidth(styleConfig.stampBorderWidthMm * mm);
    canvas.drawLine(xApprovalsEndMm * mm, stampBottomMm * mm, xApprovalsEndMm * mm, (stampBottomMm + 55.0) * mm);
    canvas.strokePath();

    // --- ЛЕВЫЙ БЛОК (0..65 мм) ---
    // В эталонной Форме 3 (по ГОСТ 21.101 и образцу 09/2025-НВК):
    // y=0..15 мм сверху (stampBottomMm + 40..55) - 3 строки изменений
    // y=15..20 мм сверху (stampBottomMm + 35..40) - шапка таблицы изменений
    // y=20..55 мм сверху (stampBottomMm + 0..35) - 7 строк согласований по 5 мм
    canvas.setLineWidth(styleConfig.stampGridWidthMm * mm);

    // Горизонтальные линии строк изменений (y = stampBottomMm + 40, 45, 50)
    canvas.drawLine(stampLeftMm * mm, (stampBottomMm + 50.0) * mm, xApprovalsEndMm * mm, (stampBottomMm + 50.0) * mm);
    canvas.drawLine(stampLeftMm * mm, (stampBottomMm + 45.0) * mm, xApprovalsEndMm * mm, (stampBottomMm + 45.0) * mm);
    canvas.drawLine(stampLeftMm * mm, (stampBottomMm + 40.0) * mm, xApprovalsEndMm * mm, (stampBottomMm + 40.0) * mm);

    // Линия под шапкой таблицы изменений (y = stampBottomMm + 35)
    canvas.drawLine(stampLeftMm * mm, (stampBottomMm + 35.0) * mm, xApprovalsEndMm * mm, (stampBottomMm + 35.0) * mm);

    // Вертикальные линии колонок изменений (проходят от stampBottomMm + 35 до stampBottomMm + 55)
    final xRevIzmMm = stampLeftMm + 10.0;
    final xRevKolMm = stampLeftMm + 20.0;
    final xRevListMm = stampLeftMm + 30.0;
    final xRevDocMm = stampLeftMm + 45.0;
    final xRevSignMm = stampLeftMm + 55.0;

    canvas.drawLine(xRevIzmMm * mm, (stampBottomMm + 35.0) * mm, xRevIzmMm * mm, (stampBottomMm + 55.0) * mm);
    canvas.drawLine(xRevKolMm * mm, (stampBottomMm + 35.0) * mm, xRevKolMm * mm, (stampBottomMm + 55.0) * mm);
    canvas.drawLine(xRevListMm * mm, (stampBottomMm + 35.0) * mm, xRevListMm * mm, (stampBottomMm + 55.0) * mm);
    canvas.drawLine(xRevDocMm * mm, (stampBottomMm + 35.0) * mm, xRevDocMm * mm, (stampBottomMm + 55.0) * mm);
    canvas.drawLine(xRevSignMm * mm, (stampBottomMm + 35.0) * mm, xRevSignMm * mm, (stampBottomMm + 55.0) * mm);

    // 7 строк согласований (y = stampBottomMm + 5, 10, 15, 20, 25, 30)
    for (int i = 1; i <= 6; i++) {
      final yMm = stampBottomMm + (i * 5.0);
      canvas.drawLine(stampLeftMm * mm, yMm * mm, xApprovalsEndMm * mm, yMm * mm);
    }

    // Вертикальные линии блока согласований (от stampBottomMm до stampBottomMm + 35)
    final xRoleMm = stampLeftMm + 17.0;
    final xNameMm = stampLeftMm + 40.0;
    final xSignMm = stampLeftMm + 55.0;

    canvas.drawLine(xRoleMm * mm, stampBottomMm * mm, xRoleMm * mm, (stampBottomMm + 35.0) * mm);
    canvas.drawLine(xNameMm * mm, stampBottomMm * mm, xNameMm * mm, (stampBottomMm + 35.0) * mm);
    canvas.drawLine(xSignMm * mm, stampBottomMm * mm, xSignMm * mm, (stampBottomMm + 35.0) * mm);
    canvas.strokePath();

    // --- ПРАВЫЙ БЛОК (65..185 мм, ширина 120 мм) ---
    final stampRightMm = widthMm - sheet.format.frameRightMm;
    final xCenterEndMm = stampLeftMm + 135.0;

    // Строка 1: Шифр проекта (15 мм сверху, y: stampBottomMm + 40..55)
    final yRow1Mm = stampBottomMm + 40.0;
    canvas.setLineWidth(styleConfig.stampBorderWidthMm * mm);
    canvas.drawLine(xApprovalsEndMm * mm, yRow1Mm * mm, stampRightMm * mm, yRow1Mm * mm);

    // Строка 2: Объект (15 мм, y: stampBottomMm + 25..40)
    final yRow2Mm = stampBottomMm + 25.0;
    canvas.drawLine(xApprovalsEndMm * mm, yRow2Mm * mm, stampRightMm * mm, yRow2Mm * mm);

    // Разделитель между 70 мм и 50 мм справа: от stampBottomMm до yRow2Mm
    canvas.drawLine(xCenterEndMm * mm, stampBottomMm * mm, xCenterEndMm * mm, yRow2Mm * mm);

    // Разделитель строк 3 и 4: y = stampBottomMm + 15 (Строка 3: 10 мм, Строка 4: 15 мм)
    final yRow3Mm = stampBottomMm + 15.0;
    canvas.drawLine(xApprovalsEndMm * mm, yRow3Mm * mm, stampRightMm * mm, yRow3Mm * mm);
    canvas.strokePath();

    // Строка 3 Справа: Стадия | Лист | Листов
    // Шапка (5 мм, y = stampBottomMm + 20)
    canvas.setLineWidth(styleConfig.stampGridWidthMm * mm);
    final yStageHeaderMm = stampBottomMm + 20.0;
    canvas.drawLine(xCenterEndMm * mm, yStageHeaderMm * mm, stampRightMm * mm, yStageHeaderMm * mm);

    final xStageMm = xCenterEndMm + 15.0;
    final xSheetMm = xCenterEndMm + 32.0;
    canvas.drawLine(xStageMm * mm, yRow3Mm * mm, xStageMm * mm, yRow2Mm * mm);
    canvas.drawLine(xSheetMm * mm, yRow3Mm * mm, xSheetMm * mm, yRow2Mm * mm);
    canvas.strokePath();
  }

  /// Отрисовка трубопроводной сети, выносок и размеров внутри видового экрана
  static void _drawPdfNetworkInViewport({
    required PdfGraphics canvas,
    required DrawingSheet sheet,
    required PipingNetwork network,
    required ProjectionType projectionType,
    required DrawingStyleConfig styleConfig,
    required double heightMm,
    required double mm,
  }) {
    final vp = sheet.viewport;
    final projector = AxonometryProjector(projectionType: projectionType);

    // Координаты видового экрана в PDF (PDF y снизу)
    final vpXPt = vp.xMm * mm;
    final vpYPt = (heightMm - vp.yMm - vp.heightMm) * mm;
    final vpWPt = vp.widthMm * mm;
    final vpHPt = vp.heightMm * mm;

    // Рамка видового экрана (тонкая)
    canvas.setStrokeColor(PdfColors.blueGrey300);
    canvas.setLineWidth(0.25 * mm);
    canvas.drawRect(vpXPt, vpYPt, vpWPt, vpHPt);
    canvas.strokePath();

    // Клиппирование области видового экрана
    canvas.saveContext();
    canvas.drawRect(vpXPt, vpYPt, vpWPt, vpHPt);
    canvas.clipPath();

    // Трассы трубопроводов
    for (final seg in network.segments.values) {
      final isVisible = vp.visibleSystemIds == null || vp.visibleSystemIds!.contains(seg.systemId);
      if (!isVisible && !vp.ghostInactiveSystems) continue;

      final n1 = network.nodes[seg.startNodeId];
      final n2 = network.nodes[seg.endNodeId];
      if (n1 == null || n2 == null) continue;

      final raw1 = projector.projectRaw(n1.x, n1.y, n1.z);
      final raw2 = projector.projectRaw(n2.x, n2.y, n2.z);

      final p1Mm = ViewportTransformService.model2dToSheetMm(raw1, vp);
      final p2Mm = ViewportTransformService.model2dToSheetMm(raw2, vp);

      final x1Pt = p1Mm.dx * mm;
      final y1Pt = (heightMm - p1Mm.dy) * mm;
      final x2Pt = p2Mm.dx * mm;
      final y2Pt = (heightMm - p2Mm.dy) * mm;

      if (isVisible) {
        final sys = network.systems[seg.systemId];
        final pdfColor = sys != null ? PdfColor.fromInt(sys.colorValue) : PdfColors.black;
        canvas.setStrokeColor(pdfColor);
        canvas.setLineWidth(styleConfig.pipeLineWidthMm * mm);
      } else {
        canvas.setStrokeColor(PdfColors.grey400);
        canvas.setLineWidth(styleConfig.thinLineWidthMm * mm);
      }

      canvas.drawLine(x1Pt, y1Pt, x2Pt, y2Pt);
      canvas.strokePath();
    }

    // Сварные стыки
    for (final joint in network.weldJoints.values) {
      final seg = network.segments[joint.segmentId];
      if (seg == null) continue;
      final isVisible = vp.visibleSystemIds == null || vp.visibleSystemIds!.contains(seg.systemId);
      if (!isVisible) continue;

      final n1 = network.nodes[seg.startNodeId];
      final n2 = network.nodes[seg.endNodeId];
      if (n1 == null || n2 == null) continue;

      final pos = joint.calculatePosition(n1, n2);
      final raw = projector.projectRaw(pos.x, pos.y, pos.z);
      final pMm = ViewportTransformService.model2dToSheetMm(raw, vp);
      final xPt = pMm.dx * mm;
      final yPt = (heightMm - pMm.dy) * mm;

      canvas.setFillColor(PdfColors.red700);
      canvas.drawEllipse(xPt, yPt, 1.2 * mm, 1.2 * mm);
      canvas.fillPath();
    }

    // Векторные линии линейных размеров (ГОСТ 2.307)
    for (final dim in network.dimensions.values) {
      final raw1 = projector.projectRaw(dim.startPoint.x, dim.startPoint.y, dim.startPoint.z);
      final raw2 = projector.projectRaw(dim.endPoint.x, dim.endPoint.y, dim.endPoint.z);
      final p1Mm = ViewportTransformService.model2dToSheetMm(raw1, vp);
      final p2Mm = ViewportTransformService.model2dToSheetMm(raw2, vp);

      final delta = p2Mm - p1Mm;
      final dist2d = delta.distance;
      if (dist2d < 1.0) continue;

      final u = delta / dist2d;
      final n = Offset(-u.dy, u.dx);
      final offsetDist = (dim.offsetDistance == 0.0 ? 10.0 : dim.offsetDistance * vp.viewScale);
      final offsetVec = n * offsetDist;

      final d1 = p1Mm + offsetVec;
      final d2 = p2Mm + offsetVec;
      final overshoot = (offsetDist >= 0 ? 2.0 : -2.0);
      final ext1End = d1 + n * overshoot;
      final ext2End = d2 + n * overshoot;

      canvas.setStrokeColor(PdfColors.black);
      canvas.setLineWidth(styleConfig.thinLineWidthMm * mm);

      // Выносные линии
      canvas.drawLine(p1Mm.dx * mm, (heightMm - p1Mm.dy) * mm, ext1End.dx * mm, (heightMm - ext1End.dy) * mm);
      canvas.drawLine(p2Mm.dx * mm, (heightMm - p2Mm.dy) * mm, ext2End.dx * mm, (heightMm - ext2End.dy) * mm);

      // Размерная линия
      canvas.drawLine(d1.dx * mm, (heightMm - d1.dy) * mm, d2.dx * mm, (heightMm - d2.dy) * mm);
      canvas.strokePath();

      // Строительные засечки ГОСТ 45°
      final tickLen = 1.8;
      final tickDir = (u + n) / math.sqrt(2) * tickLen;
      canvas.setLineWidth(styleConfig.pipeLineWidthMm * mm);
      canvas.drawLine(
        (d1.dx - tickDir.dx) * mm,
        (heightMm - (d1.dy - tickDir.dy)) * mm,
        (d1.dx + tickDir.dx) * mm,
        (heightMm - (d1.dy + tickDir.dy)) * mm,
      );
      canvas.drawLine(
        (d2.dx - tickDir.dx) * mm,
        (heightMm - (d2.dy - tickDir.dy)) * mm,
        (d2.dx + tickDir.dx) * mm,
        (heightMm - (d2.dy + tickDir.dy)) * mm,
      );
      canvas.strokePath();
    }

    // Векторные линии выносок
    for (final callout in network.callouts.values) {
      final anchor3D = CalloutPainter.getTarget3DPoint(network, callout);
      if (anchor3D == null) continue;

      final anchorRaw = projector.projectRaw(anchor3D.x, anchor3D.y, anchor3D.z);
      final anchorMm = ViewportTransformService.model2dToSheetMm(anchorRaw, vp);

      final isRight = callout.shelfDirection == ShelfDirection.right
          ? true
          : (callout.shelfDirection == ShelfDirection.left
              ? false
              : callout.screenOffsetX >= 0);
      final leaderEndMm = anchorMm + Offset(callout.screenOffsetX * 0.25, callout.screenOffsetY * 0.25);
      final shelfLengthMm = 18.0;
      final shelfDir = isRight ? 1.0 : -1.0;
      final shelfEndMm = leaderEndMm + Offset(shelfLengthMm * shelfDir, 0);

      canvas.setStrokeColor(PdfColors.black);
      canvas.setLineWidth(styleConfig.thinLineWidthMm * mm);

      // Линия выноски и полка
      canvas.drawLine(anchorMm.dx * mm, (heightMm - anchorMm.dy) * mm, leaderEndMm.dx * mm, (heightMm - leaderEndMm.dy) * mm);
      canvas.drawLine(leaderEndMm.dx * mm, (heightMm - leaderEndMm.dy) * mm, shelfEndMm.dx * mm, (heightMm - shelfEndMm.dy) * mm);
      canvas.strokePath();

      // Точка у основания
      canvas.setFillColor(PdfColors.black);
      canvas.drawEllipse(anchorMm.dx * mm, (heightMm - anchorMm.dy) * mm, 0.6 * mm, 0.6 * mm);
      canvas.fillPath();
    }

    canvas.restoreContext();
  }

  /// Генерация текстовых аннотаций видового экрана (размерные числа, тексты выносок)
  static List<pw.Widget> _buildViewportAnnotationTexts({
    required DrawingSheet sheet,
    required PipingNetwork network,
    required ProjectionType projectionType,
    required pw.Font fontRegular,
    required pw.Font fontBold,
    required double heightMm,
    required double mm,
  }) {
    final vp = sheet.viewport;
    final projector = AxonometryProjector(projectionType: projectionType);
    final widgets = <pw.Widget>[];

    // Размеры (размерные числа над размерной линией)
    for (final dim in network.dimensions.values) {
      final raw1 = projector.projectRaw(dim.startPoint.x, dim.startPoint.y, dim.startPoint.z);
      final raw2 = projector.projectRaw(dim.endPoint.x, dim.endPoint.y, dim.endPoint.z);
      final p1Mm = ViewportTransformService.model2dToSheetMm(raw1, vp);
      final p2Mm = ViewportTransformService.model2dToSheetMm(raw2, vp);

      final delta = p2Mm - p1Mm;
      final dist2d = delta.distance;
      if (dist2d < 1.0) continue;

      final u = delta / dist2d;
      final n = Offset(-u.dy, u.dx);
      final offsetDist = (dim.offsetDistance == 0.0 ? 10.0 : dim.offsetDistance * vp.viewScale);
      final offsetVec = n * offsetDist;

      final midMm = (p1Mm + p2Mm) / 2.0 + offsetVec;
      final textPosMm = midMm + n * (offsetDist >= 0 ? 2.5 : -2.5);

      // Проверяем попадание в рамку видового экрана
      if (textPosMm.dx < vp.xMm || textPosMm.dx > vp.xMm + vp.widthMm ||
          textPosMm.dy < vp.yMm || textPosMm.dy > vp.yMm + vp.heightMm) {
        continue;
      }

      widgets.add(
        pw.Positioned(
          left: (textPosMm.dx - 12.0) * mm,
          top: (textPosMm.dy - 3.0) * mm,
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 1.5, vertical: 0.5),
            color: PdfColors.white,
            child: pw.Text(
              dim.displayText,
              style: pw.TextStyle(font: fontRegular, fontSize: 6.5),
            ),
          ),
        ),
      );
    }

    // Выноски (текст на полке)
    for (final callout in network.callouts.values) {
      final anchor3D = CalloutPainter.getTarget3DPoint(network, callout);
      if (anchor3D == null) continue;

      final anchorRaw = projector.projectRaw(anchor3D.x, anchor3D.y, anchor3D.z);
      final anchorMm = ViewportTransformService.model2dToSheetMm(anchorRaw, vp);

      final isRight = callout.shelfDirection == ShelfDirection.right
          ? true
          : (callout.shelfDirection == ShelfDirection.left
              ? false
              : callout.screenOffsetX >= 0);
      final leaderEndMm = anchorMm + Offset(callout.screenOffsetX * 0.25, callout.screenOffsetY * 0.25);
      final textX = isRight ? leaderEndMm.dx + 1.0 : leaderEndMm.dx - 22.0;
      final textY = leaderEndMm.dy - 3.5;

      if (leaderEndMm.dx < vp.xMm - 20 || leaderEndMm.dx > vp.xMm + vp.widthMm + 20 ||
          leaderEndMm.dy < vp.yMm - 20 || leaderEndMm.dy > vp.yMm + vp.heightMm + 20) {
        continue;
      }

      final text = network.generateCalloutText(callout, defaultCalloutTemplates);

      widgets.add(
        pw.Positioned(
          left: textX * mm,
          top: textY * mm,
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 1.0),
            color: PdfColors.white,
            child: pw.Text(
              text,
              style: pw.TextStyle(font: fontRegular, fontSize: 6.5),
            ),
          ),
        ),
      );
    }

    return widgets;
  }

  /// Генерация текстовых виджетов для граф штампа по ГОСТ 21.101-2020 / СПДС (Форма 3)
  static List<pw.Widget> _buildTitleBlockTexts({
    required DrawingSheet sheet,
    required pw.Font fontRegular,
    required pw.Font fontBold,
    required double mm,
  }) {
    final widthMm = sheet.format.widthMm;
    final heightMm = sheet.format.heightMm;
    final tb = sheet.titleBlockData;

    final stampLeft = (widthMm - sheet.format.frameRightMm - 185.0) * mm;
    final stampTop = (heightMm - sheet.format.frameBottomMm - 55.0) * mm;

    final widgets = <pw.Widget>[];

    // --- ЛЕВЫЙ БЛОК (0..65 мм) ---
    // В Form 3: 3 пустые строки изменений (0..15 мм),
    // Затем строка 4 (15..20 мм) - шапка таблицы изменений:
    final revHeaderTop = stampTop + 15.0 * mm;

    widgets.add(pw.Positioned(
      left: stampLeft,
      top: revHeaderTop,
      child: pw.Container(
        width: 10.0 * mm,
        height: 5.0 * mm,
        alignment: pw.Alignment.center,
        child: pw.Text('Изм.', style: pw.TextStyle(font: fontRegular, fontSize: 5)),
      ),
    ));
    widgets.add(pw.Positioned(
      left: stampLeft + 10.0 * mm,
      top: revHeaderTop,
      child: pw.Container(
        width: 10.0 * mm,
        height: 5.0 * mm,
        alignment: pw.Alignment.center,
        child: pw.Text('Кол.уч', style: pw.TextStyle(font: fontRegular, fontSize: 5)),
      ),
    ));
    widgets.add(pw.Positioned(
      left: stampLeft + 20.0 * mm,
      top: revHeaderTop,
      child: pw.Container(
        width: 10.0 * mm,
        height: 5.0 * mm,
        alignment: pw.Alignment.center,
        child: pw.Text('Лист', style: pw.TextStyle(font: fontRegular, fontSize: 5)),
      ),
    ));
    widgets.add(pw.Positioned(
      left: stampLeft + 30.0 * mm,
      top: revHeaderTop,
      child: pw.Container(
        width: 15.0 * mm,
        height: 5.0 * mm,
        alignment: pw.Alignment.center,
        child: pw.Text('№ док.', style: pw.TextStyle(font: fontRegular, fontSize: 5)),
      ),
    ));
    widgets.add(pw.Positioned(
      left: stampLeft + 45.0 * mm,
      top: revHeaderTop,
      child: pw.Container(
        width: 10.0 * mm,
        height: 5.0 * mm,
        alignment: pw.Alignment.center,
        child: pw.Text('Подп.', style: pw.TextStyle(font: fontRegular, fontSize: 5)),
      ),
    ));
    widgets.add(pw.Positioned(
      left: stampLeft + 55.0 * mm,
      top: revHeaderTop,
      child: pw.Container(
        width: 10.0 * mm,
        height: 5.0 * mm,
        alignment: pw.Alignment.center,
        child: pw.Text('Дата', style: pw.TextStyle(font: fontRegular, fontSize: 5)),
      ),
    ));

    // Строки согласований: строки 5..11 (20..55 мм: 7 строк по 5 мм)
    final approvals = tb.approvals.isNotEmpty
        ? tb.approvals
        : const [
            TitleBlockApproval(role: 'Геодезист', name: ''),
            TitleBlockApproval(role: 'Исп. директор', name: ''),
            TitleBlockApproval(role: 'Разраб.', name: ''),
            TitleBlockApproval(role: 'Пров.', name: ''),
            TitleBlockApproval(role: 'ГИП', name: ''),
          ];

    for (int i = 0; i < approvals.length && i < 7; i++) {
      final app = approvals[i];
      final rowTop = stampTop + (20.0 + i * 5.0) * mm + (1.2 * mm);

      // Должность (17 мм)
      if (app.role.isNotEmpty) {
        widgets.add(pw.Positioned(
          left: stampLeft + 1.5 * mm,
          top: rowTop,
          child: pw.Text(app.role, style: pw.TextStyle(font: fontRegular, fontSize: 6)),
        ));
      }

      // Фамилия (23 мм)
      if (app.name.isNotEmpty) {
        widgets.add(pw.Positioned(
          left: stampLeft + 18.5 * mm,
          top: rowTop,
          child: pw.Text(app.name, style: pw.TextStyle(font: fontRegular, fontSize: 6.5)),
        ));
      }

      // Дата (10 мм)
      if (app.date.isNotEmpty) {
        widgets.add(pw.Positioned(
          left: stampLeft + 56.0 * mm,
          top: rowTop,
          child: pw.Text(app.date, style: pw.TextStyle(font: fontRegular, fontSize: 5.5)),
        ));
      }
    }

    // --- ПРАВЫЙ БЛОК (65..185 мм, ширина 120 мм) ---
    final xCenter = stampLeft + 65.0 * mm;
    final xRight = stampLeft + 135.0 * mm;

    // Строка 1 (0..15 мм): Графа 4: Обозначение документа / шифр проекта (120 мм ширина)
    if (tb.documentCode.isNotEmpty) {
      widgets.add(pw.Positioned(
        left: xCenter,
        top: stampTop,
        child: pw.Container(
          width: 120.0 * mm,
          height: 15.0 * mm,
          alignment: pw.Alignment.center,
          child: pw.Text(tb.documentCode, style: pw.TextStyle(font: fontBold, fontSize: 11)),
        ),
      ));
    }

    // Строка 2 (15..30 мм): Графа 1: Наименование объекта строительства (120 мм ширина)
    if (tb.projectName.isNotEmpty) {
      widgets.add(pw.Positioned(
        left: xCenter + 2.0 * mm,
        top: stampTop + 16.0 * mm,
        child: pw.Container(
          width: 116.0 * mm,
          height: 13.0 * mm,
          alignment: pw.Alignment.centerLeft,
          child: pw.Text(
            tb.projectName,
            style: pw.TextStyle(font: fontRegular, fontSize: 7.5),
            maxLines: 2,
          ),
        ),
      ));
    }

    // Строка 3 (30..40 мм, высота 10 мм):
    // Слева (65..135 мм, 70 мм): Графа 2: Наименование здания / сооружения
    if (tb.buildingName.isNotEmpty) {
      widgets.add(pw.Positioned(
        left: xCenter + 2.0 * mm,
        top: stampTop + 31.0 * mm,
        child: pw.Container(
          width: 66.0 * mm,
          height: 8.5 * mm,
          alignment: pw.Alignment.centerLeft,
          child: pw.Text(
            tb.buildingName,
            style: pw.TextStyle(font: fontRegular, fontSize: 7.5),
            maxLines: 2,
          ),
        ),
      ));
    }

    // Справа (135..185 мм, 50 мм): Стадия | Лист | Листов
    // Шапка (30..35 мм: 5 мм)
    widgets.add(pw.Positioned(
      left: xRight,
      top: stampTop + 30.0 * mm,
      child: pw.Container(
        width: 15.0 * mm,
        height: 5.0 * mm,
        alignment: pw.Alignment.center,
        child: pw.Text('Стадия', style: pw.TextStyle(font: fontRegular, fontSize: 5)),
      ),
    ));
    widgets.add(pw.Positioned(
      left: xRight + 15.0 * mm,
      top: stampTop + 30.0 * mm,
      child: pw.Container(
        width: 17.0 * mm,
        height: 5.0 * mm,
        alignment: pw.Alignment.center,
        child: pw.Text('Лист', style: pw.TextStyle(font: fontRegular, fontSize: 5)),
      ),
    ));
    widgets.add(pw.Positioned(
      left: xRight + 32.0 * mm,
      top: stampTop + 30.0 * mm,
      child: pw.Container(
        width: 18.0 * mm,
        height: 5.0 * mm,
        alignment: pw.Alignment.center,
        child: pw.Text('Листов', style: pw.TextStyle(font: fontRegular, fontSize: 5)),
      ),
    ));

    // Значения (35..40 мм: 5 мм)
    widgets.add(pw.Positioned(
      left: xRight,
      top: stampTop + 35.0 * mm,
      child: pw.Container(
        width: 15.0 * mm,
        height: 5.0 * mm,
        alignment: pw.Alignment.center,
        child: pw.Text(tb.stage, style: pw.TextStyle(font: fontBold, fontSize: 8)),
      ),
    ));
    widgets.add(pw.Positioned(
      left: xRight + 15.0 * mm,
      top: stampTop + 35.0 * mm,
      child: pw.Container(
        width: 17.0 * mm,
        height: 5.0 * mm,
        alignment: pw.Alignment.center,
        child: pw.Text(tb.sheetNumber.toString(), style: pw.TextStyle(font: fontBold, fontSize: 8)),
      ),
    ));
    widgets.add(pw.Positioned(
      left: xRight + 32.0 * mm,
      top: stampTop + 35.0 * mm,
      child: pw.Container(
        width: 18.0 * mm,
        height: 5.0 * mm,
        alignment: pw.Alignment.center,
        child: pw.Text(tb.totalSheets.toString(), style: pw.TextStyle(font: fontBold, fontSize: 8)),
      ),
    ));

    // Строка 4 (40..55 мм, высота 15 мм):
    // Слева (65..135 мм, 70 мм): Графа 3: Наименование схемы / чертежа
    if (tb.drawingTitle.isNotEmpty) {
      widgets.add(pw.Positioned(
        left: xCenter + 2.0 * mm,
        top: stampTop + 41.0 * mm,
        child: pw.Container(
          width: 66.0 * mm,
          height: 13.0 * mm,
          alignment: pw.Alignment.centerLeft,
          child: pw.Text(
            tb.drawingTitle,
            style: pw.TextStyle(font: fontBold, fontSize: 8.5),
            maxLines: 2,
          ),
        ),
      ));
    }

    // Справа (135..185 мм, 50 мм): Графа 9: Организация
    if (tb.organization.isNotEmpty) {
      widgets.add(pw.Positioned(
        left: xRight + 1.0 * mm,
        top: stampTop + 41.0 * mm,
        child: pw.Container(
          width: 48.0 * mm,
          height: 13.0 * mm,
          alignment: pw.Alignment.center,
          child: pw.Text(
            tb.organization,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: fontBold, fontSize: 8),
          ),
        ),
      ));
    }

    return widgets;
  }

  /// Виджет правого верхнего угла (Приложение к акту)
  static List<pw.Widget> _buildTopRightCornerBlock({
    required DrawingSheet sheet,
    required pw.Font fontRegular,
    required double mm,
  }) {
    final tr = sheet.titleBlockData.topRightCorner;
    final text = tr.formattedText;
    if (text.isEmpty || tr.mode == TopRightCornerMode.none) return const [];

    final widthMm = sheet.format.widthMm;
    final frameRightMm = widthMm - sheet.format.frameRightMm;

    final blockW = tr.widthMm;
    final blockH = tr.heightMm;
    final blockX = tr.xMm ?? (frameRightMm - blockW);
    final blockY = tr.yMm ?? sheet.format.frameTopMm;

    return [
      pw.Positioned(
        left: blockX * mm,
        top: blockY * mm,
        child: pw.Container(
          width: blockW * mm,
          height: blockH * mm,
          padding: const pw.EdgeInsets.all(2.0),
          decoration: tr.hasBorder
              ? pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.black, width: 0.5),
                  color: PdfColors.white,
                )
              : null,
          alignment: pw.Alignment.topRight,
          child: pw.Text(
            text,
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(font: fontRegular, fontSize: 7, fontStyle: pw.FontStyle.italic),
          ),
        ),
      ),
    ];
  }

  /// Виджет технических требований (ТТ) / примечаний
  static pw.Widget _buildTechnicalRequirements({
    required DrawingSheet sheet,
    required pw.Font fontRegular,
    required pw.Font fontBold,
    required double mm,
  }) {
    final tt = sheet.technicalRequirements!;
    final blockW = tt.widthMm;
    final blockH = tt.heightMm;
    final blockX = tt.xMm;
    final blockY = tt.yMm;

    return pw.Positioned(
      left: blockX * mm,
      top: blockY * mm,
      child: pw.Container(
        width: blockW * mm,
        height: blockH * mm,
        padding: const pw.EdgeInsets.all(3.0),
        decoration: tt.hasBorder
            ? pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.black, width: 0.5),
                color: PdfColors.white,
              )
            : const pw.BoxDecoration(color: PdfColors.white),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (tt.title.isNotEmpty) ...[
              pw.Text(
                tt.title,
                style: pw.TextStyle(font: fontBold, fontSize: 7.5),
              ),
              pw.SizedBox(height: 1.5 * mm),
            ],
            pw.Expanded(
              child: pw.Text(
                tt.text,
                style: pw.TextStyle(font: fontRegular, fontSize: 6.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Виджет блока «Условные обозначения» (Легенда)
  static pw.Widget _buildDrawingLegend({
    required DrawingSheet sheet,
    required pw.Font fontRegular,
    required pw.Font fontBold,
    required double mm,
  }) {
    final leg = sheet.legend!;

    return pw.Positioned(
      left: leg.xMm * mm,
      top: leg.yMm * mm,
      child: pw.Container(
        width: leg.widthMm * mm,
        height: leg.heightMm * mm,
        padding: const pw.EdgeInsets.all(3.0),
        decoration: leg.hasBorder
            ? pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.black, width: 0.5),
                color: PdfColors.white,
              )
            : const pw.BoxDecoration(color: PdfColors.white),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              leg.title,
              style: pw.TextStyle(font: fontBold, fontSize: 7.5),
            ),
            pw.SizedBox(height: 1.5 * mm),
            pw.Expanded(
              child: pw.ListView.builder(
                itemCount: leg.items.length,
                itemBuilder: (ctx, i) {
                  final item = leg.items[i];
                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 1.0),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Container(
                          width: 14.0 * mm,
                          height: 3.5 * mm,
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(color: PdfColors.grey500, width: 0.5),
                          ),
                          alignment: pw.Alignment.center,
                          child: pw.Text(
                            item.subLabel ?? item.label,
                            style: pw.TextStyle(font: fontRegular, fontSize: 5),
                          ),
                        ),
                        pw.SizedBox(width: 2.0 * mm),
                        pw.Expanded(
                          child: pw.Text(
                            item.label,
                            style: pw.TextStyle(font: fontRegular, fontSize: 6),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Загрузка TTF шрифта с поддержкой кириллицы (Roboto)
  static Future<pw.Font> _loadFont({bool isBold = false}) async {
    final fileName = isBold ? 'Roboto-Bold.ttf' : 'Roboto-Regular.ttf';

    // 1. Попытка чтения локального файла в assets/fonts (для Desktop и Unit тестов)
    try {
      final file = File('assets/fonts/$fileName');
      if (file.existsSync()) {
        final bytes = await file.readAsBytes();
        return pw.Font.ttf(bytes.buffer.asByteData());
      }
    } catch (_) {}

    // 2. Попытка загрузки через rootBundle (для бандла приложения)
    try {
      final data = await rootBundle.load('assets/fonts/$fileName');
      return pw.Font.ttf(data);
    } catch (_) {}

    // 3. Fallback: Google Fonts онлайн или Helvetica
    try {
      return isBold ? await PdfGoogleFonts.robotoBold() : await PdfGoogleFonts.robotoRegular();
    } catch (_) {
      return isBold ? pw.Font.helveticaBold() : pw.Font.helvetica();
    }
  }

  /// Сохранение сгенерированного PDF файла через нативный диалог (FilePicker / Share)
  static Future<bool> savePdfFile({
    required Uint8List bytes,
    required String suggestedFileName,
  }) async {
    String name = suggestedFileName.trim();
    if (!name.toLowerCase().endsWith('.pdf')) {
      name = '$name.pdf';
    }

    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Сохранить чертеж в формате PDF',
        fileName: name,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: bytes,
      );

      if (uri == null) return false;

      String targetPath = uri.scheme == 'file'
          ? uri.toFilePath()
          : (uri.path.isNotEmpty ? uri.path : uri.toString());
      if (!targetPath.toLowerCase().endsWith('.pdf')) {
        targetPath = '$targetPath.pdf';
      }

      final file = File(targetPath);
      await file.writeAsBytes(bytes, flush: true);
      return true;
    } else {
      // Mobile / Web шеринг
      return await Printing.sharePdf(bytes: bytes, filename: name);
    }
  }

  /// Отправка листа на печать в системный диалог принтера
  static Future<bool> printSheet({
    required Uint8List bytes,
    String jobName = 'Чертеж_АКСО',
  }) async {
    return await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => bytes,
      name: jobName,
    );
  }
}
