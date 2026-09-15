import 'package:flutter/material.dart';

import '../../../core/math/axonometry_projector.dart';
import '../../../domain/models/piping_network.dart';
import '../../../domain/enums/weld_type.dart';
import '../smart_callout.dart';

class AnnotationPainter {
  static void paint(
    Canvas canvas,
    AxonometryProjector projector,
    PipingNetwork network,
    String? selectedNodeId,
    bool showWelds,
    bool showCallouts, {
    String? selectedWeldId,
  }) {
    if (showWelds) {
      for (final weld in network.weldJoints.values) {
        final seg = network.segments[weld.segmentId];
        if (seg == null) continue;
        final start = network.nodes[seg.startNodeId];
        final end = network.nodes[seg.endNodeId];
        if (start == null || end == null) continue;

        final p1 = projector.project(start);
        final p2 = projector.project(end);

        final weldPos = Offset(
          p1.dx + (p2.dx - p1.dx) * weld.ratio,
          p1.dy + (p2.dy - p1.dy) * weld.ratio,
        );

        if (weld.id == selectedWeldId) {
          final glowPaint = Paint()
            ..color = Colors.cyanAccent.withValues(alpha: 0.35)
            ..style = PaintingStyle.fill;
          canvas.drawCircle(weldPos, 14.0, glowPaint);
          final borderPaint = Paint()
            ..color = Colors.cyanAccent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5;
          canvas.drawCircle(weldPos, 14.0, borderPaint);
        }

        SmartCallout.drawWeldCallout(
          canvas,
          weldPoint: weldPos,
          weldNumber: weld.number,
          stamp: weld.stamp,
          gostType: weld.weldType.shortName,
          color: const Color(0xFF37474F),
        );
      }
    }

    for (final node in network.nodes.values) {
      final screenPos = projector.project(node);
      final isSelected = node.id == selectedNodeId;
      final hasFitting = network.fittings.containsKey(node.id);
      final connected = network.getConnectedSegments(node.id);

      if (isSelected) {
        final glowPaint = Paint()
          ..color = Colors.amber.withValues(alpha: 0.35)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(screenPos, 9.0, glowPaint);

        final nodePaint = Paint()
          ..color = Colors.amber.shade700
          ..style = PaintingStyle.fill;
        canvas.drawCircle(screenPos, 5.0, nodePaint);

        final borderPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        canvas.drawCircle(screenPos, 5.0, borderPaint);
      } else if (!hasFitting && connected.length <= 1) {
        final nodePaint = Paint()
          ..color = const Color(0xFF37474F)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(screenPos, 3.5, nodePaint);

        final borderPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
        canvas.drawCircle(screenPos, 3.5, borderPaint);
      }

      if (showCallouts) {
        final hasVertical = connected.any((s) {
          final sNode = network.nodes[s.startNodeId];
          final eNode = network.nodes[s.endNodeId];
          return sNode != null && eNode != null && s.isVertical(sNode, eNode);
        });

        if (connected.length == 1 || hasVertical || node.customElevation != null) {
          SmartCallout.drawElevationCallout(
            canvas,
            point: screenPos,
            elevationText: node.elevationString,
            color: const Color(0xFF263238),
          );
        }
      }
    }
  }
}
