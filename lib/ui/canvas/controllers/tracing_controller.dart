import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/math/axonometry_projector.dart';
import '../../../core/math/snap_engine.dart';
import '../../../domain/models/node_3d.dart';

/// Контроллер трассировки трубопроводов и разбивочных осей:
/// Режимы угловой привязки (Орто, Изометрия, шаг углов),
/// расчет векторов направления и конечных точек.
class TracingController {
  AngleSnapMode angleSnapMode = AngleSnapMode.ortho90;
  double customAngleDegrees = 15.0;
  bool isObjectTrackingEnabled = true;

  Node3D? traceStartNode;
  Node3D? axisStartNode;
  String currentAxisLabel = '1';
  bool isBuildingGridAxis = true;

  void setAngleSnapMode(AngleSnapMode mode) {
    angleSnapMode = mode;
  }

  void toggleObjectTracking() {
    isObjectTrackingEnabled = !isObjectTrackingEnabled;
  }

  void resetTrace() {
    traceStartNode = null;
  }

  void resetAxis() {
    axisStartNode = null;
  }

  /// Расчет единичного вектора направления (dirX, dirY, dirZ) от начального узла
  ({double dirX, double dirY, double dirZ}) computeTraceDirection({
    required Node3D startNode,
    required AxonometryProjector projector,
    required double currentElevationZ,
    Offset? currentCursorScreenPos,
    SnapResult? currentSnapResult,
    bool isSnapEnabled = true,
  }) {
    double dirX = 1.0;
    double dirY = 0.0;
    double dirZ = 0.0;

    if (isSnapEnabled && currentSnapResult != null && currentSnapResult.type != SnapType.none) {
      final snapWorld = currentSnapResult.worldPoint;
      final dx = snapWorld.x - startNode.x;
      final dy = snapWorld.y - startNode.y;
      final dz = snapWorld.z - startNode.z;
      final dist = math.sqrt(dx * dx + dy * dy + dz * dz);
      if (dist > 1e-6) {
        dirX = dx / dist;
        dirY = dy / dist;
        dirZ = dz / dist;
      }
    } else if (currentCursorScreenPos != null) {
      final rawWorld = projector.unproject(currentCursorScreenPos, currentElevationZ);
      final rawDx = rawWorld.x - startNode.x;
      final rawDy = rawWorld.y - startNode.y;
      final rawDz = rawWorld.z - startNode.z;

      if (angleSnapMode == AngleSnapMode.ortho90) {
        if (rawDx.abs() >= rawDy.abs()) {
          dirX = rawDx >= 0 ? 1.0 : -1.0;
          dirY = 0.0;
          dirZ = 0.0;
        } else {
          dirX = 0.0;
          dirY = rawDy >= 0 ? 1.0 : -1.0;
          dirZ = 0.0;
        }
      } else {
        final dist = math.sqrt(rawDx * rawDx + rawDy * rawDy + rawDz * rawDz);
        if (dist > 1e-6) {
          dirX = rawDx / dist;
          dirY = rawDy / dist;
          dirZ = rawDz / dist;
        }
      }
    }

    return (dirX: dirX, dirY: dirY, dirZ: dirZ);
  }

  /// Расчет координат конечной точки по направлению и длине
  Node3D calculateEndPoint({
    required Node3D startNode,
    required double lengthMm,
    required AxonometryProjector projector,
    required double currentElevationZ,
    Offset? currentCursorScreenPos,
    SnapResult? currentSnapResult,
    bool isSnapEnabled = true,
    double? dirX,
    double? dirY,
    double? dirZ,
  }) {
    final ({double dirX, double dirY, double dirZ}) dir;
    if (dirX != null || dirY != null || dirZ != null) {
      final dx = dirX ?? 0.0;
      final dy = dirY ?? 0.0;
      final dz = dirZ ?? 0.0;
      final mag = math.sqrt(dx * dx + dy * dy + dz * dz);
      if (mag > 1e-6) {
        dir = (dirX: dx / mag, dirY: dy / mag, dirZ: dz / mag);
      } else {
        dir = computeTraceDirection(
          startNode: startNode,
          projector: projector,
          currentElevationZ: currentElevationZ,
          currentCursorScreenPos: currentCursorScreenPos,
          currentSnapResult: currentSnapResult,
          isSnapEnabled: isSnapEnabled,
        );
      }
    } else {
      dir = computeTraceDirection(
        startNode: startNode,
        projector: projector,
        currentElevationZ: currentElevationZ,
        currentCursorScreenPos: currentCursorScreenPos,
        currentSnapResult: currentSnapResult,
        isSnapEnabled: isSnapEnabled,
      );
    }

    final endX = double.parse((startNode.x + dir.dirX * lengthMm).toStringAsFixed(2));
    final endY = double.parse((startNode.y + dir.dirY * lengthMm).toStringAsFixed(2));
    final endZ = double.parse((startNode.z + dir.dirZ * lengthMm).toStringAsFixed(2));

    return Node3D(id: '', x: endX, y: endY, z: endZ);
  }
}
