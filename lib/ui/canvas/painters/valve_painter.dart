import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../core/math/axonometry_projector.dart';
import '../../../domain/models/drawing_style_config.dart';
import '../../../domain/models/piping_network.dart';
import '../../../domain/models/custom_valve_definition.dart';
import '../../../domain/services/custom_valve_catalog.dart';
import '../../../domain/services/element_3d_geometry.dart';

class ValvePainter {
  static void paint(
    Canvas canvas,
    AxonometryProjector projector,
    PipingNetwork network, {
    bool isVolumeMode = false,
    String? selectedValveId,
    DrawingStyleConfig? styleConfig,
    double? sheetZoom,
    Map<String, CustomValveDefinition>? customValves,
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

      final customDef = valve.customDefinitionId != null
          ? (customValves?[valve.customDefinitionId!] ??
              CustomValveCatalog.instance.getById(valve.customDefinitionId!))
          : null;

      final wireSegments = Element3dGeometry.generateValveWireframe(
        valve,
        start,
        end,
        pipeOuterDiameter: seg.outerDiameterMm,
        customDefinition: customDef,
      );

      final isSelected = valve.id == selectedValveId;
      final valveStroke = (styleConfig != null && sheetZoom != null)
          ? math.max(0.5, styleConfig.fittingLineWidthMm * sheetZoom)
          : (isSelected ? 2.5 : 1.6);
      final strokePaint = Paint()
        ..color = isSelected ? Colors.amber : color
        ..style = PaintingStyle.stroke
        ..strokeWidth = valveStroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final handlePaint = Paint()
        ..color = isSelected ? Colors.amber : color
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.5, valveStroke * 0.45)
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
        final paint = wire.layer == Element3dGeometry.layerHandles ? handlePaint : strokePaint;
        canvas.drawLine(p1, p2, paint);
      }
    }
  }
}
