import 'package:flutter/material.dart';

import '../../../core/math/axonometry_projector.dart';
import '../../../domain/models/piping_network.dart';
import '../../../domain/services/element_3d_geometry.dart';

class ValvePainter {
  static void paint(
    Canvas canvas,
    AxonometryProjector projector,
    PipingNetwork network, {
    bool isVolumeMode = false,
    String? selectedValveId,
  }) {
    // В объемном 3D-режиме арматура визуализируется твердотельными телами в Solid3dEngine
    if (isVolumeMode) return;

    for (final valve in network.valves.values) {
      final seg = network.segments[valve.segmentId];
      if (seg == null) continue;
      final start = network.nodes[seg.startNodeId];
      final end = network.nodes[seg.endNodeId];
      if (start == null || end == null) continue;

      final sys = network.systems[seg.systemId];
      final color = sys != null ? Color(sys.colorValue) : Colors.black87;

      final wireSegments = Element3dGeometry.generateValveWireframe(
        valve,
        start,
        end,
        pipeOuterDiameter: seg.outerDiameterMm,
      );

      final isSelected = valve.id == selectedValveId;
      final strokePaint = Paint()
        ..color = isSelected ? Colors.amber : color
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 2.5 : 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      if (isSelected) {
        final glowPaint = Paint()
          ..color = Colors.amber.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6.0
          ..strokeCap = StrokeCap.round;
        for (final wire in wireSegments) {
          final p1 = projector.project(wire.startNode);
          final p2 = projector.project(wire.endNode);
          canvas.drawLine(p1, p2, glowPaint);
        }
      }

      for (final wire in wireSegments) {
        final p1 = projector.project(wire.startNode);
        final p2 = projector.project(wire.endNode);
        canvas.drawLine(p1, p2, strokePaint);
      }
    }
  }
}
