import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../domain/enums/projection_type.dart';
import '../../domain/models/drawing_legend.dart';
import '../../domain/models/drawing_sheet.dart';
import '../../domain/models/drawing_style_config.dart';
import '../../domain/models/piping_network.dart';
import '../../domain/models/title_block_data.dart';
import '../../domain/services/viewport_transform_service.dart';
import 'painters/callout_painter.dart';
import 'painters/dimension_painter.dart';

/// Интерактивный CustomPainter для отображения листа бумаги по ГОСТ 21.101-2020,
/// рамок 20-5-5-5 мм, штампа 185х55 мм, примечаний ТТ и клиппированного видового экрана
class SheetCanvasPainter extends CustomPainter {
  final DrawingSheet sheet;
  final PipingNetwork network;
  final double sheetZoom;
  final Offset sheetPan;
  final bool isViewportFocused;
  final bool isViewportSelected;
  final String? selectedSheetBlock; // 'viewport', 'notes', 'act', 'legend'
  final String? activeGrip;
  final ProjectionType projectionType;
  final DrawingStyleConfig styleConfig;

  SheetCanvasPainter({
    required this.sheet,
    required this.network,
    required this.sheetZoom,
    required this.sheetPan,
    this.isViewportFocused = false,
    this.isViewportSelected = false,
    this.selectedSheetBlock,
    this.activeGrip,
    this.projectionType = ProjectionType.gostFrontal45,
    this.styleConfig = const DrawingStyleConfig(),
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Фон стола и лист бумаги с падающей тенью
    final paperW = sheet.format.widthMm * sheetZoom;
    final paperH = sheet.format.heightMm * sheetZoom;
    final paperRect = Rect.fromLTWH(sheetPan.dx, sheetPan.dy, paperW, paperH);

    _drawPaperWithShadow(canvas, paperRect);

    // 2. Рамка листа по ГОСТ (20 мм слева для подшивки, 5 мм с остальных сторон)
    final frameRect = Rect.fromLTRB(
      paperRect.left + (sheet.format.frameLeftMm * sheetZoom),
      paperRect.top + (sheet.format.frameTopMm * sheetZoom),
      paperRect.right - (sheet.format.frameRightMm * sheetZoom),
      paperRect.bottom - (sheet.format.frameBottomMm * sheetZoom),
    );

    // 3. Видовой экран (Viewport) с клиппированием и прорисовкой сети
    // Рисуется первым, чтобы штамп, рамка и ТТ в пространстве листа перекрывали модель
    _drawViewport(canvas, paperRect);

    // 4. Рамка листа по ГОСТ (20-5-5-5 мм)
    _drawGostFrame(canvas, frameRect);

    // 5. Заголовок схемы в левом верхнем углу (как в исполнительных схемах)
    _drawSheetHeaderTitle(canvas, frameRect);

    // 6. Правый верхний угол (Приложение к акту в рамке)
    _drawTopRightCorner(canvas, frameRect, paperRect);

    // 7. Поле подшивки слева (Инв. № подл., Взам. инв. №)
    _drawArchiveField(canvas, paperRect, frameRect);

    // 8. Блок Технических требований (ТТ)
    if (sheet.technicalRequirements != null && sheet.technicalRequirements!.text.isNotEmpty) {
      _drawTechnicalRequirements(canvas, frameRect, paperRect);
    }

    // 8.1. Блок Условных обозначений
    if (sheet.legend != null && sheet.legend!.isVisible) {
      _drawLegend(canvas, frameRect, paperRect);
    }

    // 9. Основная надпись (штамп 185х55 мм в правом нижнем углу с непрозрачной белой подложкой)
    _drawTitleBlock(canvas, frameRect);

    // 10. Подпись формата листа за пределами рамки (напр. "Формат А3")
    _drawSheetFormatLabel(canvas, frameRect, paperRect);

    // 11. Интерактивные CAD-ручки (AutoCAD Grips) активного элемента в пространстве листа
    if (!isViewportFocused) {
      _drawActiveElementGrips(canvas, paperRect, frameRect);
    }
  }

  void _drawPaperWithShadow(Canvas canvas, Rect paperRect) {
    // Тень листа (аппаратно-ускоренная тень через drawShadow без дорогого программного MaskFilter.blur)
    final shadowPath = Path()..addRect(paperRect);
    canvas.drawShadow(shadowPath, Colors.black.withValues(alpha: 0.45), 8.0, false);

    // Белый лист бумаги
    final paperPaint = Paint()..color = Colors.white;
    canvas.drawRect(paperRect, paperPaint);

    // Тонкая линия обрезки по краю бумаги
    final borderPaint = Paint()
      ..color = const Color(0xFFCCCCCC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRect(paperRect, borderPaint);
  }

  void _drawGostFrame(Canvas canvas, Rect frameRect) {
    final framePaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, styleConfig.frameLineWidthMm * sheetZoom);
    canvas.drawRect(frameRect, framePaint);
  }

  void _drawSheetHeaderTitle(Canvas canvas, Rect frameRect) {
    final title = sheet.titleBlockData.drawingTitle;
    if (title.isEmpty) return;
    _drawText(
      canvas,
      title,
      Offset(frameRect.left + (5.0 * sheetZoom), frameRect.top + (3.0 * sheetZoom)),
      3.5 * sheetZoom,
      isBold: true,
    );
  }

  void _drawSheetFormatLabel(Canvas canvas, Rect frameRect, Rect paperRect) {
    final label = 'Формат ${sheet.format.type.name.toUpperCase()}';
    final offset = Offset(frameRect.right - (28.0 * sheetZoom), frameRect.bottom + (1.2 * sheetZoom));
    _drawText(canvas, label, offset, 2.4 * sheetZoom);
  }

  // =========================================================================
  // --- Статические хелперы для вычисления экранных координат блоков листа ---
  // =========================================================================

  static Rect getViewportScreenRect({
    required DrawingSheet sheet,
    required Rect paperRect,
    required double sheetZoom,
  }) {
    final vp = sheet.viewport;
    return Rect.fromLTWH(
      paperRect.left + (vp.xMm * sheetZoom),
      paperRect.top + (vp.yMm * sheetZoom),
      vp.widthMm * sheetZoom,
      vp.heightMm * sheetZoom,
    );
  }

  static Rect getStampScreenRect({
    required Rect frameRect,
    required double sheetZoom,
  }) {
    final stampW = 185.0 * sheetZoom;
    final stampH = 55.0 * sheetZoom;
    return Rect.fromLTWH(
      frameRect.right - stampW,
      frameRect.bottom - stampH,
      stampW,
      stampH,
    );
  }

  static Rect getActAttachmentScreenRect({
    required DrawingSheet sheet,
    required Rect paperRect,
    required Rect frameRect,
    required double sheetZoom,
  }) {
    final tr = sheet.titleBlockData.topRightCorner;
    final wMm = tr.widthMm;
    final hMm = tr.heightMm;

    if (tr.xMm != null && tr.yMm != null) {
      return Rect.fromLTWH(
        paperRect.left + (tr.xMm! * sheetZoom),
        paperRect.top + (tr.yMm! * sheetZoom),
        wMm * sheetZoom,
        hMm * sheetZoom,
      );
    }
    return Rect.fromLTWH(
      frameRect.right - (wMm * sheetZoom),
      frameRect.top,
      wMm * sheetZoom,
      hMm * sheetZoom,
    );
  }

  static Rect getTechnicalRequirementsScreenRect({
    required DrawingSheet sheet,
    required Rect paperRect,
    required Rect frameRect,
    required double sheetZoom,
  }) {
    final tt = sheet.technicalRequirements;
    final wMm = tt?.widthMm ?? 185.0;
    final hMm = tt?.heightMm ?? 55.0;

    if (tt != null) {
      return Rect.fromLTWH(
        paperRect.left + (tt.xMm * sheetZoom),
        paperRect.top + (tt.yMm * sheetZoom),
        wMm * sheetZoom,
        hMm * sheetZoom,
      );
    }
    final stampH = 55.0 * sheetZoom;
    final ttHeight = hMm * sheetZoom;
    return Rect.fromLTWH(
      frameRect.right - (wMm * sheetZoom),
      frameRect.bottom - stampH - ttHeight - (4.0 * sheetZoom),
      wMm * sheetZoom,
      ttHeight,
    );
  }

  static Rect getLegendScreenRect({
    required DrawingSheet sheet,
    required Rect paperRect,
    required Rect frameRect,
    required double sheetZoom,
  }) {
    final leg = sheet.legend ?? DrawingLegend.createDefault();
    return Rect.fromLTWH(
      paperRect.left + (leg.xMm * sheetZoom),
      paperRect.top + (leg.yMm * sheetZoom),
      leg.widthMm * sheetZoom,
      leg.heightMm * sheetZoom,
    );
  }

  void _drawTopRightCorner(Canvas canvas, Rect frameRect, Rect paperRect) {
    final tr = sheet.titleBlockData.topRightCorner;
    final text = tr.formattedText;
    if (text.isEmpty || tr.mode == TopRightCornerMode.none) return;

    final boxRect = getActAttachmentScreenRect(
      sheet: sheet,
      paperRect: paperRect,
      frameRect: frameRect,
      sheetZoom: sheetZoom,
    );

    // Белая подложка
    canvas.drawRect(boxRect, Paint()..color = Colors.white);

    // Рамка по контуру (если включена)
    if (tr.hasBorder) {
      final borderPaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.5, styleConfig.thinLineWidthMm * sheetZoom);
      canvas.drawRect(boxRect, borderPaint);
    }

    final lines = text.split('\n');
    final lineH = 3.6 * sheetZoom;
    double curY = boxRect.top + math.max(2.0 * sheetZoom, (boxRect.height - (lines.length * lineH)) / 2.0);
    for (final line in lines) {
      _drawCenteredText(canvas, line, Rect.fromLTWH(boxRect.left, curY, boxRect.width, lineH), 2.2 * sheetZoom);
      curY += lineH;
    }
  }

  void _drawTechnicalRequirements(Canvas canvas, Rect frameRect, Rect paperRect) {
    final tt = sheet.technicalRequirements;
    if (tt == null || tt.text.isEmpty) return;

    final rect = getTechnicalRequirementsScreenRect(
      sheet: sheet,
      paperRect: paperRect,
      frameRect: frameRect,
      sheetZoom: sheetZoom,
    );

    // 1. Белая подложка
    canvas.drawRect(rect, Paint()..color = Colors.white);

    // 2. Рамка (если включена)
    if (tt.hasBorder) {
      final borderPaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.6, styleConfig.thinLineWidthMm * sheetZoom);
      canvas.drawRect(rect, borderPaint);
    }

    // 3. Заголовок
    final title = tt.title.isNotEmpty ? tt.title : 'Технические требования:';
    _drawText(
      canvas,
      title,
      Offset(rect.left + (4.0 * sheetZoom), rect.top + (3.0 * sheetZoom)),
      2.8 * sheetZoom,
      isBold: true,
    );

    // 4. Текст строк
    final lines = tt.text.split('\n');
    double y = rect.top + (7.5 * sheetZoom);
    final lineStep = 4.0 * sheetZoom;
    for (final line in lines) {
      if (y + lineStep > rect.bottom + 2.0) break;
      _drawText(
        canvas,
        line,
        Offset(rect.left + (4.0 * sheetZoom), y),
        2.5 * sheetZoom,
      );
      y += lineStep;
    }
  }

  void _drawLegend(Canvas canvas, Rect frameRect, Rect paperRect) {
    final leg = sheet.legend;
    if (leg == null || !leg.isVisible) return;

    final rect = getLegendScreenRect(
      sheet: sheet,
      paperRect: paperRect,
      frameRect: frameRect,
      sheetZoom: sheetZoom,
    );

    // 1. Белая подложка
    canvas.drawRect(rect, Paint()..color = Colors.white);

    // 2. Рамка (если включена)
    if (leg.hasBorder) {
      final borderPaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.6, styleConfig.thinLineWidthMm * sheetZoom);
      canvas.drawRect(rect, borderPaint);
    }

    // 3. Заголовок
    final title = leg.title.isNotEmpty ? leg.title : 'Условные обозначения:';
    _drawText(
      canvas,
      title,
      Offset(rect.left + 4.0 * sheetZoom, rect.top + 3.0 * sheetZoom),
      3.0 * sheetZoom,
      isBold: true,
    );

    // 4. Элементы легенды
    double curY = rect.top + (9.0 * sheetZoom);
    final rowH = (rect.height - (10.0 * sheetZoom)) / math.max(1, leg.items.length);
    final itemH = math.max(5.0 * sheetZoom, rowH);

    for (final item in leg.items) {
      if (curY + itemH > rect.bottom + 2.0) break;
      _drawLegendItem(
        canvas,
        item,
        Rect.fromLTWH(rect.left + 4.0 * sheetZoom, curY, rect.width - 8.0 * sheetZoom, itemH),
      );
      curY += itemH;
    }
  }

  void _drawLegendItem(Canvas canvas, LegendItem item, Rect rowRect) {
    final iconW = 26.0 * sheetZoom;
    final iconRect = Rect.fromLTWH(rowRect.left, rowRect.top, iconW, rowRect.height);
    final midY = iconRect.center.dy;

    switch (item.type) {
      case LegendItemType.dimension:
        final p1 = Offset(iconRect.left + 2.0 * sheetZoom, midY);
        final p2 = Offset(iconRect.right - 2.0 * sheetZoom, midY);
        final linePaint = Paint()
          ..color = const Color(0xFF37474F)
          ..strokeWidth = math.max(0.6, styleConfig.thinLineWidthMm * sheetZoom)
          ..style = PaintingStyle.stroke;
        canvas.drawLine(p1, p2, linePaint);
        final tickLen = 2.5 * sheetZoom;
        canvas.drawLine(p1.translate(-tickLen, tickLen), p1.translate(tickLen, -tickLen), linePaint);
        canvas.drawLine(p2.translate(-tickLen, tickLen), p2.translate(tickLen, -tickLen), linePaint);
        _drawCenteredText(canvas, '1000', Rect.fromLTWH(iconRect.left, midY - 4.5 * sheetZoom, iconW, 4.0 * sheetZoom), 1.8 * sheetZoom);
        _drawCenteredText(canvas, '1005', Rect.fromLTWH(iconRect.left, midY + 1.0 * sheetZoom, iconW, 4.0 * sheetZoom), 1.8 * sheetZoom);
        break;

      case LegendItemType.elevation:
        final flagH = 4.0 * sheetZoom;
        final flagW = 3.0 * sheetZoom;
        final tip = Offset(iconRect.left + 5.0 * sheetZoom, midY + 2.0 * sheetZoom);
        final flagBaseY = tip.dy - flagH;
        final flagPath = Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(tip.dx - flagW, flagBaseY)
          ..lineTo(tip.dx + flagW, flagBaseY)
          ..close();
        final markPaint = Paint()
          ..color = const Color(0xFF1976D2)
          ..strokeWidth = math.max(0.6, styleConfig.thinLineWidthMm * sheetZoom)
          ..style = PaintingStyle.stroke;
        canvas.drawPath(flagPath, markPaint);
        canvas.drawLine(Offset(tip.dx, flagBaseY), Offset(tip.dx, tip.dy - 6.0 * sheetZoom), markPaint);
        canvas.drawLine(Offset(tip.dx, tip.dy - 6.0 * sheetZoom), Offset(iconRect.right - 2.0 * sheetZoom, tip.dy - 6.0 * sheetZoom), markPaint);
        _drawText(canvas, '+2.450', Offset(tip.dx + 2.0 * sheetZoom, tip.dy - 10.0 * sheetZoom), 1.8 * sheetZoom, color: const Color(0xFF1976D2));
        break;

      case LegendItemType.pipeSystem:
        final p1 = Offset(iconRect.left + 2.0 * sheetZoom, midY);
        final p2 = Offset(iconRect.right - 2.0 * sheetZoom, midY);
        final pSysId = item.systemId ?? item.systemCode;
        final pipeColor = pSysId != null && network.systems.containsKey(pSysId)
            ? Color(network.systems[pSysId]!.colorValue)
            : const Color(0xFF1976D2);
        final pipePaint = Paint()
          ..color = pipeColor
          ..strokeWidth = math.max(1.2, styleConfig.pipeLineWidthMm * sheetZoom)
          ..style = PaintingStyle.stroke;
        canvas.drawLine(p1, p2, pipePaint);
        break;

      case LegendItemType.weldJoint:
        final p1 = Offset(iconRect.left + 2.0 * sheetZoom, midY);
        final p2 = Offset(iconRect.right - 2.0 * sheetZoom, midY);
        final pipePaint = Paint()
          ..color = const Color(0xFF455A64)
          ..strokeWidth = math.max(1.0, styleConfig.pipeLineWidthMm * 0.7 * sheetZoom)
          ..style = PaintingStyle.stroke;
        canvas.drawLine(p1, p2, pipePaint);
        final dotPaint = Paint()
          ..color = const Color(0xFFE53935)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(iconRect.center.dx, midY), 2.2 * sheetZoom, dotPaint);
        break;

      case LegendItemType.valve:
        final vMid = iconRect.center;
        final vPaint = Paint()
          ..color = const Color(0xFF1976D2)
          ..strokeWidth = math.max(0.6, styleConfig.thinLineWidthMm * sheetZoom)
          ..style = PaintingStyle.stroke;
        final vPath = Path()
          ..moveTo(vMid.dx - 6.0 * sheetZoom, vMid.dy - 3.0 * sheetZoom)
          ..lineTo(vMid.dx, vMid.dy)
          ..lineTo(vMid.dx - 6.0 * sheetZoom, vMid.dy + 3.0 * sheetZoom)
          ..close()
          ..moveTo(vMid.dx + 6.0 * sheetZoom, vMid.dy - 3.0 * sheetZoom)
          ..lineTo(vMid.dx, vMid.dy)
          ..lineTo(vMid.dx + 6.0 * sheetZoom, vMid.dy + 3.0 * sheetZoom)
          ..close();
        canvas.drawPath(vPath, vPaint);
        break;

      case LegendItemType.fitting:
        final fMid = iconRect.center;
        final fPaint = Paint()
          ..color = const Color(0xFF5E35B1)
          ..strokeWidth = math.max(1.0, styleConfig.pipeLineWidthMm * 0.8 * sheetZoom)
          ..style = PaintingStyle.stroke;
        final fPath = Path()
          ..moveTo(fMid.dx - 5.0 * sheetZoom, fMid.dy + 3.0 * sheetZoom)
          ..lineTo(fMid.dx, fMid.dy)
          ..lineTo(fMid.dx + 5.0 * sheetZoom, fMid.dy - 3.0 * sheetZoom);
        canvas.drawPath(fPath, fPaint);
        break;

      case LegendItemType.custom:
        final ptPaint = Paint()..color = Colors.black;
        canvas.drawCircle(Offset(iconRect.center.dx, midY), 2.0 * sheetZoom, ptPaint);
        break;
    }

    final textX = rowRect.left + iconW + 4.0 * sheetZoom;
    final textRect = Rect.fromLTRB(textX, rowRect.top, rowRect.right, rowRect.bottom);
    _drawMultilineText(
      canvas,
      item.label,
      textRect,
      2.4 * sheetZoom,
    );
  }

  void _drawTitleBlock(Canvas canvas, Rect frameRect) {
    final stampW = 185.0 * sheetZoom;
    final stampH = 55.0 * sheetZoom;
    final stampRect = Rect.fromLTWH(
      frameRect.right - stampW,
      frameRect.bottom - stampH,
      stampW,
      stampH,
    );

    // Непрозрачная белая подложка штампа
    final bgPaint = Paint()..color = Colors.white;
    canvas.drawRect(stampRect, bgPaint);

    // Внешняя рамка штампа (основная сплошная линия по ГОСТ 2.303)
    final borderPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, styleConfig.stampBorderWidthMm * sheetZoom);
    canvas.drawRect(stampRect, borderPaint);

    // Тонкие линии внутренней сетки штампа
    final gridPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.5, styleConfig.stampGridWidthMm * sheetZoom);

    // Основной вертикальный разделитель: X = 65 мм слева (блок согласований/изменений)
    final xApprovalsEnd = stampRect.left + (65.0 * sheetZoom);
    canvas.drawLine(Offset(xApprovalsEnd, stampRect.top), Offset(xApprovalsEnd, stampRect.bottom), borderPaint);

    // Сквозная горизонтальная линия на отметке Y = 25 мм по всей ширине штампа (0..185 мм)
    // Разделяет верхнюю зону (изменения / шифр / объект) и нижнюю зону (согласования / здание / схема / стадия / организация)
    final yMid25 = stampRect.top + (25.0 * sheetZoom);
    canvas.drawLine(Offset(stampRect.left, yMid25), Offset(stampRect.right, yMid25), borderPaint);

    // --- ЛЕВЫЙ БЛОК (0..65 мм, высота 55 мм = 11 строк по 5 мм) ---
    // Таблица изменений (Y = 0..25 мм, 5 строк по 5 мм):
    // Строки 1, 2, 3, 4 (Y = 5, 10, 15, 20 мм)
    for (int i = 1; i <= 4; i++) {
      final y = stampRect.top + (i * 5.0 * sheetZoom);
      canvas.drawLine(Offset(stampRect.left, y), Offset(xApprovalsEnd, y), gridPaint);
    }

    // Вертикальные линии колонок таблицы изменений (Y = 0..25 мм):
    // X = 10 мм (Изм.)
    // X = 20 мм (Кол. уч.)
    // X = 30 мм (Лист)
    // X = 40 мм (№ док.)
    // X = 55 мм (Подп.)
    // X = 65 мм (Дата, граница xApprovalsEnd)
    final xRevIzm = stampRect.left + (10.0 * sheetZoom);
    final xRevKol = stampRect.left + (20.0 * sheetZoom);
    final xRevList = stampRect.left + (30.0 * sheetZoom);
    final xRevDoc = stampRect.left + (40.0 * sheetZoom);
    final xRevSign = stampRect.left + (55.0 * sheetZoom);

    canvas.drawLine(Offset(xRevIzm, stampRect.top), Offset(xRevIzm, yMid25), gridPaint);
    canvas.drawLine(Offset(xRevKol, stampRect.top), Offset(xRevKol, yMid25), gridPaint);
    canvas.drawLine(Offset(xRevList, stampRect.top), Offset(xRevList, yMid25), gridPaint);
    canvas.drawLine(Offset(xRevDoc, stampRect.top), Offset(xRevDoc, yMid25), gridPaint);
    canvas.drawLine(Offset(xRevSign, stampRect.top), Offset(xRevSign, yMid25), gridPaint);

    // Строка 5 (Y = 20..25 мм, h = 5 мм): Шапка таблицы изменений по ГОСТ 21.101-2020 Форма 3
    final yRevHeaderTop = stampRect.top + (20.0 * sheetZoom);
    _drawCenteredText(canvas, 'Изм.', Rect.fromLTRB(stampRect.left, yRevHeaderTop, xRevIzm, yMid25), 1.8 * sheetZoom);
    _drawCenteredText(canvas, 'Кол. уч.', Rect.fromLTRB(xRevIzm, yRevHeaderTop, xRevKol, yMid25), 1.8 * sheetZoom);
    _drawCenteredText(canvas, 'Лист', Rect.fromLTRB(xRevKol, yRevHeaderTop, xRevList, yMid25), 1.8 * sheetZoom);
    _drawCenteredText(canvas, '№ док.', Rect.fromLTRB(xRevList, yRevHeaderTop, xRevDoc, yMid25), 1.8 * sheetZoom);
    _drawCenteredText(canvas, 'Подп.', Rect.fromLTRB(xRevDoc, yRevHeaderTop, xRevSign, yMid25), 1.8 * sheetZoom);
    _drawCenteredText(canvas, 'Дата', Rect.fromLTRB(xRevSign, yRevHeaderTop, xApprovalsEnd, yMid25), 1.8 * sheetZoom);

    // Отрисовка записей изменений (tb.revisions) снизу вверх в строках над шапкой:
    final tb = sheet.titleBlockData;
    for (int r = 0; r < tb.revisions.length && r < 4; r++) {
      final rev = tb.revisions[r];
      final revYTop = stampRect.top + ((3 - r) * 5.0 * sheetZoom);
      final revYBot = revYTop + (5.0 * sheetZoom);
      _drawCenteredText(canvas, rev.changeIndex, Rect.fromLTRB(stampRect.left, revYTop, xRevIzm, revYBot), 1.8 * sheetZoom);
      _drawCenteredText(canvas, rev.changeCount, Rect.fromLTRB(xRevIzm, revYTop, xRevKol, revYBot), 1.8 * sheetZoom);
      _drawCenteredText(canvas, rev.sheetNum, Rect.fromLTRB(xRevKol, revYTop, xRevList, revYBot), 1.8 * sheetZoom);
      _drawCenteredText(canvas, rev.docNum, Rect.fromLTRB(xRevList, revYTop, xRevDoc, revYBot), 1.8 * sheetZoom);
      _drawCenteredText(canvas, rev.signature, Rect.fromLTRB(xRevDoc, revYTop, xRevSign, revYBot), 1.8 * sheetZoom);
      _drawCenteredText(canvas, rev.date, Rect.fromLTRB(xRevSign, revYTop, xApprovalsEnd, revYBot), 1.8 * sheetZoom);
    }

    // Блок согласований: Графы 10..13 (Y = 25..55 мм, 6 строк по 5 мм)
    // Колонки: Должность (20 мм: 0..20), Фамилия (20 мм: 20..40), Подпись (15 мм: 40..55), Дата (10 мм: 55..65)
    final xRole = stampRect.left + (20.0 * sheetZoom);
    final xName = stampRect.left + (40.0 * sheetZoom);
    final xSign = stampRect.left + (55.0 * sheetZoom);

    canvas.drawLine(Offset(xRole, yMid25), Offset(xRole, stampRect.bottom), gridPaint);
    canvas.drawLine(Offset(xName, yMid25), Offset(xName, stampRect.bottom), gridPaint);
    canvas.drawLine(Offset(xSign, yMid25), Offset(xSign, stampRect.bottom), gridPaint);

    for (int i = 1; i <= 5; i++) {
      final y = yMid25 + (i * 5.0 * sheetZoom);
      canvas.drawLine(Offset(stampRect.left, y), Offset(xApprovalsEnd, y), gridPaint);
    }

    // Заполнение строк согласований (до 6 строк)
    final approvals = tb.approvals.isNotEmpty
        ? tb.approvals
        : const [
            TitleBlockApproval(role: 'Геодезист', name: ''),
            TitleBlockApproval(role: 'Исп. директор', name: ''),
            TitleBlockApproval(role: 'Разраб.', name: ''),
            TitleBlockApproval(role: 'Пров.', name: ''),
            TitleBlockApproval(role: 'ГИП', name: ''),
          ];

    for (int i = 0; i < approvals.length && i < 6; i++) {
      final app = approvals[i];
      final y = yMid25 + (i * 5.0 * sheetZoom) + (1.2 * sheetZoom);
      if (app.role.isNotEmpty) {
        _drawText(canvas, app.role, Offset(stampRect.left + 1.5 * sheetZoom, y), 2.2 * sheetZoom);
      }
      if (app.name.isNotEmpty) {
        _drawText(canvas, app.name, Offset(xRole + 1.5 * sheetZoom, y), 2.2 * sheetZoom);
      }
      if (app.date.isNotEmpty) {
        _drawText(canvas, app.date, Offset(xSign + 1.0 * sheetZoom, y), 2.0 * sheetZoom);
      }
    }

    // --- ПРАВЫЙ БЛОК (65..185 мм, ширина 120 мм) ---
    // Строка 1: Графа 4 (Шифр проекта / обозначение документа, Y = 0..10 мм, высота 10 мм)
    final yRow1 = stampRect.top + (10.0 * sheetZoom);
    canvas.drawLine(Offset(xApprovalsEnd, yRow1), Offset(stampRect.right, yRow1), borderPaint);

    if (tb.documentCode.isNotEmpty) {
      _drawCenteredText(
        canvas,
        tb.documentCode,
        Rect.fromLTRB(xApprovalsEnd, stampRect.top, stampRect.right, yRow1),
        4.8 * sheetZoom,
        isBold: true,
      );
    }

    // Строка 2: Графа 1 (Наименование объекта строительства, Y = 10..25 мм, высота 15 мм)
    // Линия Y = 25 мм уже нарисована как сквозная yMid25
    if (tb.projectName.isNotEmpty) {
      _drawMultilineText(
        canvas,
        tb.projectName,
        Rect.fromLTRB(xApprovalsEnd + 2.0 * sheetZoom, yRow1 + 1.5 * sheetZoom, stampRect.right - 2.0 * sheetZoom, yMid25 - 1.5 * sheetZoom),
        2.6 * sheetZoom,
      );
    }

    // Разделитель между левой (70 мм) и правой (50 мм) частями:
    // от yMid25 (25 мм) до низа штампа (55 мм)
    final xCenterEnd = stampRect.left + (135.0 * sheetZoom);
    canvas.drawLine(Offset(xCenterEnd, yMid25), Offset(xCenterEnd, stampRect.bottom), borderPaint);

    // Горизонтальный разделитель строк 3 и 4 при Y = 40.0 мм (ГОСТ Форма 3)
    final yRow3 = stampRect.top + (40.0 * sheetZoom);
    canvas.drawLine(Offset(xApprovalsEnd, yRow3), Offset(stampRect.right, yRow3), borderPaint);

    // Строка 3 Слева: Графа 2 (Наименование здания / сооружения / этап, Y = 25..40 мм, высота 15 мм)
    if (tb.buildingName.isNotEmpty) {
      _drawMultilineText(
        canvas,
        tb.buildingName,
        Rect.fromLTRB(xApprovalsEnd + 2.0 * sheetZoom, yMid25 + 1.5 * sheetZoom, xCenterEnd - 2.0 * sheetZoom, yRow3 - 1.5 * sheetZoom),
        2.8 * sheetZoom,
        textAlign: TextAlign.center,
      );
    }

    // Строка 3 Справа: Стадия | Лист | Листов (Y = 25..40 мм, высота 15 мм)
    // Шапка: Y = 25..30 мм (высота 5 мм)
    final yStageHeader = yMid25 + (5.0 * sheetZoom);
    canvas.drawLine(Offset(xCenterEnd, yStageHeader), Offset(stampRect.right, yStageHeader), gridPaint);

    // Вертикальные линии колонок: Стадия (15 мм: 135..150), Лист (15 мм: 150..165), Листов (20 мм: 165..185)
    final xStage = xCenterEnd + (15.0 * sheetZoom);
    final xSheet = xCenterEnd + (30.0 * sheetZoom);
    canvas.drawLine(Offset(xStage, yMid25), Offset(xStage, yRow3), borderPaint);
    canvas.drawLine(Offset(xSheet, yMid25), Offset(xSheet, yRow3), borderPaint);

    _drawCenteredText(canvas, 'Стадия', Rect.fromLTRB(xCenterEnd, yMid25, xStage, yStageHeader), 1.8 * sheetZoom);
    _drawCenteredText(canvas, 'Лист', Rect.fromLTRB(xStage, yMid25, xSheet, yStageHeader), 1.8 * sheetZoom);
    _drawCenteredText(canvas, 'Листов', Rect.fromLTRB(xSheet, yMid25, stampRect.right, yStageHeader), 1.8 * sheetZoom);

    // Значения: Y = 30..40 мм (высота 10 мм)
    _drawCenteredText(canvas, tb.stage, Rect.fromLTRB(xCenterEnd, yStageHeader, xStage, yRow3), 3.2 * sheetZoom, isBold: true);
    _drawCenteredText(canvas, tb.sheetNumber.toString(), Rect.fromLTRB(xStage, yStageHeader, xSheet, yRow3), 3.2 * sheetZoom, isBold: true);
    _drawCenteredText(canvas, tb.totalSheets.toString(), Rect.fromLTRB(xSheet, yStageHeader, stampRect.right, yRow3), 3.2 * sheetZoom, isBold: true);

    // Строка 4 Слева: Графа 3 (Наименование схемы / чертежа, Y = 40..55 мм, высота 15 мм)
    if (tb.drawingTitle.isNotEmpty) {
      _drawMultilineText(
        canvas,
        tb.drawingTitle,
        Rect.fromLTRB(xApprovalsEnd + 2.0 * sheetZoom, yRow3 + 1.5 * sheetZoom, xCenterEnd - 2.0 * sheetZoom, stampRect.bottom - 1.0 * sheetZoom),
        2.8 * sheetZoom,
        isBold: true,
      );
    }

    // Строка 4 Справа: Графа 9 (Организация, Y = 40..55 мм, высота 15 мм)
    if (tb.organization.isNotEmpty) {
      _drawCenteredText(
        canvas,
        tb.organization,
        Rect.fromLTRB(xCenterEnd + 1.0 * sheetZoom, yRow3 + 1.0 * sheetZoom, stampRect.right - 1.0 * sheetZoom, stampRect.bottom - 1.0 * sheetZoom),
        3.2 * sheetZoom,
        isBold: true,
      );
    }
  }

  void _drawActiveElementGrips(Canvas canvas, Rect paperRect, Rect frameRect) {
    Rect? targetRect;
    String? blockTitle;

    if (isViewportSelected || selectedSheetBlock == 'viewport') {
      targetRect = getViewportScreenRect(sheet: sheet, paperRect: paperRect, sheetZoom: sheetZoom);
      blockTitle = 'ВЭ: ${sheet.viewport.widthMm.round()} × ${sheet.viewport.heightMm.round()} мм';
    } else if (selectedSheetBlock == 'notes' && sheet.technicalRequirements != null) {
      targetRect = getTechnicalRequirementsScreenRect(sheet: sheet, paperRect: paperRect, frameRect: frameRect, sheetZoom: sheetZoom);
      final tt = sheet.technicalRequirements!;
      final w = tt.widthMm;
      final h = tt.heightMm;
      blockTitle = 'ТТ: ${w.round()} × ${h.round()} мм';
    } else if (selectedSheetBlock == 'act') {
      targetRect = getActAttachmentScreenRect(sheet: sheet, paperRect: paperRect, frameRect: frameRect, sheetZoom: sheetZoom);
      final tr = sheet.titleBlockData.topRightCorner;
      final w = tr.widthMm;
      final h = tr.heightMm;
      blockTitle = 'Акт: ${w.round()} × ${h.round()} мм';
    } else if (selectedSheetBlock == 'legend' && sheet.legend != null && sheet.legend!.isVisible) {
      targetRect = getLegendScreenRect(sheet: sheet, paperRect: paperRect, frameRect: frameRect, sheetZoom: sheetZoom);
      final leg = sheet.legend!;
      blockTitle = 'Обозначения: ${leg.widthMm.round()} × ${leg.heightMm.round()} мм';
    }

    if (targetRect == null) return;

    final selBorderPaint = Paint()
      ..color = const Color(0xFF1976D2).withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawRect(targetRect, selBorderPaint);

    final grips = {
      'nw': targetRect.topLeft,
      'n': Offset(targetRect.center.dx, targetRect.top),
      'ne': targetRect.topRight,
      'e': Offset(targetRect.right, targetRect.center.dy),
      'se': targetRect.bottomRight,
      's': Offset(targetRect.center.dx, targetRect.bottom),
      'sw': targetRect.bottomLeft,
      'w': Offset(targetRect.left, targetRect.center.dy),
    };

    const gripSize = 8.0;
    for (final entry in grips.entries) {
      final key = entry.key;
      final pt = entry.value;
      final gripRect = Rect.fromCenter(center: pt, width: gripSize, height: gripSize);

      final isGripActive = activeGrip == key;
      final fillPaint = Paint()
        ..color = isGripActive ? const Color(0xFF00E5FF) : const Color(0xFF1976D2)
        ..style = PaintingStyle.fill;
      final strokePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      canvas.drawRect(gripRect, fillPaint);
      canvas.drawRect(gripRect, strokePaint);
    }

    if (activeGrip != null && blockTitle != null) {
      _drawBadge(canvas, blockTitle, targetRect.topCenter.translate(-60, -26));
    }
  }

  void _drawArchiveField(Canvas canvas, Rect paperRect, Rect frameRect) {
    // Вертикальное размещение вдоль левого поля (20 мм)
    final arch = sheet.titleBlockData.archive;
    if (arch.invNumberPrimary.isEmpty && arch.invNumberReplaced.isEmpty) return;

    canvas.save();
    // Поворачиваем холст на 90° для вертикальных надписей
    canvas.translate(paperRect.left + (8.0 * sheetZoom), frameRect.bottom - (40.0 * sheetZoom));
    canvas.rotate(-math.pi / 2);

    if (arch.invNumberPrimary.isNotEmpty) {
      _drawText(canvas, 'Инв. № подл.: ${arch.invNumberPrimary} ${arch.invDatePrimary}', Offset.zero, 2.2 * sheetZoom);
    }
    if (arch.invNumberReplaced.isNotEmpty) {
      _drawText(canvas, 'Взам. инв. №: ${arch.invNumberReplaced}', Offset(0, 5.0 * sheetZoom), 2.2 * sheetZoom);
    }

    canvas.restore();
  }

  void _drawViewport(Canvas canvas, Rect paperRect) {
    final vp = sheet.viewport;
    final vpRectScreen = Rect.fromLTWH(
      paperRect.left + (vp.xMm * sheetZoom),
      paperRect.top + (vp.yMm * sheetZoom),
      vp.widthMm * sheetZoom,
      vp.heightMm * sheetZoom,
    );

    // Граница видового экрана
    if (isViewportFocused) {
      final activePaint = Paint()
        ..color = const Color(0xFF1976D2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawRect(vpRectScreen, activePaint);

      // Бейдж активного видового экрана
      final scaleBadge = ViewportTransformService.formatScaleText(vp.viewScale);
      _drawBadge(canvas, '[Фокус видового экрана | $scaleBadge]', vpRectScreen.topLeft.translate(4, 4));
    } else {
      // Тонкая пунктирная нейтральная рамка
      final borderPaint = Paint()
        ..color = const Color(0xFFB0BEC5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawRect(vpRectScreen, borderPaint);
    }

    // Клиппирование области видового экрана
    canvas.save();
    canvas.clipRect(vpRectScreen);

    // Отрисовка трубопроводной сети внутри видового экрана
    _paintNetworkInViewport(canvas, vp);

    canvas.restore();
  }

  void _paintNetworkInViewport(Canvas canvas, SheetViewport vp) {
    final vpProjector = ViewportTransformService.createViewportProjector(
      viewport: vp,
      sheetPanPx: sheetPan,
      sheetZoom: sheetZoom,
      projectionType: projectionType,
    );

    for (final seg in network.segments.values) {
      final isVisible = vp.visibleSystemIds == null || vp.visibleSystemIds!.contains(seg.systemId);
      if (!isVisible && !vp.ghostInactiveSystems) {
        continue;
      }

      final n1 = network.nodes[seg.startNodeId];
      final n2 = network.nodes[seg.endNodeId];
      if (n1 == null || n2 == null) continue;

      final raw1 = vpProjector.projectRaw(n1.x, n1.y, n1.z);
      final raw2 = vpProjector.projectRaw(n2.x, n2.y, n2.z);

      final p1SheetMm = ViewportTransformService.model2dToSheetMm(raw1, vp);
      final p2SheetMm = ViewportTransformService.model2dToSheetMm(raw2, vp);

      final p1Screen = ViewportTransformService.sheetMmToScreen(p1SheetMm, sheetPan, sheetZoom);
      final p2Screen = ViewportTransformService.sheetMmToScreen(p2SheetMm, sheetPan, sheetZoom);

      final sys = network.systems[seg.systemId];
      final baseColor = sys != null ? Color(sys.colorValue) : const Color(0xFF1976D2);
      final strokeColor = isVisible ? baseColor : const Color(0xFFB0BEC5).withValues(alpha: 0.5);

      final pipePaint = Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, (isVisible ? styleConfig.pipeLineWidthMm : styleConfig.thinLineWidthMm) * sheetZoom);

      canvas.drawLine(p1Screen, p2Screen, pipePaint);

      // Подпись диаметра трубы
      if (isVisible) {
        final mid = Offset((p1Screen.dx + p2Screen.dx) / 2.0, (p1Screen.dy + p2Screen.dy) / 2.0);
        _drawText(
          canvas,
          'Ду${seg.dn}',
          mid.translate(0, -5.0 * sheetZoom),
          styleConfig.textHeightSmallMm * sheetZoom,
          color: strokeColor,
        );
      }
    }

    // Отрисовка сварных стыков
    for (final joint in network.weldJoints.values) {
      final seg = network.segments[joint.segmentId];
      if (seg == null) continue;
      final isVisible = vp.visibleSystemIds == null || vp.visibleSystemIds!.contains(seg.systemId);
      if (!isVisible) continue;

      final n1 = network.nodes[seg.startNodeId];
      final n2 = network.nodes[seg.endNodeId];
      if (n1 == null || n2 == null) continue;

      final pos = joint.calculatePosition(n1, n2);
      final raw = vpProjector.projectRaw(pos.x, pos.y, pos.z);
      final pSheetMm = ViewportTransformService.model2dToSheetMm(raw, vp);
      final pScreen = ViewportTransformService.sheetMmToScreen(pSheetMm, sheetPan, sheetZoom);

      // Засечка сварного стыка
      final weldPaint = Paint()
        ..color = const Color(0xFFE53935)
        ..strokeWidth = math.max(1.0, styleConfig.thinLineWidthMm * sheetZoom);
      canvas.drawCircle(pScreen, 2.5 * sheetZoom, weldPaint);
    }

    // Отрисовка умных выносок (Callout) и отметок уровня на видовом экране
    CalloutPainter.paint(
      canvas,
      vpProjector,
      network,
      templates: null,
      annotationScale: (sheetZoom * 0.85).clamp(0.6, 3.0),
    );

    // Отрисовка линейных размеров по ГОСТ 2.307
    DimensionPainter.paint(
      canvas,
      vpProjector,
      network,
      annotationScale: (sheetZoom * 0.85).clamp(0.6, 3.0),
    );
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    double fontSize, {
    bool isBold = false,
    bool isItalic = false,
    Color color = Colors.black,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: math.max(6.0, fontSize),
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
          fontFamily: styleConfig.fontFamily == 'Roboto' ? 'Roboto' : null,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, offset);
  }

  void _drawBadge(Canvas canvas, String label, Offset offset) {
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    final bgRect = Rect.fromLTWH(offset.dx, offset.dy, tp.width + 12, tp.height + 6);
    final bgPaint = Paint()..color = const Color(0xFF1976D2);
    canvas.drawRRect(RRect.fromRectAndRadius(bgRect, const Radius.circular(4)), bgPaint);
    tp.paint(canvas, offset.translate(6, 3));
  }

  void _drawCenteredText(
    Canvas canvas,
    String text,
    Rect rect,
    double fontSize, {
    bool isBold = false,
    Color color = Colors.black,
  }) {
    if (text.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: math.max(4.0, fontSize),
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          fontFamily: styleConfig.fontFamily == 'Roboto' ? 'Roboto' : null,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    tp.layout(maxWidth: rect.width);
    final offset = Offset(
      rect.left + math.max(0.0, (rect.width - tp.width) / 2.0),
      rect.top + math.max(0.0, (rect.height - tp.height) / 2.0),
    );
    tp.paint(canvas, offset);
  }

  void _drawMultilineText(
    Canvas canvas,
    String text,
    Rect rect,
    double fontSize, {
    bool isBold = false,
    TextAlign textAlign = TextAlign.left,
    Color color = Colors.black,
  }) {
    if (text.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: math.max(4.0, fontSize),
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          fontFamily: styleConfig.fontFamily == 'Roboto' ? 'Roboto' : null,
        ),
      ),
      textAlign: textAlign,
      textDirection: TextDirection.ltr,
      maxLines: 4,
      ellipsis: '...',
    );
    tp.layout(maxWidth: math.max(10.0, rect.width));
    final double offsetX = textAlign == TextAlign.center
        ? rect.left + math.max(0.0, (rect.width - tp.width) / 2.0)
        : rect.left;
    final offset = Offset(offsetX, rect.top + math.max(0.0, (rect.height - tp.height) / 2.0));
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant SheetCanvasPainter oldDelegate) {
    return oldDelegate.sheet != sheet ||
        oldDelegate.network != network ||
        oldDelegate.sheetZoom != sheetZoom ||
        oldDelegate.sheetPan != sheetPan ||
        oldDelegate.isViewportFocused != isViewportFocused ||
        oldDelegate.isViewportSelected != isViewportSelected ||
        oldDelegate.selectedSheetBlock != selectedSheetBlock ||
        oldDelegate.activeGrip != activeGrip ||
        oldDelegate.projectionType != projectionType ||
        oldDelegate.styleConfig != styleConfig;
  }
}
