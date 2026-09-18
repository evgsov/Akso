import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../core/math/axonometry_projector.dart';
import '../../../domain/models/callout.dart';
import '../../../domain/models/node_3d.dart';
import '../../../domain/models/piping_network.dart';
import '../../../domain/models/project_model.dart';

/// Отрисовщик умных выносок (Callout) на аксонометрическом холсте
/// с экранным автовыравниванием по ГОСТ 2.316 / ГОСТ 21.101.
class CalloutPainter {
  final PipingNetwork network;
  final AxonometryProjector projector;
  final ProjectModel? project;
  final Map<String, String>? templates;
  final String? selectedCalloutId;

  const CalloutPainter({
    required this.network,
    required this.projector,
    this.project,
    this.templates,
    this.selectedCalloutId,
  });

  /// Отрисовка всех выносок через экземпляр класса
  void paintCallouts(Canvas canvas) {
    paint(
      canvas,
      projector,
      network,
      project: project,
      templates: templates ?? project?.calloutTemplates,
      selectedCalloutId: selectedCalloutId,
    );
  }

  /// Статический метод отрисовки умных выносок сети
  static void paint(
    Canvas canvas,
    AxonometryProjector projector,
    PipingNetwork network, {
    ProjectModel? project,
    Map<String, String>? templates,
    String? selectedCalloutId,
  }) {
    if (network.callouts.isEmpty) return;

    final effectiveTemplates = templates ?? project?.calloutTemplates ?? defaultCalloutTemplates;

    for (final callout in network.callouts.values) {
      final anchor3D = getTarget3DPoint(network, callout);
      if (anchor3D == null) continue;

      final anchorScreen = projector.project(anchor3D);
      final isSelected = callout.id == selectedCalloutId;

      _paintSingleCallout(
        canvas,
        network,
        callout,
        anchorScreen,
        effectiveTemplates,
        isSelected,
      );
    }
  }

  /// Вычисляет абсолютную 3D-точку привязки для выноски:
  /// - для узла — координаты узла;
  /// - для сегмента — геометрическая середина сегмента;
  /// - для арматуры/стыка/опоры — положение на сегменте по ratio;
  /// - для оборудования — центр оборудования.
  static Node3D? getTarget3DPoint(PipingNetwork network, Callout callout) {
    switch (callout.targetType) {
      case CalloutTargetType.node:
        return network.nodes[callout.targetId];

      case CalloutTargetType.segment:
        // 1. Проверяем, не привязана ли выноска напрямую к физической катушке
        final spool = network.spools[callout.targetId];
        if (spool != null && spool.startPoint != null && spool.endPoint != null) {
          return Node3D(
            id: 'anchor_${callout.id}',
            x: (spool.startPoint!.x + spool.endPoint!.x) / 2.0,
            y: (spool.startPoint!.y + spool.endPoint!.y) / 2.0,
            z: (spool.startPoint!.z + spool.endPoint!.z) / 2.0,
          );
        }

        final seg = network.segments[callout.targetId];
        if (seg == null) return null;

        // 2. Если выноска привязана к сегменту, у которого ровно одна катушка —
        // привязываем стрелку к геометрической середине физической трубы катушки
        final segSpools = network.spools.values.where((s) => s.segmentId == seg.id).toList();
        if (segSpools.length == 1 &&
            segSpools.first.startPoint != null &&
            segSpools.first.endPoint != null) {
          final s = segSpools.first;
          return Node3D(
            id: 'anchor_${callout.id}',
            x: (s.startPoint!.x + s.endPoint!.x) / 2.0,
            y: (s.startPoint!.y + s.endPoint!.y) / 2.0,
            z: (s.startPoint!.z + s.endPoint!.z) / 2.0,
          );
        }

        // 3. Иначе привязываем к середине осевой линии сегмента
        final start = network.nodes[seg.startNodeId];
        final end = network.nodes[seg.endNodeId];
        if (start == null || end == null) return null;
        return Node3D(
          id: 'anchor_${callout.id}',
          x: (start.x + end.x) / 2.0,
          y: (start.y + end.y) / 2.0,
          z: (start.z + end.z) / 2.0,
        );

      case CalloutTargetType.valve:
        final valve = network.valves[callout.targetId];
        if (valve == null) return null;
        final seg = network.segments[valve.segmentId];
        if (seg == null) return null;
        final start = network.nodes[seg.startNodeId];
        final end = network.nodes[seg.endNodeId];
        if (start == null || end == null) return null;
        return Node3D(
          id: 'anchor_${callout.id}',
          x: start.x + (end.x - start.x) * valve.ratio,
          y: start.y + (end.y - start.y) * valve.ratio,
          z: start.z + (end.z - start.z) * valve.ratio,
        );

      case CalloutTargetType.weld:
        final weld = network.weldJoints[callout.targetId];
        if (weld == null) return null;
        final seg = network.segments[weld.segmentId];
        if (seg == null) return null;
        final start = network.nodes[seg.startNodeId];
        final end = network.nodes[seg.endNodeId];
        if (start == null || end == null) return null;
        return Node3D(
          id: 'anchor_${callout.id}',
          x: start.x + (end.x - start.x) * weld.ratio,
          y: start.y + (end.y - start.y) * weld.ratio,
          z: start.z + (end.z - start.z) * weld.ratio,
        );

      case CalloutTargetType.support:
        final sup = network.supports[callout.targetId];
        if (sup == null) return null;
        final seg = network.segments[sup.segmentId];
        if (seg == null) return null;
        final start = network.nodes[seg.startNodeId];
        final end = network.nodes[seg.endNodeId];
        if (start == null || end == null) return null;
        final r = sup.distanceRatio.clamp(0.0, 1.0);
        return Node3D(
          id: 'anchor_${callout.id}',
          x: start.x + (end.x - start.x) * r,
          y: start.y + (end.y - start.y) * r,
          z: start.z + (end.z - start.z) * r,
        );

      case CalloutTargetType.equipment:
        final eq = network.equipments[callout.targetId];
        if (eq == null) return null;
        return Node3D(
          id: 'anchor_${callout.id}',
          x: eq.x,
          y: eq.y,
          z: eq.z + eq.height / 2.0,
        );

      case CalloutTargetType.nozzle:
        final node = network.nodes[callout.targetId];
        if (node != null) return node;
        for (final eq in network.equipments.values) {
          for (final noz in eq.nozzles) {
            if (noz.id == callout.targetId) {
              final rad = eq.rotationAngleDeg * math.pi / 180.0;
              final cosA = math.cos(rad);
              final sinA = math.sin(rad);
              final wx = eq.x + noz.localX * cosA - noz.localY * sinA;
              final wy = eq.y + noz.localX * sinA + noz.localY * cosA;
              final wz = eq.z + noz.localZ;
              return Node3D(id: 'anchor_${callout.id}', x: wx, y: wy, z: wz);
            }
          }
        }
        return null;

      case CalloutTargetType.fitting:
        final fit = network.fittings[callout.targetId] ??
            network.fittings.values.where((f) => f.id == callout.targetId).firstOrNull;
        if (fit == null) return null;
        return network.nodes[fit.nodeId];
    }
  }

  /// Получение экранных границ (bounding box) текста и полочки выноски для hit-test
  static Rect? getCalloutBounds(
    PipingNetwork network,
    AxonometryProjector projector,
    Callout callout, {
    Map<String, String>? templates,
    ProjectModel? project,
  }) {
    final anchor3D = getTarget3DPoint(network, callout);
    if (anchor3D == null) return null;

    final anchorScreen = projector.project(anchor3D);
    final textPos = Offset(
      anchorScreen.dx + callout.screenOffsetX,
      anchorScreen.dy + callout.screenOffsetY,
    );

    final effectiveTemplates = templates ?? project?.calloutTemplates ?? defaultCalloutTemplates;
    final topText = network.generateCalloutText(callout, effectiveTemplates);
    final bottomText = network.generateCalloutBottomText(callout, effectiveTemplates);

    final topTp = TextPainter(
      text: TextSpan(
        text: topText,
        style: TextStyle(
          fontSize: callout.textHeight,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    double bottomHeight = 0.0;
    double maxTextWidth = topTp.width;
    if (bottomText != null && bottomText.trim().isNotEmpty) {
      final bottomTp = TextPainter(
        text: TextSpan(
          text: bottomText,
          style: TextStyle(
            fontSize: callout.textHeight * 0.9,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      bottomHeight = bottomTp.height + 4.0;
      maxTextWidth = math.max(maxTextWidth, bottomTp.width);
    }

    final isRight = callout.shelfDirection == ShelfDirection.right
        ? true
        : (callout.shelfDirection == ShelfDirection.left
            ? false
            : callout.screenOffsetX >= 0);

    if (callout.targetType == CalloutTargetType.node) {
      if (callout.arrowOnNode) {
        final shelfY = anchorScreen.dy + callout.screenOffsetY;
        final bgTop = shelfY - topTp.height - 4.0;
        final totalTextH = topTp.height + 4.0 + bottomHeight;
        final minY = math.min(bgTop, math.min(shelfY, anchorScreen.dy)) - 2.0;
        final maxY = math.max(bgTop + totalTextH, math.max(shelfY, anchorScreen.dy)) + 2.0;
        final shelfLength = maxTextWidth + 8.0;
        if (isRight) {
          return Rect.fromLTRB(
            anchorScreen.dx - 8.0,
            minY,
            anchorScreen.dx + shelfLength + 4.0,
            maxY,
          );
        } else {
          return Rect.fromLTRB(
            anchorScreen.dx - shelfLength - 4.0,
            minY,
            anchorScreen.dx + 8.0,
            maxY,
          );
        }
      }

      const flagH = 14.4;
      final shelfY = textPos.dy - flagH;
      final bgTop = shelfY - topTp.height - 4.0;
      final totalHeight = (textPos.dy - bgTop) + (bottomHeight > 0 ? bottomHeight : 4.0);
      if (isRight) {
        return Rect.fromLTWH(
          textPos.dx - 8.0,
          bgTop,
          maxTextWidth + 18.0,
          totalHeight,
        );
      } else {
        return Rect.fromLTWH(
          textPos.dx - maxTextWidth - 10.0,
          bgTop,
          maxTextWidth + 18.0,
          totalHeight,
        );
      }
    }

    final totalHeight = topTp.height + 6.0 + bottomHeight;
    if (isRight) {
      return Rect.fromLTWH(
        textPos.dx,
        textPos.dy - topTp.height - 4.0,
        maxTextWidth + 10.0,
        totalHeight,
      );
    } else {
      return Rect.fromLTWH(
        textPos.dx - maxTextWidth - 10.0,
        textPos.dy - topTp.height - 4.0,
        maxTextWidth + 10.0,
        totalHeight,
      );
    }
  }

  /// Проверка попадания клика в текст выноски (hit test)
  static String? hitTest(
    Offset screenPos,
    PipingNetwork network,
    AxonometryProjector projector, {
    Map<String, String>? templates,
    ProjectModel? project,
    double hitTolerance = 6.0,
  }) {
    // Проверяем в обратном порядке (верхние выноски первыми)
    final calloutList = network.callouts.values.toList().reversed;
    for (final callout in calloutList) {
      final bounds = getCalloutBounds(
        network,
        projector,
        callout,
        templates: templates,
        project: project,
      );
      if (bounds != null && bounds.inflate(hitTolerance).contains(screenPos)) {
        return callout.id;
      }
    }
    return null;
  }

  static void _paintSingleCallout(
    Canvas canvas,
    PipingNetwork network,
    Callout callout,
    Offset anchorScreen,
    Map<String, String> templates,
    bool isSelected,
  ) {
    final textPos = Offset(
      anchorScreen.dx + callout.screenOffsetX,
      anchorScreen.dy + callout.screenOffsetY,
    );

    final topText = network.generateCalloutText(callout, templates);
    final bottomText = network.generateCalloutBottomText(callout, templates);
    final isRight = callout.shelfDirection == ShelfDirection.right
        ? true
        : (callout.shelfDirection == ShelfDirection.left
            ? false
            : callout.screenOffsetX >= 0);

    final primaryColor = isSelected ? const Color(0xFF2563EB) : Color(callout.textColor);

    final linePaint = Paint()
      ..color = primaryColor
      ..strokeWidth = isSelected ? 2.0 : 1.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter;

    final topTp = TextPainter(
      text: TextSpan(
        text: topText,
        style: TextStyle(
          color: primaryColor,
          fontSize: callout.textHeight,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    TextPainter? bottomTp;
    if (bottomText != null && bottomText.trim().isNotEmpty) {
      bottomTp = TextPainter(
        text: TextSpan(
          text: bottomText,
          style: TextStyle(
            color: primaryColor.withValues(alpha: 0.9),
            fontSize: callout.textHeight * 0.9,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    }

    final maxTextWidth = math.max(topTp.width, bottomTp?.width ?? 0.0);
    final shelfLength = maxTextWidth + 8.0;
    final shelfEnd = Offset(
      isRight ? textPos.dx + shelfLength : textPos.dx - shelfLength,
      textPos.dy,
    );

    if (callout.targetType == CalloutTargetType.node) {
      final styleName = templates['elevation_style'];
      final defaultStyle = ElevationMarkStyleExt.fromString(styleName, fallback: ElevationMarkStyle.gostOutline);
      final effectiveStyle = callout.elevationStyle ?? defaultStyle;

      const flagSize = 8.0;
      final flagH = flagSize * 1.3;
      final flagW = flagSize * 0.75;

      if (callout.arrowOnNode) {
        // --- РЕЖИМ 1: Стрелка знака отметки установлена строго на узле (по ГОСТ 21.101) ---
        final shelfY = anchorScreen.dy + callout.screenOffsetY;
        final isAbove = shelfY <= anchorScreen.dy;
        final flagBaseY = isAbove ? anchorScreen.dy - flagH : anchorScreen.dy + flagH;

        switch (effectiveStyle) {
          case ElevationMarkStyle.gostOutline:
            final flagPath = Path()
              ..moveTo(anchorScreen.dx, anchorScreen.dy)
              ..lineTo(anchorScreen.dx - flagW, flagBaseY)
              ..lineTo(anchorScreen.dx + flagW, flagBaseY)
              ..close();
            canvas.drawPath(flagPath, linePaint);
            canvas.drawLine(Offset(anchorScreen.dx, flagBaseY), Offset(anchorScreen.dx, shelfY), linePaint);
            break;

          case ElevationMarkStyle.gostFilled:
            final flagPath = Path()
              ..moveTo(anchorScreen.dx, anchorScreen.dy)
              ..lineTo(anchorScreen.dx - flagW, flagBaseY)
              ..lineTo(anchorScreen.dx + flagW, flagBaseY)
              ..close();
            final fillPaint = Paint()
              ..color = primaryColor
              ..style = PaintingStyle.fill;
            canvas.drawPath(flagPath, fillPaint);
            canvas.drawPath(flagPath, linePaint);
            canvas.drawLine(Offset(anchorScreen.dx, flagBaseY), Offset(anchorScreen.dx, shelfY), linePaint);
            break;

          case ElevationMarkStyle.compactFlag:
            canvas.drawLine(anchorScreen, Offset(anchorScreen.dx, shelfY), linePaint);
            canvas.drawLine(
              Offset(anchorScreen.dx - 3.5, anchorScreen.dy + 3.5),
              Offset(anchorScreen.dx + 3.5, anchorScreen.dy - 3.5),
              linePaint,
            );
            break;

          case ElevationMarkStyle.isoCircle:
            const circleR = 4.5;
            final circlePaint = Paint()
              ..color = primaryColor
              ..strokeWidth = isSelected ? 2.0 : 1.2
              ..style = PaintingStyle.stroke;
            canvas.drawCircle(anchorScreen, circleR, circlePaint);
            canvas.drawLine(Offset(anchorScreen.dx - circleR, anchorScreen.dy), Offset(anchorScreen.dx + circleR, anchorScreen.dy), linePaint);
            canvas.drawLine(Offset(anchorScreen.dx, anchorScreen.dy - circleR), Offset(anchorScreen.dx, anchorScreen.dy + circleR), linePaint);
            final circleEdgeY = isAbove ? anchorScreen.dy - circleR : anchorScreen.dy + circleR;
            canvas.drawLine(Offset(anchorScreen.dx, circleEdgeY), Offset(anchorScreen.dx, shelfY), linePaint);
            break;
        }

        final shelfStart = Offset(anchorScreen.dx, shelfY);
        final shelfEnd = Offset(
          isRight ? anchorScreen.dx + shelfLength : anchorScreen.dx - shelfLength,
          shelfY,
        );

        final bgTop = shelfY - topTp.height - 4.0;
        final totalHeight = topTp.height + 4.0 + (bottomTp != null ? bottomTp.height + 4.0 : 0.0);
        final bgRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            isRight ? anchorScreen.dx : anchorScreen.dx - shelfLength,
            bgTop,
            shelfLength,
            totalHeight,
          ),
          const Radius.circular(2.0),
        );

        canvas.drawRRect(
          bgRect,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.92)
            ..style = PaintingStyle.fill,
        );

        canvas.drawLine(shelfStart, shelfEnd, linePaint);

        final textLeft = isRight ? anchorScreen.dx + 4.0 : anchorScreen.dx - shelfLength + 4.0;
        topTp.paint(canvas, Offset(textLeft, shelfY - topTp.height - 2.0));

        if (bottomTp != null) {
          bottomTp.paint(canvas, Offset(textLeft, shelfY + 2.0));
        }

        if (isSelected) {
          final borderPaint = Paint()
            ..color = const Color(0xFF2563EB).withValues(alpha: 0.75)
            ..strokeWidth = 1.2
            ..style = PaintingStyle.stroke;
          canvas.drawRRect(bgRect, borderPaint);

          final gripPaint = Paint()
            ..color = const Color(0xFF2563EB)
            ..style = PaintingStyle.fill;
          canvas.drawRect(
            Rect.fromCenter(center: shelfStart, width: 6.0, height: 6.0),
            gripPaint,
          );
        }
        return;
      }

      // --- РЕЖИМ 2: Стрелка на выносной ножке (со смещением от узла) ---
      final flagTopY = textPos.dy - flagH;
      final shelfY = effectiveStyle == ElevationMarkStyle.compactFlag
          ? textPos.dy - 12.0
          : flagTopY - 4.0;

      // 1. Выносная ножка от объекта к основанию стрелки отметки
      if ((anchorScreen - textPos).distance > 2.0) {
        canvas.drawLine(anchorScreen, textPos, linePaint);
      }

      // 2. Отрисовка знака отметки в соответствии со стилем
      switch (effectiveStyle) {
        case ElevationMarkStyle.gostOutline:
          final flagPath = Path()
            ..moveTo(textPos.dx, textPos.dy)
            ..lineTo(textPos.dx - flagW, flagTopY)
            ..lineTo(textPos.dx + flagW, flagTopY)
            ..close();
          canvas.drawPath(flagPath, linePaint);
          canvas.drawLine(Offset(textPos.dx, flagTopY), Offset(textPos.dx, shelfY), linePaint);
          break;

        case ElevationMarkStyle.gostFilled:
          final flagPath = Path()
            ..moveTo(textPos.dx, textPos.dy)
            ..lineTo(textPos.dx - flagW, flagTopY)
            ..lineTo(textPos.dx + flagW, flagTopY)
            ..close();
          final fillPaint = Paint()
            ..color = primaryColor
            ..style = PaintingStyle.fill;
          canvas.drawPath(flagPath, fillPaint);
          canvas.drawPath(flagPath, linePaint);
          canvas.drawLine(Offset(textPos.dx, flagTopY), Offset(textPos.dx, shelfY), linePaint);
          break;

        case ElevationMarkStyle.compactFlag:
          canvas.drawLine(textPos, Offset(textPos.dx, shelfY), linePaint);
          canvas.drawLine(
            Offset(textPos.dx - 3.5, textPos.dy + 3.5),
            Offset(textPos.dx + 3.5, textPos.dy - 3.5),
            linePaint,
          );
          break;

        case ElevationMarkStyle.isoCircle:
          const circleR = 4.5;
          final circlePaint = Paint()
            ..color = primaryColor
            ..strokeWidth = isSelected ? 2.0 : 1.2
            ..style = PaintingStyle.stroke;
          canvas.drawCircle(textPos, circleR, circlePaint);
          canvas.drawLine(Offset(textPos.dx - circleR, textPos.dy), Offset(textPos.dx + circleR, textPos.dy), linePaint);
          canvas.drawLine(Offset(textPos.dx, textPos.dy - circleR), Offset(textPos.dx, textPos.dy + circleR), linePaint);
          canvas.drawLine(Offset(textPos.dx, textPos.dy - circleR), Offset(textPos.dx, shelfY), linePaint);
          break;
      }

      // 3. Горизонтальная полочка
      final shelfEnd = Offset(
        isRight ? textPos.dx + shelfLength : textPos.dx - shelfLength,
        shelfY,
      );

      final bgTop = shelfY - topTp.height - 4.0;
      final totalHeight = topTp.height + 4.0 + (bottomTp != null ? bottomTp.height + 4.0 : 0.0);
      final bgRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          isRight ? textPos.dx : textPos.dx - shelfLength,
          bgTop,
          shelfLength,
          totalHeight,
        ),
        const Radius.circular(2.0),
      );

      canvas.drawRRect(
        bgRect,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.92)
          ..style = PaintingStyle.fill,
      );

      canvas.drawLine(Offset(textPos.dx, shelfY), shelfEnd, linePaint);

      final textLeft = isRight ? textPos.dx + 4.0 : textPos.dx - shelfLength + 4.0;
      topTp.paint(canvas, Offset(textLeft, shelfY - topTp.height - 2.0));

      if (bottomTp != null) {
        bottomTp.paint(canvas, Offset(textLeft, shelfY + 2.0));
      }

      if (isSelected) {
        final borderPaint = Paint()
          ..color = const Color(0xFF2563EB).withValues(alpha: 0.75)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke;
        canvas.drawRRect(bgRect, borderPaint);

        final gripPaint = Paint()
          ..color = const Color(0xFF2563EB)
          ..style = PaintingStyle.fill;
        canvas.drawRect(
          Rect.fromCenter(center: textPos, width: 6.0, height: 6.0),
          gripPaint,
        );
      }
      return;
    }

    // 1. Точка привязки (кружок на 3D объекте по ГОСТ)
    final dotPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(anchorScreen, 3.0, dotPaint);

    // 2. Наклонная линия-ножка от объекта до излома (textPos)
    canvas.drawLine(anchorScreen, textPos, linePaint);

    // 3. Фон для текста над и под полочкой (рисуем ДО линии полочки для четкости)
    final bgTop = textPos.dy - topTp.height - 4.0;
    final totalHeight = topTp.height + 4.0 + (bottomTp != null ? bottomTp.height + 4.0 : 0.0);
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        isRight ? textPos.dx : textPos.dx - shelfLength,
        bgTop,
        shelfLength,
        totalHeight,
      ),
      const Radius.circular(2.0),
    );

    canvas.drawRRect(
      bgRect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.92)
        ..style = PaintingStyle.fill,
    );

    // 4. Горизонтальная полочка выноски (поверх белой плашки по ГОСТ 2.316)
    canvas.drawLine(textPos, shelfEnd, linePaint);

    // Отрисовка текста над полочкой
    final textLeft = isRight ? textPos.dx + 4.0 : textPos.dx - shelfLength + 4.0;
    final textTop = textPos.dy - topTp.height - 2.0;
    topTp.paint(canvas, Offset(textLeft, textTop));

    // Отрисовка текста под полочкой (если есть)
    if (bottomTp != null) {
      final bottomTextTop = textPos.dy + 2.0;
      bottomTp.paint(canvas, Offset(textLeft, bottomTextTop));
    }

    // 5. Визуальный маркер выделения выноски (CAD handle/grip)
    if (isSelected) {
      final borderPaint = Paint()
        ..color = const Color(0xFF2563EB).withValues(alpha: 0.75)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      canvas.drawRRect(bgRect, borderPaint);

      // Ручка перетаскивания (Grip point) в точке излома
      final gripPaint = Paint()
        ..color = const Color(0xFF2563EB)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(textPos, 3.5, gripPaint);
      canvas.drawCircle(
        textPos,
        3.5,
        Paint()
          ..color = Colors.white
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke,
      );
    }
  }

  /// Вычисление единичного вектора нормали в плоскости экрана к трубе, примыкающей к узлу.
  /// Работает для прямых углов (90°), наклонных (45°, 30°) и произвольных уклонов.
  static Offset computeNodeNormalVector(
    PipingNetwork network,
    AxonometryProjector projector,
    String nodeId,
  ) {
    final connected = network.getConnectedSegments(nodeId);
    if (connected.isEmpty) {
      return const Offset(1.0, 0.0);
    }
    final seg = connected.first;
    final s = network.nodes[seg.startNodeId];
    final e = network.nodes[seg.endNodeId];
    if (s == null || e == null) {
      return const Offset(1.0, 0.0);
    }
    final p1 = projector.project(s);
    final p2 = projector.project(e);
    final v = Offset(p2.dx - p1.dx, p2.dy - p1.dy);
    final len = v.distance;
    if (len < 0.001) {
      return const Offset(1.0, 0.0);
    }
    var n = Offset(-v.dy / len, v.dx / len);
    if (n.dx < 0 || (n.dx == 0 && n.dy > 0)) {
      n = -n;
    }
    return n;
  }
}
