import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Прямоугольное препятствие (полочка выноски, оборудование и т.д.)
class RectObstacle {
  final Rect rect;
  final String? id;

  const RectObstacle(this.rect, [this.id]);
}

/// Линейное препятствие (коридор трубы или линия-выноска)
class SegmentObstacle {
  final Offset p1;
  final Offset p2;
  final double radius;
  final String? id;

  const SegmentObstacle(this.p1, this.p2, {this.radius = 0.0, this.id});
}

/// 2D Пространственная карта препятствий для расстановки выносок
class CalloutObstacleMap {
  final List<RectObstacle> rects = [];
  final List<SegmentObstacle> pipes = [];
  final List<SegmentObstacle> leaderLines = [];

  void addRect(Rect rect, [String? id]) {
    rects.add(RectObstacle(rect, id));
  }

  void addPipe(Offset p1, Offset p2, double radiusPx, [String? id]) {
    pipes.add(SegmentObstacle(p1, p2, radius: radiusPx, id: id));
  }

  void addLeaderLine(Offset start, Offset end, [String? id]) {
    leaderLines.add(SegmentObstacle(start, end, radius: 0.0, id: id));
  }

  /// Проверяет пересечение полочки с другими прямоугольниками выносок
  bool testShelfRectOverlap(Rect shelfRect) {
    for (final r in rects) {
      if (r.rect.overlaps(shelfRect)) {
        return true;
      }
    }
    return false;
  }

  /// Проверяет пересечение полочки с коридорами трубопроводов
  bool testShelfPipeCollision(Rect shelfRect) {
    for (final pipe in pipes) {
      if (_rectCollidesWithSegment(shelfRect, pipe.p1, pipe.p2, pipe.radius)) {
        return true;
      }
    }
    return false;
  }

  /// Проверяет, пересекается ли прямоугольник полочки с другими выносками
  /// или коридорами трубопроводов
  bool testShelfCollision(Rect shelfRect) {
    return testShelfRectOverlap(shelfRect) || testShelfPipeCollision(shelfRect);
  }

  /// Подсчитывает количество пересечений стрелки-выноски с чужими трубами
  /// и другими линиями-выносками
  int countLeaderLineIntersections(Offset start, Offset end) {
    int count = 0;

    for (final pipe in pipes) {
      if (_segmentsIntersect(start, end, pipe.p1, pipe.p2)) {
        count++;
      }
    }

    for (final leader in leaderLines) {
      if (_segmentsIntersect(start, end, leader.p1, leader.p2)) {
        count++;
      }
    }

    return count;
  }

  /// Расстояние от точки p до отрезка [s1, s2]
  double pointToSegmentDistance(Offset p, Offset s1, Offset s2) {
    return _pointToSegmentDist(p, s1, s2);
  }

  static double _pointToSegmentDist(Offset p, Offset s1, Offset s2) {
    final dx = s2.dx - s1.dx;
    final dy = s2.dy - s1.dy;
    final lenSq = dx * dx + dy * dy;
    if (lenSq <= 1e-9) {
      return (p - s1).distance;
    }
    final t = ((p.dx - s1.dx) * dx + (p.dy - s1.dy) * dy) / lenSq;
    final clampedT = t.clamp(0.0, 1.0);
    final proj = Offset(s1.dx + clampedT * dx, s1.dy + clampedT * dy);
    return (p - proj).distance;
  }

  static double _pointToRectDist(Offset p, Rect rect) {
    final dx = math.max(0.0, math.max(rect.left - p.dx, p.dx - rect.right));
    final dy = math.max(0.0, math.max(rect.top - p.dy, p.dy - rect.bottom));
    return math.sqrt(dx * dx + dy * dy);
  }

  static bool _rectCollidesWithSegment(
    Rect rect,
    Offset p1,
    Offset p2,
    double radius,
  ) {
    // 1. Проверяем расстояние от концов отрезка до прямоугольника
    if (_pointToRectDist(p1, rect) <= radius) return true;
    if (_pointToRectDist(p2, rect) <= radius) return true;

    // 2. Проверяем расстояние от 4 углов прямоугольника до отрезка
    if (_pointToSegmentDist(rect.topLeft, p1, p2) <= radius) return true;
    if (_pointToSegmentDist(rect.topRight, p1, p2) <= radius) return true;
    if (_pointToSegmentDist(rect.bottomLeft, p1, p2) <= radius) return true;
    if (_pointToSegmentDist(rect.bottomRight, p1, p2) <= radius) return true;

    // 3. Проверяем прямое пересечение отрезка с 4 сторонами прямоугольника
    final rTL = rect.topLeft;
    final rTR = rect.topRight;
    final rBL = rect.bottomLeft;
    final rBR = rect.bottomRight;

    if (_segmentsIntersect(p1, p2, rTL, rTR, tolerance: 0.0) ||
        _segmentsIntersect(p1, p2, rTR, rBR, tolerance: 0.0) ||
        _segmentsIntersect(p1, p2, rBR, rBL, tolerance: 0.0) ||
        _segmentsIntersect(p1, p2, rBL, rTL, tolerance: 0.0)) {
      return true;
    }

    // 4. Проверяем, лежит ли середина отрезка внутри прямоугольника
    final mid = Offset((p1.dx + p2.dx) * 0.5, (p1.dy + p2.dy) * 0.5);
    if (rect.contains(mid)) return true;

    return false;
  }

  static bool _segmentsIntersect(
    Offset a1,
    Offset a2,
    Offset b1,
    Offset b2, {
    double tolerance = 0.02,
  }) {
    final dax = a2.dx - a1.dx;
    final day = a2.dy - a1.dy;
    final dbx = b2.dx - b1.dx;
    final dby = b2.dy - b1.dy;

    final denom = dax * dby - day * dbx;
    if (denom.abs() < 1e-9) return false;

    final t = ((b1.dx - a1.dx) * dby - (b1.dy - a1.dy) * dbx) / denom;
    final u = ((b1.dx - a1.dx) * day - (b1.dy - a1.dy) * dax) / denom;

    return t >= tolerance && t <= (1.0 - tolerance) && u >= 0.0 && u <= 1.0;
  }
}

/// Кандидат расположения выноски с рассчитанной стоимостью (штрафом)
class CalloutCandidate {
  final Offset offset;
  final Rect shelfBounds;
  final double cost;

  const CalloutCandidate({
    required this.offset,
    required this.shelfBounds,
    required this.cost,
  });
}

/// Движок интеллектуального размещения и предотвращения коллизий выносок
class CalloutLayoutEngine {
  static const double shelfTextOverlapPenalty = 10000.0;
  static const double shelfPipeOverlapPenalty = 5000.0;
  static const double leaderCrossPenalty = 800.0;
  static const double distancePenaltyWeight = 1.5;
  static const double columnAlignmentReward = 150.0;

  /// Оценивает и находит наилучшее смещение (dx, dy) для выноски вокруг точки anchor
  static Offset? evaluateBestOffset({
    required Offset anchor,
    required double textWidth,
    required double textHeight,
    required CalloutObstacleMap obstacleMap,
    List<double>? existingShelfXPositions,
    double minRadius = 35.0,
    double maxRadius = 150.0,
  }) {
    final candidate = findBestCandidate(
      anchor: anchor,
      textWidth: textWidth,
      textHeight: textHeight,
      obstacleMap: obstacleMap,
      existingShelfXPositions: existingShelfXPositions,
      minRadius: minRadius,
      maxRadius: maxRadius,
    );
    return candidate?.offset;
  }

  /// Генерирует веер кандидатов и выбирает кандидата с минимальной стоимостью
  static CalloutCandidate? findBestCandidate({
    required Offset anchor,
    required double textWidth,
    required double textHeight,
    required CalloutObstacleMap obstacleMap,
    List<double>? existingShelfXPositions,
    double minRadius = 35.0,
    double maxRadius = 150.0,
  }) {
    final shelfWidth = textWidth + 10.0;
    final totalHeight = textHeight + 8.0;

    // Секторы углов (в градусах). В экранной системе Y направлен вниз.
    // Отрицательные углы соответствуют направлению вверх.
    final angleDegrees = <double>[
      // Квадрант I: Вверх-вправо (приоритет по ГОСТ)
      -45.0, -30.0, -60.0, -15.0, -75.0,
      // Квадрант IV: Вниз-вправо
      45.0, 30.0, 60.0, 15.0, 75.0,
      // Квадрант II: Вверх-влево
      -135.0, -150.0, -120.0, -165.0, -105.0,
      // Квадрант III: Вниз-влево
      135.0, 150.0, 120.0, 165.0, 105.0,
    ];

    // Динамические радиусы отступа от точки привязки
    final radii = <double>[
      minRadius,
      minRadius + 15.0,
      minRadius + 30.0,
      minRadius + 50.0,
      minRadius + 75.0,
      maxRadius,
    ];

    CalloutCandidate? bestCandidate;
    double lowestCost = double.infinity;

    for (final r in radii) {
      for (final deg in angleDegrees) {
        final rad = deg * math.pi / 180.0;
        final dx = r * math.cos(rad);
        final dy = r * math.sin(rad);
        final offset = Offset(dx, dy);

        final shelfStart = anchor + offset;
        final bounds = Rect.fromLTWH(
          shelfStart.dx,
          shelfStart.dy - textHeight - 4.0,
          shelfWidth,
          totalHeight,
        );

        double cost = 0.0;

        // 1. Штраф за перекрытие текста/других полочек
        if (obstacleMap.testShelfRectOverlap(bounds)) {
          cost += shelfTextOverlapPenalty;
        }

        // 2. Штраф за перекрытие трубы полочкой
        if (obstacleMap.testShelfPipeCollision(bounds)) {
          cost += shelfPipeOverlapPenalty;
        }

        // 3. Штраф за пересечение стрелки-выноски с чужими объектами
        final crosses = obstacleMap.countLeaderLineIntersections(anchor, shelfStart);
        cost += crosses * leaderCrossPenalty;

        // 4. Штраф за удаленность от объекта
        cost += (r / minRadius) * distancePenaltyWeight;

        // 5. Небольшой приоритет естественного чертежного направления (вверх-вправо)
        if (dy > 0) cost += 30.0; // вниз
        if (dx < 0) cost += 25.0; // влево

        // 6. Бонус за выравнивание полочки в общую вертикальную колонку ("гребенка")
        if (existingShelfXPositions != null && existingShelfXPositions.isNotEmpty) {
          for (final colX in existingShelfXPositions) {
            if ((shelfStart.dx - colX).abs() <= 6.0) {
              cost -= columnAlignmentReward;
              break;
            }
          }
        }

        final candidate = CalloutCandidate(
          offset: offset,
          shelfBounds: bounds,
          cost: cost,
        );

        if (cost < lowestCost) {
          lowestCost = cost;
          bestCandidate = candidate;
        }
      }
    }

    return bestCandidate;
  }
}
