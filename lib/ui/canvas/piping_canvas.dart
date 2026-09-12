import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/math/axonometry_projector.dart';
import '../../core/math/snap_engine.dart';
import '../../domain/models/node_3d.dart';

import '../../domain/models/piping_network.dart';
import 'painters/grid_painter.dart';
import 'painters/pipe_painter.dart';
import 'painters/fitting_painter.dart';
import 'painters/valve_painter.dart';
import 'painters/annotation_painter.dart';



/// Данные о длине и угле отрезка трассировки для отображения в HUD
class TraceHudInfo {
  final double lengthMm;
  final int angleDegrees;
  final String text;

  const TraceHudInfo({
    required this.lengthMm,
    required this.angleDegrees,
    required this.text,
  });
}

/// Холст для визуализации и интерактивного черчения трубопроводной сети
class PipingCanvasPainter extends CustomPainter {
  final PipingNetwork network;
  final AxonometryProjector projector;
  final String? selectedNodeId;
  final String? selectedSegmentId;
  final String? activeSystemId;
  final Node3D? activeTraceStart;
  final Offset? activeTraceEnd;
  final Node3D? activeAxisStart;
  final SnapResult? snapResult;
  final bool showWelds;
  final bool showCallouts;
  final bool showGrid;
  final double currentElevationZ;

  PipingCanvasPainter({
    required this.network,
    required this.projector,
    this.selectedNodeId,
    this.selectedSegmentId,
    this.activeSystemId,
    this.activeTraceStart,
    this.activeTraceEnd,
    this.activeAxisStart,
    this.snapResult,
    this.showWelds = true,
    this.showCallouts = true,
    this.showGrid = true,
    this.currentElevationZ = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Сетка фона
    if (showGrid) {
      GridPainter.paint(canvas, size, projector, currentElevationZ);
    }

    // Строительные оси здания
    _drawConstructionAxes(canvas);

    // 2. Оси координат в левом нижнем углу
    _drawCoordinateAxes(canvas, size);

    // 3. Отрисовка труб (сегментов)
    final screenPoints = <String, Offset>{};
    for (final node in network.nodes.values) {
      screenPoints[node.id] = projector.project(node);
    }

    PipePainter.paint(
      canvas,
      size,
      projector,
      network,
      selectedSegmentId,
      null,
      screenPoints,
      showCallouts,
    );

    // 4. Отрисовка арматуры
    ValvePainter.paint(canvas, projector, network);

    // 4.1. Отрисовка фасонных деталей
    FittingPainter.paint(canvas, projector, network, selectedNodeId, showCallouts);

    // 5 & 6. Отрисовка сварных стыков, узлов сети и отметок
    AnnotationPainter.paint(canvas, projector, network, selectedNodeId, showWelds, showCallouts);

    // 7. Интерактивная линия трассировки (когда стилус ведет новую трубу)
    if (activeTraceStart != null && activeTraceEnd != null) {
      final pStart = projector.project(activeTraceStart!);
      final tracePaint = Paint()
        ..color = Colors.teal
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round;

      // Пунктирная направляющая
      canvas.drawLine(pStart, activeTraceEnd!, tracePaint);
      canvas.drawCircle(activeTraceEnd!, 5.0, tracePaint);
    }

    // 8. Интерактивная линия строительной оси
    if (activeAxisStart != null && activeTraceEnd != null) {
      final pAxisStart = projector.project(activeAxisStart!);
      final axisPreviewPaint = Paint()
        ..color = const Color(0xFF78909C)
        ..strokeWidth = 2.0;
      _drawDashedLine(canvas, pAxisStart, activeTraceEnd!, axisPreviewPaint);
      canvas.drawCircle(activeTraceEnd!, 5.0, axisPreviewPaint);
    }

    // 9. Индикатор магнитной привязки и полярных углов
    _drawSnapIndicator(canvas);

    // 10. HUD длины и угла активного отрезка трассировки
    _drawTraceHud(canvas, size);
  }

  void _drawCoordinateAxes(Canvas canvas, Size size) {
    final origin = Offset(60, size.height - 60);
    const axisLen = 40.0;

    final p0 = const Node3D(id: '0', x: 0, y: 0, z: 0);
    final pX = const Node3D(id: 'x', x: axisLen * 10, y: 0, z: 0);
    final pY = const Node3D(id: 'y', x: 0, y: axisLen * 10, z: 0);
    final pZ = const Node3D(id: 'z', x: 0, y: 0, z: axisLen * 10);

    final s0 = projector.project(p0);
    final sX = projector.project(pX);
    final sY = projector.project(pY);
    final sZ = projector.project(pZ);

    final dirX = (sX - s0);
    final dirY = (sY - s0);
    final dirZ = (sZ - s0);

    final lenX = math.max(dirX.distance, 1.0);
    final lenY = math.max(dirY.distance, 1.0);
    final lenZ = math.max(dirZ.distance, 1.0);

    final endX = origin + (dirX / lenX) * axisLen;
    final endY = origin + (dirY / lenY) * axisLen;
    final endZ = origin + (dirZ / lenZ) * axisLen;

    _drawAxis(canvas, origin, endX, Colors.red, 'X');
    _drawAxis(canvas, origin, endY, Colors.green, 'Y');
    _drawAxis(canvas, origin, endZ, Colors.blue, 'Z');
  }

  void _drawAxis(Canvas canvas, Offset p1, Offset p2, Color color, String label) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0;
    canvas.drawLine(p1, p2, paint);

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, p2 + const Offset(3, -7));
  }

  void _drawConstructionAxes(Canvas canvas) {
    for (final axis in network.axes.values) {
      final p1 = projector.project(axis.startPoint);
      final p2 = projector.project(axis.endPoint);

      final axisPaint = Paint()
        ..color = const Color(0xFF78909C)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;

      _drawDashedLine(canvas, p1, p2, axisPaint);

      if (axis.isBuildingGrid && axis.label.isNotEmpty) {
        _drawGridBubble(canvas, p1, axis.label);
        _drawGridBubble(canvas, p2, axis.label);
      }
    }
  }

  void _drawGridBubble(Canvas canvas, Offset center, String label) {
    const r = 13.0;
    canvas.drawCircle(center, r, Paint()..color = Colors.white..style = PaintingStyle.fill);
    canvas.drawCircle(center, r, Paint()..color = const Color(0xFF546E7A)..strokeWidth = 1.4..style = PaintingStyle.stroke);

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xFF37474F),
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
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

  void _drawSnapIndicator(Canvas canvas) {
    if (snapResult == null || snapResult!.type == SnapType.none) return;

    final pt = snapResult!.screenPoint;

    if (snapResult!.type == SnapType.node) {
      // Зеленый ромб с подсветкой
      final greenPaint = Paint()
        ..color = const Color(0xFF00C853)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      final path = Path()
        ..moveTo(pt.dx, pt.dy - 9)
        ..lineTo(pt.dx + 9, pt.dy)
        ..lineTo(pt.dx, pt.dy + 9)
        ..lineTo(pt.dx - 9, pt.dy)
        ..close();
      canvas.drawPath(path, greenPaint);
      canvas.drawCircle(pt, 14.0, Paint()..color = const Color(0xFF00C853).withValues(alpha: 0.2)..style = PaintingStyle.fill);

      _drawSnapBadge(canvas, pt + const Offset(14, -14), snapResult!.label, const Color(0xFF00C853));
    } else if (snapResult!.type == SnapType.segmentAxis) {
      // Бирюзовый крестик врезки
      final cyanPaint = Paint()
        ..color = const Color(0xFF00B0FF)
        ..strokeWidth = 2.0;
      canvas.drawLine(pt - const Offset(8, 8), pt + const Offset(8, 8), cyanPaint);
      canvas.drawLine(pt - const Offset(-8, 8), pt + const Offset(-8, 8), cyanPaint);
      canvas.drawCircle(pt, 12.0, Paint()..color = const Color(0xFF00B0FF).withValues(alpha: 0.15)..style = PaintingStyle.fill);

      _drawSnapBadge(canvas, pt + const Offset(14, -14), snapResult!.label, const Color(0xFF00B0FF));
    } else if (snapResult!.type == SnapType.polarAngle) {
      // Направляющий луч от начала трассировки
      final startNode = activeTraceStart ?? activeAxisStart;
      if (startNode != null) {
        final startPt = projector.project(startNode);
        final rayPaint = Paint()
          ..color = Colors.amber.shade700
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke;
        _drawDashedLine(canvas, startPt, pt, rayPaint);
      }
      final orangePaint = Paint()
        ..color = Colors.amber.shade800
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      canvas.drawRect(Rect.fromCenter(center: pt, width: 12, height: 12), orangePaint);

      // Если HUD не активен, рисуем компактный бейдж полярной привязки
      if (activeTraceStart == null && activeAxisStart == null) {
        _drawSnapBadge(canvas, pt + const Offset(14, -14), snapResult!.label, Colors.amber.shade900);
      }
    }
  }

  /// Вычисление информации о длине и угле для HUD трассировки
  static TraceHudInfo computeTraceHudInfo(Node3D startNode, Node3D endNode) {
    final lengthMm = startNode.distanceTo(endNode);

    final dx = endNode.x - startNode.x;
    final dy = endNode.y - startNode.y;
    double angleDeg = 0.0;
    if (dx.abs() > 0.001 || dy.abs() > 0.001) {
      angleDeg = math.atan2(dy, dx) * 180.0 / math.pi;
      if (angleDeg < 0) {
        angleDeg += 360.0;
      }
    }
    final angleInt = angleDeg.round() % 360;
    final text = 'L: ${lengthMm.round()} мм | ∠: $angleInt°';

    return TraceHudInfo(
      lengthMm: lengthMm,
      angleDegrees: angleInt,
      text: text,
    );
  }

  /// Вычисление экранной позиции бейджа HUD с защитой от перекрытия курсора и выхода за границы экрана
  static Offset computeBadgePosition({
    required Offset cursorOffset,
    required Size badgeSize,
    required Size canvasSize,
    double offsetDistance = 16.0,
  }) {
    double posX = cursorOffset.dx + offsetDistance;
    double posY = cursorOffset.dy + offsetDistance;

    if (canvasSize.width.isFinite && posX + badgeSize.width > canvasSize.width - 8) {
      posX = cursorOffset.dx - offsetDistance - badgeSize.width;
    }
    if (canvasSize.height.isFinite && posY + badgeSize.height > canvasSize.height - 8) {
      posY = cursorOffset.dy - offsetDistance - badgeSize.height;
    }
    if (posX < 8) posX = 8;
    if (posY < 8) posY = 8;

    return Offset(posX, posY);
  }

  void _drawTraceHud(Canvas canvas, Size size) {
    final startNode = activeTraceStart ?? activeAxisStart;
    if (startNode == null || activeTraceEnd == null) return;

    final endNode = (snapResult != null && snapResult!.type != SnapType.none)
        ? snapResult!.worldPoint
        : projector.unproject(activeTraceEnd!, currentElevationZ);

    final hudInfo = computeTraceHudInfo(startNode, endNode);
    final isPolarLocked = snapResult?.type == SnapType.polarAngle;

    final tp = TextPainter(
      text: TextSpan(
        text: hudInfo.text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const paddingH = 8.0;
    const paddingV = 4.0;
    final badgeSize = Size(tp.width + paddingH * 2, tp.height + paddingV * 2);

    final badgePos = computeBadgePosition(
      cursorOffset: activeTraceEnd!,
      badgeSize: badgeSize,
      canvasSize: size,
    );

    final badgeRect = Rect.fromLTWH(badgePos.dx, badgePos.dy, badgeSize.width, badgeSize.height);
    final rrect = RRect.fromRectAndRadius(badgeRect, const Radius.circular(6.0));

    // Тень бейджа для читаемости на любом фоне холста
    canvas.drawShadow(
      Path()..addRRect(rrect),
      Colors.black.withValues(alpha: 0.45),
      4.0,
      false,
    );

    // Полупрозрачный темный фон
    final bgPaint = Paint()
      ..color = const Color(0xE61E293B) // Slate 800 с 90% непрозрачностью
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, bgPaint);

    // Рамка бейджа (золотистая при фиксации полярного угла, полупрозрачная белая в обычном режиме)
    final borderPaint = Paint()
      ..color = isPolarLocked ? Colors.amber.shade600 : const Color(0x33FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(rrect, borderPaint);

    // Отрисовка текста
    tp.paint(canvas, Offset(badgePos.dx + paddingH, badgePos.dy + paddingV));
  }

  void _drawSnapBadge(Canvas canvas, Offset pos, String text, Color accentColor) {
    if (text.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(pos.dx - 4, pos.dy - 2, tp.width + 8, tp.height + 4),
      const Radius.circular(4),
    );
    canvas.drawRRect(bgRect, Paint()..color = accentColor);
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(covariant PipingCanvasPainter oldDelegate) {
    return true;
  }
}
