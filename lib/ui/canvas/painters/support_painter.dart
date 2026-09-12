import 'package:flutter/material.dart';

import '../../../core/math/axonometry_projector.dart';
import '../../../domain/models/pipe_support.dart';
import '../../../domain/models/piping_network.dart';

/// Отрисовка опор и подвесок трубопровода в аксонометрии
class SupportPainter {
  static void paint(
    Canvas canvas,
    AxonometryProjector projector,
    PipingNetwork network,
  ) {
    if (network.supports.isEmpty) return;

    for (final support in network.supports.values) {
      final seg = network.segments[support.segmentId];
      if (seg == null) continue;
      final start = network.nodes[seg.startNodeId];
      final end = network.nodes[seg.endNodeId];
      if (start == null || end == null) continue;

      final p1 = projector.project(start);
      final p2 = projector.project(end);

      final ratio = support.distanceRatio.clamp(0.0, 1.0);
      final center = Offset(
        p1.dx + (p2.dx - p1.dx) * ratio,
        p1.dy + (p2.dy - p1.dy) * ratio,
      );

      final dir = p2 - p1;
      final len = dir.distance;
      final u = len > 0.001 ? dir / len : const Offset(1, 0);

      // Нормаль к сегменту трубы на экране
      var n = Offset(-u.dy, u.dx);
      // Предпочитаем ориентацию вниз (по гравитации), либо вправо при вертикальной трубе
      if (n.dy < -0.01 || (n.dy.abs() <= 0.01 && n.dx < 0)) {
        n = -n;
      }

      final strokePaint = Paint()
        ..color = const Color(0xFF263238)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final fillPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;

      switch (support.type) {
        case PipeSupportType.fixed:
          _drawFixedSupport(canvas, center, u, n, strokePaint, fillPaint);
          break;
        case PipeSupportType.sliding:
          _drawSlidingSupport(canvas, center, u, n, strokePaint, fillPaint);
          break;
        case PipeSupportType.spring:
          _drawSpringSupport(canvas, center, u, n, strokePaint);
          break;
        case PipeSupportType.guide:
          _drawGuideSupport(canvas, center, u, n, strokePaint, fillPaint);
          break;
      }

      // Маркировка опоры (напр. "ОП-1", "НО-2")
      if (support.name.isNotEmpty) {
        _drawLabel(canvas, center, u, n, support);
      }
    }
  }

  /// Неподвижная опора: треугольная опора с заземленной пластиной
  static void _drawFixedSupport(
    Canvas canvas,
    Offset center,
    Offset u,
    Offset n,
    Paint strokePaint,
    Paint fillPaint,
  ) {
    // Хомут на трубе
    canvas.drawLine(center - u * 5, center + u * 5, strokePaint..strokeWidth = 3.0);
    strokePaint.strokeWidth = 2.0;

    // Треугольная стойка
    final baseCenter = center + n * 16.0;
    final baseLeft = baseCenter - u * 9.0;
    final baseRight = baseCenter + u * 9.0;

    final triPath = Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(baseLeft.dx, baseLeft.dy)
      ..lineTo(baseRight.dx, baseRight.dy)
      ..close();

    canvas.drawPath(triPath, fillPaint);
    canvas.drawPath(triPath, strokePaint);

    // Опорная плита
    final plateLeft = baseCenter - u * 12.0;
    final plateRight = baseCenter + u * 12.0;
    canvas.drawLine(plateLeft, plateRight, strokePaint..strokeWidth = 2.5);
    strokePaint.strokeWidth = 2.0;

    // Штриховка заделки / фундамента
    _drawGroundHatch(canvas, baseCenter, u, n, 12.0);
  }

  /// Скользящая опора: стойка с опорным башмаком и зазором скольжения
  static void _drawSlidingSupport(
    Canvas canvas,
    Offset center,
    Offset u,
    Offset n,
    Paint strokePaint,
    Paint fillPaint,
  ) {
    // Стойка
    final shoeCenter = center + n * 10.0;
    canvas.drawLine(center, shoeCenter, strokePaint);

    // Верхняя скользящая планка
    final shoeLeft = shoeCenter - u * 8.0;
    final shoeRight = shoeCenter + u * 8.0;
    canvas.drawLine(shoeLeft, shoeRight, strokePaint..strokeWidth = 2.5);

    // Нижняя опорная плита (с зазором 4px)
    final baseCenter = center + n * 14.0;
    final baseLeft = baseCenter - u * 11.0;
    final baseRight = baseCenter + u * 11.0;
    canvas.drawLine(baseLeft, baseRight, strokePaint..strokeWidth = 2.5);
    strokePaint.strokeWidth = 2.0;

    // Штриховка основания
    _drawGroundHatch(canvas, baseCenter, u, n, 11.0);
  }

  /// Пружинная подвеска: тяга с пружиной и верхним подвесом
  static void _drawSpringSupport(
    Canvas canvas,
    Offset center,
    Offset u,
    Offset n,
    Paint strokePaint,
  ) {
    // Подвеска направлена вверх (в сторону перекрытия: -n)
    final up = -n;
    final rodStart = center;
    final springStart = center + up * 8.0;
    final springEnd = center + up * 24.0;
    final anchor = center + up * 30.0;

    // Нижняя тяга
    canvas.drawLine(rodStart, springStart, strokePaint);

    // Зигзаг пружины
    final springPath = Path()..moveTo(springStart.dx, springStart.dy);
    const coils = 4;
    final segHeight = (24.0 - 8.0) / coils;
    for (var i = 0; i < coils; i++) {
      final sign = (i % 2 == 0) ? 1.0 : -1.0;
      final midY = springStart + up * (i * segHeight + segHeight * 0.5) + u * (sign * 6.0);
      final nextY = springStart + up * ((i + 1) * segHeight);
      springPath.lineTo(midY.dx, midY.dy);
      springPath.lineTo(nextY.dx, nextY.dy);
    }
    canvas.drawPath(springPath, strokePaint);

    // Верхняя тяга к перекрытию
    canvas.drawLine(springEnd, anchor, strokePaint);

    // Верхняя плита крепления
    final plateLeft = anchor - u * 9.0;
    final plateRight = anchor + u * 9.0;
    canvas.drawLine(plateLeft, plateRight, strokePaint..strokeWidth = 2.5);
    strokePaint.strokeWidth = 2.0;

    // Штриховка перекрытия
    _drawGroundHatch(canvas, anchor, u, up, 9.0);
  }

  /// Направляющая опора: скользящая опора с боковыми упорами-ограничителями
  static void _drawGuideSupport(
    Canvas canvas,
    Offset center,
    Offset u,
    Offset n,
    Paint strokePaint,
    Paint fillPaint,
  ) {
    // Стойка
    final shoeCenter = center + n * 10.0;
    canvas.drawLine(center, shoeCenter, strokePaint);

    // Скользящий башмак
    final shoeLeft = shoeCenter - u * 7.0;
    final shoeRight = shoeCenter + u * 7.0;
    canvas.drawLine(shoeLeft, shoeRight, strokePaint..strokeWidth = 2.5);

    // Нижняя плита
    final baseCenter = center + n * 14.0;
    final baseLeft = baseCenter - u * 12.0;
    final baseRight = baseCenter + u * 12.0;
    canvas.drawLine(baseLeft, baseRight, strokePaint..strokeWidth = 2.5);

    // Боковые упоры-ограничители (уголки)
    final leftGuideTop = baseCenter - u * 9.0 - n * 7.0;
    final leftGuideBottom = baseCenter - u * 9.0;
    canvas.drawLine(leftGuideTop, leftGuideBottom, strokePaint..strokeWidth = 2.0);

    final rightGuideTop = baseCenter + u * 9.0 - n * 7.0;
    final rightGuideBottom = baseCenter + u * 9.0;
    canvas.drawLine(rightGuideTop, rightGuideBottom, strokePaint..strokeWidth = 2.0);

    // Штриховка основания
    _drawGroundHatch(canvas, baseCenter, u, n, 12.0);
  }

  /// Наклонная штриховка строительного основания / фундамента
  static void _drawGroundHatch(
    Canvas canvas,
    Offset baseCenter,
    Offset u,
    Offset n,
    double halfWidth,
  ) {
    final hatchPaint = Paint()
      ..color = const Color(0xFF78909C)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    const count = 4;
    final step = (halfWidth * 2) / (count + 1);
    for (var i = 1; i <= count; i++) {
      final pOnBase = baseCenter - u * halfWidth + u * (i * step);
      final hatchEnd = pOnBase + n * 5.0 - u * 4.0;
      canvas.drawLine(pOnBase, hatchEnd, hatchPaint);
    }
  }

  /// Отрисовка текстового бейджа маркировки опоры
  static void _drawLabel(
    Canvas canvas,
    Offset center,
    Offset u,
    Offset n,
    PipeSupport support,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: support.name,
        style: const TextStyle(
          color: Color(0xFF263238),
          fontSize: 9.5,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final labelOffset = (support.type == PipeSupportType.spring)
        ? center - n * 38.0 - Offset(tp.width / 2, tp.height)
        : center + n * 24.0 - Offset(tp.width / 2, 0);

    final bgRect = Rect.fromLTWH(
      labelOffset.dx - 3,
      labelOffset.dy - 1,
      tp.width + 6,
      tp.height + 2,
    );

    final bgPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = const Color(0xFF90A4AE)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(3.0)),
      bgPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(3.0)),
      borderPaint,
    );

    tp.paint(canvas, labelOffset);
  }
}
