import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../domain/models/equipment.dart';
import '../../domain/models/node_3d.dart';
import '../../domain/models/piping_network.dart';
import 'axonometry_projector.dart';

enum SnapType {
  none,
  node,
  endpoint,
  midpoint,
  intersection,
  perpendicular,
  segmentAxis,
  gridAxis,
  polarAngle,
  equipmentFace,
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
  final String? snappedEquipmentId;
  final EquipmentFace? snappedEquipmentFace;
  final double? snappedAngleDegrees;
  final double? distanceLengthMm;

  const SnapResult({
    required this.type,
    required this.screenPoint,
    required this.worldPoint,
    this.label = '',
    this.snappedNodeId,
    this.snappedSegmentId,
    this.snappedEquipmentId,
    this.snappedEquipmentFace,
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
    // 1. Дискретные точки (Endpoint узлов труб, края осей и пересечения)
    // Соревнуются по минимальному экранному расстоянию до курсора
    SnapResult? bestDiscreteSnap;
    double minDiscreteDist = nodeSnapScreenRadius;

    // 1.1. Проверка примагничивания к существующим узлам труб (Node / Endpoint)
    for (final node in network.nodes.values) {
      if (traceStartNode != null && node.id == traceStartNode.id) continue;
      final proj = projector.project(node);
      final dist = (proj - screenPos).distance;
      if (dist <= minDiscreteDist) {
        final elevM = (node.z / 1000.0).toStringAsFixed(3);
        final sign = node.z >= 0 ? '+' : '';
        bestDiscreteSnap = SnapResult(
          type: SnapType.node,
          screenPoint: proj,
          worldPoint: node,
          snappedNodeId: node.id,
          label: 'Узел [∇$sign$elevM]',
        );
        minDiscreteDist = dist;
      }
    }

    // 1.2. Проверка краев (концов) строительных и опорных осей (Endpoint)
    for (final axis in network.axes.values) {
      final endpoints = <Node3D>[
        Node3D(id: '', x: axis.startPoint.x, y: axis.startPoint.y, z: currentElevationZ),
        Node3D(id: '', x: axis.endPoint.x, y: axis.endPoint.y, z: currentElevationZ),
      ];
      // Если ось создана на другой высоте Z, также проверяем оригинальные концы
      if ((axis.startPoint.z - currentElevationZ).abs() > 1.0) {
        endpoints.add(axis.startPoint);
        endpoints.add(axis.endPoint);
      }

      for (final pt in endpoints) {
        final proj = projector.project(pt);
        final dist = (proj - screenPos).distance;
        // Край оси выбирается, если он ближе к курсору (при равенстве узел трубы в приоритете)
        if (dist < minDiscreteDist || (dist <= minDiscreteDist && bestDiscreteSnap?.type != SnapType.node)) {
          final label = axis.isBuildingGrid && axis.label.isNotEmpty
              ? 'Край оси ${axis.label}'
              : 'Край опорной линии';
          bestDiscreteSnap = SnapResult(
            type: SnapType.endpoint,
            screenPoint: proj,
            worldPoint: pt,
            snappedSegmentId: axis.id,
            label: label,
          );
          minDiscreteDist = dist;
        }
      }
    }

    // 1.3. Проверка пересечений строительных и опорных осей (Intersection)
    final axisList = network.axes.values.toList();
    for (int i = 0; i < axisList.length; i++) {
      for (int j = i + 1; j < axisList.length; j++) {
        final a1 = axisList[i];
        final a2 = axisList[j];
        final inter = _lineIntersection2D(
          a1.startPoint.x, a1.startPoint.y, a1.endPoint.x, a1.endPoint.y,
          a2.startPoint.x, a2.startPoint.y, a2.endPoint.x, a2.endPoint.y,
        );
        if (inter != null) {
          final interWorld = Node3D(id: '', x: inter.dx, y: inter.dy, z: currentElevationZ);
          final proj = projector.project(interWorld);
          final dist = (proj - screenPos).distance;
          if (dist <= nodeSnapScreenRadius) {
            // Пересечение побеждает только если оно ближе к курсору, чем край оси или узел (с запасом 2px)
            if (bestDiscreteSnap == null || dist < minDiscreteDist - 2.0) {
              final l1 = a1.isBuildingGrid && a1.label.isNotEmpty ? a1.label : 'оп.';
              final l2 = a2.isBuildingGrid && a2.label.isNotEmpty ? a2.label : 'оп.';
              bestDiscreteSnap = SnapResult(
                type: SnapType.intersection,
                screenPoint: proj,
                worldPoint: interWorld,
                label: 'Пересечение [$l1 / $l2]',
              );
              minDiscreteDist = dist;
            }
          }
        }
      }
    }

    // 1.4. Проверка пересечений сегментов труб со строительными осями
    for (final seg in network.segments.values) {
      final s = network.nodes[seg.startNodeId];
      final e = network.nodes[seg.endNodeId];
      if (s == null || e == null) continue;
      if ((s.z - currentElevationZ).abs() > 10.0 && (e.z - currentElevationZ).abs() > 10.0) continue;
      for (final axis in network.axes.values) {
        final inter = _lineIntersection2D(
          s.x, s.y, e.x, e.y,
          axis.startPoint.x, axis.startPoint.y, axis.endPoint.x, axis.endPoint.y,
        );
        if (inter != null) {
          final interWorld = Node3D(id: '', x: inter.dx, y: inter.dy, z: currentElevationZ);
          final proj = projector.project(interWorld);
          final dist = (proj - screenPos).distance;
          if (dist <= nodeSnapScreenRadius) {
            if (bestDiscreteSnap == null || dist < minDiscreteDist - 2.0) {
              final axLabel = axis.isBuildingGrid && axis.label.isNotEmpty ? 'Ось ${axis.label}' : 'Опорная линия';
              bestDiscreteSnap = SnapResult(
                type: SnapType.intersection,
                screenPoint: proj,
                worldPoint: interWorld,
                label: 'Пересечение [Ду${seg.dn} / $axLabel]',
              );
              minDiscreteDist = dist;
            }
          }
        }
      }
    }

    // Если найдена дискретная точка с наименьшим расстоянием — возвращаем её
    if (bestDiscreteSnap != null) {
      return bestDiscreteSnap;
    }

    // 2. Поиск ближайшей геометрической точки на отрезках (Midpoint и Perpendicular 90°)
    SnapResult? bestFeatureSnap;
    double minFeatureDist = nodeSnapScreenRadius;

    // Проверка середины сегментов труб (Midpoint)
    for (final seg in network.segments.values) {
      final s = network.nodes[seg.startNodeId];
      final e = network.nodes[seg.endNodeId];
      if (s == null || e == null) continue;
      final midWorld = Node3D(
        id: '',
        x: (s.x + e.x) / 2.0,
        y: (s.y + e.y) / 2.0,
        z: (s.z + e.z) / 2.0,
      );
      final proj = projector.project(midWorld);
      final dist = (proj - screenPos).distance;
      if (dist <= minFeatureDist) {
        minFeatureDist = dist;
        bestFeatureSnap = SnapResult(
          type: SnapType.midpoint,
          screenPoint: proj,
          worldPoint: midWorld,
          snappedSegmentId: seg.id,
          label: 'Середина трубы Ду${seg.dn}',
        );
      }
    }

    // Проверка середины строительных и опорных осей (Midpoint)
    for (final axis in network.axes.values) {
      if ((axis.startPoint.z - currentElevationZ).abs() > 10.0 &&
          (axis.endPoint.z - currentElevationZ).abs() > 10.0) {
        continue;
      }
      final midWorld = Node3D(
        id: '',
        x: (axis.startPoint.x + axis.endPoint.x) / 2.0,
        y: (axis.startPoint.y + axis.endPoint.y) / 2.0,
        z: currentElevationZ,
      );
      final proj = projector.project(midWorld);
      final dist = (proj - screenPos).distance;
      if (dist <= minFeatureDist) {
        minFeatureDist = dist;
        final label = axis.isBuildingGrid && axis.label.isNotEmpty
            ? 'Середина оси ${axis.label}'
            : 'Середина опорной линии';
        bestFeatureSnap = SnapResult(
          type: SnapType.midpoint,
          screenPoint: proj,
          worldPoint: midWorld,
          snappedSegmentId: axis.id,
          label: label,
        );
      }
    }

    // Проверка центров граней оборудования (Equipment Face Centers)
    for (final eq in network.equipments.values) {
      final rad = eq.rotationAngleDeg * math.pi / 180.0;
      final cosA = math.cos(rad);
      final sinA = math.sin(rad);

      Node3D localToWorld(double lx, double ly, double lz) {
        final wx = eq.x + lx * cosA - ly * sinA;
        final wy = eq.y + lx * sinA + ly * cosA;
        final wz = eq.z + lz;
        return Node3D(id: '', x: wx, y: wy, z: wz);
      }

      final facePoints = <MapEntry<EquipmentFace, Node3D>>[];

      if (eq.type == EquipmentType.box) {
        facePoints.add(MapEntry(EquipmentFace.top, localToWorld(0, 0, eq.height)));
        facePoints.add(MapEntry(EquipmentFace.bottom, localToWorld(0, 0, 0)));
        facePoints.add(MapEntry(EquipmentFace.right, localToWorld(eq.width / 2.0, 0, eq.height / 2.0)));
        facePoints.add(MapEntry(EquipmentFace.left, localToWorld(-eq.width / 2.0, 0, eq.height / 2.0)));
        facePoints.add(MapEntry(EquipmentFace.front, localToWorld(0, eq.length / 2.0, eq.height / 2.0)));
        facePoints.add(MapEntry(EquipmentFace.back, localToWorld(0, -eq.length / 2.0, eq.height / 2.0)));
      } else if (eq.type == EquipmentType.cylinderVertical) {
        final r = eq.width / 2.0;
        facePoints.add(MapEntry(EquipmentFace.top, localToWorld(0, 0, eq.height)));
        facePoints.add(MapEntry(EquipmentFace.bottom, localToWorld(0, 0, 0)));
        facePoints.add(MapEntry(EquipmentFace.cylindrical, localToWorld(r, 0, eq.height / 2.0)));
        facePoints.add(MapEntry(EquipmentFace.cylindrical, localToWorld(-r, 0, eq.height / 2.0)));
        facePoints.add(MapEntry(EquipmentFace.cylindrical, localToWorld(0, r, eq.height / 2.0)));
        facePoints.add(MapEntry(EquipmentFace.cylindrical, localToWorld(0, -r, eq.height / 2.0)));
      } else {
        // cylinderHorizontal
        final r = eq.width / 2.0;
        final halfL = eq.length / 2.0;
        facePoints.add(MapEntry(EquipmentFace.front, localToWorld(0, halfL, eq.height / 2.0)));
        facePoints.add(MapEntry(EquipmentFace.back, localToWorld(0, -halfL, eq.height / 2.0)));
        facePoints.add(MapEntry(EquipmentFace.top, localToWorld(0, 0, eq.height)));
        facePoints.add(MapEntry(EquipmentFace.bottom, localToWorld(0, 0, 0)));
        facePoints.add(MapEntry(EquipmentFace.right, localToWorld(r, 0, eq.height / 2.0)));
        facePoints.add(MapEntry(EquipmentFace.left, localToWorld(-r, 0, eq.height / 2.0)));
      }

      for (final entry in facePoints) {
        final face = entry.key;
        final ptWorld = entry.value;

        if (traceStartNode != null) {
          final distStart = math.sqrt(
            math.pow(ptWorld.x - traceStartNode.x, 2) +
                math.pow(ptWorld.y - traceStartNode.y, 2) +
                math.pow(ptWorld.z - traceStartNode.z, 2),
          );
          if (distStart < 10.0) continue;
        }

        final proj = projector.project(ptWorld);
        final dist = (proj - screenPos).distance;
        if (dist <= minFeatureDist) {
          minFeatureDist = dist;
          String faceName;
          switch (face) {
            case EquipmentFace.top:
              faceName = 'Верх';
              break;
            case EquipmentFace.bottom:
              faceName = 'Дно';
              break;
            case EquipmentFace.right:
              faceName = 'Право';
              break;
            case EquipmentFace.left:
              faceName = 'Лево';
              break;
            case EquipmentFace.front:
              faceName = 'Перед';
              break;
            case EquipmentFace.back:
              faceName = 'Зад';
              break;
            case EquipmentFace.cylindrical:
              faceName = 'Стенка';
              break;
          }
          bestFeatureSnap = SnapResult(
            type: SnapType.equipmentFace,
            screenPoint: proj,
            worldPoint: ptWorld,
            snappedEquipmentId: eq.id,
            snappedEquipmentFace: face,
            label: 'Грань ${eq.name} [$faceName]',
          );
        }
      }
    }

    // Проверка перпендикуляра к сегментам труб (Perpendicular 90°)
    if (traceStartNode != null) {
      for (final seg in network.segments.values) {
        final s = network.nodes[seg.startNodeId];
        final e = network.nodes[seg.endNodeId];
        if (s == null || e == null) continue;
        if (s.id == traceStartNode.id || e.id == traceStartNode.id) continue;

        final vx = e.x - s.x;
        final vy = e.y - s.y;
        final vz = e.z - s.z;
        final vLenSq = vx * vx + vy * vy + vz * vz;
        if (vLenSq < 1.0) continue;

        final ux = traceStartNode.x - s.x;
        final uy = traceStartNode.y - s.y;
        final uz = traceStartNode.z - s.z;

        final t = (ux * vx + uy * vy + uz * vz) / vLenSq;
        if (t > 0.02 && t < 0.98) {
          final perpWorld = Node3D(
            id: '',
            x: s.x + vx * t,
            y: s.y + vy * t,
            z: s.z + vz * t,
          );
          final dist3d = math.sqrt(
            math.pow(perpWorld.x - traceStartNode.x, 2) +
                math.pow(perpWorld.y - traceStartNode.y, 2) +
                math.pow(perpWorld.z - traceStartNode.z, 2),
          );
          if (dist3d < 20.0) continue;

          final proj = projector.project(perpWorld);
          final dist = (proj - screenPos).distance;
          if (dist <= minFeatureDist) {
            minFeatureDist = dist;
            bestFeatureSnap = SnapResult(
              type: SnapType.perpendicular,
              screenPoint: proj,
              worldPoint: perpWorld,
              snappedSegmentId: seg.id,
              label: 'Перпендикуляр 90° [Ду${seg.dn}]',
            );
          }
        }
      }

      // Проверка перпендикуляра к строительным и опорным осям (Perpendicular 90°)
      for (final axis in network.axes.values) {
        final ax = axis.endPoint.x - axis.startPoint.x;
        final ay = axis.endPoint.y - axis.startPoint.y;
        final aLenSq = ax * ax + ay * ay;
        if (aLenSq < 1.0) continue;

        final ux = traceStartNode.x - axis.startPoint.x;
        final uy = traceStartNode.y - axis.startPoint.y;
        final t = (ux * ax + uy * ay) / aLenSq;

        if (t > 0.02 && t < 0.98) {
          final perpWorld = Node3D(
            id: '',
            x: axis.startPoint.x + ax * t,
            y: axis.startPoint.y + ay * t,
            z: currentElevationZ,
          );
          final dist3d = math.sqrt(
            math.pow(perpWorld.x - traceStartNode.x, 2) +
                math.pow(perpWorld.y - traceStartNode.y, 2),
          );
          if (dist3d < 20.0) continue;

          final proj = projector.project(perpWorld);
          final dist = (proj - screenPos).distance;
          if (dist <= minFeatureDist) {
            minFeatureDist = dist;
            final label = axis.isBuildingGrid && axis.label.isNotEmpty
                ? 'Перпендикуляр 90° [Ось ${axis.label}]'
                : 'Перпендикуляр 90° [Опорная линия]';
            bestFeatureSnap = SnapResult(
              type: SnapType.perpendicular,
              screenPoint: proj,
              worldPoint: perpWorld,
              snappedSegmentId: axis.id,
              label: label,
            );
          }
        }
      }
    }

    if (bestFeatureSnap != null) {
      return bestFeatureSnap;
    }

    // 4. Проверка примагничивания к осям труб (сегментов - Nearest)
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

    // 3. Проверка примагничивания к строительным осям и вспомогательным линиям (по всей высоте Z)
    for (final axis in network.axes.values) {
      final aWorld = Node3D(id: '', x: axis.startPoint.x, y: axis.startPoint.y, z: currentElevationZ);
      final bWorld = Node3D(id: '', x: axis.endPoint.x, y: axis.endPoint.y, z: currentElevationZ);

      final p1 = projector.project(aWorld);
      final p2 = projector.project(bWorld);
      final dist = _distanceToLineSegment(screenPos, p1, p2);

      if (dist <= segmentSnapScreenRadius) {
        final ratio = _calcAxisRatio(p1, p2, screenPos);
        final snappedWorld = Node3D(
          id: '',
          x: axis.startPoint.x + (axis.endPoint.x - axis.startPoint.x) * ratio,
          y: axis.startPoint.y + (axis.endPoint.y - axis.startPoint.y) * ratio,
          z: currentElevationZ,
        );
        final snappedScreen = projector.project(snappedWorld);
        final elevM = (currentElevationZ / 1000.0).toStringAsFixed(3);
        final sign = currentElevationZ >= 0 ? '+' : '';
        final label = axis.isBuildingGrid && axis.label.isNotEmpty
            ? 'Ось ${axis.label} [∇$sign$elevM]'
            : 'Опорная линия [∇$sign$elevM]';

        return SnapResult(
          type: SnapType.gridAxis,
          screenPoint: snappedScreen,
          worldPoint: snappedWorld,
          snappedSegmentId: axis.id,
          label: label,
        );
      }
    }

    // 4. Полярное отслеживание углов, если мы чертим от начального узла
    final rawWorld = projector.unproject(screenPos, currentElevationZ);
    if (traceStartNode != null && angleMode != AngleSnapMode.free) {
      final dx = rawWorld.x - traceStartNode.x;
      final dy = rawWorld.y - traceStartNode.y;
      final dist = math.sqrt(dx * dx + dy * dy);

      if (dist > 50.0) {
        // Угол в диапазоне [-180, 180] градусов
        double rawAngleDeg = math.atan2(dy, dx) * 180.0 / math.pi;
        if (rawAngleDeg < 0) rawAngleDeg += 360.0; // [0, 360)

        // Проверяем магнитное притяжение к длине стыка встык отводов (T1 + T2)
        double? buttJointDistance;
        final connectedSegs = network.getConnectedSegments(traceStartNode.id);
        if (connectedSegs.isNotEmpty) {
          final lastSeg = connectedSegs.last;
          final t1 = network.getElbowTangentMm(traceStartNode.id);
          final effT1 = t1 > 0 ? t1 : (lastSeg.dn * 1.5);
          final effT2 = lastSeg.dn * 1.5;
          final targetMm = effT1 + effT2;
          if ((dist - targetMm).abs() <= 25.0) {
            buttJointDistance = targetMm;
          }
        }

        // Проверяем нормальные углы под 90° к прилегающим трубам начального узла
        for (final seg in connectedSegs) {
          final otherNode = network.nodes[seg.startNodeId == traceStartNode.id ? seg.endNodeId : seg.startNodeId];
          if (otherNode == null) continue;
          final pdx = traceStartNode.x - otherNode.x;
          final pdy = traceStartNode.y - otherNode.y;
          if (pdx.abs() > 1e-3 || pdy.abs() > 1e-3) {
            double pipeAngleDeg = math.atan2(pdy, pdx) * 180.0 / math.pi;
            if (pipeAngleDeg < 0) pipeAngleDeg += 360.0;
            final normalAngles = [
              (pipeAngleDeg + 90.0) % 360.0,
              (pipeAngleDeg + 270.0) % 360.0,
            ];
            for (final normAngle in normalAngles) {
              final diff = (rawAngleDeg - normAngle).abs();
              final cyclicDiff = math.min(diff, 360.0 - diff);
              if (cyclicDiff <= angleSnapToleranceDegrees) {
                final rad = normAngle * math.pi / 180.0;
                final effectiveDist = buttJointDistance ?? dist;
                final snappedX = traceStartNode.x + effectiveDist * math.cos(rad);
                final snappedY = traceStartNode.y + effectiveDist * math.sin(rad);
                final snappedWorld = Node3D(
                  id: '',
                  x: (snappedX / 10.0).round() * 10.0,
                  y: (snappedY / 10.0).round() * 10.0,
                  z: currentElevationZ,
                );
                final snappedScreen = projector.project(snappedWorld);

                final snapLabel = buttJointDistance != null
                    ? '🧲 Стык встык (${buttJointDistance.round()} мм) | ∠90° (Перпендикуляр)'
                    : 'L: ${dist.round()} мм | ∠90° к трубе (Перпендикуляр)';

                return SnapResult(
                  type: SnapType.polarAngle,
                  screenPoint: snappedScreen,
                  worldPoint: snappedWorld,
                  snappedAngleDegrees: normAngle,
                  distanceLengthMm: effectiveDist,
                  label: snapLabel,
                );
              }
            }
          }
        }

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
          final effectiveDist = buttJointDistance ?? dist;
          final snappedX = traceStartNode.x + effectiveDist * math.cos(rad);
          final snappedY = traceStartNode.y + effectiveDist * math.sin(rad);
          final snappedWorld = Node3D(
            id: '',
            x: (snappedX / 10.0).round() * 10.0,
            y: (snappedY / 10.0).round() * 10.0,
            z: currentElevationZ,
          );
          final snappedScreen = projector.project(snappedWorld);

          final snapLabel = buttJointDistance != null
              ? '🧲 Стык встык (${buttJointDistance.round()} мм) | ∠${bestAngle.round()}°'
              : 'L: ${dist.round()} мм | ∠${bestAngle.round()}°';

          return SnapResult(
            type: SnapType.polarAngle,
            screenPoint: snappedScreen,
            worldPoint: snappedWorld,
            snappedAngleDegrees: bestAngle,
            distanceLengthMm: effectiveDist,
            label: snapLabel,
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

  double _calcAxisRatio(Offset a, Offset b, Offset p) {
    final len = (b - a).distance;
    if (len < 1.0) return 0.5;
    final u = (b - a) / len;
    final v = p - a;
    final proj = v.dx * u.dx + v.dy * u.dy;
    return (proj / len).clamp(0.0, 1.0);
  }

  double _distanceToLineSegment(Offset p, Offset a, Offset b) {
    final l2 = (b - a).distanceSquared;
    if (l2 == 0.0) return (p - a).distance;
    final t = (((p.dx - a.dx) * (b.dx - a.dx) + (p.dy - a.dy) * (b.dy - a.dy)) / l2).clamp(0.0, 1.0);
    final projection = Offset(a.dx + t * (b.dx - a.dx), a.dy + t * (b.dy - a.dy));
    return (p - projection).distance;
  }

  static Offset? _lineIntersection2D(
    double x1, double y1, double x2, double y2,
    double x3, double y3, double x4, double y4,
  ) {
    final denom = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4);
    if (denom.abs() < 1e-5) return null;

    final t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / denom;
    final u = -((x1 - x2) * (y1 - y3) - (y1 - y2) * (x1 - x3)) / denom;

    if (t >= -0.05 && t <= 1.05 && u >= -0.05 && u <= 1.05) {
      final ix = x1 + t * (x2 - x1);
      final iy = y1 + t * (y2 - y1);
      return Offset(ix, iy);
    }
    return null;
  }
}
