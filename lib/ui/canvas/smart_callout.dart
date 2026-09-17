import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Класс умных выносок с экранным автовыравниванием (Billboard)
/// Полочка выноски ВСЕГДА строго горизонтальна по ГОСТ 2.316 независимо от ракурса
class SmartCallout {
  /// Отрисовка выноски сварного соединения (№ шва и клеймо сварщика)
  /// Обозначение по ГОСТ 2.312 / ГОСТ 21.602
  static void drawWeldCallout(
    Canvas canvas, {
    required Offset weldPoint,
    required int weldNumber,
    required String stamp,
    required String gostType,
    Color color = Colors.black87,
    bool isLeftSided = false,
    bool drawMarker = true,
  }) {
    final leaderLength = 35.0;
    final shelfLength = 65.0;
    final shelfDirection = isLeftSided ? -1.0 : 1.0;

    // Точка начала на трубе: четкая засечка / точка
    if (drawMarker) {
      final dotPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(weldPoint, 3.5, dotPaint);
    }

    // Ножка выноски под углом ~45-60 градусов
    final elbowPoint = Offset(
      weldPoint.dx + (isLeftSided ? -leaderLength * 0.7 : leaderLength * 0.7),
      weldPoint.dy - leaderLength * 0.7,
    );

    // Конец горизонтальной полочки
    final shelfEndPoint = Offset(
      elbowPoint.dx + shelfLength * shelfDirection,
      elbowPoint.dy,
    );

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(weldPoint.dx, weldPoint.dy)
      ..lineTo(elbowPoint.dx, elbowPoint.dy)
      ..lineTo(shelfEndPoint.dx, shelfEndPoint.dy);
    canvas.drawPath(path, linePaint);

    // Текст над полочкой: № шва и тип шва (например, "№1 С17")
    final topText = '№$weldNumber $gostType';
    final topTextPainter = TextPainter(
      text: TextSpan(
        text: topText,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final textX = isLeftSided
        ? shelfEndPoint.dx + 4
        : elbowPoint.dx + 4;
    topTextPainter.paint(canvas, Offset(textX, elbowPoint.dy - 14));

    // Текст под полочкой: клеймо сварщика (например, "Кл. ИВ-24")
    if (stamp.isNotEmpty) {
      final bottomText = 'Кл. $stamp';
      final bottomTextPainter = TextPainter(
        text: TextSpan(
          text: bottomText,
          style: TextStyle(
            color: color.withValues(alpha: 0.85),
            fontSize: 10,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      bottomTextPainter.paint(canvas, Offset(textX, elbowPoint.dy + 2));
    }
  }

  /// Отрисовка флажка высотной отметки уровня по ГОСТ 21.101 (∇ +2.500)
  static void drawElevationCallout(
    Canvas canvas, {
    required Offset point,
    required String elevationText,
    Color color = Colors.black87,
    bool isLeftSided = false,
  }) {
    const flagSize = 7.0;
    const shelfLength = 55.0;
    final dir = isLeftSided ? -1.0 : 1.0;

    // Стрелка/флажок уровня: треугольник вершиной на точку отметки
    final flagPath = Path()
      ..moveTo(point.dx, point.dy)
      ..lineTo(point.dx - flagSize * 0.7 * dir, point.dy - flagSize * 1.3)
      ..lineTo(point.dx + flagSize * 0.7 * dir, point.dy - flagSize * 1.3)
      ..close();

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawPath(flagPath, fillPaint);

    // Вертикальная ножка от треугольника вверх к полочке
    final topOfFlagY = point.dy - flagSize * 1.3;
    final shelfY = topOfFlagY - 4.0;

    final shelfPath = Path()
      ..moveTo(point.dx, topOfFlagY)
      ..lineTo(point.dx, shelfY)
      ..lineTo(point.dx + shelfLength * dir, shelfY);
    canvas.drawPath(shelfPath, fillPaint);

    // Текст отметки (например, "+2.500") над полочкой
    final tp = TextPainter(
      text: TextSpan(
        text: elevationText,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final textX = isLeftSided ? (point.dx - shelfLength + 4) : (point.dx + 4);
    tp.paint(canvas, Offset(textX, shelfY - 14));
  }

  /// Отрисовка выноски диаметра трубы (например, "Ду 50" или "Ø 57x3.5")
  static void drawDiameterCallout(
    Canvas canvas, {
    required Offset midPoint,
    required String text,
    Color color = Colors.black87,
    bool isUp = true,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          backgroundColor: Colors.white.withValues(alpha: 0.75),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final offset = isUp ? const Offset(-15, -16) : const Offset(-15, 6);
    tp.paint(canvas, midPoint + offset);
  }

  /// Отрисовка стрелки уклона трубы по СПДС (i = 0.002)
  static void drawSlopeCallout(
    Canvas canvas, {
    required Offset p1,
    required Offset p2,
    required double slope,
    Color color = Colors.black54,
  }) {
    if (slope <= 0.0001) return;

    final midX = (p1.dx + p2.dx) / 2.0;
    final midY = (p1.dy + p2.dy) / 2.0;
    final mid = Offset(midX, midY);

    final angle = math.atan2(p2.dy - p1.dy, p2.dx - p1.dx);
    final slopeStr = 'i=${slope.toStringAsFixed(3)}';

    canvas.save();
    canvas.translate(mid.dx, mid.dy);
    canvas.rotate(angle);

    // Стрелка вдоль трубы
    final arrowPaint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final arrowPath = Path()
      ..moveTo(-15, -6)
      ..lineTo(15, -6)
      ..lineTo(10, -9)
      ..moveTo(15, -6)
      ..lineTo(10, -3);
    canvas.drawPath(arrowPath, arrowPaint);

    final tp = TextPainter(
      text: TextSpan(
        text: slopeStr,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(canvas, Offset(-tp.width / 2, -20));

    canvas.restore();
  }

  /// Отрисовка умной выноски для арматуры, фасонных деталей и оборудования
  /// по ГОСТ 2.316 / ГОСТ 21.101 с двухполочной полочкой:
  /// - Сверху: наименование / тип / Ду (например, "Задвижка 30ч6бр Ду100")
  /// - Снизу: ГОСТ / марка стали / позиция (например, "ГОСТ 5762-2002 / Поз. 4")
  static void drawElementCallout(
    Canvas canvas, {
    required Offset anchorPoint,
    required String topText,
    String? bottomText,
    Color color = Colors.black87,
    bool isLeftSided = false,
    double leaderLength = 35.0,
    double minShelfLength = 65.0,
  }) {
    // 1. Измерить текст над и под полочкой
    final topTp = TextPainter(
      text: TextSpan(
        text: topText,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
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
            color: color.withValues(alpha: 0.85),
            fontSize: 10,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    }

    final maxTextWidth = math.max(topTp.width, bottomTp?.width ?? 0.0);
    final shelfLength = math.max(minShelfLength, maxTextWidth + 10.0);
    final shelfDirection = isLeftSided ? -1.0 : 1.0;

    // 2. Точка начала на элементе: засечка/точка
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(anchorPoint, 3.0, dotPaint);

    // 3. Точка излома (начало полочки)
    final elbowPoint = Offset(
      anchorPoint.dx + (isLeftSided ? -leaderLength * 0.7 : leaderLength * 0.7),
      anchorPoint.dy - leaderLength * 0.7,
    );

    // 4. Конец полочки
    final shelfEndPoint = Offset(
      elbowPoint.dx + shelfLength * shelfDirection,
      elbowPoint.dy,
    );

    // 5. Белая фоновая плашка под текстом для изоляции от чертежа
    final shelfLeft = isLeftSided ? shelfEndPoint.dx : elbowPoint.dx;
    final totalHeight = topTp.height + 4.0 + (bottomTp != null ? bottomTp.height + 4.0 : 0.0);
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        shelfLeft,
        elbowPoint.dy - topTp.height - 3.0,
        shelfLength,
        totalHeight,
      ),
      const Radius.circular(2.0),
    );
    canvas.drawRRect(
      bgRect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.fill,
    );

    // 6. Линия-выноска и полочка
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    final path = Path()
      ..moveTo(anchorPoint.dx, anchorPoint.dy)
      ..lineTo(elbowPoint.dx, elbowPoint.dy)
      ..lineTo(shelfEndPoint.dx, shelfEndPoint.dy);
    canvas.drawPath(path, linePaint);

    // 7. Отрисовка текста
    final textX = isLeftSided ? shelfEndPoint.dx + 4 : elbowPoint.dx + 4;
    topTp.paint(canvas, Offset(textX, elbowPoint.dy - topTp.height - 2.0));

    if (bottomTp != null) {
      bottomTp.paint(canvas, Offset(textX, elbowPoint.dy + 2.0));
    }
  }
}
