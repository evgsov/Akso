import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../core/math/axonometry_projector.dart';
import '../../../domain/models/linear_dimension.dart';
import '../../../domain/models/piping_network.dart';

/// Отрисовка размерных линий по ГОСТ 2.307-2011 / СПДС
/// (выносные линии, параллельная размерная линия, засечки 45°, размерные числа)
class DimensionPainter {
  static void paint(
    Canvas canvas,
    AxonometryProjector projector,
    PipingNetwork network, {
    LinearDimension? previewDimension,
    String? selectedDimensionId,
    Set<String>? selectedDimensionIds,
  }) {
    for (final dim in network.dimensions.values) {
      final isSelected = dim.id == selectedDimensionId ||
          (selectedDimensionIds != null && selectedDimensionIds.contains(dim.id));
      _paintDimension(canvas, projector, dim, isSelected: isSelected);
    }

    if (previewDimension != null) {
      _paintDimension(canvas, projector, previewDimension, isPreview: true);
    }
  }

  static void _paintDimension(
    Canvas canvas,
    AxonometryProjector projector,
    LinearDimension dim, {
    bool isSelected = false,
    bool isPreview = false,
  }) {
    final p1 = projector.project(dim.startPoint);
    final p2 = projector.project(dim.endPoint);

    final delta = p2 - p1;
    final dist2d = delta.distance;
    if (dist2d < 1.0) return;

    // Единичный вектор вдоль измеряемого отрезка
    final u = delta / dist2d;
    // Нормаль к отрезку (повернута на 90 градусов против часовой стрелки)
    final n = Offset(-u.dy, u.dx);

    final offsetDist = dim.offsetDistance == 0.0 ? 35.0 : dim.offsetDistance;
    final offsetVec = n * offsetDist;

    // Точки размерной линии
    final d1 = p1 + offsetVec;
    final d2 = p2 + offsetVec;

    // Вылет выносных линий за размерную линию
    final overshoot = (offsetDist >= 0 ? 4.0 : -4.0);
    final ext1End = d1 + n * overshoot;
    final ext2End = d2 + n * overshoot;

    final lineColor = isPreview
        ? Colors.teal
        : (isSelected ? Colors.amber.shade800 : const Color(0xFF37474F));

    final linePaint = Paint()
      ..color = lineColor.withValues(alpha: isPreview ? 0.75 : 0.9)
      ..strokeWidth = isSelected ? 1.5 : 1.0
      ..style = PaintingStyle.stroke;

    final tickPaint = Paint()
      ..color = lineColor
      ..strokeWidth = isSelected ? 2.2 : 1.8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // 1. Выносные линии
    canvas.drawLine(p1, ext1End, linePaint);
    canvas.drawLine(p2, ext2End, linePaint);

    // 2. Размерная линия
    canvas.drawLine(d1, d2, linePaint);

    // 3. Строительные засечки ГОСТ под углом 45°
    // Засечка направлена под 45° к размерной линии
    const tickLen = 6.0;
    final tickDir = (u + n) / math.sqrt(2) * tickLen;

    canvas.drawLine(d1 - tickDir, d1 + tickDir, tickPaint);
    canvas.drawLine(d2 - tickDir, d2 + tickDir, tickPaint);

    // 4. Текст размера (размерное число в мм по ГОСТ)
    final text = dim.displayText;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: lineColor,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          fontFamily: 'Roboto',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final mid = (d1 + d2) / 2;

    // Вычисляем угол наклона размерной линии в радианах
    var angle = math.atan2(delta.dy, delta.dx);
    // Приводим угол к диапазону [-π/2, π/2], чтобы текст никогда не был перевернут «вверх ногами»
    if (angle > math.pi / 2) {
      angle -= math.pi;
    } else if (angle < -math.pi / 2) {
      angle += math.pi;
    }

    canvas.save();
    canvas.translate(mid.dx, mid.dy);
    canvas.rotate(angle);

    // Подложка под текст, чтобы размерная линия не пересекала число
    const padH = 4.0;
    const padV = 2.0;
    final bgRect = Rect.fromCenter(
      center: Offset.zero,
      width: tp.width + padH * 2,
      height: tp.height + padV * 2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(2)),
      Paint()..color = Colors.white.withValues(alpha: 0.95),
    );

    if (isSelected) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(bgRect, const Radius.circular(2)),
        Paint()
          ..color = Colors.amber
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke,
      );
    }

    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }
}
