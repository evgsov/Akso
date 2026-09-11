import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../domain/enums/valve_type.dart';

/// Отрисовщик условных графических обозначений (УГО) арматуры по ГОСТ 21.205
class ValveSymbolPainter {
  /// Отрисовка арматуры в заданной точке с поворотом вдоль оси трубы
  static void drawValve(
    Canvas canvas, {
    required Offset center,
    required double angleRad,
    required ValveType type,
    required Color color,
    double size = 16.0,
    bool isReversed = false,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angleRad + (isReversed ? math.pi : 0.0));

    final strokePaint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final halfL = size * 0.9;
    final halfH = size * 0.45;

    switch (type) {
      case ValveType.gateValve:
        // Задвижка клиновая: два встречных треугольника + шток + маховик
        _drawTwoTriangles(canvas, halfL, halfH, fillPaint, strokePaint);
        // Шток вверх
        canvas.drawLine(Offset.zero, Offset(0, -halfH * 1.5), strokePaint);
        // Маховик (круг или перекладина)
        canvas.drawOval(
          Rect.fromCenter(center: Offset(0, -halfH * 1.5), width: halfL * 0.9, height: halfH * 0.7),
          strokePaint,
        );
        break;

      case ValveType.butterflyValve:
        // Затвор дисковый «баттерфляй»: два треугольника + центральная вертикальная полоса (диск) + рукоятка
        _drawTwoTriangles(canvas, halfL, halfH, fillPaint, strokePaint);
        // Диск поворотный
        final diskPaint = Paint()
          ..color = color
          ..strokeWidth = 2.4
          ..style = PaintingStyle.stroke;
        canvas.drawLine(Offset(0, -halfH * 1.1), Offset(0, halfH * 1.1), diskPaint);
        // Рукоятка
        canvas.drawLine(Offset(0, -halfH * 1.1), Offset(halfL * 0.6, -halfH * 1.7), strokePaint);
        break;

      case ValveType.ballValve:
        // Кран шаровой: два треугольника + круг в центре + рукоятка
        _drawTwoTriangles(canvas, halfL, halfH, fillPaint, strokePaint);
        canvas.drawCircle(Offset.zero, halfH * 0.6, fillPaint);
        canvas.drawCircle(Offset.zero, halfH * 0.6, strokePaint);
        // Рукоятка-рычаг
        canvas.drawLine(Offset.zero, Offset(halfL * 0.8, -halfH * 1.4), strokePaint);
        break;

      case ValveType.checkValve:
        // Клапан обратный: треугольники, левый залит, показывает направление потока
        _drawTwoTriangles(canvas, halfL, halfH, fillPaint, strokePaint);
        final solidPaint = Paint()
          ..color = color
          ..style = PaintingStyle.fill;
        final rightTri = Path()
          ..moveTo(0, 0)
          ..lineTo(halfL, -halfH)
          ..lineTo(halfL, halfH)
          ..close();
        canvas.drawPath(rightTri, solidPaint);
        break;

      case ValveType.strainer:
        // Фильтр сетчатый осадочный (грязевик): треугольники + косой отстойник
        _drawTwoTriangles(canvas, halfL, halfH, fillPaint, strokePaint);
        final branchPath = Path()
          ..moveTo(0, 0)
          ..lineTo(halfL * 0.6, halfH * 1.8)
          ..lineTo(halfL * 0.2, halfH * 2.0)
          ..lineTo(-halfL * 0.2, halfH * 0.8)
          ..close();
        canvas.drawPath(branchPath, fillPaint);
        canvas.drawPath(branchPath, strokePaint);
        break;

      case ValveType.waterMeter:
        // Счетчик воды / водомер: треугольники + круг с буквой 'В'
        _drawTwoTriangles(canvas, halfL, halfH, fillPaint, strokePaint);
        canvas.drawCircle(Offset.zero, halfH * 0.9, fillPaint);
        canvas.drawCircle(Offset.zero, halfH * 0.9, strokePaint);
        final tp = TextPainter(
          text: TextSpan(
            text: 'В',
            style: TextStyle(
              color: color,
              fontSize: halfH * 1.1,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
        break;

      case ValveType.balancingValve:
        // Балансировочный клапан
        _drawTwoTriangles(canvas, halfL, halfH, fillPaint, strokePaint);
        canvas.drawLine(Offset.zero, Offset(0, -halfH * 1.4), strokePaint);
        // Два штуцера для подключения манометра
        canvas.drawCircle(Offset(-halfL * 0.4, -halfH * 0.9), 2.0, strokePaint);
        canvas.drawCircle(Offset(halfL * 0.4, -halfH * 0.9), 2.0, strokePaint);
        break;

      case ValveType.pressureGauge:
        // Манометр: бобышка + круг со стрелкой
        canvas.drawLine(Offset.zero, Offset(0, -halfH * 1.5), strokePaint);
        canvas.drawCircle(Offset(0, -halfH * 2.5), halfH * 1.0, fillPaint);
        canvas.drawCircle(Offset(0, -halfH * 2.5), halfH * 1.0, strokePaint);
        canvas.drawLine(
          Offset(0, -halfH * 2.5),
          Offset(halfH * 0.6, -halfH * 3.1),
          strokePaint,
        );
        break;

      case ValveType.thermometer:
        // Термометр в гильзе
        canvas.drawLine(Offset.zero, Offset(0, -halfH * 1.2), strokePaint);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(0, -halfH * 2.2), width: halfH * 0.7, height: halfH * 2.0),
            Radius.circular(halfH * 0.35),
          ),
          fillPaint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(0, -halfH * 2.2), width: halfH * 0.7, height: halfH * 2.0),
            Radius.circular(halfH * 0.35),
          ),
          strokePaint,
        );
        break;

      case ValveType.airVent:
        // Автоматический воздухоотводчик: цилиндр + стрелка вверх
        canvas.drawLine(Offset.zero, Offset(0, -halfH * 1.0), strokePaint);
        canvas.drawRect(
          Rect.fromCenter(center: Offset(0, -halfH * 1.8), width: halfH * 1.0, height: halfH * 1.5),
          fillPaint,
        );
        canvas.drawRect(
          Rect.fromCenter(center: Offset(0, -halfH * 1.8), width: halfH * 1.0, height: halfH * 1.5),
          strokePaint,
        );
        // Стрелка выпуска воздуха
        canvas.drawLine(Offset(0, -halfH * 2.6), Offset(0, -halfH * 3.4), strokePaint);
        canvas.drawLine(Offset(-3, -halfH * 3.0), Offset(0, -halfH * 3.4), strokePaint);
        canvas.drawLine(Offset(3, -halfH * 3.0), Offset(0, -halfH * 3.4), strokePaint);
        break;

      case ValveType.drainValve:
        // Спускник: кран вниз со сливной трубкой
        _drawTwoTriangles(canvas, halfL * 0.7, halfH * 0.7, fillPaint, strokePaint);
        canvas.drawLine(Offset.zero, Offset(0, halfH * 1.8), strokePaint);
        canvas.drawLine(Offset(0, halfH * 1.8), Offset(halfL * 0.5, halfH * 2.2), strokePaint);
        break;
    }

    canvas.restore();
  }

  static void _drawTwoTriangles(
    Canvas canvas,
    double halfL,
    double halfH,
    Paint fillPaint,
    Paint strokePaint,
  ) {
    final path = Path()
      ..moveTo(-halfL, -halfH)
      ..lineTo(0, 0)
      ..lineTo(-halfL, halfH)
      ..close()
      ..moveTo(halfL, -halfH)
      ..lineTo(0, 0)
      ..lineTo(halfL, halfH)
      ..close();

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, strokePaint);
  }
}
