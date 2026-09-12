import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../core/math/axonometry_projector.dart';
import '../../../domain/models/piping_network.dart';
import '../valve_symbol_painter.dart';

class ValvePainter {
  static void paint(
    Canvas canvas,
    AxonometryProjector projector,
    PipingNetwork network,
  ) {
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

      ValveSymbolPainter.drawValve(
        canvas,
        center: valvePos,
        angleRad: angle,
        type: valve.valveType,
        color: color,
        size: _calcValveSize(valve.dn),
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
