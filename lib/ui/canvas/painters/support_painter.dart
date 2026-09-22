import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../core/math/axonometry_projector.dart';
import '../../../domain/models/drawing_style_config.dart';
import '../../../domain/models/pipe_support.dart';
import '../../../domain/models/piping_network.dart';
import '../../../domain/services/element_3d_geometry.dart';

/// Отрисовка опор и подвесок трубопровода в виде пространственного 3D-проволочного каркаса
class SupportPainter {
  static void paint(
    Canvas canvas,
    AxonometryProjector projector,
    PipingNetwork network, {
    bool isVolumeMode = false,
    String? selectedSupportId,
    DrawingStyleConfig? styleConfig,
    double? sheetZoom,
  }) {
    // В объемном 3D-режиме опоры визуализируются твердотельными телами в Solid3dEngine
    if (network.supports.isEmpty || isVolumeMode) return;

    for (final support in network.supports.values) {
      final seg = network.segments[support.segmentId];
      if (seg == null) continue;
      final start = network.nodes[seg.startNodeId];
      final end = network.nodes[seg.endNodeId];
      if (start == null || end == null) continue;

      final isSelected = support.id == selectedSupportId;
      final wireSegments = Element3dGeometry.generateSupportWireframe(
        support,
        start,
        end,
        pipeOuterDiameter: seg.outerDiameterMm,
      );

      final sys = network.systems[seg.systemId];
      final baseColor = sys != null ? Color(sys.colorValue) : const Color(0xFF263238);

      final supportStroke = (styleConfig != null && sheetZoom != null)
          ? math.max(0.5, styleConfig.thinLineWidthMm * sheetZoom)
          : (isSelected ? 2.5 : 1.8);
      final strokePaint = Paint()
        ..color = isSelected ? Colors.amber : baseColor
        ..strokeWidth = supportStroke
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      if (isSelected) {
        final glowPaint = Paint()
          ..color = Colors.amber.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6.0
          ..strokeCap = StrokeCap.round;
        for (final wire in wireSegments) {
          final wp1 = projector.project(wire.startNode);
          final wp2 = projector.project(wire.endNode);
          canvas.drawLine(wp1, wp2, glowPaint);
        }
      }

      for (final wire in wireSegments) {
        final wp1 = projector.project(wire.startNode);
        final wp2 = projector.project(wire.endNode);
        canvas.drawLine(wp1, wp2, strokePaint);
      }

      // Центр опоры на оси трубы
      final worldCenter = support.calculatePosition(start, end);
      final center = projector.project(worldCenter);

      if (isSelected) {
        final highlightPaint = Paint()
          ..color = Colors.amber
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        final glowPaint = Paint()
          ..color = Colors.amber.withValues(alpha: 0.25)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(center, 12.0, glowPaint);
        canvas.drawCircle(center, 12.0, highlightPaint);
      }

      if (support.name.isNotEmpty) {
        _drawLabel(canvas, center, support);
      }
    }
  }

  /// Маркировка опоры (напр. "ОП-1", "НО-2")
  static void _drawLabel(
    Canvas canvas,
    Offset center,
    PipeSupport support,
  ) {
    final label = support.name.isNotEmpty ? support.name : support.type.shortCode;
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xFF263238),
          fontSize: 9.5,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final labelOffset = center + Offset(-tp.width / 2, 14.0);

    final bgRect = Rect.fromLTWH(
      labelOffset.dx - 3,
      labelOffset.dy - 1,
      tp.width + 6,
      tp.height + 2,
    );

    final bgPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = const Color(0xFF90A4AE)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(3.0)),
      bgPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(3.0)),
      borderPaint,
    );

    tp.paint(canvas, labelOffset);
  }
}
