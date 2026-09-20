import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/math/axonometry_projector.dart';
import '../../../domain/models/node_3d.dart';
import '../../../domain/models/piping_network.dart';

/// Контроллер селекции: одиночный выбор, мультиселекция,
/// рамочный выбор (Marquee Window / Crossing), модификаторы Shift / Ctrl.
class SelectionController {
  final Set<String> selectedNodeIds = {};
  final Set<String> selectedSegmentIds = {};
  final Set<String> selectedEquipmentIds = {};
  final Set<String> selectedAxisIds = {};
  final Set<String> selectedDimensionIds = {};
  final Set<String> selectedSpoolIds = {};
  String? selectedCalloutId;

  String? selectedNodeId;
  String? selectedSegmentId;
  String? selectedSpoolId;
  String? selectedEquipmentId;
  String? selectedAxisId;
  String? selectedDimensionId;
  String? selectedValveId;
  String? selectedSupportId;
  String? selectedWeldId;

  // Рамочный выбор (Marquee Box Selection)
  Rect? selectionBoxRect;
  Offset? boxSelectStart;
  bool isCrossingSelection = false;
  bool boxSelectIsShift = false;
  bool boxSelectIsCtrl = false;

  bool get hasSelection =>
      selectedNodeIds.isNotEmpty ||
      selectedSegmentIds.isNotEmpty ||
      selectedSpoolIds.isNotEmpty ||
      selectedEquipmentIds.isNotEmpty ||
      selectedAxisIds.isNotEmpty ||
      selectedDimensionIds.isNotEmpty ||
      selectedNodeId != null ||
      selectedSegmentId != null ||
      selectedSpoolId != null ||
      selectedEquipmentId != null ||
      selectedAxisId != null ||
      selectedDimensionId != null ||
      selectedCalloutId != null ||
      selectedValveId != null ||
      selectedSupportId != null ||
      selectedWeldId != null;

  void clearSelection() {
    selectedNodeIds.clear();
    selectedSegmentIds.clear();
    selectedSpoolIds.clear();
    selectedEquipmentIds.clear();
    selectedAxisIds.clear();
    selectedDimensionIds.clear();
    selectedCalloutId = null;
    selectedNodeId = null;
    selectedSegmentId = null;
    selectedSpoolId = null;
    selectedEquipmentId = null;
    selectedAxisId = null;
    selectedDimensionId = null;
    selectedValveId = null;
    selectedSupportId = null;
    selectedWeldId = null;
    cancelBoxSelection();
  }

  void startBoxSelection(Offset screenPos, {bool isShift = false, bool isCtrl = false}) {
    boxSelectStart = screenPos;
    selectionBoxRect = Rect.fromPoints(screenPos, screenPos);
    isCrossingSelection = false;
    boxSelectIsShift = isShift;
    boxSelectIsCtrl = isCtrl;
  }

  void updateBoxSelection(Offset currentScreenPos) {
    if (boxSelectStart == null) return;
    selectionBoxRect = Rect.fromPoints(boxSelectStart!, currentScreenPos);
    isCrossingSelection = currentScreenPos.dx < boxSelectStart!.dx;
  }

  void cancelBoxSelection() {
    boxSelectStart = null;
    selectionBoxRect = null;
    boxSelectIsShift = false;
    boxSelectIsCtrl = false;
  }

  /// Фиксация рамки выбора и применение к элементам сети
  void commitBoxSelection({
    required PipingNetwork network,
    required AxonometryProjector projector,
    required double currentElevationZ,
  }) {
    if (selectionBoxRect == null) return;
    final rect = selectionBoxRect!;
    final isCrossing = isCrossingSelection;

    final boxedNodeIds = <String>{};
    for (final node in network.nodes.values) {
      final p = projector.project(node);
      if (rect.contains(p)) {
        boxedNodeIds.add(node.id);
      }
    }

    final boxedSegmentIds = <String>{};
    for (final seg in network.segments.values) {
      final s = network.nodes[seg.startNodeId];
      final e = network.nodes[seg.endNodeId];
      if (s == null || e == null) continue;
      final p1 = projector.project(s);
      final p2 = projector.project(e);
      if (isCrossing) {
        if (rect.contains(p1) || rect.contains(p2) || segmentIntersectsRect(p1, p2, rect)) {
          boxedSegmentIds.add(seg.id);
          boxedNodeIds.add(s.id);
          boxedNodeIds.add(e.id);
        }
      } else {
        if (rect.contains(p1) && rect.contains(p2)) {
          boxedSegmentIds.add(seg.id);
          boxedNodeIds.add(s.id);
          boxedNodeIds.add(e.id);
        }
      }
    }

    final boxedEquipmentIds = <String>{};
    for (final eq in network.equipments.values) {
      final p = projector.projectCoordinates(eq.x, eq.y, eq.z);
      final w = math.max(20.0, (eq.width / 2) * projector.scale);
      final l = math.max(20.0, (eq.length / 2) * projector.scale);
      final eqBounds = Rect.fromCenter(center: p, width: w * 2, height: l * 2);
      if (isCrossing) {
        if (rect.overlaps(eqBounds) || rect.contains(p)) {
          boxedEquipmentIds.add(eq.id);
        }
      } else {
        if (rect.contains(eqBounds.topLeft) && rect.contains(eqBounds.bottomRight)) {
          boxedEquipmentIds.add(eq.id);
        }
      }
    }

    final boxedAxisIds = <String>{};
    for (final axis in network.axes.values) {
      final p1Native = projector.project(axis.startPoint);
      final p2Native = projector.project(axis.endPoint);

      final aWorld = Node3D(id: '', x: axis.startPoint.x, y: axis.startPoint.y, z: currentElevationZ);
      final bWorld = Node3D(id: '', x: axis.endPoint.x, y: axis.endPoint.y, z: currentElevationZ);
      final p1z = projector.project(aWorld);
      final p2z = projector.project(bWorld);

      bool matches(Offset p1, Offset p2) {
        if (isCrossing) {
          return rect.contains(p1) || rect.contains(p2) || segmentIntersectsRect(p1, p2, rect);
        } else {
          return rect.contains(p1) && rect.contains(p2);
        }
      }

      if (matches(p1Native, p2Native) || matches(p1z, p2z)) {
        boxedAxisIds.add(axis.id);
      }
    }

    final boxedDimensionIds = <String>{};
    for (final dim in network.dimensions.values) {
      final p1 = projector.project(dim.startPoint);
      final p2 = projector.project(dim.endPoint);
      if (isCrossing) {
        if (rect.contains(p1) || rect.contains(p2) || segmentIntersectsRect(p1, p2, rect)) {
          boxedDimensionIds.add(dim.id);
        }
      } else {
        if (rect.contains(p1) && rect.contains(p2)) {
          boxedDimensionIds.add(dim.id);
        }
      }
    }

    final boxedSpoolIds = <String>{};
    for (final spool in network.spools.values) {
      if (boxedSegmentIds.contains(spool.segmentId)) {
        boxedSpoolIds.add(spool.id);
      }
    }

    if (boxSelectIsShift) {
      selectedNodeIds.removeAll(boxedNodeIds);
      selectedSegmentIds.removeAll(boxedSegmentIds);
      selectedSpoolIds.removeAll(boxedSpoolIds);
      selectedEquipmentIds.removeAll(boxedEquipmentIds);
      selectedAxisIds.removeAll(boxedAxisIds);
      selectedDimensionIds.removeAll(boxedDimensionIds);
      if (selectedNodeId != null && !selectedNodeIds.contains(selectedNodeId)) {
        selectedNodeId = selectedNodeIds.isEmpty ? null : selectedNodeIds.first;
      }
      if (selectedSegmentId != null && !selectedSegmentIds.contains(selectedSegmentId)) {
        selectedSegmentId = selectedSegmentIds.isEmpty ? null : selectedSegmentIds.first;
      }
      if (selectedSpoolId != null && !selectedSpoolIds.contains(selectedSpoolId)) {
        selectedSpoolId = selectedSpoolIds.isEmpty ? null : selectedSpoolIds.first;
      }
    } else if (boxSelectIsCtrl) {
      selectedNodeIds.addAll(boxedNodeIds);
      selectedSegmentIds.addAll(boxedSegmentIds);
      selectedSpoolIds.addAll(boxedSpoolIds);
      selectedEquipmentIds.addAll(boxedEquipmentIds);
      selectedAxisIds.addAll(boxedAxisIds);
      selectedDimensionIds.addAll(boxedDimensionIds);
      if (selectedNodeId == null && selectedNodeIds.isNotEmpty) {
        selectedNodeId = selectedNodeIds.first;
      }
      if (selectedSegmentId == null && selectedSegmentIds.isNotEmpty) {
        selectedSegmentId = selectedSegmentIds.first;
      }
      if (selectedSpoolId == null && selectedSpoolIds.isNotEmpty) {
        selectedSpoolId = selectedSpoolIds.first;
      }
    } else {
      selectedNodeIds
        ..clear()
        ..addAll(boxedNodeIds);
      selectedSegmentIds
        ..clear()
        ..addAll(boxedSegmentIds);
      selectedSpoolIds
        ..clear()
        ..addAll(boxedSpoolIds);
      selectedEquipmentIds
        ..clear()
        ..addAll(boxedEquipmentIds);
      selectedAxisIds
        ..clear()
        ..addAll(boxedAxisIds);
      selectedDimensionIds
        ..clear()
        ..addAll(boxedDimensionIds);
      selectedNodeId = selectedNodeIds.isEmpty ? null : selectedNodeIds.first;
      selectedSegmentId = selectedSegmentIds.isEmpty ? null : selectedSegmentIds.first;
      selectedSpoolId = selectedSpoolIds.isEmpty ? null : selectedSpoolIds.first;
      selectedEquipmentId = selectedEquipmentIds.isEmpty ? null : selectedEquipmentIds.first;
      selectedAxisId = selectedAxisIds.isEmpty ? null : selectedAxisIds.first;
      selectedDimensionId = selectedDimensionIds.isEmpty ? null : selectedDimensionIds.first;
    }

    cancelBoxSelection();
  }

  static bool segmentIntersectsRect(Offset p1, Offset p2, Rect rect) {
    if (rect.contains(p1) || rect.contains(p2)) return true;
    final rLeft = rect.left, rRight = rect.right, rTop = rect.top, rBottom = rect.bottom;
    return linesIntersect(p1, p2, Offset(rLeft, rTop), Offset(rRight, rTop)) ||
        linesIntersect(p1, p2, Offset(rRight, rTop), Offset(rRight, rBottom)) ||
        linesIntersect(p1, p2, Offset(rRight, rBottom), Offset(rLeft, rBottom)) ||
        linesIntersect(p1, p2, Offset(rLeft, rBottom), Offset(rLeft, rTop));
  }

  static bool linesIntersect(Offset a1, Offset a2, Offset b1, Offset b2) {
    double ccw(Offset a, Offset b, Offset c) =>
        (c.dy - a.dy) * (b.dx - a.dx) - (b.dy - a.dy) * (c.dx - a.dx);
    return (ccw(a1, b1, b2) * ccw(a2, b1, b2) <= 0) &&
        (ccw(a1, a2, b1) * ccw(a1, a2, b2) <= 0);
  }
}
