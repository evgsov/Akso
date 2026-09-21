import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/math/axonometry_projector.dart';
import '../../../domain/enums/projection_type.dart';

class GridPainter {
  static void paint(
    Canvas canvas,
    Size size,
    AxonometryProjector projector,
    double currentElevationZ,
  ) {
    // 1. Адаптивный шаг мировой сетки в миллиметрах в зависимости от масштаба
    const standardStepsMm = [
      50.0,
      100.0,
      200.0,
      500.0,
      1000.0,
      2000.0,
      5000.0,
      10000.0,
      20000.0,
      50000.0,
    ];

    double stepMm = 1000.0;
    for (final s in standardStepsMm) {
      if (s * projector.scale >= 50.0) {
        stepMm = s;
        break;
      }
    }

    // 2. Определение видимого диапазона в мировых координатах на плоскости Z = currentElevationZ
    final pTL = projector.unproject(const Offset(-120, -120), currentElevationZ);
    final pTR = projector.unproject(Offset(size.width + 120, -120), currentElevationZ);
    final pBL = projector.unproject(Offset(-120, size.height + 120), currentElevationZ);
    final pBR = projector.unproject(Offset(size.width + 120, size.height + 120), currentElevationZ);
    final pCenter = projector.unproject(Offset(size.width / 2, size.height / 2), currentElevationZ);

    double minX = math.min(math.min(pTL.x, pTR.x), math.min(pBL.x, pBR.x));
    double maxX = math.max(math.max(pTL.x, pTR.x), math.max(pBL.x, pBR.x));
    double minY = math.min(math.min(pTL.y, pTR.y), math.min(pBL.y, pBR.y));
    double maxY = math.max(math.max(pTL.y, pTR.y), math.max(pBL.y, pBR.y));

    // В 3D-орбите ограничиваем радиус сетки вокруг фокуса камеры, чтобы линии не уходили в бесконечность
    if (projector.projectionType == ProjectionType.orbit3d) {
      final maxSpanMm = (size.longestSide / projector.scale) * 1.6;
      minX = math.max(minX, pCenter.x - maxSpanMm);
      maxX = math.min(maxX, pCenter.x + maxSpanMm);
      minY = math.max(minY, pCenter.y - maxSpanMm);
      maxY = math.min(maxY, pCenter.y + maxSpanMm);
    }

    // Защита от избыточного числа линий: увеличиваем шаг, если линий больше 80
    const maxLines = 80;
    while (((maxX - minX) / stepMm > maxLines || (maxY - minY) / stepMm > maxLines) &&
        stepMm < standardStepsMm.last) {
      final nextIdx = standardStepsMm.indexOf(stepMm) + 1;
      if (nextIdx < standardStepsMm.length) {
        stepMm = standardStepsMm[nextIdx];
      } else {
        break;
      }
    }

    final startX = (minX / stepMm).floor() * stepMm;
    final endX = (maxX / stepMm).ceil() * stepMm;
    final startY = (minY / stepMm).floor() * stepMm;
    final endY = (maxY / stepMm).ceil() * stepMm;

    // Стили линий сетки
    final regularPaint = Paint()
      ..color = Colors.blueGrey.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final majorPaint = Paint()
      ..color = Colors.blueGrey.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    final axisXPaint = Paint()
      ..color = const Color(0xFFEF5350).withValues(alpha: 0.55)
      ..strokeWidth = 1.6; // Ось X (красная)
    final axisYPaint = Paint()
      ..color = const Color(0xFF66BB6A).withValues(alpha: 0.55)
      ..strokeWidth = 1.6; // Ось Y (зеленая)

    // Пакетная оптимизация (Draw Call Batching): объединяем линии в Path,
    // чтобы сократить количество вызовов GPU со ~160 до 2 на каждом кадре.
    final regularPath = Path();
    final majorPath = Path();

    // 1. Линии сетки, параллельные оси Y (постоянный X)
    for (double x = startX; x <= endX + 1e-4; x += stepMm) {
      final p1 = projector.projectCoordinates(x, startY, currentElevationZ);
      final p2 = projector.projectCoordinates(x, endY, currentElevationZ);

      final index = (x / stepMm).round();
      if (index == 0) {
        canvas.drawLine(p1, p2, axisYPaint);
      } else if (index % 5 == 0) {
        majorPath.moveTo(p1.dx, p1.dy);
        majorPath.lineTo(p2.dx, p2.dy);
      } else {
        regularPath.moveTo(p1.dx, p1.dy);
        regularPath.lineTo(p2.dx, p2.dy);
      }
    }

    // 2. Линии сетки, параллельные оси X (постоянный Y)
    for (double y = startY; y <= endY + 1e-4; y += stepMm) {
      final p1 = projector.projectCoordinates(startX, y, currentElevationZ);
      final p2 = projector.projectCoordinates(endX, y, currentElevationZ);

      final index = (y / stepMm).round();
      if (index == 0) {
        canvas.drawLine(p1, p2, axisXPaint);
      } else if (index % 5 == 0) {
        majorPath.moveTo(p1.dx, p1.dy);
        majorPath.lineTo(p2.dx, p2.dy);
      } else {
        regularPath.moveTo(p1.dx, p1.dy);
        regularPath.lineTo(p2.dx, p2.dy);
      }
    }

    canvas.drawPath(regularPath, regularPaint);
    canvas.drawPath(majorPath, majorPaint);

    // 3. Маркер мирового центра координат (0, 0, Z)
    final origin = projector.projectCoordinates(0, 0, currentElevationZ);
    if (origin.dx >= -40 && origin.dx <= size.width + 40 &&
        origin.dy >= -40 && origin.dy <= size.height + 40) {
      final originPaint = Paint()
        ..color = const Color(0xFF546E7A)
        ..strokeWidth = 1.6;

      canvas.drawCircle(origin, 5.0, Paint()..color = Colors.white..style = PaintingStyle.fill);
      canvas.drawCircle(origin, 5.0, originPaint..style = PaintingStyle.stroke);
      canvas.drawLine(Offset(origin.dx - 8, origin.dy), Offset(origin.dx + 8, origin.dy), originPaint);
      canvas.drawLine(Offset(origin.dx, origin.dy - 8), Offset(origin.dx, origin.dy + 8), originPaint);

      final elevText = currentElevationZ != 0.0
          ? ' (∇${(currentElevationZ / 1000).toStringAsFixed(3)}м)'
          : '';
      final tp = TextPainter(
        text: TextSpan(
          text: '(0,0)$elevText',
          style: const TextStyle(
            color: Color(0xFF455A64),
            fontSize: 9.0,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            backgroundColor: Color(0xD0FFFFFF),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, origin + const Offset(7, 3));
    }

    // 4. Масштабная линейка (Scale Bar) внизу экрана
    final stepPx = stepMm * projector.scale;
    _drawScaleBar(canvas, size, stepMm, stepPx);
  }

  static void _drawScaleBar(Canvas canvas, Size size, double stepMm, double stepPx) {
    const barLeft = 24.0;
    final barY = size.height - 105.0;

    final barPaint = Paint()
      ..color = const Color(0xFF546E7A)
      ..strokeWidth = 1.8;

    // Горизонтальная черта длиною stepPx
    canvas.drawLine(Offset(barLeft, barY), Offset(barLeft + stepPx, barY), barPaint);
    // Засечки по краям
    canvas.drawLine(Offset(barLeft, barY - 4), Offset(barLeft, barY + 4), barPaint);
    canvas.drawLine(Offset(barLeft + stepPx, barY - 4), Offset(barLeft + stepPx, barY + 4), barPaint);

    final label = stepMm >= 1000.0 ? '${(stepMm / 1000.0).toStringAsFixed(stepMm % 1000 == 0 ? 0 : 1)} м' : '${stepMm.round()} мм';
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xFF455A64),
          fontSize: 9.5,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
          backgroundColor: Color(0xD0F8F9FA),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(barLeft + (stepPx - tp.width) / 2, barY - 14));
  }
}
