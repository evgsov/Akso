import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/math/axonometry_projector.dart';
import '../../domain/enums/projection_type.dart';
import '../../domain/models/drawing_sheet.dart';
import '../../domain/models/drawing_style_config.dart';
import '../../domain/models/piping_network.dart';
import '../../domain/models/title_block_data.dart';
import '../../domain/services/viewport_transform_service.dart';

/// Интерактивный CustomPainter для отображения листа бумаги по ГОСТ 21.101-2020,
/// рамок 20-5-5-5 мм, штампа 185х55 мм, примечаний ТТ и клиппированного видового экрана
class SheetCanvasPainter extends CustomPainter {
  final DrawingSheet sheet;
  final PipingNetwork network;
  final double sheetZoom;
  final Offset sheetPan;
  final bool isViewportFocused;
  final bool isViewportSelected;
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
    _drawTopRightCorner(canvas, frameRect);

    // 7. Поле подшивки слева (Инв. № подл., Взам. инв. №)
    _drawArchiveField(canvas, paperRect, frameRect);

    // 8. Блок Технических требований (ТТ) над штампом
    if (sheet.technicalRequirements != null && sheet.technicalRequirements!.text.isNotEmpty) {
      _drawTechnicalRequirements(canvas, frameRect);
    }

    // 9. Основная надпись (штамп 185х55 мм в правом нижнем углу с непрозрачной белой подложкой)
    _drawTitleBlock(canvas, frameRect);

    // 10. Подпись формата листа за пределами рамки (напр. "Формат А3")
    _drawSheetFormatLabel(canvas, frameRect, paperRect);

    // 11. Интерактивные CAD-ручки (AutoCAD Grips) видового экрана в пространстве листа
    if (!isViewportFocused) {
      _drawViewportGrips(canvas, paperRect);
    }
  }

  void _drawPaperWithShadow(Canvas canvas, Rect paperRect) {
    // Тень листа
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawRect(paperRect.shift(const Offset(4, 6)), shadowPaint);

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

  void _drawTopRightCorner(Canvas canvas, Rect frameRect) {
    final tr = sheet.titleBlockData.topRightCorner;
    final text = tr.formattedText;
    if (text.isEmpty) return;

    final lines = text.split('\n');
    final lineH = 3.6 * sheetZoom;
    final boxH = (lines.length * lineH) + (4.0 * sheetZoom);
    final maxLen = lines.fold<int>(0, (prev, line) => math.max(prev, line.length));
    final boxW = math.max(60.0 * sheetZoom, (maxLen * 2.2 * sheetZoom) + (10.0 * sheetZoom));

    final boxRect = Rect.fromLTWH(
      frameRect.right - boxW,
      frameRect.top,
      boxW,
      boxH,
    );

    // Белая подложка
    canvas.drawRect(boxRect, Paint()..color = Colors.white);

    // Рамка по контуру
    final borderPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.5, styleConfig.thinLineWidthMm * sheetZoom);
    canvas.drawRect(boxRect, borderPaint);

    double curY = boxRect.top + (2.0 * sheetZoom);
    for (final line in lines) {
      _drawCenteredText(canvas, line, Rect.fromLTWH(boxRect.left, curY, boxRect.width, lineH), 2.2 * sheetZoom);
      curY += lineH;
    }
  }

  void _drawTechnicalRequirements(Canvas canvas, Rect frameRect) {
    final tt = sheet.technicalRequirements!;
    final stampW = 185.0 * sheetZoom;
    final stampH = 55.0 * sheetZoom;
    final ttBottom = frameRect.bottom - stampH - (5.0 * sheetZoom);

    final lines = tt.text.split('\n');
    final startY = ttBottom - (lines.length * 4.2 * sheetZoom) - (6.0 * sheetZoom);

    // Непрозрачная белая подложка под ТТ
    final bgRect = Rect.fromLTRB(
      frameRect.right - stampW,
      startY - (2.0 * sheetZoom),
      frameRect.right,
      ttBottom,
    );
    canvas.drawRect(bgRect, Paint()..color = Colors.white);

    _drawText(
      canvas,
      'Технические требования:',
      Offset(frameRect.right - stampW + (2.0 * sheetZoom), startY),
      2.8 * sheetZoom,
      isBold: true,
    );

    double y = startY + (4.5 * sheetZoom);
    for (final line in lines) {
      _drawText(
        canvas,
        line,
        Offset(frameRect.right - stampW + (2.0 * sheetZoom), y),
        2.5 * sheetZoom,
      );
      y += 3.8 * sheetZoom;
    }
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

    // Непрозрачная белая подложка штампа (чтобы линии модели не просвечивали)
    final bgPaint = Paint()..color = Colors.white;
    canvas.drawRect(stampRect, bgPaint);

    // Внешняя рамка штампа
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

    // Основной вертикальный разделитель: 65 мм слева (блок согласований/изменений)
    final xApprovalsEnd = stampRect.left + (65.0 * sheetZoom);
    canvas.drawLine(Offset(xApprovalsEnd, stampRect.top), Offset(xApprovalsEnd, stampRect.bottom), borderPaint);

    // --- ЛЕВЫЙ БЛОК (0..65 мм) ---
    // 1. Верхняя строка: Таблица регистрации изменений (Изм. | Кол.уч | Лист | № док. | Подп. | Дата)
    final yRevHeader = stampRect.top + (5.0 * sheetZoom);
    canvas.drawLine(Offset(stampRect.left, yRevHeader), Offset(xApprovalsEnd, yRevHeader), borderPaint);

    final xRevIzm = stampRect.left + (10.0 * sheetZoom);
    final xRevKol = stampRect.left + (20.0 * sheetZoom);
    final xRevList = stampRect.left + (30.0 * sheetZoom);
    final xRevDoc = stampRect.left + (45.0 * sheetZoom);
    final xRevSign = stampRect.left + (55.0 * sheetZoom);

    canvas.drawLine(Offset(xRevIzm, stampRect.top), Offset(xRevIzm, yRevHeader), gridPaint);
    canvas.drawLine(Offset(xRevKol, stampRect.top), Offset(xRevKol, yRevHeader), gridPaint);
    canvas.drawLine(Offset(xRevList, stampRect.top), Offset(xRevList, yRevHeader), gridPaint);
    canvas.drawLine(Offset(xRevDoc, stampRect.top), Offset(xRevDoc, yRevHeader), gridPaint);
    canvas.drawLine(Offset(xRevSign, stampRect.top), Offset(xRevSign, yRevHeader), gridPaint);

    _drawCenteredText(canvas, 'Изм.', Rect.fromLTRB(stampRect.left, stampRect.top, xRevIzm, yRevHeader), 1.8 * sheetZoom);
    _drawCenteredText(canvas, 'Кол.уч', Rect.fromLTRB(xRevIzm, stampRect.top, xRevKol, yRevHeader), 1.8 * sheetZoom);
    _drawCenteredText(canvas, 'Лист', Rect.fromLTRB(xRevKol, stampRect.top, xRevList, yRevHeader), 1.8 * sheetZoom);
    _drawCenteredText(canvas, '№ док.', Rect.fromLTRB(xRevList, stampRect.top, xRevDoc, yRevHeader), 1.8 * sheetZoom);
    _drawCenteredText(canvas, 'Подп.', Rect.fromLTRB(xRevDoc, stampRect.top, xRevSign, yRevHeader), 1.8 * sheetZoom);
    _drawCenteredText(canvas, 'Дата', Rect.fromLTRB(xRevSign, stampRect.top, xApprovalsEnd, yRevHeader), 1.8 * sheetZoom);

    // 2. Строки согласований (от yRevHeader до низа штампа, 10 строк по 5 мм)
    final xRole = stampRect.left + (17.0 * sheetZoom);
    final xName = stampRect.left + (40.0 * sheetZoom);
    final xSign = stampRect.left + (55.0 * sheetZoom);

    canvas.drawLine(Offset(xRole, yRevHeader), Offset(xRole, stampRect.bottom), gridPaint);
    canvas.drawLine(Offset(xName, yRevHeader), Offset(xName, stampRect.bottom), gridPaint);
    canvas.drawLine(Offset(xSign, yRevHeader), Offset(xSign, stampRect.bottom), gridPaint);

    for (int i = 1; i <= 9; i++) {
      final y = yRevHeader + (i * 5.0 * sheetZoom);
      canvas.drawLine(Offset(stampRect.left, y), Offset(xApprovalsEnd, y), gridPaint);
    }

    // Заполнение строк согласований
    final tb = sheet.titleBlockData;
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
      final y = yRevHeader + (i * 5.0 * sheetZoom) + (1.2 * sheetZoom);
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
    // Строка 1: Графа 4 (Шифр проекта / Обозначение документа, напр. 09/2025-НВК)
    // Высота 15 мм, на ВСЮ ширину 120 мм от 65 до 185 мм
    final yRow1 = stampRect.top + (15.0 * sheetZoom);
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

    // Строка 2: Графа 1 (Наименование объекта строительства)
    // Высота 15 мм, на ВСЮ ширину 120 мм от 65 до 185 мм (y: 15..30 мм)
    final yRow2 = stampRect.top + (30.0 * sheetZoom);
    canvas.drawLine(Offset(xApprovalsEnd, yRow2), Offset(stampRect.right, yRow2), borderPaint);

    if (tb.projectName.isNotEmpty) {
      _drawMultilineText(
        canvas,
        tb.projectName,
        Rect.fromLTRB(xApprovalsEnd + 2.0 * sheetZoom, yRow1 + 1.5 * sheetZoom, stampRect.right - 2.0 * sheetZoom, yRow2 - 1.5 * sheetZoom),
        2.6 * sheetZoom,
      );
    }

    // Разделитель центральной части (70 мм) и правого столбца (50 мм):
    // От yRow2 (30 мм) до низа штампа (55 мм)
    final xCenterEnd = stampRect.left + (135.0 * sheetZoom);
    canvas.drawLine(Offset(xCenterEnd, yRow2), Offset(xCenterEnd, stampRect.bottom), borderPaint);

    // Горизонтальный разделитель строк 3 и 4 при Y = 42.5 мм
    final yRow3 = stampRect.top + (42.5 * sheetZoom);
    canvas.drawLine(Offset(xApprovalsEnd, yRow3), Offset(stampRect.right, yRow3), borderPaint);

    // Строка 3 Слева: Графа 2 (Наименование здания / сооружения / этап)
    if (tb.buildingName.isNotEmpty) {
      _drawMultilineText(
        canvas,
        tb.buildingName,
        Rect.fromLTRB(xApprovalsEnd + 2.0 * sheetZoom, yRow2 + 1.5 * sheetZoom, xCenterEnd - 2.0 * sheetZoom, yRow3 - 1.5 * sheetZoom),
        2.8 * sheetZoom,
      );
    }

    // Строка 3 Справа: Стадия | Лист | Листов (50 мм)
    // Шапка 5 мм
    final yStageHeader = yRow2 + (5.0 * sheetZoom);
    canvas.drawLine(Offset(xCenterEnd, yStageHeader), Offset(stampRect.right, yStageHeader), gridPaint);

    final xStage = xCenterEnd + (15.0 * sheetZoom);
    final xSheet = xCenterEnd + (30.0 * sheetZoom);
    canvas.drawLine(Offset(xStage, yRow2), Offset(xStage, yRow3), gridPaint);
    canvas.drawLine(Offset(xSheet, yRow2), Offset(xSheet, yRow3), gridPaint);

    _drawCenteredText(canvas, 'Стадия', Rect.fromLTRB(xCenterEnd, yRow2, xStage, yStageHeader), 1.8 * sheetZoom);
    _drawCenteredText(canvas, 'Лист', Rect.fromLTRB(xStage, yRow2, xSheet, yStageHeader), 1.8 * sheetZoom);
    _drawCenteredText(canvas, 'Листов', Rect.fromLTRB(xSheet, yRow2, stampRect.right, yStageHeader), 1.8 * sheetZoom);

    _drawCenteredText(canvas, tb.stage, Rect.fromLTRB(xCenterEnd, yStageHeader, xStage, yRow3), 3.2 * sheetZoom, isBold: true);
    _drawCenteredText(canvas, tb.sheetNumber.toString(), Rect.fromLTRB(xStage, yStageHeader, xSheet, yRow3), 3.2 * sheetZoom, isBold: true);
    _drawCenteredText(canvas, tb.totalSheets.toString(), Rect.fromLTRB(xSheet, yStageHeader, stampRect.right, yRow3), 3.2 * sheetZoom, isBold: true);

    // Строка 4 Слева: Графа 3 (Наименование схемы / чертежа)
    if (tb.drawingTitle.isNotEmpty) {
      _drawMultilineText(
        canvas,
        tb.drawingTitle,
        Rect.fromLTRB(xApprovalsEnd + 2.0 * sheetZoom, yRow3 + 1.5 * sheetZoom, xCenterEnd - 2.0 * sheetZoom, stampRect.bottom - 1.0 * sheetZoom),
        2.8 * sheetZoom,
        isBold: true,
      );
    }

    // Строка 4 Справа: Графа 5 (Организация, напр. ООО "СтарКом")
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

  void _drawViewportGrips(Canvas canvas, Rect paperRect) {
    if (!isViewportSelected && activeGrip == null) return;

    final vp = sheet.viewport;
    final vpRectScreen = Rect.fromLTWH(
      paperRect.left + (vp.xMm * sheetZoom),
      paperRect.top + (vp.yMm * sheetZoom),
      vp.widthMm * sheetZoom,
      vp.heightMm * sheetZoom,
    );

    // Тонкая синяя пунктирная/сплошная рамка вокруг выбранного ВЭ в пространстве листа
    final selBorderPaint = Paint()
      ..color = const Color(0xFF1976D2).withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawRect(vpRectScreen, selBorderPaint);

    final grips = {
      'nw': vpRectScreen.topLeft,
      'n': Offset(vpRectScreen.center.dx, vpRectScreen.top),
      'ne': vpRectScreen.topRight,
      'e': Offset(vpRectScreen.right, vpRectScreen.center.dy),
      'se': vpRectScreen.bottomRight,
      's': Offset(vpRectScreen.center.dx, vpRectScreen.bottom),
      'sw': vpRectScreen.bottomLeft,
      'w': Offset(vpRectScreen.left, vpRectScreen.center.dy),
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

    // Если активен drag ручки или выделен ВЭ — бейдж с физическими размерами
    if (activeGrip != null) {
      final dimBadge = 'ВЭ: ${vp.widthMm.round()} × ${vp.heightMm.round()} мм';
      _drawBadge(canvas, dimBadge, vpRectScreen.topCenter.translate(-60, -26));
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
    final projector = AxonometryProjector(projectionType: projectionType);

    for (final seg in network.segments.values) {
      final isVisible = vp.visibleSystemIds == null || vp.visibleSystemIds!.contains(seg.systemId);
      if (!isVisible && !vp.ghostInactiveSystems) {
        continue;
      }

      final n1 = network.nodes[seg.startNodeId];
      final n2 = network.nodes[seg.endNodeId];
      if (n1 == null || n2 == null) continue;

      final raw1 = projector.projectRaw(n1.x, n1.y, n1.z);
      final raw2 = projector.projectRaw(n2.x, n2.y, n2.z);

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
      final raw = projector.projectRaw(pos.x, pos.y, pos.z);
      final pSheetMm = ViewportTransformService.model2dToSheetMm(raw, vp);
      final pScreen = ViewportTransformService.sheetMmToScreen(pSheetMm, sheetPan, sheetZoom);

      // Засечка сварного стыка
      final weldPaint = Paint()
        ..color = const Color(0xFFE53935)
        ..strokeWidth = math.max(1.0, styleConfig.thinLineWidthMm * sheetZoom);
      canvas.drawCircle(pScreen, 2.5 * sheetZoom, weldPaint);
    }
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
      textDirection: TextDirection.ltr,
      maxLines: 4,
      ellipsis: '...',
    );
    tp.layout(maxWidth: math.max(10.0, rect.width));
    final offset = Offset(rect.left, rect.top + math.max(0.0, (rect.height - tp.height) / 2.0));
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
        oldDelegate.activeGrip != activeGrip ||
        oldDelegate.projectionType != projectionType;
  }
}
