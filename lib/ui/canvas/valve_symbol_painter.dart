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
    bool isFlanged = false,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angleRad + (isReversed ? math.pi : 0.0));

    final strokePaint = Paint()
      ..color = color
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter;

    final hatchPaint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.95)
      ..style = PaintingStyle.fill;

    final halfL = size * 0.9;
    final halfH = size * 0.45;

    switch (type) {
      case ValveType.gateValve:
        // Задвижка клиновая по ГОСТ 21.205: два контурных треугольника с тонкой штриховкой + шпиндель + маховик со спицами
        _drawTwoTriangles(canvas, halfL, halfH, fillPaint, strokePaint, hatchPaint: hatchPaint, isFlanged: isFlanged);
        // Шток вверх с упорным кольцом (буртиком)
        canvas.drawLine(Offset.zero, Offset(0, -halfH * 1.55), strokePaint);
        canvas.drawLine(Offset(-2.0, -halfH * 0.7), Offset(2.0, -halfH * 0.7), strokePaint);
        // Маховик (эллипс со спицами-перекрестием)
        final wheelCenter = Offset(0, -halfH * 1.55);
        final wheelRect = Rect.fromCenter(center: wheelCenter, width: halfL * 0.85, height: halfH * 0.65);
        canvas.drawOval(wheelRect, fillPaint);
        canvas.drawOval(wheelRect, strokePaint);
        canvas.drawLine(Offset(-halfL * 0.35, wheelCenter.dy), Offset(halfL * 0.35, wheelCenter.dy), hatchPaint);
        canvas.drawLine(Offset(0, wheelCenter.dy - halfH * 0.28), Offset(0, wheelCenter.dy + halfH * 0.28), hatchPaint);
        break;

      case ValveType.butterflyValve:
        // Затвор дисковый «баттерфляй»: встречные треугольники + центральный диск + рукоятка поворота
        _drawTwoTriangles(canvas, halfL, halfH, fillPaint, strokePaint, isFlanged: isFlanged);
        // Поворотный диск по центру
        final diskPaint = Paint()
          ..color = color
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke;
        canvas.drawLine(Offset(0, -halfH * 1.15), Offset(0, halfH * 1.15), diskPaint);
        // Шпиндель и рукоятка управления с фиксатором
        canvas.drawLine(Offset(0, -halfH * 1.15), Offset(halfL * 0.65, -halfH * 1.75), strokePaint);
        canvas.drawCircle(Offset(halfL * 0.65, -halfH * 1.75), 1.8, strokePaint);
        break;

      case ValveType.ballValve:
        // Кран шаровой: треугольники + окружность шаровой пробки с протоком + рычаг
        _drawTwoTriangles(canvas, halfL, halfH, fillPaint, strokePaint, isFlanged: isFlanged);
        canvas.drawCircle(Offset.zero, halfH * 0.65, fillPaint);
        canvas.drawCircle(Offset.zero, halfH * 0.65, strokePaint);
        // Открытый проход в шаре
        canvas.drawLine(Offset(-halfH * 0.65, 0), Offset(halfH * 0.65, 0), hatchPaint);
        // Рукоятка-рычаг с накладкой
        canvas.drawLine(Offset.zero, Offset(halfL * 0.85, -halfH * 1.45), strokePaint);
        canvas.drawCircle(Offset(halfL * 0.85, -halfH * 1.45), 2.2, Paint()..color = color..style = PaintingStyle.fill);
        break;

      case ValveType.checkValve:
        // Клапан обратный по ГОСТ 21.205: контурные треугольники + стрелка направления потока + наклонное седло
        _drawTwoTriangles(canvas, halfL, halfH, fillPaint, strokePaint, isFlanged: isFlanged);
        // Наклонное седло клапана (затвор)
        canvas.drawLine(Offset(-halfL * 0.25, -halfH * 0.85), Offset(halfL * 0.25, halfH * 0.85), strokePaint);
        // Стрелка направления потока вдоль оси трубы
        final arrowPaint = Paint()
          ..color = color
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke;
        canvas.drawLine(Offset(-halfL * 0.6, 0), Offset(halfL * 0.6, 0), arrowPaint);
        // Наконечник стрелки
        final arrowHead = Path()
          ..moveTo(halfL * 0.6, 0)
          ..lineTo(halfL * 0.35, -halfH * 0.4)
          ..moveTo(halfL * 0.6, 0)
          ..lineTo(halfL * 0.35, halfH * 0.4);
        canvas.drawPath(arrowHead, arrowPaint);
        break;

      case ValveType.strainer:
        // Фильтр сетчатый осадочный (грязевик): треугольники + косой отстойник с металлической сеткой
        _drawTwoTriangles(canvas, halfL, halfH, fillPaint, strokePaint, isFlanged: isFlanged);
        final branchPath = Path()
          ..moveTo(0, 0)
          ..lineTo(halfL * 0.65, halfH * 1.85)
          ..lineTo(halfL * 0.25, halfH * 2.05)
          ..lineTo(-halfL * 0.2, halfH * 0.85)
          ..close();
        canvas.drawPath(branchPath, fillPaint);
        canvas.drawPath(branchPath, strokePaint);
        // Сетка фильтра (cross-hatch линии)
        canvas.drawLine(Offset(0, halfH * 0.8), Offset(halfL * 0.45, halfH * 1.4), hatchPaint);
        canvas.drawLine(Offset(0, halfH * 1.2), Offset(halfL * 0.35, halfH * 1.8), hatchPaint);
        // Сливная пробка на отстойнике
        canvas.drawLine(Offset(halfL * 0.25, halfH * 2.05), Offset(halfL * 0.65, halfH * 1.85), strokePaint);
        break;

      case ValveType.waterMeter:
        // Счетчик воды / водомер: треугольники + измерительная камера с буквой 'В' и импульсными засечками
        _drawTwoTriangles(canvas, halfL, halfH, fillPaint, strokePaint, isFlanged: isFlanged);
        canvas.drawCircle(Offset.zero, halfH * 0.95, fillPaint);
        canvas.drawCircle(Offset.zero, halfH * 0.95, strokePaint);
        final tp = TextPainter(
          text: TextSpan(
            text: 'В',
            style: TextStyle(
              color: color,
              fontSize: halfH * 1.15,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
        break;

      case ValveType.balancingValve:
        // Балансировочный клапан: треугольники + измерительные штуцеры давления
        _drawTwoTriangles(canvas, halfL, halfH, fillPaint, strokePaint, hatchPaint: hatchPaint, isFlanged: isFlanged);
        canvas.drawLine(Offset.zero, Offset(0, -halfH * 1.4), strokePaint);
        // Измерительные ниппели со штуцерами
        canvas.drawLine(Offset(-halfL * 0.45, -halfH * 0.4), Offset(-halfL * 0.45, -halfH * 1.1), strokePaint);
        canvas.drawLine(Offset(halfL * 0.45, -halfH * 0.4), Offset(halfL * 0.45, -halfH * 1.1), strokePaint);
        canvas.drawCircle(Offset(-halfL * 0.45, -halfH * 1.1), 1.8, strokePaint);
        canvas.drawCircle(Offset(halfL * 0.45, -halfH * 1.1), 1.8, strokePaint);
        break;

      case ValveType.pressureGauge:
        // Манометр: штуцерная бобышка + циферблат со стрелкой и шкалой
        canvas.drawLine(Offset.zero, Offset(0, -halfH * 1.4), strokePaint);
        final gaugeCenter = Offset(0, -halfH * 2.5);
        final gaugeRadius = halfH * 1.1;
        canvas.drawCircle(gaugeCenter, gaugeRadius, fillPaint);
        canvas.drawCircle(gaugeCenter, gaugeRadius, strokePaint);
        // Стрелка манометра
        canvas.drawLine(gaugeCenter, Offset(halfH * 0.6, -halfH * 3.1), strokePaint);
        canvas.drawCircle(gaugeCenter, 1.5, Paint()..color = color..style = PaintingStyle.fill);
        break;

      case ValveType.thermometer:
        // Термометр в гильзе: защитная гильза + стеклянная шкала
        canvas.drawLine(Offset.zero, Offset(0, -halfH * 1.2), strokePaint);
        final thermRect = Rect.fromCenter(center: Offset(0, -halfH * 2.3), width: halfH * 0.7, height: halfH * 2.2);
        canvas.drawRRect(RRect.fromRectAndRadius(thermRect, Radius.circular(halfH * 0.35)), fillPaint);
        canvas.drawRRect(RRect.fromRectAndRadius(thermRect, Radius.circular(halfH * 0.35)), strokePaint);
        // Капиллярная трубка
        canvas.drawLine(Offset(0, -halfH * 1.4), Offset(0, -halfH * 3.0), hatchPaint);
        break;

      case ValveType.airVent:
        // Автоматический воздухоотводчик: цилиндрический поплавковый корпус + сбросной клапан
        canvas.drawLine(Offset.zero, Offset(0, -halfH * 1.0), strokePaint);
        final ventRect = Rect.fromCenter(center: Offset(0, -halfH * 1.85), width: halfH * 1.05, height: halfH * 1.55);
        canvas.drawRect(ventRect, fillPaint);
        canvas.drawRect(ventRect, strokePaint);
        // Стрелка выхода воздуха вверх
        canvas.drawLine(Offset(0, -halfH * 2.65), Offset(0, -halfH * 3.45), strokePaint);
        canvas.drawLine(Offset(-2.5, -halfH * 3.1), Offset(0, -halfH * 3.45), strokePaint);
        canvas.drawLine(Offset(2.5, -halfH * 3.1), Offset(0, -halfH * 3.45), strokePaint);
        break;

      case ValveType.drainValve:
        // Спускник: кран со сливным патрубком вниз
        _drawTwoTriangles(canvas, halfL * 0.7, halfH * 0.7, fillPaint, strokePaint);
        canvas.drawLine(Offset.zero, Offset(0, halfH * 1.8), strokePaint);
        canvas.drawLine(Offset(0, halfH * 1.8), Offset(halfL * 0.5, halfH * 2.3), strokePaint);
        break;
    }

    canvas.restore();
  }

  static void _drawTwoTriangles(
    Canvas canvas,
    double halfL,
    double halfH,
    Paint fillPaint,
    Paint strokePaint, {
    Paint? hatchPaint,
    bool isFlanged = false,
  }) {
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

    // Тонкая внутренняя чертежная штриховка под 45 градусов (ГОСТ)
    if (hatchPaint != null) {
      canvas.save();
      canvas.clipPath(path);
      for (double x = -halfL * 1.5; x <= halfL * 1.5; x += 3.5) {
        canvas.drawLine(Offset(x, -halfH * 1.5), Offset(x + halfH * 2.5, halfH * 1.5), hatchPaint);
      }
      canvas.restore();
    }

    canvas.drawPath(path, strokePaint);

    // Торцевые фланцевые засечки по ГОСТ на стыках с трубой (только для фланцевой арматуры)
    if (isFlanged) {
      final tickH = halfH * 1.25;
      canvas.drawLine(Offset(-halfL, -tickH), Offset(-halfL, tickH), strokePaint);
      canvas.drawLine(Offset(halfL, -tickH), Offset(halfL, tickH), strokePaint);
    }
  }
}
