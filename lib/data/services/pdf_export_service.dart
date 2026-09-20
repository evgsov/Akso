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
              // 1. Векторные линии рамки, штампа, видового экрана и трубопроводной сети
              pw.CustomPaint(
                size: PdfPoint(pageFormat.width, pageFormat.height),
                painter: (canvas, size) {
                  _drawPdfGostFrameAndStampGrid(canvas, sheet, styleConfig, mm);
                  _drawPdfNetworkInViewport(
                    canvas: canvas,
                    sheet: sheet,
                    network: network,
                    projectionType: projectionType,
                    styleConfig: styleConfig,
                    heightMm: heightMm,
                    mm: mm,
                  );
                },
              ),

              // 2. Текстовые поля штампа (Форма 3 по ГОСТ 21.101-2020)
              ..._buildTitleBlockTexts(
                sheet: sheet,
                fontRegular: fontRegular,
                fontBold: fontBold,
                mm: mm,
              ),

              // 3. Блок приложения к акту (правый верхний угол)
              ..._buildTopRightCornerBlock(
                sheet: sheet,
                fontRegular: fontRegular,
                mm: mm,
              ),

              // 4. Технические требования (ТТ) над штампом
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

    // Внешний контур штампа
    canvas.setLineWidth(styleConfig.stampBorderWidthMm * mm);
    canvas.drawRect(stampLeftMm * mm, stampBottomMm * mm, 185.0 * mm, 55.0 * mm);
    canvas.strokePath();

    // Тонкие линии внутренней сетки штампа
    canvas.setLineWidth(styleConfig.stampGridWidthMm * mm);

    // Вертикальные линии согласований (слева в штампе)
    final xRoleMm = stampLeftMm + 17.0;
    final xNameMm = stampLeftMm + 40.0;
    final xSignMm = stampLeftMm + 55.0;
    final xApprovalsEndMm = stampLeftMm + 65.0;
    final xCenterEndMm = stampLeftMm + 135.0;

    canvas.drawLine(xRoleMm * mm, stampBottomMm * mm, xRoleMm * mm, (stampBottomMm + 55.0) * mm);
    canvas.drawLine(xNameMm * mm, stampBottomMm * mm, xNameMm * mm, (stampBottomMm + 55.0) * mm);
    canvas.drawLine(xSignMm * mm, stampBottomMm * mm, xSignMm * mm, (stampBottomMm + 55.0) * mm);
    canvas.strokePath();

    // Разделитель блока согласований и центрального блока (толстая линия)
    canvas.setLineWidth(styleConfig.stampBorderWidthMm * mm);
    canvas.drawLine(xApprovalsEndMm * mm, stampBottomMm * mm, xApprovalsEndMm * mm, (stampBottomMm + 55.0) * mm);
    canvas.drawLine(xCenterEndMm * mm, stampBottomMm * mm, xCenterEndMm * mm, (stampBottomMm + 55.0) * mm);
    canvas.strokePath();

    // Горизонтальные строки блока согласований (8 строк по 5 мм снизу)
    canvas.setLineWidth(styleConfig.stampGridWidthMm * mm);
    for (int i = 1; i <= 8; i++) {
      final yMm = stampBottomMm + (i * 5.0);
      canvas.drawLine(stampLeftMm * mm, yMm * mm, xApprovalsEndMm * mm, yMm * mm);
    }
    canvas.strokePath();

    // Разделители правого блока (Стадия 15мм, Лист 15мм, Листов 20мм)
    final yStageValuesMm = stampBottomMm + 35.0;
    final yStageHeaderMm = stampBottomMm + 50.0;
    final stampRightMm = widthMm - sheet.format.frameRightMm;

    canvas.drawLine(xCenterEndMm * mm, yStageHeaderMm * mm, stampRightMm * mm, yStageHeaderMm * mm);
    canvas.drawLine(xCenterEndMm * mm, yStageValuesMm * mm, stampRightMm * mm, yStageValuesMm * mm);

    final xStageMm = xCenterEndMm + 15.0;
    final xSheetMm = xCenterEndMm + 30.0;
    canvas.drawLine(xStageMm * mm, yStageValuesMm * mm, xStageMm * mm, (stampBottomMm + 55.0) * mm);
    canvas.drawLine(xSheetMm * mm, yStageValuesMm * mm, xSheetMm * mm, (stampBottomMm + 55.0) * mm);

    // Горизонтальные строки центрального блока (Шифр, Объект, Здание)
    final yObjMm = stampBottomMm + 25.0;
    final yBuildingMm = stampBottomMm + 15.0;
    final yCodeMm = stampBottomMm + 40.0;

    canvas.drawLine(xApprovalsEndMm * mm, yCodeMm * mm, xCenterEndMm * mm, yCodeMm * mm);
    canvas.drawLine(xApprovalsEndMm * mm, yObjMm * mm, xCenterEndMm * mm, yObjMm * mm);
    canvas.drawLine(xApprovalsEndMm * mm, yBuildingMm * mm, xCenterEndMm * mm, yBuildingMm * mm);
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

  /// Генерация текстовых виджетов для граф штампа по ГОСТ 21.101-2020
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

    // Фамилии и согласования (Разраб., Пров., Т.контр., ГИП, Н.контр., Утв.)
    final roles = ['Разраб.', 'Пров.', 'Т.контр.', '', 'ГИП', 'Н.контр.', 'Утв.'];
    for (int i = 0; i < roles.length; i++) {
      final role = roles[i];
      if (role.isEmpty) continue;

      final rowTop = stampTop + (55.0 - (roles.length - i) * 5.0) * mm + (1.2 * mm);
      // Роль
      widgets.add(pw.Positioned(
        left: stampLeft + 1.5 * mm,
        top: rowTop,
        child: pw.Text(role, style: pw.TextStyle(font: fontRegular, fontSize: 6)),
      ));

      final app = tb.approvals.firstWhere(
        (a) => a.role == role,
        orElse: () => const TitleBlockApproval(role: '', name: ''),
      );

      // Фамилия
      if (app.name.isNotEmpty) {
        widgets.add(pw.Positioned(
          left: stampLeft + 18.5 * mm,
          top: rowTop,
          child: pw.Text(app.name, style: pw.TextStyle(font: fontRegular, fontSize: 6.5)),
        ));
      }

      // Дата
      if (app.date.isNotEmpty) {
        widgets.add(pw.Positioned(
          left: stampLeft + 56.0 * mm,
          top: rowTop,
          child: pw.Text(app.date, style: pw.TextStyle(font: fontRegular, fontSize: 5.5)),
        ));
      }
    }

    final xCenter = stampLeft + 65.0 * mm;

    // Графа 4: Обозначение документа / шифр проекта (15 мм высота)
    if (tb.documentCode.isNotEmpty) {
      widgets.add(pw.Positioned(
        left: xCenter + 4.0 * mm,
        top: stampTop + 3.5 * mm,
        child: pw.Text(tb.documentCode, style: pw.TextStyle(font: fontBold, fontSize: 11)),
      ));
    }

    // Графа 1: Наименование объекта
    if (tb.projectName.isNotEmpty) {
      widgets.add(pw.Positioned(
        left: xCenter + 2.5 * mm,
        top: stampTop + 17.5 * mm,
        child: pw.Text(tb.projectName, style: pw.TextStyle(font: fontRegular, fontSize: 8)),
      ));
    }

    // Графа 2: Наименование здания / сооружения
    if (tb.buildingName.isNotEmpty) {
      widgets.add(pw.Positioned(
        left: xCenter + 2.5 * mm,
        top: stampTop + 32.5 * mm,
        child: pw.Text(tb.buildingName, style: pw.TextStyle(font: fontRegular, fontSize: 8)),
      ));
    }

    // Графа 3: Наименование схемы / чертежа
    if (tb.drawingTitle.isNotEmpty) {
      widgets.add(pw.Positioned(
        left: xCenter + 2.5 * mm,
        top: stampTop + 43.0 * mm,
        child: pw.Text(tb.drawingTitle, style: pw.TextStyle(font: fontBold, fontSize: 9)),
      ));
    }

    // Правый блок: Стадия, Лист, Листов
    final xRight = stampLeft + 135.0 * mm;
    widgets.add(pw.Positioned(
      left: xRight + 2.0 * mm,
      top: stampTop + 1.0 * mm,
      child: pw.Text('Стадия', style: pw.TextStyle(font: fontRegular, fontSize: 5)),
    ));
    widgets.add(pw.Positioned(
      left: xRight + 17.0 * mm,
      top: stampTop + 1.0 * mm,
      child: pw.Text('Лист', style: pw.TextStyle(font: fontRegular, fontSize: 5)),
    ));
    widgets.add(pw.Positioned(
      left: xRight + 32.0 * mm,
      top: stampTop + 1.0 * mm,
      child: pw.Text('Листов', style: pw.TextStyle(font: fontRegular, fontSize: 5)),
    ));

    // Значения
    widgets.add(pw.Positioned(
      left: xRight + 5.0 * mm,
      top: stampTop + 8.0 * mm,
      child: pw.Text(tb.stage, style: pw.TextStyle(font: fontBold, fontSize: 9)),
    ));
    widgets.add(pw.Positioned(
      left: xRight + 19.0 * mm,
      top: stampTop + 8.0 * mm,
      child: pw.Text(tb.sheetNumber.toString(), style: pw.TextStyle(font: fontBold, fontSize: 9)),
    ));
    widgets.add(pw.Positioned(
      left: xRight + 36.0 * mm,
      top: stampTop + 8.0 * mm,
      child: pw.Text(tb.totalSheets.toString(), style: pw.TextStyle(font: fontBold, fontSize: 9)),
    ));

    // Организация (Графа 9)
    if (tb.organization.isNotEmpty) {
      widgets.add(pw.Positioned(
        left: xRight + 2.0 * mm,
        top: stampTop + 26.0 * mm,
        child: pw.SizedBox(
          width: 46.0 * mm,
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
