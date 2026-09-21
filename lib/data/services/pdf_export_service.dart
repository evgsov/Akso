import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/math/axonometry_projector.dart';
import '../../domain/enums/projection_type.dart';
import '../../domain/models/drawing_sheet.dart';
import '../../domain/models/drawing_style_config.dart';
import '../../domain/models/piping_network.dart';
import '../../domain/models/title_block_data.dart';
import '../../domain/services/viewport_transform_service.dart';

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
              // 1. Векторные линии видового экрана, рамки листа и штампа
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

              // 2. Заголовок схемы в левом верхнем углу (как в исполнительных схемах)
              if (sheet.titleBlockData.drawingTitle.isNotEmpty)
                pw.Positioned(
                  left: (sheet.format.frameLeftMm + 5.0) * mm,
                  top: (sheet.format.frameTopMm + 2.5) * mm,
                  child: pw.Text(
                    sheet.titleBlockData.drawingTitle,
                    style: pw.TextStyle(font: fontBold, fontSize: 9.5),
                  ),
                ),

              // 3. Надпись формата листа под штампом за рамкой
              pw.Positioned(
                right: sheet.format.frameRightMm * mm,
                bottom: (sheet.format.frameBottomMm - 4.0) * mm,
                child: pw.Text(
                  'Формат ${sheet.format.type.name.toUpperCase()}',
                  style: pw.TextStyle(font: fontRegular, fontSize: 7),
                ),
              ),

              // 4. Текстовые поля штампа (Форма 3 по ГОСТ 21.101-2020 / СПДС)
              ..._buildTitleBlockTexts(
                sheet: sheet,
                fontRegular: fontRegular,
                fontBold: fontBold,
                mm: mm,
              ),

              // 5. Блок приложения к акту (правый верхний угол)
              ..._buildTopRightCornerBlock(
                sheet: sheet,
                fontRegular: fontRegular,
                mm: mm,
              ),

              // 6. Технические требования (ТТ) над штампом
              if (sheet.technicalRequirements != null &&
                  sheet.technicalRequirements!.text.isNotEmpty)
                _buildTechnicalRequirements(
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

  /// Отрисовка внешней рамки листа по ГОСТ (20-5-5-5 мм) и сетки штампа (185х55 мм)
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

    // Внешняя толстая рамка чертежа
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

    // Непрозрачная белая подложка штампа (чтобы линии видового экрана не просвечивали)
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
    // 1. Верхняя строка: Таблица регистрации изменений (Изм. | Кол.уч | Лист | № док. | Подп. | Дата)
    canvas.setLineWidth(styleConfig.stampGridWidthMm * mm);
    final yRevHeaderMm = stampBottomMm + 50.0;
    canvas.drawLine(stampLeftMm * mm, yRevHeaderMm * mm, xApprovalsEndMm * mm, yRevHeaderMm * mm);

    final xRevIzmMm = stampLeftMm + 10.0;
    final xRevKolMm = stampLeftMm + 20.0;
    final xRevListMm = stampLeftMm + 30.0;
    final xRevDocMm = stampLeftMm + 45.0;
    final xRevSignMm = stampLeftMm + 55.0;

    canvas.drawLine(xRevIzmMm * mm, yRevHeaderMm * mm, xRevIzmMm * mm, (stampBottomMm + 55.0) * mm);
    canvas.drawLine(xRevKolMm * mm, yRevHeaderMm * mm, xRevKolMm * mm, (stampBottomMm + 55.0) * mm);
    canvas.drawLine(xRevListMm * mm, yRevHeaderMm * mm, xRevListMm * mm, (stampBottomMm + 55.0) * mm);
    canvas.drawLine(xRevDocMm * mm, yRevHeaderMm * mm, xRevDocMm * mm, (stampBottomMm + 55.0) * mm);
    canvas.drawLine(xRevSignMm * mm, yRevHeaderMm * mm, xRevSignMm * mm, (stampBottomMm + 55.0) * mm);

    // 2. Строки согласований (от низа до yRevHeaderMm)
    final xRoleMm = stampLeftMm + 17.0;
    final xNameMm = stampLeftMm + 40.0;
    final xSignMm = stampLeftMm + 55.0;

    canvas.drawLine(xRoleMm * mm, stampBottomMm * mm, xRoleMm * mm, yRevHeaderMm * mm);
    canvas.drawLine(xNameMm * mm, stampBottomMm * mm, xNameMm * mm, yRevHeaderMm * mm);
    canvas.drawLine(xSignMm * mm, stampBottomMm * mm, xSignMm * mm, yRevHeaderMm * mm);

    for (int i = 1; i <= 9; i++) {
      final yMm = stampBottomMm + (i * 5.0);
      canvas.drawLine(stampLeftMm * mm, yMm * mm, xApprovalsEndMm * mm, yMm * mm);
    }
    canvas.strokePath();

    // --- ПРАВЫЙ БЛОК (65..185 мм, ширина 120 мм) ---
    final stampRightMm = widthMm - sheet.format.frameRightMm;
    final xCenterEndMm = stampLeftMm + 135.0;

    // Строка 1: Графа 4 (Шифр проекта, 15 мм сверху, y: +40..+55)
    final yRow1Mm = stampBottomMm + 40.0;
    canvas.setLineWidth(styleConfig.stampBorderWidthMm * mm);
    canvas.drawLine(xApprovalsEndMm * mm, yRow1Mm * mm, stampRightMm * mm, yRow1Mm * mm);

    // Строка 2: Графа 1 (Наименование объекта, 15 мм, y: +25..+40)
    final yRow2Mm = stampBottomMm + 25.0;
    canvas.drawLine(xApprovalsEndMm * mm, yRow2Mm * mm, stampRightMm * mm, yRow2Mm * mm);

    // Разделитель между 70 мм и 50 мм справа: от stampBottomMm до yRow2Mm
    canvas.drawLine(xCenterEndMm * mm, stampBottomMm * mm, xCenterEndMm * mm, yRow2Mm * mm);

    // Разделитель строк 3 и 4 (y: +12.5)
    final yRow3Mm = stampBottomMm + 12.5;
    canvas.drawLine(xApprovalsEndMm * mm, yRow3Mm * mm, stampRightMm * mm, yRow3Mm * mm);
    canvas.strokePath();

    // Строка 3 Справа: Стадия | Лист | Листов (шапка 5 мм при y: +20)
    canvas.setLineWidth(styleConfig.stampGridWidthMm * mm);
    final yStageHeaderMm = stampBottomMm + 20.0;
    canvas.drawLine(xCenterEndMm * mm, yStageHeaderMm * mm, stampRightMm * mm, yStageHeaderMm * mm);

    final xStageMm = xCenterEndMm + 15.0;
    final xSheetMm = xCenterEndMm + 30.0;
    canvas.drawLine(xStageMm * mm, yRow3Mm * mm, xStageMm * mm, yRow2Mm * mm);
    canvas.drawLine(xSheetMm * mm, yRow3Mm * mm, xSheetMm * mm, yRow2Mm * mm);
    canvas.strokePath();
  }

  /// Отрисовка трубопроводной сети внутри клиппированного видового экрана
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

    canvas.restoreContext();
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
    // 1. Шапка таблицы изменений (0..5 мм)
    widgets.add(pw.Positioned(
      left: stampLeft,
      top: stampTop,
      child: pw.Container(
        width: 10.0 * mm,
        height: 5.0 * mm,
        alignment: pw.Alignment.center,
        child: pw.Text('Изм.', style: pw.TextStyle(font: fontRegular, fontSize: 5)),
      ),
    ));
    widgets.add(pw.Positioned(
      left: stampLeft + 10.0 * mm,
      top: stampTop,
      child: pw.Container(
        width: 10.0 * mm,
        height: 5.0 * mm,
        alignment: pw.Alignment.center,
        child: pw.Text('Кол.уч', style: pw.TextStyle(font: fontRegular, fontSize: 5)),
      ),
    ));
    widgets.add(pw.Positioned(
      left: stampLeft + 20.0 * mm,
      top: stampTop,
      child: pw.Container(
        width: 10.0 * mm,
        height: 5.0 * mm,
        alignment: pw.Alignment.center,
        child: pw.Text('Лист', style: pw.TextStyle(font: fontRegular, fontSize: 5)),
      ),
    ));
    widgets.add(pw.Positioned(
      left: stampLeft + 30.0 * mm,
      top: stampTop,
      child: pw.Container(
        width: 15.0 * mm,
        height: 5.0 * mm,
        alignment: pw.Alignment.center,
        child: pw.Text('№ док.', style: pw.TextStyle(font: fontRegular, fontSize: 5)),
      ),
    ));
    widgets.add(pw.Positioned(
      left: stampLeft + 45.0 * mm,
      top: stampTop,
      child: pw.Container(
        width: 10.0 * mm,
        height: 5.0 * mm,
        alignment: pw.Alignment.center,
        child: pw.Text('Подп.', style: pw.TextStyle(font: fontRegular, fontSize: 5)),
      ),
    ));
    widgets.add(pw.Positioned(
      left: stampLeft + 55.0 * mm,
      top: stampTop,
      child: pw.Container(
        width: 10.0 * mm,
        height: 5.0 * mm,
        alignment: pw.Alignment.center,
        child: pw.Text('Дата', style: pw.TextStyle(font: fontRegular, fontSize: 5)),
      ),
    ));

    // 2. Строки согласований (5..55 мм: 10 строк по 5 мм)
    final approvals = tb.approvals.isNotEmpty
        ? tb.approvals
        : const [
            TitleBlockApproval(role: 'Геодезист', name: ''),
            TitleBlockApproval(role: 'Исп. директор', name: ''),
            TitleBlockApproval(role: 'Разраб.', name: ''),
            TitleBlockApproval(role: 'Пров.', name: ''),
            TitleBlockApproval(role: 'ГИП', name: ''),
          ];

    for (int i = 0; i < approvals.length && i < 10; i++) {
      final app = approvals[i];
      final rowTop = stampTop + (5.0 + i * 5.0) * mm + (1.2 * mm);

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

    // Графа 4: Обозначение документа / шифр проекта (0..15 мм, 120 мм ширина)
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

    // Графа 1: Наименование объекта строительства (15..30 мм, 120 мм ширина)
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

    // Графа 2: Наименование здания / сооружения (30..42.5 мм, 70 мм слева)
    if (tb.buildingName.isNotEmpty) {
      widgets.add(pw.Positioned(
        left: xCenter + 2.0 * mm,
        top: stampTop + 31.0 * mm,
        child: pw.Container(
          width: 66.0 * mm,
          height: 10.5 * mm,
          alignment: pw.Alignment.centerLeft,
          child: pw.Text(
            tb.buildingName,
            style: pw.TextStyle(font: fontRegular, fontSize: 7.5),
            maxLines: 2,
          ),
        ),
      ));
    }

    // Правый столбец строки 3: Стадия | Лист | Листов (30..42.5 мм, 50 мм справа)
    // Шапка (5 мм: 30..35 мм)
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
        width: 15.0 * mm,
        height: 5.0 * mm,
        alignment: pw.Alignment.center,
        child: pw.Text('Лист', style: pw.TextStyle(font: fontRegular, fontSize: 5)),
      ),
    ));
    widgets.add(pw.Positioned(
      left: xRight + 30.0 * mm,
      top: stampTop + 30.0 * mm,
      child: pw.Container(
        width: 20.0 * mm,
        height: 5.0 * mm,
        alignment: pw.Alignment.center,
        child: pw.Text('Листов', style: pw.TextStyle(font: fontRegular, fontSize: 5)),
      ),
    ));

    // Значения (7.5 мм: 35..42.5 мм)
    widgets.add(pw.Positioned(
      left: xRight,
      top: stampTop + 35.0 * mm,
      child: pw.Container(
        width: 15.0 * mm,
        height: 7.5 * mm,
        alignment: pw.Alignment.center,
        child: pw.Text(tb.stage, style: pw.TextStyle(font: fontBold, fontSize: 8)),
      ),
    ));
    widgets.add(pw.Positioned(
      left: xRight + 15.0 * mm,
      top: stampTop + 35.0 * mm,
      child: pw.Container(
        width: 15.0 * mm,
        height: 7.5 * mm,
        alignment: pw.Alignment.center,
        child: pw.Text(tb.sheetNumber.toString(), style: pw.TextStyle(font: fontBold, fontSize: 8)),
      ),
    ));
    widgets.add(pw.Positioned(
      left: xRight + 30.0 * mm,
      top: stampTop + 35.0 * mm,
      child: pw.Container(
        width: 20.0 * mm,
        height: 7.5 * mm,
        alignment: pw.Alignment.center,
        child: pw.Text(tb.totalSheets.toString(), style: pw.TextStyle(font: fontBold, fontSize: 8)),
      ),
    ));

    // Строка 4 Слева: Графа 3: Наименование схемы / чертежа (42.5..55 мм, 70 мм слева)
    if (tb.drawingTitle.isNotEmpty) {
      widgets.add(pw.Positioned(
        left: xCenter + 2.0 * mm,
        top: stampTop + 43.5 * mm,
        child: pw.Container(
          width: 66.0 * mm,
          height: 10.5 * mm,
          alignment: pw.Alignment.centerLeft,
          child: pw.Text(
            tb.drawingTitle,
            style: pw.TextStyle(font: fontBold, fontSize: 8.5),
            maxLines: 2,
          ),
        ),
      ));
    }

    // Строка 4 Справа: Графа 5: Организация (42.5..55 мм, 50 мм справа)
    if (tb.organization.isNotEmpty) {
      widgets.add(pw.Positioned(
        left: xRight + 1.0 * mm,
        top: stampTop + 43.5 * mm,
        child: pw.Container(
          width: 48.0 * mm,
          height: 10.5 * mm,
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
    if (text.isEmpty) return const [];

    final widthMm = sheet.format.widthMm;
    final frameRightMm = widthMm - sheet.format.frameRightMm;

    return [
      pw.Positioned(
        right: (widthMm - frameRightMm + 2.0) * mm,
        top: (sheet.format.frameTopMm + 2.0) * mm,
        child: pw.SizedBox(
          width: 90.0 * mm,
          child: pw.Text(
            text,
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(font: fontRegular, fontSize: 7, fontStyle: pw.FontStyle.italic),
          ),
        ),
      ),
    ];
  }

  /// Виджет технических требований (ТТ) над штампом
  static pw.Widget _buildTechnicalRequirements({
    required DrawingSheet sheet,
    required pw.Font fontRegular,
    required pw.Font fontBold,
    required double mm,
  }) {
    final tt = sheet.technicalRequirements!;
    final widthMm = sheet.format.widthMm;
    final heightMm = sheet.format.heightMm;

    final frameRightMm = widthMm - sheet.format.frameRightMm;
    final stampTopMm = heightMm - sheet.format.frameBottomMm - 55.0;

    return pw.Positioned(
      right: (widthMm - frameRightMm + 2.0) * mm,
      bottom: (heightMm - stampTopMm + 3.0) * mm,
      child: pw.Container(
        width: 180.0 * mm,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Технические требования:',
              style: pw.TextStyle(font: fontBold, fontSize: 7.5),
            ),
            pw.SizedBox(height: 2.0 * mm),
            pw.Text(
              tt.text,
              style: pw.TextStyle(font: fontRegular, fontSize: 6.8),
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
