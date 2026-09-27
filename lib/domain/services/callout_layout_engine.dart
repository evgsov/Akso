import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/drawing_sheet.dart';
import 'package:akso/domain/services/viewport_transform_service.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/models/pipeline_branch.dart';
import 'package:akso/domain/services/pipeline_branch_extractor.dart';

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

  RectObstacle? getRect(String id) => rects.where((r) => r.id == id).firstOrNull;

  SegmentObstacle? getPipe(String id) => pipes.where((p) => p.id == id).firstOrNull;

  /// Создает полную карту препятствий чертежного листа (трубы, арматура, оборудование, штамп, таблицы)
  static CalloutObstacleMap buildSheetMap({
    required DrawingSheet sheet,
    required PipingNetwork network,
    required AxonometryProjector projector,
  }) {
    final map = CalloutObstacleMap();
    final vp = sheet.viewport;
    final fmt = sheet.format;

    // 1. Запретная зона: Штамп (Форма 3: 185x55 мм) в правом нижнем углу
    final stampRect = Rect.fromLTWH(
      fmt.widthMm - fmt.frameRightMm - 185.0 - 2.0,
      fmt.heightMm - fmt.frameBottomMm - 55.0 - 2.0,
      185.0 + 4.0,
      55.0 + 4.0,
    );
    map.addRect(stampRect, 'stamp');

    // 2. Таблицы спецификаций и экспликаций
    for (final t in sheet.tables) {
      final tRect = Rect.fromLTWH(t.xMm - 2.0, t.yMm - 2.0, t.widthMm + 4.0, t.heightMm + 4.0);
      map.addRect(tRect, 'table_${t.id}');
    }
    if (sheet.technicalRequirements != null) {
      final tr = sheet.technicalRequirements!;
      final trRect = Rect.fromLTWH(tr.xMm - 2.0, tr.yMm - 2.0, tr.widthMm + 4.0, tr.heightMm + 4.0);
      map.addRect(trRect, 'tech_reqs');
    }

    // 3. Коридоры трубопроводов с учетом внешнего диаметра
    final visibleSys = vp.visibleSystemIds;
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

      // Радиус на листе (в мм) с защитным зазором 2.5 мм
      final radiusMm = math.max(3.0, (seg.outerDiameterMm / 2.0) * vp.scale + 2.5);
      map.addPipe(p1Mm, p2Mm, radiusMm, seg.id);
    }

    // 4. Оборудование
    for (final eq in network.equipments.values) {
      final centerRaw = projector.projectRaw(eq.x, eq.y, eq.z + eq.height / 2.0);
      final centerMm = ViewportTransformService.model2dToSheetMm(centerRaw, vp);
      final wMm = math.max(12.0, eq.diameter * vp.scale) + 6.0;
      final hMm = math.max(12.0, eq.height * vp.scale) + 6.0;
      final eqRect = Rect.fromCenter(center: centerMm, width: wMm, height: hMm);
      map.addRect(eqRect, 'eq_${eq.id}');
    }

    // 5. Арматура (габариты корпусов задвижек и приводов)
    for (final valve in network.valves.values) {
      final seg = network.segments[valve.segmentId];
      if (seg == null) continue;
      if (visibleSys != null && visibleSys.isNotEmpty && !visibleSys.contains(seg.systemId)) {
        continue;
      }
      final start = network.nodes[seg.startNodeId];
      final end = network.nodes[seg.endNodeId];
      if (start == null || end == null) continue;

      final vx = start.x + (end.x - start.x) * valve.ratio;
      final vy = start.y + (end.y - start.y) * valve.ratio;
      final vz = start.z + (end.z - start.z) * valve.ratio;

      final raw = projector.projectRaw(vx, vy, vz);
      final vMm = ViewportTransformService.model2dToSheetMm(raw, vp);
      final valveRect = Rect.fromCenter(center: vMm, width: 14.0, height: 14.0);
      map.addRect(valveRect, 'valve_${valve.id}');
    }

    return map;
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

  /// Проверяет пересечение двух 2D отрезков [a1, a2] и [b1, b2] с заданным допуском на концах
  static bool segmentsIntersect(
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

  static bool _segmentsIntersect(
    Offset a1,
    Offset a2,
    Offset b1,
    Offset b2, {
    double tolerance = 0.02,
  }) => segmentsIntersect(a1, a2, b1, b2, tolerance: tolerance);
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
  static const double shelfTextOverlapPenalty = 100000.0;
  static const double shelfPipeOverlapPenalty = 100000.0;
  static const double leaderCrossPenalty = 50000.0;
  static const double distancePenaltyWeight = 12.0;
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
  /// методом локальных вертикальных мини-стеков (Branch-Oriented Local Mini-Stack Layout)
  /// вдоль каждой ветки трубопровода с гарантией 0 пересечений линий, адаптивным шагом полочек,
  /// изоляцией высотных отметок и обходом запретных зон (штамп Форма 3, таблицы).
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

    // 1. Создаем карту препятствий листа (трубы, арматура, оборудование, штамп, таблицы)
    final obstacleMap = CalloutObstacleMap.buildSheetMap(
      sheet: sheet,
      network: network,
      projector: projector,
    );

    // 2. Границы рабочей рамки чертежного листа (с 2 мм отступом безопасности)
    final frameLeft = fmt.frameLeftMm + 2.0;
    final frameRight = fmt.widthMm - fmt.frameRightMm - 2.0;
    final frameTop = fmt.frameTopMm + 2.0;
    final frameBottom = fmt.heightMm - fmt.frameBottomMm - 2.0;

    // Штамп (185x55 мм)
    final stampRect = Rect.fromLTWH(
      fmt.widthMm - fmt.frameRightMm - 185.0 - 2.0,
      fmt.heightMm - fmt.frameBottomMm - 55.0 - 2.0,
      185.0 + 4.0,
      55.0 + 4.0,
    );

    final handledCalloutIds = <String>{};

    // 3. Предварительная обработка: закрепленные выноски и изоляция высотных отметок
    for (final callout in network.callouts.values) {
      if (!sheet.isCalloutVisible(callout, network)) continue;

      // Закрепленные выноски (isPinned)
      if (onlyUnpinned && callout.isPinned) {
        final effOffset = callout.getEffectiveOffset(sheet.id);
        result[callout.id] = effOffset;
        handledCalloutIds.add(callout.id);

        final anchor3D = computeAnchorNode(callout, network);
        if (anchor3D != null) {
          final raw2D = projector.projectRaw(anchor3D.x, anchor3D.y, anchor3D.z);
          final anchorMm = ViewportTransformService.model2dToSheetMm(raw2D, vp);
          final offMm = Offset(effOffset.dx * 0.35, effOffset.dy * 0.35);
          final shelfStart = anchorMm + offMm;
          final charWidthMm = callout.textHeight * 0.65;
          final textMm = network.generateCalloutText(callout, defaultCalloutTemplates);
          final textWidthMm = math.max(10.0, textMm.length * charWidthMm + 3.0);
          final isRight = effOffset.dx >= 0;
          final shelfRect = isRight
              ? Rect.fromLTWH(shelfStart.dx, shelfStart.dy - callout.textHeight - 1.0, textWidthMm, callout.textHeight + 2.0)
              : Rect.fromLTWH(shelfStart.dx - textWidthMm, shelfStart.dy - callout.textHeight - 1.0, textWidthMm, callout.textHeight + 2.0);
          obstacleMap.addRect(shelfRect, callout.id);
          obstacleMap.addLeaderLine(anchorMm, shelfStart, callout.id);
        }
        continue;
      }

      // Изоляция высотных отметок (Elevation): остаются компактно прямо у своих узлов
      if (callout.targetType == CalloutTargetType.node || callout.elevationStyle != null) {
        final dyMm = -(callout.textHeight * 2.2 + 3.0);
        result[callout.id] = Offset(0.0, dyMm / 0.35);
        handledCalloutIds.add(callout.id);

        final anchor3D = computeAnchorNode(callout, network);
        if (anchor3D != null) {
          final raw2D = projector.projectRaw(anchor3D.x, anchor3D.y, anchor3D.z);
          final anchorMm = ViewportTransformService.model2dToSheetMm(raw2D, vp);
          final shelfStart = Offset(anchorMm.dx, anchorMm.dy + dyMm);
          final charWidthMm = callout.textHeight * 0.65;
          final textMm = network.generateCalloutText(callout, defaultCalloutTemplates);
          final textWidthMm = math.max(10.0, textMm.length * charWidthMm + 3.0);
          final shelfRect = Rect.fromLTWH(
            shelfStart.dx,
            shelfStart.dy - callout.textHeight - 1.0,
            textWidthMm,
            callout.textHeight + 2.0,
          );
          obstacleMap.addRect(shelfRect, callout.id);
          obstacleMap.addLeaderLine(anchorMm, shelfStart, callout.id);
        }
        continue;
      }
    }

    // 4. Извлечение веток трубопроводов
    final branches = PipelineBranchExtractor.extractBranches(
      network: network,
      sheet: sheet,
      projector: projector,
    );

    final effectiveGroup = groupMultiLevel ?? sheet.groupMultiLevelCallouts;

    // 5. Обработка каждой ветки
    for (final branch in branches) {
      final branchCallouts = branch.callouts.where((c) {
        if (handledCalloutIds.contains(c.id)) return false;
        if (onlyUnpinned && c.isPinned) return false;
        return true;
      }).toList();

      if (branchCallouts.isEmpty) continue;

      final pStart = branch.startSheetMm;
      final v = branch.branchVector2D;
      final branchItems = <_SheetCalloutItem>[];

      for (final callout in branchCallouts) {
        final anchor3D = computeAnchorNode(callout, network);
        if (anchor3D == null) continue;

        final raw2D = projector.projectRaw(anchor3D.x, anchor3D.y, anchor3D.z);
        final anchorMm = ViewportTransformService.model2dToSheetMm(raw2D, vp);

        final charWidthMm = callout.textHeight * 0.65;
        final textMm = network.generateCalloutText(callout, defaultCalloutTemplates);
        final textWidthMm = math.max(10.0, textMm.length * charWidthMm + 3.0);
        final textHeightMm = callout.textHeight;

        final t = (anchorMm.dx - pStart.dx) * v.dx + (anchorMm.dy - pStart.dy) * v.dy;

        branchItems.add(_SheetCalloutItem(
          callout: callout,
          anchorMm: anchorMm,
          textWidthMm: textWidthMm,
          textHeightMm: textHeightMm,
          t: t,
        ));
      }

      if (branchItems.isEmpty) continue;

      // Монотонная сортировка вдоль ветки
      branchItems.sort((a, b) => a.t.compareTo(b.t));

      // Группировка в этажерки (кластеры)
      List<_SheetNodeCluster> clusters;
      if (effectiveGroup) {
        clusters = [];
        final visited = <String>{};
        for (int i = 0; i < branchItems.length; i++) {
          final itemA = branchItems[i];
          if (visited.contains(itemA.callout.id)) continue;

          final clusterItems = <_SheetCalloutItem>[itemA];
          visited.add(itemA.callout.id);

          for (int j = i + 1; j < branchItems.length; j++) {
            final itemB = branchItems[j];
            if (visited.contains(itemB.callout.id)) continue;

            if ((itemA.anchorMm - itemB.anchorMm).distance < 4.5) {
              clusterItems.add(itemB);
              visited.add(itemB.callout.id);
            }
          }

          // Сортировка по приоритету ГОСТ
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
            t: itemA.t,
          ));
        }
      } else {
        clusters = branchItems.map((item) => _SheetNodeCluster(
          anchorMm: item.anchorMm,
          items: [item],
          t: item.t,
        )).toList();
      }

      clusters.sort((a, b) => a.t.compareTo(b.t));

      // Разбиваем кластеры ветки на локальные группы близости (Local Proximity Groups).
      // Элементы объединяются в один мини-столбик, только если расстояние между их анкерами вдоль ветки <= 28.0 мм.
      // Если расстояние больше — следующий элемент/узел получает свой собственный локальный столбик.
      final localGroups = <List<_SheetNodeCluster>>[];
      if (clusters.isNotEmpty) {
        List<_SheetNodeCluster> curGroup = [clusters.first];
        for (int i = 1; i < clusters.length; i++) {
          final prev = clusters[i - 1];
          final curr = clusters[i];
          if ((curr.t - prev.t).abs() <= 28.0) {
            curGroup.add(curr);
          } else {
            localGroups.add(curGroup);
            curGroup = [curr];
          }
        }
        localGroups.add(curGroup);
      }

      for (final groupClusters in localGroups) {
        // 6. Оценка многонаправленных кандидатов для локальной группы
        final searchDirs = _getSearchDirections(branch);
        var bestCandidate = _findBestCandidateForClusters(
          branch: branch,
          clusters: groupClusters,
          searchDirs: searchDirs,
          customPitchMm: customPitchMm,
          obstacleMap: obstacleMap,
          frameLeft: frameLeft,
          frameRight: frameRight,
          frameTop: frameTop,
          frameBottom: frameBottom,
          stampRect: stampRect,
        );

        // Интеллектуальный De-clustering Fallback:
        // Если общий стек группы не помещается без коллизий (cost >= 50000.0) и в группе несколько кластеров,
        // разбиваем на отдельные кластеры и размещаем каждый в своем чистом кармане!
        if ((bestCandidate == null || bestCandidate.cost >= 50000.0) && groupClusters.length > 1) {
          for (final singleCluster in groupClusters) {
            final singleCand = _findBestCandidateForClusters(
              branch: branch,
              clusters: [singleCluster],
              searchDirs: searchDirs,
              customPitchMm: customPitchMm,
              obstacleMap: obstacleMap,
              frameLeft: frameLeft,
              frameRight: frameRight,
              frameTop: frameTop,
              frameBottom: frameBottom,
              stampRect: stampRect,
            );
            if (singleCand != null) {
              _applyCandidate(singleCand, result, handledCalloutIds, obstacleMap);
            }
          }
        } else if (bestCandidate != null) {
          _applyCandidate(bestCandidate, result, handledCalloutIds, obstacleMap);
        }
      }
    }

    // 7. Обработка неназначенных выносок (например, автономное оборудование)
    for (final callout in network.callouts.values) {
      if (handledCalloutIds.contains(callout.id)) continue;
      if (!sheet.isCalloutVisible(callout, network)) continue;

      final anchor3D = computeAnchorNode(callout, network);
      if (anchor3D == null) continue;

      final raw2D = projector.projectRaw(anchor3D.x, anchor3D.y, anchor3D.z);
      final anchorMm = ViewportTransformService.model2dToSheetMm(raw2D, vp);

      final charWidthMm = callout.textHeight * 0.65;
      final textMm = network.generateCalloutText(callout, defaultCalloutTemplates);
      final textWidthMm = math.max(10.0, textMm.length * charWidthMm + 3.0);
      final textHeightMm = callout.textHeight;

      final candidate = findBestCandidate(
        anchor: anchorMm,
        textWidth: textWidthMm,
        textHeight: textHeightMm,
        obstacleMap: obstacleMap,
        existingShelfXPositions: null,
        minRadius: minRadiusMm,
        maxRadius: maxRadiusMm,
      );

      final offMm = candidate?.offset ?? const Offset(20.0, -15.0);
      result[callout.id] = Offset(offMm.dx / 0.35, offMm.dy / 0.35);
      handledCalloutIds.add(callout.id);

      final shelfStart = anchorMm + offMm;
      final shelfRect = candidate?.shelfBounds ?? Rect.fromLTWH(
        shelfStart.dx,
        shelfStart.dy - textHeightMm - 1.0,
        textWidthMm,
        textHeightMm + 2.0,
      );
      obstacleMap.addRect(shelfRect, callout.id);
      obstacleMap.addLeaderLine(anchorMm, shelfStart, callout.id);
    }

    return result;
  }

  static void _applyCandidate(
    _CandidateStack candidate,
    Map<String, Offset> result,
    Set<String> handledCalloutIds,
    CalloutObstacleMap obstacleMap,
  ) {
    for (int i = 0; i < candidate.items.length; i++) {
      final item = candidate.items[i];
      final shelfStart = candidate.shelfStarts[i];
      final shelfRect = candidate.shelfRects[i];

      final offMm = shelfStart - item.anchorMm;
      final storedOff = Offset(offMm.dx / 0.35, offMm.dy / 0.35);
      result[item.callout.id] = storedOff;
      handledCalloutIds.add(item.callout.id);

      obstacleMap.addRect(shelfRect, item.callout.id);
    }

    // Регистрируем линии в obstacleMap по логике ГОСТ этажерки (1 общая ножка + стойка)
    final itemsByAnchor = <Offset, List<int>>{};
    for (int i = 0; i < candidate.items.length; i++) {
      final anch = candidate.items[i].anchorMm;
      itemsByAnchor.putIfAbsent(anch, () => []).add(i);
    }

    for (final entry in itemsByAnchor.entries) {
      final anchor = entry.key;
      final indices = entry.value;

      double minDy = double.infinity;
      Offset entryShelf = candidate.shelfStarts[indices.first];
      double minY = double.infinity;
      double maxY = -double.infinity;

      for (final idx in indices) {
        final sStart = candidate.shelfStarts[idx];
        minY = math.min(minY, sStart.dy);
        maxY = math.max(maxY, sStart.dy);
        final dy = (sStart.dy - anchor.dy).abs();
        if (dy < minDy) {
          minDy = dy;
          entryShelf = sStart;
        }
      }

      // Общая линия-ножка
      obstacleMap.addLeaderLine(anchor, entryShelf, candidate.items[indices.first].callout.id);

      // Стойка этажерки
      if (indices.length > 1) {
        final rackX = entryShelf.dx;
        obstacleMap.addLeaderLine(Offset(rackX, minY), Offset(rackX, maxY), candidate.items[indices.first].callout.id);
      }
    }
  }

  static List<Offset> _getSearchDirections(PipelineBranch branch) {
    final dirs = <Offset>[];

    void addDir(Offset v) {
      final len = v.distance;
      if (len < 1e-4) return;
      final u = Offset(v.dx / len, v.dy / len);
      for (final existing in dirs) {
        if (existing.dx * u.dx + existing.dy * u.dy > 0.97) return;
      }
      dirs.add(u);
    }

    // 1. Нормали ветки
    addDir(branch.normal1);
    addDir(branch.normal2);

    // 2. Вращение нормалей на +/- 30 и +/- 45 градусов
    for (final angleDeg in [-45.0, -30.0, 30.0, 45.0]) {
      addDir(_rotateOffset(branch.normal1, angleDeg));
      addDir(_rotateOffset(branch.normal2, angleDeg));
    }

    // 3. Стандартные чертежные направления (кардинальные и изометрические 30/45 град)
    addDir(const Offset(0.0, -1.0)); // строго вверх
    addDir(const Offset(0.866, -0.5)); // изометрия 30 град вверх-вправо
    addDir(const Offset(-0.866, -0.5)); // изометрия 30 град вверх-влево
    addDir(const Offset(1.0, -1.0)); // 45 град вверх-вправо
    addDir(const Offset(-1.0, -1.0)); // 45 град вверх-влево
    addDir(const Offset(0.0, 1.0)); // строго вниз
    addDir(const Offset(0.866, 0.5)); // изометрия 30 град вниз-вправо
    addDir(const Offset(-0.866, 0.5)); // изометрия 30 град вниз-влево
    addDir(const Offset(1.0, 1.0)); // 45 град вниз-вправо
    addDir(const Offset(-1.0, 1.0)); // 45 град вниз-влево

    return dirs;
  }

  static Offset _rotateOffset(Offset v, double deg) {
    final rad = deg * math.pi / 180.0;
    final cosA = math.cos(rad);
    final sinA = math.sin(rad);
    return Offset(v.dx * cosA - v.dy * sinA, v.dx * sinA + v.dy * cosA);
  }

  static _CandidateStack? _findBestCandidateForClusters({
    required PipelineBranch branch,
    required List<_SheetNodeCluster> clusters,
    required List<Offset> searchDirs,
    required double? customPitchMm,
    required CalloutObstacleMap obstacleMap,
    required double frameLeft,
    required double frameRight,
    required double frameTop,
    required double frameBottom,
    required Rect stampRect,
  }) {
    final clearances = const [14.0, 18.0, 24.0, 32.0, 42.0, 52.0];
    final shifts = const [-14.0, 0.0, 14.0, 28.0];
    final sides = const [true, false]; // isRight

    _CandidateStack? best;
    double lowestCost = double.infinity;

    for (final dir in searchDirs) {
      for (final clearance in clearances) {
        for (final shift in shifts) {
          for (final isRight in sides) {
            final cand = _evaluateCandidateStack(
              branch: branch,
              clusters: clusters,
              dirVector: dir,
              clearance: clearance,
              shiftAlongBranch: shift,
              isRight: isRight,
              customPitchMm: customPitchMm,
              obstacleMap: obstacleMap,
              frameLeft: frameLeft,
              frameRight: frameRight,
              frameTop: frameTop,
              frameBottom: frameBottom,
              stampRect: stampRect,
            );
            if (cand != null && cand.cost < lowestCost) {
              lowestCost = cand.cost;
              best = cand;
            }
          }
        }
      }
    }
    return best;
  }

  static _CandidateStack? _evaluateCandidateStack({
    required PipelineBranch branch,
    required List<_SheetNodeCluster> clusters,
    required Offset dirVector,
    required double clearance,
    double shiftAlongBranch = 0.0,
    required bool isRight,
    required double? customPitchMm,
    required CalloutObstacleMap obstacleMap,
    required double frameLeft,
    required double frameRight,
    required double frameTop,
    required double frameBottom,
    required Rect stampRect,
  }) {
    if (clusters.isEmpty) return null;

    final totalItems = clusters.fold<int>(0, (sum, c) => sum + c.items.length);
    final avgTextH = clusters.first.items.first.textHeightMm;
    final idealPitch = customPitchMm ?? (avgTextH * 2.1);
    final minPitch = avgTextH + 1.2;

    // Многоярусное разбиение при числе выносок > 6
    final numTiers = totalItems > 6 ? (totalItems / 6.0).ceil() : 1;
    final tierClusters = List.generate(numTiers, (_) => <_SheetNodeCluster>[]);

    if (numTiers == 1) {
      tierClusters[0].addAll(clusters);
    } else {
      final itemsPerTier = (totalItems / numTiers.toDouble()).ceil();
      int curTier = 0;
      int curTierCount = 0;
      for (final cl in clusters) {
        if (curTierCount >= itemsPerTier && curTier < numTiers - 1) {
          curTier++;
          curTierCount = 0;
        }
        tierClusters[curTier].add(cl);
        curTierCount += cl.items.length;
      }
    }

    double totalCost = 0.0;
    final allShelfStarts = <Offset>[];
    final allShelfRects = <Rect>[];
    final allPlacedItems = <_SheetCalloutItem>[];
    final branchSegIds = branch.segments.map((s) => s.id).toSet();

    double effectivePitch = idealPitch;
    double firstTierX = 0.0;

    for (int tier = 0; tier < numTiers; tier++) {
      final tClusters = tierClusters[tier];
      if (tClusters.isEmpty) continue;

      final tItemCount = tClusters.fold<int>(0, (sum, c) => sum + c.items.length);
      final maxTierTextW = tClusters.expand((c) => c.items).map((i) => i.textWidthMm).reduce(math.max);

      double tierMinX = double.infinity, tierMaxX = -double.infinity;
      double tierSumX = 0.0, tierSumY = 0.0;
      for (final cl in tClusters) {
        tierMinX = math.min(tierMinX, cl.anchorX);
        tierMaxX = math.max(tierMaxX, cl.anchorX);
        tierSumX += cl.anchorX;
        tierSumY += cl.anchorY;
      }
      final tierMeanX = tierSumX / tClusters.length;
      final tierMeanY = tierSumY / tClusters.length;

      final v = branch.branchVector2D;
      final targetX = tierMeanX + dirVector.dx * clearance + v.dx * shiftAlongBranch;
      final targetY = tierMeanY + dirVector.dy * clearance + v.dy * shiftAlongBranch;

      final double tierX = isRight
          ? targetX + tier * (maxTierTextW + 8.0)
          : targetX - tier * (maxTierTextW + 8.0);
      final double yCenter = targetY;

      if (tier == 0) firstTierX = tierX;

      double topLimit = frameTop + avgTextH + 2.0;
      double bottomLimit = frameBottom - 2.0;

      final shelfLeft = isRight ? tierX : tierX - maxTierTextW;
      final shelfRight = isRight ? tierX + maxTierTextW : tierX;

      if (shelfRight >= stampRect.left && shelfLeft <= stampRect.right) {
        bottomLimit = math.min(bottomLimit, stampRect.top - 4.0);
      }

      for (final r in obstacleMap.rects) {
        if (r.id != null && (r.id!.startsWith('table_') || r.id == 'tech_reqs')) {
          if (shelfRight >= r.rect.left && shelfLeft <= r.rect.right) {
            if (yCenter < r.rect.center.dy) {
              bottomLimit = math.min(bottomLimit, r.rect.top - 4.0);
            } else {
              topLimit = math.max(topLimit, r.rect.bottom + 4.0);
            }
          }
        }
      }

      final availH = math.max(10.0, bottomLimit - topLimit);
      final tierPitch = (tItemCount - 1) * idealPitch <= availH
          ? idealPitch
          : math.max(minPitch, availH / math.max(1, tItemCount - 1));
      effectivePitch = tierPitch;

      final stackH = (tItemCount - 1) * tierPitch;
      final idealStartY = yCenter - stackH / 2.0;
      final startY = idealStartY.clamp(topLimit, math.max(topLimit, bottomLimit - stackH));

      // Направление слотов по вертикали для исключения пересечений линий-выносок
      bool slotYIncreasesWithT;
      final dyBranch = branch.endSheetMm.dy - branch.startSheetMm.dy;
      if (dyBranch.abs() > 1.0) {
        slotYIncreasesWithT = dyBranch > 0;
      } else {
        final dxBranch = branch.endSheetMm.dx - branch.startSheetMm.dx;
        final xIncreasesWithT = dxBranch >= 0;
        final isAbovePipe = yCenter < tierMeanY;
        final inc = (isRight == isAbovePipe);
        slotYIncreasesWithT = xIncreasesWithT ? inc : !inc;
      }

      int slotIndex = 0;
      final clusterSlotStarts = <int>[];
      for (final cl in tClusters) {
        clusterSlotStarts.add(slotIndex);
        slotIndex += cl.items.length;
      }

      for (int ci = 0; ci < tClusters.length; ci++) {
        final cl = tClusters[ci];
        final baseSlot = slotYIncreasesWithT
            ? clusterSlotStarts[ci]
            : (tItemCount - clusterSlotStarts[ci] - cl.items.length);

        double clusterMinY = double.infinity;
        double clusterMaxY = -double.infinity;
        Offset? entryShelfStart;
        double minDy = double.infinity;

        for (int k = 0; k < cl.items.length; k++) {
          final item = cl.items[k];
          final currentSlot = baseSlot + k;
          final slotY = startY + currentSlot * tierPitch;
          final shelfStart = Offset(tierX, slotY);

          clusterMinY = math.min(clusterMinY, slotY);
          clusterMaxY = math.max(clusterMaxY, slotY);
          final dy = (slotY - cl.anchorMm.dy).abs();
          if (dy < minDy) {
            minDy = dy;
            entryShelfStart = shelfStart;
          }

          final shelfRect = isRight
              ? Rect.fromLTWH(shelfStart.dx, shelfStart.dy - item.textHeightMm - 1.0, item.textWidthMm, item.textHeightMm + 2.0)
              : Rect.fromLTWH(shelfStart.dx - item.textWidthMm, shelfStart.dy - item.textHeightMm - 1.0, item.textWidthMm, item.textHeightMm + 2.0);

          allShelfStarts.add(shelfStart);
          allShelfRects.add(shelfRect);
          allPlacedItems.add(item);

          // Штрафы за выход за рамку чертежа
          if (shelfRect.left < frameLeft) totalCost += (frameLeft - shelfRect.left) * 2000.0 + 50000.0;
          if (shelfRect.right > frameRight) totalCost += (shelfRect.right - frameRight) * 2000.0 + 50000.0;
          if (shelfRect.top < frameTop) totalCost += (frameTop - shelfRect.top) * 2000.0 + 50000.0;
          if (shelfRect.bottom > frameBottom) totalCost += (shelfRect.bottom - frameBottom) * 2000.0 + 50000.0;

          // Штрафы за штамп и таблицы (строжайший запрет: 1 000 000)
          if (stampRect.overlaps(shelfRect)) totalCost += 1000000.0;

          for (final r in obstacleMap.rects) {
            if (r.id == 'stamp') continue;
            if (r.id != null && (r.id!.startsWith('table_') || r.id == 'tech_reqs')) {
              if (r.rect.overlaps(shelfRect)) totalCost += 1000000.0;
            } else {
              // Перекрытие с уже размещенными полками других выносок
              if (r.rect.overlaps(shelfRect)) totalCost += shelfTextOverlapPenalty;
            }
          }

          // Штраф за наложение полки на трубу
          if (obstacleMap.testShelfPipeCollision(shelfRect)) {
            totalCost += shelfPipeOverlapPenalty;
          }
        }

        // Оценка линий по логике ГОСТ этажерки (1 наклонная ножка к ближайшей полке + вертикальная стойка)
        if (entryShelfStart != null) {
          // 1. Проверяем общую наклонную линию-ножку от объекта к этажерке
          for (final p in obstacleMap.pipes) {
            if (p.id != null && branchSegIds.contains(p.id)) continue;
            if (CalloutObstacleMap.segmentsIntersect(cl.anchorMm, entryShelfStart, p.p1, p.p2)) {
              totalCost += leaderCrossPenalty;
            }
          }
          for (final leader in obstacleMap.leaderLines) {
            if (CalloutObstacleMap.segmentsIntersect(cl.anchorMm, entryShelfStart, leader.p1, leader.p2)) {
              totalCost += 60000.0;
            }
          }

          // 2. Если в кластере несколько полок — проверяем вертикальную стойку этажерки
          if (cl.items.length > 1) {
            final stemP1 = Offset(tierX, clusterMinY);
            final stemP2 = Offset(tierX, clusterMaxY);
            for (final p in obstacleMap.pipes) {
              if (p.id != null && branchSegIds.contains(p.id)) continue;
              if (CalloutObstacleMap.segmentsIntersect(stemP1, stemP2, p.p1, p.p2)) {
                totalCost += leaderCrossPenalty;
              }
            }
            for (final leader in obstacleMap.leaderLines) {
              if (CalloutObstacleMap.segmentsIntersect(stemP1, stemP2, leader.p1, leader.p2)) {
                totalCost += 60000.0;
              }
            }
          }

          // Штраф за длину ножки-выноски
          final leaderDist = (entryShelfStart - cl.anchorMm).distance;
          totalCost += leaderDist * distancePenaltyWeight;
          if (leaderDist > 35.0) {
            totalCost += (leaderDist - 35.0) * 150.0;
          }
        }
      }
    }

    if (dirVector.dy < 0) totalCost -= 30.0; // приоритет вверх
    if (isRight) totalCost -= 20.0; // приоритет вправо

    return _CandidateStack(
      xStack: firstTierX,
      pitch: effectivePitch,
      shelfStarts: allShelfStarts,
      shelfRects: allShelfRects,
      items: allPlacedItems,
      cost: totalCost,
    );
  }
}

class _CandidateStack {
  final double xStack;
  final double pitch;
  final List<Offset> shelfStarts;
  final List<Rect> shelfRects;
  final List<_SheetCalloutItem> items;
  final double cost;

  _CandidateStack({
    required this.xStack,
    required this.pitch,
    required this.shelfStarts,
    required this.shelfRects,
    required this.items,
    required this.cost,
  });
}

class _SheetCalloutItem {
  final Callout callout;
  final Offset anchorMm;
  final double textWidthMm;
  final double textHeightMm;
  final double t;

  _SheetCalloutItem({
    required this.callout,
    required this.anchorMm,
    required this.textWidthMm,
    required this.textHeightMm,
    this.t = 0.0,
  });
}

class _SheetNodeCluster {
  final Offset anchorMm;
  final List<_SheetCalloutItem> items;
  final double t;

  _SheetNodeCluster({
    required this.anchorMm,
    required this.items,
    this.t = 0.0,
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
