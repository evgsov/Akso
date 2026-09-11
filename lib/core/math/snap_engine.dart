import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../domain/models/node_3d.dart';
import '../../domain/models/piping_network.dart';
import 'axonometry_projector.dart';

enum SnapType {
  none,
  node,
  segmentAxis,
  gridAxis,
  polarAngle,
}

enum AngleSnapMode {
  ortho90, // 0°, 90°, 180°, 270°
  isometric45, // Шаг 45°
  iso30, // Шаг 30°
  custom, // Пользовательский шаг (например, 15°)
  free, // Без угловой привязки
}

class SnapResult {
  final SnapType type;
  final Offset screenPoint;
  final Node3D worldPoint;
  final String label;
  final String? snappedNodeId;
  final String? snappedSegmentId;
  final double? snappedAngleDegrees;
  final double? distanceLengthMm;

  const SnapResult({
    required this.type,
    required this.screenPoint,
    required this.worldPoint,
    this.label = '',
    this.snappedNodeId,
    this.snappedSegmentId,
    this.snappedAngleDegrees,
    this.distanceLengthMm,
  });

  static SnapResult none(Offset screenPoint, Node3D worldPoint) {
    return SnapResult(
      type: SnapType.none,
      screenPoint: screenPoint,
      worldPoint: worldPoint,
    );
  }
}

class SnapEngine {
  final double nodeSnapScreenRadius;
  final double segmentSnapScreenRadius;
  final double angleSnapToleranceDegrees;

  const SnapEngine({
    this.nodeSnapScreenRadius = 22.0,
    this.segmentSnapScreenRadius = 18.0,
    this.angleSnapToleranceDegrees = 6.0,
  });

  SnapResult findSnap({
    required Offset screenPos,
    required PipingNetwork network,
    required AxonometryProjector projector,
    required double currentElevationZ,
    Node3D? traceStartNode,
    AngleSnapMode angleMode = AngleSnapMode.ortho90,
    double customAngleStepDegrees = 15.0,
  }) {
    // 1. Приоритет: Проверка примагничивания к существующим узлам
    for (final node in network.nodes.values) {
      if (traceStartNode != null && node.id == traceStartNode.id) continue;
      final proj = projector.project(node);
      final dist = (proj - screenPos).distance;
      if (dist <= nodeSnapScreenRadius) {
        final elevM = (node.z / 1000.0).toStringAsFixed(3);
        final sign = node.z >= 0 ? '+' : '';
        return SnapResult(
          type: SnapType.node,
          screenPoint: proj,
          worldPoint: node,
          snappedNodeId: node.id,
          label: 'Узел [∇$sign$elevM]',
        );
      }
    }

    // 2. Проверка примагничивания к осям труб (сегментов)
    for (final seg in network.segments.values) {
      final s = network.nodes[seg.startNodeId];
      final e = network.nodes[seg.endNodeId];
      if (s == null || e == null) continue;

      final p1 = projector.project(s);
      final p2 = projector.project(e);
      final dist = _distanceToLineSegment(screenPos, p1, p2);

      if (dist <= segmentSnapScreenRadius) {
        // Вычисляем ближайшую точку на сегменте в мировых координатах
        final ratio = _calcSegmentRatio(p1, p2, screenPos);
        final snappedWorld = Node3D(
          id: '',
          x: s.x + (e.x - s.x) * ratio,
          y: s.y + (e.y - s.y) * ratio,
          z: s.z + (e.z - s.z) * ratio,
        );
        final snappedScreen = projector.project(snappedWorld);

        return SnapResult(
          type: SnapType.segmentAxis,
          screenPoint: snappedScreen,
          worldPoint: snappedWorld,
          snappedSegmentId: seg.id,
          label: 'Ось трубы Ду${seg.dn}',
        );
      }
    }

    // 3. Полярное отслеживание углов, если мы чертим от начального узла
    final rawWorld = projector.unproject(screenPos, currentElevationZ);
    if (traceStartNode != null && angleMode != AngleSnapMode.free) {
      final dx = rawWorld.x - traceStartNode.x;
      final dy = rawWorld.y - traceStartNode.y;
      final dist = math.sqrt(dx * dx + dy * dy);

      if (dist > 50.0) {
        // Угол в диапазоне [-180, 180] градусов
        double rawAngleDeg = math.atan2(dy, dx) * 180.0 / math.pi;
        if (rawAngleDeg < 0) rawAngleDeg += 360.0; // [0, 360)

        final allowedAngles = _getAllowedAngles(angleMode, customAngleStepDegrees);
        double? bestAngle;
        double minDiff = double.infinity;

        for (final targetAngle in allowedAngles) {
          final diff = (rawAngleDeg - targetAngle).abs();
          final cyclicDiff = math.min(diff, 360.0 - diff);
          if (cyclicDiff <= angleSnapToleranceDegrees && cyclicDiff < minDiff) {
            minDiff = cyclicDiff;
            bestAngle = targetAngle;
          }
        }

        if (bestAngle != null) {
          final rad = bestAngle * math.pi / 180.0;
          final snappedX = traceStartNode.x + dist * math.cos(rad);
          final snappedY = traceStartNode.y + dist * math.sin(rad);
          final snappedWorld = Node3D(
            id: '',
            x: (snappedX / 10.0).round() * 10.0,
            y: (snappedY / 10.0).round() * 10.0,
            z: currentElevationZ,
          );
          final snappedScreen = projector.project(snappedWorld);

          return SnapResult(
            type: SnapType.polarAngle,
            screenPoint: snappedScreen,
            worldPoint: snappedWorld,
            snappedAngleDegrees: bestAngle,
            distanceLengthMm: dist,
            label: 'L: ${dist.round()} мм | ∠${bestAngle.round()}°',
          );
        }
      }
    }

    // Если ничего не сработало, возвращаем обычные мировые координаты
    return SnapResult.none(screenPos, rawWorld);
  }

  List<double> _getAllowedAngles(AngleSnapMode mode, double customStep) {
    switch (mode) {
      case AngleSnapMode.ortho90:
        return [0.0, 90.0, 180.0, 270.0];
      case AngleSnapMode.isometric45:
        return [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0];
      case AngleSnapMode.iso30:
        return [0.0, 30.0, 60.0, 90.0, 120.0, 150.0, 180.0, 210.0, 240.0, 270.0, 300.0, 330.0];
      case AngleSnapMode.custom:
        final step = customStep > 0 ? customStep : 15.0;
        final angles = <double>[];
        for (double a = 0; a < 360.0; a += step) {
          angles.add(a);
        }
        return angles;
      case AngleSnapMode.free:
        return [];
    }
  }

  double _calcSegmentRatio(Offset a, Offset b, Offset p) {
    final len = (b - a).distance;
    if (len < 1.0) return 0.5;
    final u = (b - a) / len;
    final v = p - a;
    final proj = v.dx * u.dx + v.dy * u.dy;
    return (proj / len).clamp(0.05, 0.95);
  }

  double _distanceToLineSegment(Offset p, Offset a, Offset b) {
    final l2 = (b - a).distanceSquared;
    if (l2 == 0.0) return (p - a).distance;
    final t = (((p.dx - a.dx) * (b.dx - a.dx) + (p.dy - a.dy) * (b.dy - a.dy)) / l2).clamp(0.0, 1.0);
    final projection = Offset(a.dx + t * (b.dx - a.dx), a.dy + t * (b.dy - a.dy));
    return (p - projection).distance;
  }
}
