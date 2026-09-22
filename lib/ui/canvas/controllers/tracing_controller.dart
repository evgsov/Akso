import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/math/axonometry_projector.dart';
import '../../../core/math/drafting_settings.dart';
import '../../../core/math/snap_engine.dart';
import '../../../domain/models/acquired_tracking_point.dart';
import '../../../domain/models/node_3d.dart';

/// Контроллер трассировки трубопроводов и разбивочных осей:
/// Режимы угловой привязки (Орто, Изометрия, шаг углов),
/// расчет векторов направления и конечных точек,
/// объектное отслеживание (OTRACK) и параметры черчения (DraftingSettings).
class TracingController {
  AngleSnapMode angleSnapMode = AngleSnapMode.ortho90;
  double customAngleDegrees = 15.0;
  bool get isObjectTrackingEnabled => draftingSettings.enableOtrack;
  set isObjectTrackingEnabled(bool val) {
    draftingSettings = draftingSettings.copyWith(enableOtrack: val);
  }

  DraftingSettings draftingSettings = const DraftingSettings();
  final List<AcquiredTrackingPoint> acquiredPoints = [];
  Timer? _hoverDwellTimer;
  String? _pendingDwellNodeId;

  Node3D? traceStartNode;
  Node3D? axisStartNode;
  String currentAxisLabel = '1';
  bool isBuildingGridAxis = true;

  void setAngleSnapMode(AngleSnapMode mode) {
    angleSnapMode = mode;
  }

  void toggleObjectTracking() {
    draftingSettings = draftingSettings.copyWith(enableOtrack: !draftingSettings.enableOtrack);
    if (!draftingSettings.enableOtrack) {
      clearAcquiredPoints();
    }
  }

  void updateDraftingSettings(DraftingSettings newSettings) {
    draftingSettings = newSettings;
    if (!draftingSettings.enableOtrack) {
      clearAcquiredPoints();
    }
  }

  /// Обработка удержания курсора над узлом для захвата точки (Hover-to-Acquire OTRACK)
  void processHoverDwell({
    required Offset screenPos,
    Node3D? candidateNode,
    required VoidCallback onAcquired,
  }) {
    if (candidateNode == null || !draftingSettings.enableOtrack) {
      _hoverDwellTimer?.cancel();
      _hoverDwellTimer = null;
      _pendingDwellNodeId = null;
      return;
    }

    if (_pendingDwellNodeId == candidateNode.id) {
      // Курсор уже на этом узле, таймер продолжает тикать
      return;
    }

    _hoverDwellTimer?.cancel();
    _pendingDwellNodeId = candidateNode.id;

    _hoverDwellTimer = Timer(const Duration(milliseconds: 350), () {
      final existingIndex = acquiredPoints.indexWhere((p) => p.nodeId == candidateNode.id);
      if (existingIndex >= 0) {
        // Повторный навод и удержание снимает захват точки
        acquiredPoints.removeAt(existingIndex);
      } else {
        if (acquiredPoints.length >= 2) {
          acquiredPoints.removeAt(0);
        }
        acquiredPoints.add(AcquiredTrackingPoint(
          worldPoint: candidateNode,
          screenPoint: screenPos,
          nodeId: candidateNode.id,
          acquiredAt: DateTime.now(),
        ));
      }
      onAcquired();
    });
  }

  void clearAcquiredPoints() {
    _hoverDwellTimer?.cancel();
    _hoverDwellTimer = null;
    _pendingDwellNodeId = null;
    acquiredPoints.clear();
  }

  void resetTrace() {
    traceStartNode = null;
    clearAcquiredPoints();
  }

  void resetAxis() {
    axisStartNode = null;
    clearAcquiredPoints();
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
