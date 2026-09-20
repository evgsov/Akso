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
  final ProjectionType projectionType;
  final DrawingStyleConfig styleConfig;

  SheetCanvasPainter({
    required this.sheet,
    required this.network,
    required this.sheetZoom,
    required this.sheetPan,
    this.isViewportFocused = false,
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

    _drawGostFrame(canvas, frameRect);

    // 3. Основная надпись (штамп 185х55 мм в правом нижнем углу)
    _drawTitleBlock(canvas, frameRect);

    // 4. Поле подшивки слева (Инв. № подл., Взам. инв. №)
    _drawArchiveField(canvas, paperRect, frameRect);

    // 5. Правый верхний угол (Приложение к акту / Графа 26)
    _drawTopRightCorner(canvas, frameRect);

    // 6. Блок Технических требований (ТТ) над штампом
    if (sheet.technicalRequirements != null && sheet.technicalRequirements!.text.isNotEmpty) {
      _drawTechnicalRequirements(canvas, frameRect);
    }

    // 7. Видовой экран (Viewport) с клиппированием и прорисовкой сети
    _drawViewport(canvas, paperRect);
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

  void _drawTitleBlock(Canvas canvas, Rect frameRect) {
    final stampW = 185.0 * sheetZoom;
    final stampH = 55.0 * sheetZoom;
    final stampRect = Rect.fromLTWH(
      frameRect.right - stampW,
      frameRect.bottom - stampH,
      stampW,
      stampH,
    );

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

    // Вертикальные разделители:
    // 1. Колонки согласований (всего 65 мм): Роль 17мм, ФИО 23мм, Подпись 15мм, Дата 10мм
    final xRole = stampRect.left + (17.0 * sheetZoom);
    final xName = stampRect.left + (40.0 * sheetZoom);
    final xSign = stampRect.left + (55.0 * sheetZoom);
    final xApprovalsEnd = stampRect.left + (65.0 * sheetZoom);

    // 2. Разделитель правого блока: 135 мм от левого края штампа (50 мм на стадию/лист/орг)
    final xCenterEnd = stampRect.left + (135.0 * sheetZoom);

    canvas.drawLine(Offset(xRole, stampRect.top), Offset(xRole, stampRect.bottom), gridPaint);
    canvas.drawLine(Offset(xName, stampRect.top), Offset(xName, stampRect.bottom), gridPaint);
    canvas.drawLine(Offset(xSign, stampRect.top), Offset(xSign, stampRect.bottom), gridPaint);
    canvas.drawLine(Offset(xApprovalsEnd, stampRect.top), Offset(xApprovalsEnd, stampRect.bottom), borderPaint);
    canvas.drawLine(Offset(xCenterEnd, stampRect.top), Offset(xCenterEnd, stampRect.bottom), borderPaint);

    // Горизонтальные строки согласований (по 5 мм снизу)
    for (int i = 1; i <= 8; i++) {
      final y = stampRect.bottom - (i * 5.0 * sheetZoom);
      if (y > stampRect.top) {
        canvas.drawLine(Offset(stampRect.left, y), Offset(xApprovalsEnd, y), gridPaint);
      }
    }

    // Разделители правого блока (Стадия 15мм, Лист 15мм, Листов 20мм)
    final yStageHeader = stampRect.top + (5.0 * sheetZoom);
    final yStageValues = stampRect.top + (20.0 * sheetZoom);
    canvas.drawLine(Offset(xCenterEnd, yStageHeader), Offset(stampRect.right, yStageHeader), gridPaint);
    canvas.drawLine(Offset(xCenterEnd, yStageValues), Offset(stampRect.right, yStageValues), borderPaint);

    final xStage = xCenterEnd + (15.0 * sheetZoom);
    final xSheet = xCenterEnd + (30.0 * sheetZoom);
    canvas.drawLine(Offset(xStage, stampRect.top), Offset(xStage, yStageValues), gridPaint);
    canvas.drawLine(Offset(xSheet, stampRect.top), Offset(xSheet, yStageValues), gridPaint);

    // Графа 4 (Шифр проекта): верхняя половина центрального блока (высота 15 мм)
    final yCodeLine = stampRect.top + (15.0 * sheetZoom);
    canvas.drawLine(Offset(xApprovalsEnd, yCodeLine), Offset(xCenterEnd, yCodeLine), gridPaint);

    // Графы 1, 2, 3: горизонтальные строки по 15 мм
    final yObjLine = stampRect.top + (30.0 * sheetZoom);
    final yBuildingLine = stampRect.top + (40.0 * sheetZoom);
    canvas.drawLine(Offset(xApprovalsEnd, yObjLine), Offset(xCenterEnd, yObjLine), gridPaint);
    canvas.drawLine(Offset(xApprovalsEnd, yBuildingLine), Offset(xCenterEnd, yBuildingLine), gridPaint);

    // Отрисовка текстов штампа
    final tb = sheet.titleBlockData;

    // Согласования (Разраб, Пров, ГИП...)
    final roles = ['Разраб.', 'Пров.', 'Т.контр.', '', 'ГИП', 'Н.контр.', 'Утв.'];
    for (int i = 0; i < roles.length; i++) {
      final role = roles[i];
      if (role.isEmpty) continue;
      final y = stampRect.bottom - ((roles.length - i) * 5.0 * sheetZoom) + (1.2 * sheetZoom);
      _drawText(canvas, role, Offset(stampRect.left + 1.5 * sheetZoom, y), 2.2 * sheetZoom, isBold: false);

      // Ищем фамилию в approvals
      final app = tb.approvals.firstWhere((a) => a.role == role, orElse: () => const TitleBlockApproval(role: '', name: ''));
      if (app.name.isNotEmpty) {
        _drawText(canvas, app.name, Offset(xRole + 1.5 * sheetZoom, y), 2.2 * sheetZoom);
      }
      if (app.date.isNotEmpty) {
        _drawText(canvas, app.date, Offset(xSign + 1.0 * sheetZoom, y), 2.0 * sheetZoom);
      }
    }

    // Шифр проекта (Графа 4)
    if (tb.documentCode.isNotEmpty) {
      _drawText(
        canvas,
        tb.documentCode,
        Offset(xApprovalsEnd + 4.0 * sheetZoom, stampRect.top + 3.5 * sheetZoom),
        4.5 * sheetZoom,
        isBold: true,
      );
    }

    // Наименование объекта (Графа 1)
    if (tb.projectName.isNotEmpty) {
      _drawText(
        canvas,
        tb.projectName,
        Offset(xApprovalsEnd + 2.5 * sheetZoom, yCodeLine + 2.5 * sheetZoom),
        3.0 * sheetZoom,
      );
    }

    // Наименование здания (Графа 2)
    if (tb.buildingName.isNotEmpty) {
      _drawText(
        canvas,
        tb.buildingName,
        Offset(xApprovalsEnd + 2.5 * sheetZoom, yObjLine + 2.5 * sheetZoom),
        3.0 * sheetZoom,
      );
    }

    // Наименование схемы (Графа 3)
    if (tb.drawingTitle.isNotEmpty) {
      _drawText(
        canvas,
        tb.drawingTitle,
        Offset(xApprovalsEnd + 2.5 * sheetZoom, yBuildingLine + 3.0 * sheetZoom),
        3.5 * sheetZoom,
        isBold: true,
      );
    }

    // Правый блок: Заголовки "Стадия", "Лист", "Листов"
    _drawText(canvas, 'Стадия', Offset(xCenterEnd + 2.0 * sheetZoom, stampRect.top + 1.0 * sheetZoom), 1.8 * sheetZoom);
    _drawText(canvas, 'Лист', Offset(xStage + 3.0 * sheetZoom, stampRect.top + 1.0 * sheetZoom), 1.8 * sheetZoom);
    _drawText(canvas, 'Листов', Offset(xSheet + 4.0 * sheetZoom, stampRect.top + 1.0 * sheetZoom), 1.8 * sheetZoom);

    // Значения
    _drawText(canvas, tb.stage, Offset(xCenterEnd + 4.5 * sheetZoom, yStageHeader + 3.0 * sheetZoom), 3.5 * sheetZoom, isBold: true);
    _drawText(canvas, tb.sheetNumber.toString(), Offset(xStage + 5.0 * sheetZoom, yStageHeader + 3.0 * sheetZoom), 3.5 * sheetZoom, isBold: true);
    _drawText(canvas, tb.totalSheets.toString(), Offset(xSheet + 7.0 * sheetZoom, yStageHeader + 3.0 * sheetZoom), 3.5 * sheetZoom, isBold: true);

    // Графа 5 (Организация)
    if (tb.organization.isNotEmpty) {
      _drawText(
        canvas,
        tb.organization,
        Offset(xCenterEnd + 3.0 * sheetZoom, yStageValues + 5.0 * sheetZoom),
        3.2 * sheetZoom,
        isBold: true,
      );
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

  void _drawTopRightCorner(Canvas canvas, Rect frameRect) {
    final tr = sheet.titleBlockData.topRightCorner;
    final text = tr.formattedText;
    if (text.isEmpty) return;

    final lines = text.split('\n');
    double curY = frameRect.top + (4.0 * sheetZoom);
    for (final line in lines) {
      _drawText(
        canvas,
        line,
        Offset(frameRect.right - (line.length * 2.5 * sheetZoom) - (5.0 * sheetZoom), curY),
        2.5 * sheetZoom,
        isItalic: true,
      );
      curY += 4.0 * sheetZoom;
    }
  }

  void _drawTechnicalRequirements(Canvas canvas, Rect frameRect) {
    final tt = sheet.technicalRequirements!;
    final stampW = 185.0 * sheetZoom;
    final stampH = 55.0 * sheetZoom;
    final ttBottom = frameRect.bottom - stampH - (5.0 * sheetZoom);

    final lines = tt.text.split('\n');
    final startY = ttBottom - (lines.length * 4.2 * sheetZoom) - (6.0 * sheetZoom);

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

  @override
  bool shouldRepaint(covariant SheetCanvasPainter oldDelegate) {
    return oldDelegate.sheet != sheet ||
        oldDelegate.network != network ||
        oldDelegate.sheetZoom != sheetZoom ||
        oldDelegate.sheetPan != sheetPan ||
        oldDelegate.isViewportFocused != isViewportFocused ||
        oldDelegate.projectionType != projectionType;
  }
}
