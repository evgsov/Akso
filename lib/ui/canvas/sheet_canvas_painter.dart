import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/math/axonometry_projector.dart';
import '../../domain/enums/projection_type.dart';
import '../../domain/models/drawing_legend.dart';
import '../../domain/models/drawing_sheet.dart';
import '../../domain/models/drawing_style_config.dart';
import '../../domain/models/linear_dimension.dart';
import '../../domain/models/node_3d.dart';
import '../../domain/models/pipe_segment.dart';
import '../../domain/models/pipe_support.dart';
import '../../domain/models/piping_network.dart';
import '../../domain/models/piping_system.dart';
import '../../domain/models/title_block_data.dart';
import '../../domain/models/valve.dart';
import '../../domain/models/custom_valve_definition.dart';
import '../../domain/models/detail_node.dart';
import '../../domain/models/fitting.dart';
import '../../domain/services/callout_layout_engine.dart';
import '../../domain/services/sheet_geometry_builder.dart';
import '../../domain/services/viewport_transform_service.dart';
import 'painters/annotation_painter.dart';
import 'painters/callout_painter.dart';
import 'painters/dimension_painter.dart';
import 'painters/equipment_painter.dart';
import 'painters/fitting_painter.dart';
import 'painters/pipe_painter.dart';
import 'painters/support_painter.dart';
import 'painters/valve_painter.dart';

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
  final Map<String, CustomValveDefinition>? customValves;

  // Полноценные свойства отображения модели внутри видового экрана
  final bool isVolumeMode;
  final bool isCenterlineMode;
  final bool showWelds;
  final bool showCallouts;
  final Map<String, String>? calloutTemplates;
  final String? selectedNodeId;
  final Set<String>? selectedNodeIds;
  final String? selectedSegmentId;
  final Set<String>? selectedSegmentIds;
  final String? selectedEquipmentId;
  final Set<String>? selectedEquipmentIds;
  final String? selectedValveId;
  final String? selectedSupportId;
  final String? selectedWeldId;
  final String? selectedSpoolId;
  final Set<String>? selectedSpoolIds;
  final String? selectedDimensionId;
  final Set<String>? selectedDimensionIds;
  final LinearDimension? previewDimension;
  final String? selectedCalloutId;
  final String? selectedDetailNodeId;
  final double orbitAzimuth;
  final double orbitElevation;
  final Node3D targetCenter;

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
    this.customValves,
    this.isVolumeMode = false,
    this.isCenterlineMode = false,
    this.showWelds = true,
    this.showCallouts = true,
    this.calloutTemplates,
    this.selectedNodeId,
    this.selectedNodeIds,
    this.selectedSegmentId,
    this.selectedSegmentIds,
    this.selectedEquipmentId,
    this.selectedEquipmentIds,
    this.selectedValveId,
    this.selectedSupportId,
    this.selectedWeldId,
    this.selectedSpoolId,
    this.selectedSpoolIds,
    this.selectedDimensionId,
    this.selectedDimensionIds,
    this.previewDimension,
    this.selectedCalloutId,
    this.selectedDetailNodeId,
    this.orbitAzimuth = -math.pi / 4,
    this.orbitElevation = math.pi / 6,
    this.targetCenter = const Node3D(id: 'center', x: 0, y: 0, z: 0),
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

    // 12. Отладочный визуальный слой препятствий для выносок (Debug Obstacle Overlay)
    if (sheet.debugShowObstacles) {
      _drawDebugObstacles(canvas, paperRect);
    }
  }

  void _drawDebugObstacles(Canvas canvas, Rect paperRect) {
    final baseProjector = AxonometryProjector(
      projectionType: projectionType,
      orbitAzimuth: orbitAzimuth,
      orbitElevation: orbitElevation,
      targetCenter: targetCenter,
    );

    final obstacleMap = CalloutObstacleMap.buildSheetMap(
      sheet: sheet,
      network: network,
      projector: baseProjector,
    );

    // 1. Отрисовка коридоров трубопроводов (красные полупрозрачные полосы шириной 2.0 мм)
    final pipePaint = Paint()
      ..color = const Color(0x66F44336)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final pipe in obstacleMap.pipes) {
      final p1 = Offset(
        paperRect.left + pipe.p1.dx * sheetZoom,
        paperRect.top + pipe.p1.dy * sheetZoom,
      );
      final p2 = Offset(
        paperRect.left + pipe.p2.dx * sheetZoom,
        paperRect.top + pipe.p2.dy * sheetZoom,
      );
      pipePaint.strokeWidth = math.max(2.0, pipe.radius * 2.0 * sheetZoom);
      canvas.drawLine(p1, p2, pipePaint);
    }

    // 2. Отрисовка прямоугольников препятствий (штамп, таблицы, элементы, выноски)
    final stampFill = Paint()
      ..color = const Color(0x359C27B0)
      ..style = PaintingStyle.fill;
    final stampStroke = Paint()
      ..color = const Color(0xAA9C27B0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final elementFill = Paint()
      ..color = const Color(0x40FFC107)
      ..style = PaintingStyle.fill;
    final elementStroke = Paint()
      ..color = const Color(0xAAFF9800)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final calloutFill = Paint()
      ..color = const Color(0x3003A9F4)
      ..style = PaintingStyle.fill;
    final calloutStroke = Paint()
      ..color = const Color(0x8803A9F4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (final obs in obstacleMap.rects) {
      final r = Rect.fromLTRB(
        paperRect.left + obs.rect.left * sheetZoom,
        paperRect.top + obs.rect.top * sheetZoom,
        paperRect.left + obs.rect.right * sheetZoom,
        paperRect.top + obs.rect.bottom * sheetZoom,
      );

      final isStampOrTable = obs.id != null &&
          (obs.id == 'stamp' || obs.id!.startsWith('table_') || obs.id == 'tech_reqs');
      final isCallout = obs.id != null && obs.id!.startsWith('callout_');

      if (isStampOrTable) {
        canvas.drawRect(r, stampFill);
        canvas.drawRect(r, stampStroke);
      } else if (isCallout) {
        canvas.drawRect(r, calloutFill);
        canvas.drawRect(r, calloutStroke);
      } else {
        canvas.drawRect(r, elementFill);
        canvas.drawRect(r, elementStroke);
      }
    }

    // 3. Отрисовка зарегистрированных стрелок и полок выносок
    final leaderPaint = Paint()
      ..color = const Color(0x994CAF50)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final line in obstacleMap.leaderLines) {
      final p1 = Offset(
        paperRect.left + line.p1.dx * sheetZoom,
        paperRect.top + line.p1.dy * sheetZoom,
      );
      final p2 = Offset(
        paperRect.left + line.p2.dx * sheetZoom,
        paperRect.top + line.p2.dy * sheetZoom,
      );
      canvas.drawLine(p1, p2, leaderPaint);
    }

    // 4. Информационный бейдж в верхнем левом углу
    final badgeBg = Paint()..color = const Color(0xDD263238);
    final badgeRect = Rect.fromLTWH(paperRect.left + 10, paperRect.top + 10, 240, 22);
    canvas.drawRRect(RRect.fromRectAndRadius(badgeRect, const Radius.circular(4)), badgeBg);

    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'DEBUG: Сетка препятствий выносок',
        style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(paperRect.left + 16, paperRect.top + 14));
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

    // Отрисовка трубопроводной сети внутри видового экрана с полным графическим соответствием модели
    _paintNetworkInViewport(canvas, vp, vpRectScreen.size);

    canvas.restore();
  }

  void _paintNetworkInViewport(Canvas canvas, SheetViewport vp, Size vpSize) {
    final vpProjector = ViewportTransformService.createViewportProjector(
      viewport: vp,
      sheetPanPx: sheetPan,
      sheetZoom: sheetZoom,
      projectionType: projectionType,
      orbitAzimuth: orbitAzimuth,
      orbitElevation: orbitElevation,
      targetCenter: targetCenter,
    );

    final effectiveNetwork = _getEffectiveNetwork(network, vp);

    // 1. Призрак неактивных систем (если включено vp.ghostInactiveSystems и задан фильтр систем)
    if (vp.ghostInactiveSystems && vp.visibleSystemIds != null && vp.visibleSystemIds!.isNotEmpty) {
      _paintGhostInactiveSystems(canvas, vpSize, vpProjector, vp);
    }

    // 1.5. На листе детального узла — примыкающие отрезки основной магистрали с линией обрыва
    if (sheet.detailNodeId != null) {
      final dn = network.detailNodes[sheet.detailNodeId];
      if (dn != null && dn.showContextStubs) {
        _paintDetailContextStubs(canvas, vpProjector, dn);
      }
    }

    // 2. Строительные оси здания
    _drawConstructionAxesInViewport(canvas, vpProjector, effectiveNetwork);

    // 3. Технологическое оборудование и штуцеры
    EquipmentPainter.paint(
      canvas,
      vpProjector,
      effectiveNetwork,
      selectedEquipmentId: isViewportFocused ? selectedEquipmentId : null,
      selectedEquipmentIds: isViewportFocused ? selectedEquipmentIds : null,
      selectedNodeId: isViewportFocused ? selectedNodeId : null,
      styleConfig: styleConfig,
      sheetZoom: sheetZoom,
    );

    // 4. Отрисовка труб (сегментов)
    final screenPoints = <String, Offset>{};
    for (final node in effectiveNetwork.nodes.values) {
      screenPoints[node.id] = vpProjector.project(node);
    }

    PipePainter.paint(
      canvas,
      vpSize,
      vpProjector,
      effectiveNetwork,
      isViewportFocused ? selectedSegmentId : null,
      null,
      screenPoints,
      showCallouts,
      isVolumeMode,
      isViewportFocused ? selectedSegmentIds : null,
      isCenterlineMode,
      isViewportFocused ? selectedSpoolId : null,
      isViewportFocused ? selectedSpoolIds : null,
      false,
      0.0,
      styleConfig,
      sheetZoom,
      customValves,
    );

    // 5. Отрисовка арматуры
    ValvePainter.paint(
      canvas,
      vpProjector,
      effectiveNetwork,
      isVolumeMode: isVolumeMode,
      selectedValveId: isViewportFocused ? selectedValveId : null,
      styleConfig: styleConfig,
      sheetZoom: sheetZoom,
      customValves: customValves,
    );

    // 6. Отрисовка опор и подвесок
    SupportPainter.paint(
      canvas,
      vpProjector,
      effectiveNetwork,
      isVolumeMode: isVolumeMode,
      selectedSupportId: isViewportFocused ? selectedSupportId : null,
      styleConfig: styleConfig,
      sheetZoom: sheetZoom,
    );

    // 7. Отрисовка фасонных деталей (отводы, тройники, переходы, фланцы, заглушки)
    FittingPainter.paint(
      canvas,
      vpProjector,
      effectiveNetwork,
      isViewportFocused ? selectedNodeId : null,
      showCallouts,
      isVolumeMode: isVolumeMode,
      styleConfig: styleConfig,
      sheetZoom: sheetZoom,
    );

    // 8. Отрисовка сварных стыков по ГОСТ и отметок
    AnnotationPainter.paint(
      canvas,
      vpProjector,
      effectiveNetwork,
      isViewportFocused ? selectedNodeId : null,
      showWelds,
      showCallouts,
      selectedWeldId: isViewportFocused ? selectedWeldId : null,
      styleConfig: styleConfig,
      sheetZoom: sheetZoom,
    );

    // 9. Отрисовка умных выносок (Callout)
    if (showCallouts) {
      CalloutPainter.paint(
        canvas,
        vpProjector,
        effectiveNetwork,
        templates: calloutTemplates,
        selectedCalloutId: selectedCalloutId,
        annotationScale: sheetZoom,
        isPaperSpace: true,
        activeSheetId: sheet.id,
      );
    }

    // 10. Отрисовка линейных размеров по ГОСТ 2.307
    DimensionPainter.paint(
      canvas,
      vpProjector,
      effectiveNetwork,
      previewDimension: isViewportFocused ? previewDimension : null,
      selectedDimensionId: isViewportFocused ? selectedDimensionId : null,
      selectedDimensionIds: isViewportFocused ? selectedDimensionIds : null,
      annotationScale: (sheetZoom * 0.85).clamp(0.6, 3.0),
    );

    // 10.5. На обзорных листах — контуры и полки выносных узлов (DetailNode) + CAD-ручки
    if (sheet.detailNodeId == null && network.detailNodes.isNotEmpty) {
      _paintDetailNodeBoundaries(canvas, vp);
    }

    // 11. Подсветка группы выбранных элементов в активном видовом экране
    if (isViewportFocused && selectedNodeIds != null && selectedNodeIds!.length > 1) {
      final multiGlow = Paint()
        ..color = Colors.amber.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill;
      final multiRing = Paint()
        ..color = Colors.amber.shade700
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      for (final nId in selectedNodeIds!) {
        final n = effectiveNetwork.nodes[nId];
        if (n != null) {
          final pt = vpProjector.project(n);
          canvas.drawCircle(pt, 8.0, multiGlow);
          canvas.drawCircle(pt, 5.0, multiRing);
        }
      }
    }
  }

  Offset _mmToScreen(Offset ptMm) {
    return Offset(
      sheetPan.dx + ptMm.dx * sheetZoom,
      sheetPan.dy + ptMm.dy * sheetZoom,
    );
  }

  Rect _rectMmToScreen(Rect rMm) {
    return Rect.fromLTRB(
      sheetPan.dx + rMm.left * sheetZoom,
      sheetPan.dy + rMm.top * sheetZoom,
      sheetPan.dx + rMm.right * sheetZoom,
      sheetPan.dy + rMm.bottom * sheetZoom,
    );
  }

  void _paintDetailContextStubs(
    Canvas canvas,
    AxonometryProjector vpProjector,
    DetailNode dn,
  ) {
    final stubs = network.getDetailNodeAdjacentStubs(dn);
    if (stubs.isEmpty) return;

    final stubPaint = Paint()
      ..color = const Color(0xFF78909C)
      ..strokeWidth = math.max(1.2, 0.35 * sheetZoom)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final breakPaint = Paint()
      ..color = const Color(0xFF546E7A)
      ..strokeWidth = math.max(1.0, 0.25 * sheetZoom)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final stub in stubs) {
      final p1 = vpProjector.project(stub.boundaryNode);
      final p2 = vpProjector.project(stub.cutEndPoint);
      final diff = p2 - p1;
      final len = diff.distance;
      if (len < 2.0) continue;

      _drawDashedLine(canvas, p1, p2, stubPaint);

      final dir = diff / len;
      final perp = Offset(-dir.dy, dir.dx);
      final halfSpan = 3.2 * sheetZoom;
      final zigAmp = 1.3 * sheetZoom;
      final zigStep = 0.85 * sheetZoom;

      final b0 = p2 - perp * halfSpan;
      final b1 = p2 - perp * zigStep;
      final b2 = p2 - perp * (zigStep * 0.35) + dir * zigAmp;
      final b3 = p2 + perp * (zigStep * 0.35) - dir * zigAmp;
      final b4 = p2 + perp * zigStep;
      final b5 = p2 + perp * halfSpan;

      final path = Path()
        ..moveTo(b0.dx, b0.dy)
        ..lineTo(b1.dx, b1.dy)
        ..lineTo(b2.dx, b2.dy)
        ..lineTo(b3.dx, b3.dy)
        ..lineTo(b4.dx, b4.dy)
        ..lineTo(b5.dx, b5.dy);
      canvas.drawPath(path, breakPaint);
    }
  }

  void _paintDetailNodeBoundaries(Canvas canvas, SheetViewport vp) {
    final baseProjector = AxonometryProjector(
      projectionType: projectionType,
      orbitAzimuth: orbitAzimuth,
      orbitElevation: orbitElevation,
      targetCenter: targetCenter,
    );

    for (final dn in network.detailNodes.values) {
      final geom = SheetGeometryBuilder.computeDetailNodeSheetGeometry(
        detailNode: dn,
        network: network,
        viewport: vp,
        projector: baseProjector,
      );
      if (geom == null) continue;

      final isSelected = selectedDetailNodeId == dn.id;
      final contourColor = isSelected ? const Color(0xFF0288D1) : Colors.black87;
      final contourStroke = Paint()
        ..color = contourColor
        ..strokeWidth = math.max(1.0, (isSelected ? 0.45 : 0.30) * sheetZoom)
        ..style = PaintingStyle.stroke;

      final screenBounds = _rectMmToScreen(geom.boundsMm);

      if (isSelected) {
        final fillPaint = Paint()
          ..color = const Color(0x140288D1)
          ..style = PaintingStyle.fill;
        switch (dn.boundaryShape) {
          case DetailBoundaryShape.circle:
            final center = _mmToScreen(geom.centerMm);
            final r = math.max(geom.boundsMm.width, geom.boundsMm.height) / 2.0 * sheetZoom;
            canvas.drawCircle(center, r, fillPaint);
            canvas.drawCircle(center, r, contourStroke);
            break;
          case DetailBoundaryShape.oval:
            canvas.drawOval(screenBounds, fillPaint);
            canvas.drawOval(screenBounds, contourStroke);
            break;
          case DetailBoundaryShape.roundedRect:
            final r = math.min(10.0, math.min(geom.boundsMm.width, geom.boundsMm.height) * 0.22) * sheetZoom;
            final rrect = RRect.fromRectAndRadius(screenBounds, Radius.circular(r));
            canvas.drawRRect(rrect, fillPaint);
            canvas.drawRRect(rrect, contourStroke);
            break;
          case DetailBoundaryShape.polygon:
            final verts = geom.polygonVerticesMm;
            if (verts.length >= 3) {
              final path = Path()..moveTo(_mmToScreen(verts.first).dx, _mmToScreen(verts.first).dy);
              for (int i = 1; i < verts.length; i++) {
                final pt = _mmToScreen(verts[i]);
                path.lineTo(pt.dx, pt.dy);
              }
              path.close();
              canvas.drawPath(path, fillPaint);
              canvas.drawPath(path, contourStroke);
            }
            break;
        }
      } else {
        switch (dn.boundaryShape) {
          case DetailBoundaryShape.circle:
            final center = _mmToScreen(geom.centerMm);
            final r = math.max(geom.boundsMm.width, geom.boundsMm.height) / 2.0 * sheetZoom;
            canvas.drawCircle(center, r, contourStroke);
            break;
          case DetailBoundaryShape.oval:
            canvas.drawOval(screenBounds, contourStroke);
            break;
          case DetailBoundaryShape.roundedRect:
            final r = math.min(10.0, math.min(geom.boundsMm.width, geom.boundsMm.height) * 0.22) * sheetZoom;
            final rrect = RRect.fromRectAndRadius(screenBounds, Radius.circular(r));
            canvas.drawRRect(rrect, contourStroke);
            break;
          case DetailBoundaryShape.polygon:
            final verts = geom.polygonVerticesMm;
            if (verts.length >= 3) {
              final path = Path()..moveTo(_mmToScreen(verts.first).dx, _mmToScreen(verts.first).dy);
              for (int i = 1; i < verts.length; i++) {
                final pt = _mmToScreen(verts[i]);
                path.lineTo(pt.dx, pt.dy);
              }
              path.close();
              canvas.drawPath(path, contourStroke);
            }
            break;
        }
      }

      // Линия-выноска и полка "Узел А / Лист N"
      final attachPx = _mmToScreen(geom.leaderAttachMm);
      final shelfStartPx = _mmToScreen(geom.shelfStartMm);
      final shelfEndPx = _mmToScreen(geom.shelfEndMm);
      final shelfRectPx = _rectMmToScreen(geom.shelfHitRectMm);

      // Белая подложка под полку для читаемости
      canvas.drawRRect(
        RRect.fromRectAndRadius(shelfRectPx, const Radius.circular(2)),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.88)
          ..style = PaintingStyle.fill,
      );
      if (isSelected) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(shelfRectPx, const Radius.circular(2)),
          Paint()
            ..color = const Color(0xFF0288D1).withValues(alpha: 0.6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0,
        );
      }

      canvas.drawLine(attachPx, shelfStartPx, contourStroke);
      canvas.drawLine(shelfStartPx, shelfEndPx, contourStroke);

      final leftX = math.min(shelfStartPx.dx, shelfEndPx.dx) + 1.2 * sheetZoom;
      final topFontSize = styleConfig.textHeightSmallMm * 1.15 * sheetZoom;
      final botFontSize = styleConfig.textHeightSmallMm * 0.95 * sheetZoom;

      _drawText(
        canvas,
        geom.topText,
        Offset(leftX, shelfStartPx.dy - topFontSize - 1.0 * sheetZoom),
        topFontSize,
        isBold: true,
        color: isSelected ? const Color(0xFF01579B) : Colors.black,
      );
      _drawText(
        canvas,
        geom.bottomText,
        Offset(leftX, shelfStartPx.dy + 0.8 * sheetZoom),
        botFontSize,
        color: isSelected ? const Color(0xFF0277BD) : const Color(0xFF263238),
      );

      // Отрисовка интерактивных ручек (Grips) при выборе узла
      if (isSelected) {
        final gripFill = Paint()
          ..color = const Color(0xFF0288D1)
          ..style = PaintingStyle.fill;
        final gripStroke = Paint()
          ..color = Colors.white
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke;
        final midGripFill = Paint()
          ..color = const Color(0xFF00BCD4)
          ..style = PaintingStyle.fill;

        // 1. Ручка перетаскивания полки
        final shelfGripRect = Rect.fromCenter(center: shelfStartPx, width: 8.0, height: 8.0);
        canvas.drawRect(shelfGripRect, gripFill);
        canvas.drawRect(shelfGripRect, gripStroke);

        // 2. Ручки контура
        if (dn.boundaryShape == DetailBoundaryShape.polygon) {
          final verts = geom.polygonVerticesMm;
          for (int i = 0; i < verts.length; i++) {
            final vPx = _mmToScreen(verts[i]);
            final vNextPx = _mmToScreen(verts[(i + 1) % verts.length]);
            final midPx = Offset((vPx.dx + vNextPx.dx) / 2.0, (vPx.dy + vNextPx.dy) / 2.0);

            // Середина ребра (кружок для добавления новой вершины)
            canvas.drawCircle(midPx, 3.8, midGripFill);
            canvas.drawCircle(midPx, 3.8, gripStroke);

            // Вершина многоугольника (квадрат)
            final vRect = Rect.fromCenter(center: vPx, width: 7.5, height: 7.5);
            canvas.drawRect(vRect, gripFill);
            canvas.drawRect(vRect, gripStroke);
          }
        } else {
          // Ручка отступа (padding) на правом нижнем углу контура
          final padGripPx = screenBounds.bottomRight;
          final padRect = Rect.fromCenter(center: padGripPx, width: 7.5, height: 7.5);
          canvas.drawRect(padRect, gripFill);
          canvas.drawRect(padRect, gripStroke);
        }
      }
    }
  }

  PipingNetwork _getEffectiveNetwork(PipingNetwork baseNetwork, SheetViewport vp) {
    return sheet.getEffectiveNetwork(baseNetwork);
  }

  void _paintGhostInactiveSystems(
    Canvas canvas,
    Size vpSize,
    AxonometryProjector vpProjector,
    SheetViewport vp,
  ) {
    final visibleSys = vp.visibleSystemIds!;
    final inactiveSegs = Map<String, PipeSegment>.fromEntries(
      network.segments.entries.where((e) => !visibleSys.contains(e.value.systemId)),
    );
    if (inactiveSegs.isEmpty) return;

    final inactiveSegIds = inactiveSegs.keys.toSet();
    final inactiveValves = Map<String, Valve>.fromEntries(
      network.valves.entries.where((e) => inactiveSegIds.contains(e.value.segmentId)),
    );
    final inactiveSupports = Map<String, PipeSupport>.fromEntries(
      network.supports.entries.where((e) => inactiveSegIds.contains(e.value.segmentId)),
    );
    final inactiveFittings = Map<String, Fitting>.fromEntries(
      network.fittings.entries.where((e) => network.getConnectedSegments(e.value.nodeId).any((s) => inactiveSegIds.contains(s.id))),
    );

    const ghostSystem = PipingSystem(
      id: '__ghost__',
      code: 'GHOST',
      name: 'Ghost',
      colorValue: 0x4090A4AE,
      dxfAciColor: 8,
    );
    final ghostSystems = <String, PipingSystem>{
      for (final sId in network.systems.keys)
        sId: const PipingSystem(
          id: '__ghost__',
          code: 'GHOST',
          name: 'Ghost',
          colorValue: 0x4090A4AE,
          dxfAciColor: 8,
        ),
      '__ghost__': ghostSystem,
    };

    final ghostNetwork = network.copyWith(
      segments: inactiveSegs,
      valves: inactiveValves,
      supports: inactiveSupports,
      fittings: inactiveFittings,
      systems: ghostSystems,
      weldJoints: {},
      spools: {},
    );

    final ghostScreenPoints = <String, Offset>{};
    for (final node in ghostNetwork.nodes.values) {
      ghostScreenPoints[node.id] = vpProjector.project(node);
    }

    PipePainter.paint(
      canvas,
      vpSize,
      vpProjector,
      ghostNetwork,
      null,
      null,
      ghostScreenPoints,
      false,
      false,
      null,
      false,
      null,
      null,
      false,
      0.0,
      styleConfig,
      sheetZoom,
    );

    ValvePainter.paint(
      canvas,
      vpProjector,
      ghostNetwork,
      isVolumeMode: false,
      styleConfig: styleConfig,
      sheetZoom: sheetZoom,
      customValves: customValves,
    );

    SupportPainter.paint(
      canvas,
      vpProjector,
      ghostNetwork,
      isVolumeMode: false,
      styleConfig: styleConfig,
      sheetZoom: sheetZoom,
    );

    FittingPainter.paint(
      canvas,
      vpProjector,
      ghostNetwork,
      null,
      false,
      isVolumeMode: false,
      styleConfig: styleConfig,
      sheetZoom: sheetZoom,
    );
  }

  void _drawConstructionAxesInViewport(
    Canvas canvas,
    AxonometryProjector vpProjector,
    PipingNetwork net,
  ) {
    if (net.axes.isEmpty) return;
    final scale = (sheetZoom * 0.85).clamp(0.6, 2.0);

    for (final axis in net.axes.values) {
      final p1 = vpProjector.project(axis.startPoint);
      final p2 = vpProjector.project(axis.endPoint);

      final axisPaint = Paint()
        ..color = const Color(0xFF78909C)
        ..strokeWidth = math.max(0.5, styleConfig.axisLineWidthMm * sheetZoom)
        ..style = PaintingStyle.stroke;

      _drawDashedLine(canvas, p1, p2, axisPaint);

      if (axis.isBuildingGrid && axis.label.isNotEmpty) {
        _drawGridBubble(canvas, p1, axis.label, scale: scale);
        _drawGridBubble(canvas, p2, axis.label, scale: scale);
      }
    }
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    final dist = (p2 - p1).distance;
    if (dist <= 0) return;
    final unit = (p2 - p1) / dist;
    double current = 0.0;
    bool draw = true;
    while (current < dist) {
      final step = draw ? 12.0 : 6.0;
      final next = math.min(current + step, dist);
      if (draw) {
        canvas.drawLine(p1 + unit * current, p1 + unit * next, paint);
      }
      current = next;
      draw = !draw;
    }
  }

  void _drawGridBubble(Canvas canvas, Offset center, String label, {double scale = 1.0}) {
    final r = 12.0 * scale;
    canvas.drawCircle(center, r, Paint()..color = Colors.white..style = PaintingStyle.fill);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = const Color(0xFF546E7A)
        ..strokeWidth = math.max(1.0, 1.4 * scale)
        ..style = PaintingStyle.stroke,
    );

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: const Color(0xFF37474F),
          fontSize: math.max(6.0, 10.0 * scale),
          fontWeight: FontWeight.bold,
          fontFamily: styleConfig.fontFamily == 'Roboto' ? 'Roboto' : null,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
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
  bool shouldRepaint(covariant SheetCanvasPainter oldDelegate) => true;
}
