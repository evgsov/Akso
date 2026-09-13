import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../core/math/axonometry_projector.dart';
import '../../../domain/models/piping_network.dart';
import '../valve_symbol_painter.dart';

class ValvePainter {
  static void paint(
    Canvas canvas,
    AxonometryProjector projector,
    PipingNetwork network, {
    bool isVolumeMode = false,
  }) {
    for (final valve in network.valves.values) {
      final seg = network.segments[valve.segmentId];
      if (seg == null) continue;
      final start = network.nodes[seg.startNodeId];
      final end = network.nodes[seg.endNodeId];
      if (start == null || end == null) continue;

      final p1 = projector.project(start);
      final p2 = projector.project(end);

      final valvePos = Offset(
        p1.dx + (p2.dx - p1.dx) * valve.ratio,
        p1.dy + (p2.dy - p1.dy) * valve.ratio,
      );

      final angle = math.atan2(p2.dy - p1.dy, p2.dx - p1.dx);
      final sys = network.systems[seg.systemId];
      final color = sys != null ? Color(sys.colorValue) : Colors.black87;

      double size = _calcValveSize(valve.dn);
      if (isVolumeMode) {
        // Pseudo-3D: scale valve symbol to match pipe width
        final outerMm = network.pipeCatalog.getDimension(valve.dn)?.outerDiameterMm ?? valve.dn.toDouble();
        final strokeWidth = outerMm * projector.scale;
        size = math.max(16.0, strokeWidth * 2.2); 
      }

      ValveSymbolPainter.drawValve(
        canvas,
        center: valvePos,
        angleRad: angle,
        type: valve.valveType,
        color: color,
        size: size,
        isReversed: valve.isReversed,
      );
    }
  }

  static double _calcValveSize(int dn) {
    if (dn <= 25) return 14.0;
    if (dn <= 50) return 18.0;
    if (dn <= 100) return 24.0;
    return 28.0;
  }
}
