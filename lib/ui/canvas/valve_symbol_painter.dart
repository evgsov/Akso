import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../domain/enums/valve_type.dart';
import '../../domain/models/custom_valve_definition.dart';

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

  /// Отрисовка параметрического пользовательского УГО арматуры
  static void drawCustomValve(
    Canvas canvas, {
    required Offset center,
    required double angleRad,
    required ValveSymbolConfig symbolConfig,
    required Color color,
    double size = 16.0,
    bool isReversed = false,
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
      ..color = color.withValues(alpha: 0.65)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    final solidFillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final whiteFillPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.95)
      ..style = PaintingStyle.fill;

    final halfL = size * 0.9;
    final halfH = size * 0.45;

    switch (symbolConfig.bodyShape) {
      case Valve3dBodyShape.doubleCones:
        // Левое и правое крылья (треугольники)
        final leftWing = Path()
          ..moveTo(-halfL, -halfH)
          ..lineTo(0, 0)
          ..lineTo(-halfL, halfH)
          ..close();

        final rightWing = Path()
          ..moveTo(halfL, -halfH)
          ..lineTo(0, 0)
          ..lineTo(halfL, halfH)
          ..close();

        _drawWing(canvas, leftWing, symbolConfig.leftWingStyle, halfL, halfH,
            whiteFillPaint, solidFillPaint, strokePaint, hatchPaint);
        _drawWing(canvas, rightWing, symbolConfig.rightWingStyle, halfL, halfH,
            whiteFillPaint, solidFillPaint, strokePaint, hatchPaint);
        break;

      case Valve3dBodyShape.cylinder:
        // Прямоугольный корпус (цилиндр) вдоль оси трубы
        final leftCylinder = Path()
          ..moveTo(-halfL, -halfH)
          ..lineTo(0, -halfH)
          ..lineTo(0, halfH)
          ..lineTo(-halfL, halfH)
          ..close();

        final rightCylinder = Path()
          ..moveTo(0, -halfH)
          ..lineTo(halfL, -halfH)
          ..lineTo(halfL, halfH)
          ..lineTo(0, halfH)
          ..close();

        _drawWing(canvas, leftCylinder, symbolConfig.leftWingStyle, halfL, halfH,
            whiteFillPaint, solidFillPaint, strokePaint, hatchPaint);
        _drawWing(canvas, rightCylinder, symbolConfig.rightWingStyle, halfL, halfH,
            whiteFillPaint, solidFillPaint, strokePaint, hatchPaint);
        break;

      case Valve3dBodyShape.bellows:
        // Гофрированный сильфон (зигзагообразный контур)
        final bellowsPath = Path();
        const ripples = 3;
        final dx = (halfL * 2) / (ripples * 2);
        bellowsPath.moveTo(-halfL, -halfH * 0.8);
        for (int i = 0; i < ripples * 2; i++) {
          final x = -halfL + dx * (i + 1);
          final y = (i % 2 == 0) ? -halfH * 1.35 : -halfH * 0.65;
          bellowsPath.lineTo(x, y);
        }
        bellowsPath.lineTo(halfL, halfH * 0.8);
        for (int i = ripples * 2 - 1; i >= 0; i--) {
          final x = -halfL + dx * i;
          final y = (i % 2 == 0) ? halfH * 0.65 : halfH * 1.35;
          bellowsPath.lineTo(x, y);
        }
        bellowsPath.close();

        _drawWing(canvas, bellowsPath, symbolConfig.leftWingStyle, halfL, halfH,
            whiteFillPaint, solidFillPaint, strokePaint, hatchPaint);
        break;

      case Valve3dBodyShape.sphere:
        // Круглое/сферическое тело на оси трубы
        final sphereRadius = halfH * 1.15;
        final spherePath = Path()
          ..addOval(Rect.fromCircle(center: Offset.zero, radius: sphereRadius));

        _drawWing(canvas, spherePath, symbolConfig.leftWingStyle, halfL, halfH,
            whiteFillPaint, solidFillPaint, strokePaint, hatchPaint);

        // Подводящие патрубки к сфере от торцов арматуры
        canvas.drawLine(Offset(-halfL, 0), Offset(-sphereRadius, 0), strokePaint);
        canvas.drawLine(Offset(sphereRadius, 0), Offset(halfL, 0), strokePaint);
        canvas.drawLine(Offset(-halfL, -halfH * 0.5), Offset(-halfL, halfH * 0.5), strokePaint);
        canvas.drawLine(Offset(halfL, -halfH * 0.5), Offset(halfL, halfH * 0.5), strokePaint);
        break;
    }

    // Фланцевые торцевые засечки
    if (symbolConfig.hasBodyFlanges) {
      final tickH = halfH * 1.25;
      canvas.drawLine(Offset(-halfL, -tickH), Offset(-halfL, tickH), strokePaint);
      canvas.drawLine(Offset(halfL, -tickH), Offset(halfL, tickH), strokePaint);
    }

    // Разделитель по центру
    switch (symbolConfig.dividerType) {
      case ValveDividerType.none:
        break;
      case ValveDividerType.line:
        canvas.drawLine(Offset(0, -halfH), Offset(0, halfH), strokePaint);
        break;
      case ValveDividerType.slantedDisc:
        canvas.drawLine(
          Offset(-halfL * 0.25, -halfH * 0.9),
          Offset(halfL * 0.25, halfH * 0.9),
          strokePaint,
        );
        break;
      case ValveDividerType.zigzag:
        final zig = Path()
          ..moveTo(0, -halfH)
          ..lineTo(-halfL * 0.15, -halfH * 0.5)
          ..lineTo(halfL * 0.15, 0)
          ..lineTo(-halfL * 0.15, halfH * 0.5)
          ..lineTo(0, halfH);
        canvas.drawPath(zig, strokePaint);
        break;
      case ValveDividerType.arrow:
        final arrowPaint = Paint()
          ..color = color
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke;
        canvas.drawLine(Offset(-halfL * 0.6, 0), Offset(halfL * 0.6, 0), arrowPaint);
        final arrowHead = Path()
          ..moveTo(halfL * 0.6, 0)
          ..lineTo(halfL * 0.35, -halfH * 0.4)
          ..moveTo(halfL * 0.6, 0)
          ..lineTo(halfL * 0.35, halfH * 0.4);
        canvas.drawPath(arrowHead, arrowPaint);
        break;
      case ValveDividerType.circle:
        canvas.drawCircle(Offset.zero, halfH * 0.65, whiteFillPaint);
        canvas.drawCircle(Offset.zero, halfH * 0.65, strokePaint);
        break;
    }

    // Шток и привод арматуры
    switch (symbolConfig.stemType) {
      case ValveStemSymbolType.none:
        break;
      case ValveStemSymbolType.handwheel:
        canvas.drawLine(Offset.zero, Offset(0, -halfH * 1.55), strokePaint);
        canvas.drawLine(Offset(-2.0, -halfH * 0.7), Offset(2.0, -halfH * 0.7), strokePaint);
        final wheelCenter = Offset(0, -halfH * 1.55);
        final wheelRect = Rect.fromCenter(
          center: wheelCenter,
          width: halfL * 0.85,
          height: halfH * 0.65,
        );
        canvas.drawOval(wheelRect, whiteFillPaint);
        canvas.drawOval(wheelRect, strokePaint);
        canvas.drawLine(
          Offset(-halfL * 0.35, wheelCenter.dy),
          Offset(halfL * 0.35, wheelCenter.dy),
          hatchPaint,
        );
        canvas.drawLine(
          Offset(0, wheelCenter.dy - halfH * 0.28),
          Offset(0, wheelCenter.dy + halfH * 0.28),
          hatchPaint,
        );
        break;
      case ValveStemSymbolType.lever:
        canvas.drawLine(Offset.zero, Offset(halfL * 0.85, -halfH * 1.45), strokePaint);
        canvas.drawCircle(
          Offset(halfL * 0.85, -halfH * 1.45),
          2.2,
          solidFillPaint,
        );
        break;
      case ValveStemSymbolType.boxWithText:
        canvas.drawLine(Offset.zero, Offset(0, -halfH * 1.3), strokePaint);
        final boxCenter = Offset(0, -halfH * 1.95);
        final boxRect = Rect.fromCenter(
          center: boxCenter,
          width: halfL * 0.95,
          height: halfH * 1.1,
        );
        canvas.drawRect(boxRect, whiteFillPaint);
        canvas.drawRect(boxRect, strokePaint);
        if (symbolConfig.stemText.isNotEmpty) {
          final tp = TextPainter(
            text: TextSpan(
              text: symbolConfig.stemText,
              style: TextStyle(
                color: color,
                fontSize: halfH * 0.75,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(
            canvas,
            Offset(boxCenter.dx - tp.width / 2, boxCenter.dy - tp.height / 2),
          );
        }
        break;
      case ValveStemSymbolType.diaphragm:
        canvas.drawLine(Offset.zero, Offset(0, -halfH * 1.3), strokePaint);
        final dCenter = Offset(0, -halfH * 1.9);
        final dRect = Rect.fromCenter(
          center: dCenter,
          width: halfL * 1.05,
          height: halfH * 0.9,
        );
        canvas.drawOval(dRect, whiteFillPaint);
        canvas.drawOval(dRect, strokePaint);
        canvas.drawLine(
          Offset(-halfL * 0.5, dCenter.dy),
          Offset(halfL * 0.5, dCenter.dy),
          strokePaint,
        );
        if (symbolConfig.stemText.isNotEmpty) {
          final tp = TextPainter(
            text: TextSpan(
              text: symbolConfig.stemText,
              style: TextStyle(
                color: color,
                fontSize: halfH * 0.65,
                fontWeight: FontWeight.bold,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(
            canvas,
            Offset(dCenter.dx - tp.width / 2, dCenter.dy - tp.height / 2),
          );
        }
        break;
      case ValveStemSymbolType.spring:
        final spring = Path()
          ..moveTo(0, 0)
          ..lineTo(0, -halfH * 0.4)
          ..lineTo(-halfL * 0.2, -halfH * 0.7)
          ..lineTo(halfL * 0.2, -halfH * 1.0)
          ..lineTo(-halfL * 0.2, -halfH * 1.3)
          ..lineTo(halfL * 0.2, -halfH * 1.6)
          ..lineTo(0, -halfH * 1.9)
          ..lineTo(0, -halfH * 2.3);
        canvas.drawPath(spring, strokePaint);
        canvas.drawLine(
          Offset(-halfL * 0.3, -halfH * 2.3),
          Offset(halfL * 0.3, -halfH * 2.3),
          strokePaint,
        );
        break;
    }

    canvas.restore();
  }

  static void _drawWing(
    Canvas canvas,
    Path path,
    ValveWingFillStyle style,
    double halfL,
    double halfH,
    Paint whiteFillPaint,
    Paint solidFillPaint,
    Paint strokePaint,
    Paint hatchPaint,
  ) {
    switch (style) {
      case ValveWingFillStyle.outline:
        canvas.drawPath(path, whiteFillPaint);
        canvas.drawPath(path, strokePaint);
        break;
      case ValveWingFillStyle.solid:
        canvas.drawPath(path, solidFillPaint);
        canvas.drawPath(path, strokePaint);
        break;
      case ValveWingFillStyle.hatched:
        canvas.drawPath(path, whiteFillPaint);
        canvas.save();
        canvas.clipPath(path);
        final span = halfL * 2.5;
        for (double x = -span; x <= span; x += 3.0) {
          canvas.drawLine(
            Offset(x, -halfH * 2.0),
            Offset(x + halfH * 3.0, halfH * 2.0),
            hatchPaint,
          );
        }
        canvas.restore();
        canvas.drawPath(path, strokePaint);
        break;
      case ValveWingFillStyle.crossHatched:
        canvas.drawPath(path, whiteFillPaint);
        canvas.save();
        canvas.clipPath(path);
        final span = halfL * 2.5;
        for (double x = -span; x <= span; x += 3.0) {
          canvas.drawLine(
            Offset(x, -halfH * 2.0),
            Offset(x + halfH * 3.0, halfH * 2.0),
            hatchPaint,
          );
          canvas.drawLine(
            Offset(x, halfH * 2.0),
            Offset(x + halfH * 3.0, -halfH * 2.0),
            hatchPaint,
          );
        }
        canvas.restore();
        canvas.drawPath(path, strokePaint);
        break;
    }
  }
}

