import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/drawing_sheet.dart';
import 'package:akso/domain/services/viewport_transform_service.dart';
import 'package:akso/core/math/axonometry_projector.dart';

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

  /// Вычисляет 3D узел привязки для выноски любого типа
  static Node3D? computeAnchorNode(Callout callout, PipingNetwork network) {
    switch (callout.targetType) {
      case CalloutTargetType.segment:
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

        final start = network.nodes[seg.startNodeId];
        final end = network.nodes[seg.endNodeId];
        if (start == null || end == null) return null;
        return Node3D(
          id: 'anchor_${callout.id}',
          x: (start.x + end.x) / 2.0,
          y: (start.y + end.y) / 2.0,
          z: (start.z + end.z) / 2.0,
        );

      case CalloutTargetType.node:
        return network.nodes[callout.targetId];

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

  /// Вычисляет экранную точку привязки (анкер) для выноски любого типа
  static Offset? computeAnchorScreen(
    Callout callout,
    PipingNetwork network,
    AxonometryProjector projector,
  ) {
    final anchorNode = computeAnchorNode(callout, network);
    if (anchorNode == null) return null;
    return projector.project(anchorNode);
  }

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

  /// Выполняет комплексную авто-расстановку выносок с обходом препятствий и
  /// формированием гребенок (колонок)
  static Map<String, Offset> calculateLayout({
    required PipingNetwork network,
    required AxonometryProjector projector,
    bool onlyUnpinned = true,
    double minRadius = 35.0,
    double maxRadius = 150.0,
    double textWidth = 60.0,
    double textHeight = 12.0,
  }) {
    final result = <String, Offset>{};
    final obstacleMap = CalloutObstacleMap();

    // 1. Регистрируем препятствия трубопроводов
    for (final seg in network.segments.values) {
      final start = network.nodes[seg.startNodeId];
      final end = network.nodes[seg.endNodeId];
      if (start == null || end == null) continue;

      final p1 = projector.project(start);
      final p2 = projector.project(end);
      final radiusPx = math.max(4.0, seg.outerDiameterMm * 0.05 + 4.0);
      obstacleMap.addPipe(p1, p2, radiusPx, seg.id);
    }

    // 2. Регистрируем закрепленные (isPinned) выноски
    final unpinnedCallouts = <Callout>[];
    final anchorMap = <String, Offset>{};

    for (final callout in network.callouts.values) {
      final anchor = computeAnchorScreen(callout, network, projector);
      if (anchor == null) continue;
      anchorMap[callout.id] = anchor;

      if (onlyUnpinned && callout.isPinned) {
        final offset = Offset(callout.screenOffsetX, callout.screenOffsetY);
        result[callout.id] = offset;
        final shelfStart = anchor + offset;
        final shelfRect = Rect.fromLTWH(
          shelfStart.dx,
          shelfStart.dy - textHeight - 4.0,
          textWidth + 10.0,
          textHeight + 8.0,
        );
        obstacleMap.addRect(shelfRect, callout.id);
        obstacleMap.addLeaderLine(anchor, shelfStart, callout.id);
      } else {
        unpinnedCallouts.add(callout);
      }
    }

    if (unpinnedCallouts.isEmpty) {
      return result;
    }

    // 3. Сортируем незакрепленные выноски по локальной плотности анкеров
    // (наиболее стесненные/плотные узлы обрабатываются первыми)
    unpinnedCallouts.sort((a, b) {
      final anchA = anchorMap[a.id]!;
      final anchB = anchorMap[b.id]!;
      int countNearA = 0;
      int countNearB = 0;
      for (final other in anchorMap.values) {
        if ((other - anchA).distance < 160.0) countNearA++;
        if ((other - anchB).distance < 160.0) countNearB++;
      }
      return countNearB.compareTo(countNearA);
    });

    // 4. Пасс 1: Индивидуальное оптимальное размещение
    final placedShelfX = <double>[];
    final placedInfo = <_PlacedCalloutInfo>[];

    for (final callout in unpinnedCallouts) {
      final anchor = anchorMap[callout.id]!;
      final candidate = findBestCandidate(
        anchor: anchor,
        textWidth: textWidth,
        textHeight: textHeight,
        obstacleMap: obstacleMap,
        existingShelfXPositions: placedShelfX,
        minRadius: minRadius,
        maxRadius: maxRadius,
      );

      final offset = candidate?.offset ?? const Offset(45.0, -35.0);
      result[callout.id] = offset;

      final shelfStart = anchor + offset;
      final bounds = candidate?.shelfBounds ??
          Rect.fromLTWH(
            shelfStart.dx,
            shelfStart.dy - textHeight - 4.0,
            textWidth + 10.0,
            textHeight + 8.0,
          );

      obstacleMap.addRect(bounds, callout.id);
      obstacleMap.addLeaderLine(anchor, shelfStart, callout.id);
      placedShelfX.add(shelfStart.dx);

      placedInfo.add(_PlacedCalloutInfo(
        callout: callout,
        anchor: anchor,
        shelfStart: shelfStart,
        bounds: bounds,
      ));
    }

    // 5. Пасс 2: Фаза выравнивания в вертикальные гребенки (Column Stacking)
    final stepY = textHeight + 8.0; // минимальный шаг между полочками по вертикали
    final processedIds = <String>{};

    for (int i = 0; i < placedInfo.length; i++) {
      final infoA = placedInfo[i];
      if (processedIds.contains(infoA.callout.id)) continue;

      final cluster = <_PlacedCalloutInfo>[infoA];

      for (int j = i + 1; j < placedInfo.length; j++) {
        final infoB = placedInfo[j];
        if (processedIds.contains(infoB.callout.id)) continue;

        // Если полочки близки по горизонтали и точки привязки находятся в разумной близости
        if ((infoA.shelfStart.dx - infoB.shelfStart.dx).abs() <= 35.0 &&
            (infoA.anchor.dx - infoB.anchor.dx).abs() <= 180.0) {
          cluster.add(infoB);
        }
      }

      if (cluster.length >= 2) {
        // Найдена группа для гребенки: выравниваем по средней оси X
        final avgX = cluster.map((c) => c.shelfStart.dx).reduce((a, b) => a + b) / cluster.length;
        cluster.sort((a, b) => a.shelfStart.dy.compareTo(b.shelfStart.dy));

        double currentY = cluster.first.shelfStart.dy;
        for (int k = 0; k < cluster.length; k++) {
          final item = cluster[k];
          processedIds.add(item.callout.id);

          final targetY = k == 0 ? item.shelfStart.dy : math.max(item.shelfStart.dy, currentY + stepY);
          currentY = targetY;

          final candidateRect = Rect.fromLTWH(
            avgX,
            targetY - textHeight - 4.0,
            textWidth + 10.0,
            textHeight + 8.0,
          );

          // Применяем выравнивание, если полочка не падает на трубу
          if (!obstacleMap.testShelfPipeCollision(candidateRect)) {
            result[item.callout.id] = Offset(avgX - item.anchor.dx, targetY - item.anchor.dy);
          }
        }
      }
    }

    return result;
  }

  /// Выполняет контекстную авто-расстановку выносок для конкретного чертежного листа
  /// с учетом фильтра видимых категорий листа, масштаба видового экрана и запретных зон (штамп, таблицы).
  /// Выполняет контекстную авто-расстановку выносок для конкретного чертежного листа
  /// методом периферийных упорядоченных колонок (Boundary Column Stacking) с 0 пересечений,
  /// адаптивным динамическим шагом, изоляцией высотных отметок и опциональными этажерками.
  static Map<String, Offset> calculateSheetLayout({
    required DrawingSheet sheet,
    required PipingNetwork network,
    required AxonometryProjector projector,
    bool onlyUnpinned = true,
    bool? groupMultiLevel,
    double? customPitchMm,
    double minRadiusMm = 12.0,
    double maxRadiusMm = 35.0,
  }) {
    final result = <String, Offset>{};
    final vp = sheet.viewport;
    final fmt = sheet.format;

    // 1. Границы рабочей рамки чертежного листа
    final frameLeft = fmt.frameLeftMm + 2.0;
    final frameRight = fmt.widthMm - fmt.frameRightMm - 2.0;
    final frameTop = fmt.frameTopMm + 2.0;
    final frameBottom = fmt.heightMm - fmt.frameBottomMm - 2.0;

    // 2. Запретные зоны: штамп (Форма 3: 185x55 мм в правом нижнем углу) и таблицы
    final stampTop = fmt.heightMm - fmt.frameBottomMm - 55.0 - 2.0;
    double minTableY = double.infinity;
    for (final t in sheet.tables) {
      if (t.yMm < minTableY) minTableY = t.yMm;
    }
    if (sheet.technicalRequirements != null) {
      if (sheet.technicalRequirements!.yMm < minTableY) {
        minTableY = sheet.technicalRequirements!.yMm;
      }
    }

    final rightColMaxY = math.min(stampTop - 4.0, minTableY - 4.0);
    final leftColMaxY = frameBottom - 4.0;
    final colMinY = frameTop + 4.0;

    // 3. Вычисляем охватывающий прямоугольник (AABB) активных трубопроводов на листе
    final visibleSys = vp.visibleSystemIds;
    double minNetX = double.infinity, maxNetX = -double.infinity;
    double minNetY = double.infinity, maxNetY = -double.infinity;

    for (final seg in network.segments.values) {
      if (visibleSys != null && visibleSys.isNotEmpty && !visibleSys.contains(seg.systemId)) {
        continue;
      }
      final start = network.nodes[seg.startNodeId];
      final end = network.nodes[seg.endNodeId];
      if (start == null || end == null) continue;

      final p1Raw = projector.projectRaw(start.x, start.y, start.z);
      final p2Raw = projector.projectRaw(end.x, end.y, end.z);
      final p1Mm = ViewportTransformService.model2dToSheetMm(p1Raw, vp);
      final p2Mm = ViewportTransformService.model2dToSheetMm(p2Raw, vp);

      minNetX = math.min(minNetX, math.min(p1Mm.dx, p2Mm.dx));
      maxNetX = math.max(maxNetX, math.max(p1Mm.dx, p2Mm.dx));
      minNetY = math.min(minNetY, math.min(p1Mm.dy, p2Mm.dy));
      maxNetY = math.max(maxNetY, math.max(p1Mm.dy, p2Mm.dy));
    }

    if (minNetX.isInfinite) {
      minNetX = frameLeft + 35.0;
      maxNetX = frameRight - 35.0;
      minNetY = frameTop + 30.0;
      maxNetY = frameBottom - 30.0;
    }
    final midX = (minNetX + maxNetX) / 2.0;

    // 4. Отбор видимых выносок листа
    final columnCalloutItems = <_SheetCalloutItem>[];

    for (final callout in network.callouts.values) {
      if (!sheet.isCalloutVisible(callout)) continue;

      final segId = network.getTargetSegmentId(callout.targetType, callout.targetId);
      if (segId != null && visibleSys != null && visibleSys.isNotEmpty) {
        final seg = network.segments[segId];
        if (seg != null && !visibleSys.contains(seg.systemId)) continue;
      }

      final anchor3D = computeAnchorNode(callout, network);
      if (anchor3D == null) continue;

      final raw2D = projector.projectRaw(anchor3D.x, anchor3D.y, anchor3D.z);
      final anchorMm = ViewportTransformService.model2dToSheetMm(raw2D, vp);

      // Закрепленные выноски (isPinned)
      if (onlyUnpinned && callout.isPinned) {
        result[callout.id] = callout.getEffectiveOffset(sheet.id);
        continue;
      }

      // 5. Изоляция высотных отметок (Elevation): остаются прямо у своих узлов
      if (callout.targetType == CalloutTargetType.node || callout.elevationStyle != null) {
        final dyMm = -(callout.textHeight * 2.2 + 3.0);
        result[callout.id] = Offset(0.0, dyMm / 0.35);
        continue;
      }

      final charWidthMm = callout.textHeight * 0.65;
      final textMm = network.generateCalloutText(callout, defaultCalloutTemplates);
      final textWidthMm = math.max(10.0, textMm.length * charWidthMm + 3.0);

      columnCalloutItems.add(_SheetCalloutItem(
        callout: callout,
        anchorMm: anchorMm,
        textWidthMm: textWidthMm,
        textHeightMm: callout.textHeight,
      ));
    }

    if (columnCalloutItems.isEmpty) {
      return result;
    }

    // 6. Группировка по сторонам (Left vs Right)
    final leftItems = columnCalloutItems.where((c) => c.anchorMm.dx <= midX).toList();
    final rightItems = columnCalloutItems.where((c) => c.anchorMm.dx > midX).toList();

    final effectiveGroup = groupMultiLevel ?? sheet.groupMultiLevelCallouts;

    List<_SheetNodeCluster> buildClusters(List<_SheetCalloutItem> items) {
      if (items.isEmpty) return [];

      if (!effectiveGroup) {
        return items.map((item) => _SheetNodeCluster(anchorMm: item.anchorMm, items: [item])).toList();
      }

      final clusters = <_SheetNodeCluster>[];
      final visited = <String>{};

      for (int i = 0; i < items.length; i++) {
        final itemA = items[i];
        if (visited.contains(itemA.callout.id)) continue;

        final clusterItems = <_SheetCalloutItem>[itemA];
        visited.add(itemA.callout.id);

        for (int j = i + 1; j < items.length; j++) {
          final itemB = items[j];
          if (visited.contains(itemB.callout.id)) continue;

          if ((itemA.anchorMm - itemB.anchorMm).distance < 4.5) {
            clusterItems.add(itemB);
            visited.add(itemB.callout.id);
          }
        }

        // Сортировка внутри этажерки по приоритету УГО по ГОСТ:
        // Арматура (А) -> Фасонина -> Сварные стыки (К) -> Штуцеры -> Оборудование -> Опоры -> Прочее
        clusterItems.sort((a, b) {
          int priority(Callout c) {
            switch (c.targetType) {
              case CalloutTargetType.valve: return 1;
              case CalloutTargetType.fitting: return 2;
              case CalloutTargetType.weld: return 3;
              case CalloutTargetType.nozzle: return 4;
              case CalloutTargetType.equipment: return 5;
              case CalloutTargetType.support: return 6;
              default: return 7;
            }
          }
          return priority(a.callout).compareTo(priority(b.callout));
        });

        clusters.add(_SheetNodeCluster(
          anchorMm: itemA.anchorMm,
          items: clusterItems,
        ));
      }

      return clusters;
    }

    final leftClusters = buildClusters(leftItems);
    final rightClusters = buildClusters(rightItems);

    // 7. Позиционирование направляющих X
    final colLeftX = (minNetX - 22.0).clamp(frameLeft + 26.0, midX - 35.0);
    final colRightX = (maxNetX + 18.0).clamp(midX + 35.0, frameRight - 28.0);

    // 8. Sweep-Line раскладка колонки с гарантией 0 пересечений
    void layoutColumn({
      required List<_SheetNodeCluster> clusters,
      required double colX,
      required double minY,
      required double maxY,
      required bool isLeft,
    }) {
      if (clusters.isEmpty) return;

      // Монотонная сортировка вдоль оси Y для исключения пересечений линий
      clusters.sort((a, b) => a.anchorY.compareTo(b.anchorY));

      final totalShelves = clusters.fold<int>(0, (sum, c) => sum + c.items.length);
      final availHeight = math.max(10.0, maxY - minY);
      final avgTextH = clusters.first.items.first.textHeightMm;

      final idealPitch = customPitchMm ?? (avgTextH * 2.2);
      final minPitch = avgTextH + 1.2;

      // Проверка на необходимость двухрядной колонки (Multi-Tier)
      final maxShelvesSingleTier = (availHeight / minPitch).floor();
      if (totalShelves > maxShelvesSingleTier && totalShelves > 1) {
        final outerClusters = <_SheetNodeCluster>[];
        final innerClusters = <_SheetNodeCluster>[];

        for (int i = 0; i < clusters.length; i++) {
          if (i % 2 == 0) {
            outerClusters.add(clusters[i]);
          } else {
            innerClusters.add(clusters[i]);
          }
        }

        final outerX = isLeft
            ? math.max(frameLeft + 12.0, colX - 28.0)
            : math.min(frameRight - 12.0, colX + 28.0);

        layoutColumn(
          clusters: outerClusters,
          colX: outerX,
          minY: minY,
          maxY: maxY,
          isLeft: isLeft,
        );
        layoutColumn(
          clusters: innerClusters,
          colX: colX,
          minY: minY,
          maxY: maxY,
          isLeft: isLeft,
        );
        return;
      }

      // Адаптивный динамический шаг полочек
      final effectivePitch = totalShelves * idealPitch <= availHeight
          ? idealPitch
          : math.max(minPitch, availHeight / totalShelves);

      // Центрирование блока полочек по средней высоте анкеров, если места достаточно
      double startY = minY;
      final blockHeight = totalShelves * effectivePitch;
      if (blockHeight < availHeight) {
        final avgAnchorY = clusters.map((c) => c.anchorY).reduce((a, b) => a + b) / clusters.length;
        final idealStart = avgAnchorY - blockHeight / 2.0;
        startY = idealStart.clamp(minY, maxY - blockHeight);
      }

      double currentY = startY;
      for (final cluster in clusters) {
        for (int k = 0; k < cluster.items.length; k++) {
          final item = cluster.items[k];
          final slotY = currentY;
          currentY += effectivePitch;

          final offMm = Offset(colX - item.anchorMm.dx, slotY - item.anchorMm.dy);
          final storedOff = Offset(offMm.dx / 0.35, offMm.dy / 0.35);
          result[item.callout.id] = storedOff;
        }
      }
    }

    // Раскладываем левую и правую колонки
    layoutColumn(
      clusters: leftClusters,
      colX: colLeftX,
      minY: colMinY,
      maxY: leftColMaxY,
      isLeft: true,
    );

    layoutColumn(
      clusters: rightClusters,
      colX: colRightX,
      minY: colMinY,
      maxY: rightColMaxY,
      isLeft: false,
    );

    return result;
  }
}

class _SheetCalloutItem {
  final Callout callout;
  final Offset anchorMm;
  final double textWidthMm;
  final double textHeightMm;

  _SheetCalloutItem({
    required this.callout,
    required this.anchorMm,
    required this.textWidthMm,
    required this.textHeightMm,
  });
}

class _SheetNodeCluster {
  final Offset anchorMm;
  final List<_SheetCalloutItem> items;

  _SheetNodeCluster({
    required this.anchorMm,
    required this.items,
  });

  double get anchorY => anchorMm.dy;
  double get anchorX => anchorMm.dx;
  int get itemCount => items.length;
}

class _PlacedCalloutInfo {
  final Callout callout;
  final Offset anchor;
  Offset shelfStart;
  Rect bounds;

  _PlacedCalloutInfo({
    required this.callout,
    required this.anchor,
    required this.shelfStart,
    required this.bounds,
  });
}
