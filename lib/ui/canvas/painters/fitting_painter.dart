import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../../../core/math/axonometry_projector.dart';
import '../../../domain/enums/fitting_type.dart';
import '../../../domain/enums/projection_type.dart';
import '../../../domain/models/fitting.dart';
import '../../../domain/models/piping_network.dart';
import 'pipe_painter.dart';

class FittingPainter {
  static void paint(
    Canvas canvas,
    AxonometryProjector projector,
    PipingNetwork network,
    String? selectedNodeId,
    bool showCallouts, {
    bool isVolumeMode = false,
  }) {
    for (final fit in network.fittings.values) {
      if (fit.fittingType == FittingType.elbow90 || fit.fittingType == FittingType.elbow45) {
        _drawElbowSymbol(canvas, projector, network, fit, selectedNodeId, showCallouts, isVolumeMode);
      } else if (fit.fittingType == FittingType.tee) {
        _drawTeeSymbol(canvas, projector, network, fit, selectedNodeId, showCallouts, isVolumeMode);
      } else if (fit.fittingType == FittingType.reducerConcentric ||
          fit.fittingType == FittingType.reducerEccentric) {
        final node = network.nodes[fit.nodeId];
        if (node == null) continue;
        final connected = network.getConnectedSegments(fit.nodeId);
        if (connected.length != 2) continue;

        final center = projector.project(node);
        final s1 = connected[0];
        final other1 = network.nodes[s1.startNodeId == fit.nodeId ? s1.endNodeId : s1.startNodeId]!;
        final pOther = projector.project(other1);
        final angle = math.atan2(center.dy - pOther.dy, center.dx - pOther.dx);

        final sys = network.systems[s1.systemId];
        final color = sys != null ? Color(sys.colorValue) : Colors.black87;

        _drawReducerSymbol(
          canvas,
          projector: projector,
          network: network,
          isVolumeMode: isVolumeMode,
          center: center,
          angle: angle,
          dn1: fit.dn,
          dn2: fit.dnSecondary ?? fit.dn,
          isEccentric: fit.fittingType == FittingType.reducerEccentric,
          color: color,
        );
      } else if (fit.fittingType == FittingType.flange) {
        final node = network.nodes[fit.nodeId];
        if (node == null) continue;
        final connected = network.getConnectedSegments(fit.nodeId);
        if (connected.isEmpty) continue;

        final center = projector.project(node);
        final s1 = connected[0];
        final other1 = network.nodes[s1.startNodeId == fit.nodeId ? s1.endNodeId : s1.startNodeId]!;
        final pOther = projector.project(other1);
        final angle = math.atan2(center.dy - pOther.dy, center.dx - pOther.dx);

        final sys = network.systems[s1.systemId];
        final color = sys != null ? Color(sys.colorValue) : Colors.black87;

        _drawFlangeSymbol(
          canvas,
          projector: projector,
          network: network,
          isVolumeMode: isVolumeMode,
          center: center,
          angle: angle,
          dn: fit.dn,
          flangeConnectionType: fit.flangeConnectionType,
          pressurePn: fit.pressurePn,
          color: color,
          showCallouts: showCallouts,
        );
      } else if (fit.fittingType == FittingType.directBranch) {
        final node = network.nodes[fit.nodeId];
        if (node == null) continue;
        final center = projector.project(node);
        _drawDirectBranchSymbol(
          canvas,
          center: center,
          dn: fit.dn,
          dnSecondary: fit.dnSecondary,
          showCallouts: showCallouts,
        );
      } else if (fit.fittingType == FittingType.cap) {
        final node = network.nodes[fit.nodeId];
        if (node == null) continue;
        final connected = network.getConnectedSegments(fit.nodeId);
        if (connected.isEmpty) continue;

        final center = projector.project(node);
        final s1 = connected[0];
        final other1 = network.nodes[s1.startNodeId == fit.nodeId ? s1.endNodeId : s1.startNodeId]!;
        final pOther = projector.project(other1);
        final angle = math.atan2(center.dy - pOther.dy, center.dx - pOther.dx);

        final sys = network.systems[s1.systemId];
        final color = sys != null ? Color(sys.colorValue) : Colors.black87;

        _drawCapSymbol(
          canvas,
          projector: projector,
          network: network,
          isVolumeMode: isVolumeMode,
          center: center,
          angle: angle,
          dn: fit.dn,
          color: color,
        );
      }
    }
  }

  static double _calcWidth(int dn, PipingNetwork network, AxonometryProjector projector, bool isVolumeMode) {
    double w = PipePainter.calcStrokeWidth(dn);
    if (isVolumeMode) {
      final dim = network.pipeCatalog.getDimension(dn);
      final outerMm = dim != null ? dim.outerDiameterMm : dn.toDouble();
      w = outerMm * projector.scale;
      if (w < 2.0) w = 2.0;
    }
    return w;
  }
  static void _drawElbowSymbol(
    Canvas canvas,
    AxonometryProjector projector,
    PipingNetwork network,
    Fitting fit,
    String? selectedNodeId,
    bool showCallouts,
    bool isVolumeMode,
  ) {
    final node = network.nodes[fit.nodeId];
    if (node == null) return;
    final connected = network.getConnectedSegments(fit.nodeId);
    if (connected.length != 2) return;

    final sys = network.systems[connected[0].systemId];
    final color = sys != null ? Color(sys.colorValue) : Colors.black87;

    final s1 = connected[0];
    final s2 = connected[1];

    final other1 = network.nodes[s1.startNodeId == fit.nodeId ? s1.endNodeId : s1.startNodeId]!;
    final other2 = network.nodes[s2.startNodeId == fit.nodeId ? s2.endNodeId : s2.startNodeId]!;

    final ptN = projector.project(node);
    final ptO1 = projector.project(other1);
    final ptO2 = projector.project(other2);

    final pOut1 = PipePainter.calcPipeTrimmedPoint(
      network: network,
      nodeId: fit.nodeId,
      otherNodeId: other1.id,
      nodeScreen: ptN,
      otherScreen: ptO1,
      seg: s1,
    );
    final pOut2 = PipePainter.calcPipeTrimmedPoint(
      network: network,
      nodeId: fit.nodeId,
      otherNodeId: other2.id,
      nodeScreen: ptN,
      otherScreen: ptO2,
      seg: s2,
    );

    final strokeWidth = _calcWidth(fit.dn, network, projector, isVolumeMode);

    if (isVolumeMode) {
      final dx = pOut2.dx - pOut1.dx;
      final dy = pOut2.dy - pOut1.dy;
      final centerElbow = Offset(pOut1.dx + dx / 2, pOut1.dy + dy / 2);
      
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      
      final path = Path()
        ..moveTo(pOut1.dx, pOut1.dy)
        ..quadraticBezierTo(ptN.dx, ptN.dy, pOut2.dx, pOut2.dy);
      canvas.drawPath(path, paint);

      _drawWeldTickAt(canvas, pOut1, centerElbow, strokeWidth);
      _drawWeldTickAt(canvas, pOut2, centerElbow, strokeWidth);
    } else {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.square;

      canvas.drawLine(ptN, pOut1, paint);
      canvas.drawLine(ptN, pOut2, paint);

      final curvePaint = Paint()
        ..color = Colors.blueGrey.shade300
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      final path = Path()
        ..moveTo(pOut1.dx, pOut1.dy)
        ..quadraticBezierTo(ptN.dx, ptN.dy, pOut2.dx, pOut2.dy);
      canvas.drawPath(path, curvePaint);

      _drawWeldTickAt(canvas, pOut1, ptN, strokeWidth);
      _drawWeldTickAt(canvas, pOut2, ptN, strokeWidth);
    }

    if (showCallouts) {
      final tp = TextPainter(
        text: TextSpan(
          text: fit.fittingType.displayName,
          style: TextStyle(
            color: color,
            fontSize: 9.0,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            backgroundColor: Colors.white.withValues(alpha: 0.8),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, ptN + const Offset(10, 10));
    }
  }

  static void _drawWeldTickAt(Canvas canvas, Offset pos, Offset towardCenter, double strokeWidth) {
    final dx = pos.dx - towardCenter.dx;
    final dy = pos.dy - towardCenter.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 0.1) return;
    final nx = -dy / len;
    final ny = dx / len;
    
    final halfLen = math.max(strokeWidth * 0.7, 4.0);
    
    final paint = Paint()
      ..color = const Color(0xFF37474F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    
    canvas.drawLine(
      Offset(pos.dx - nx * halfLen, pos.dy - ny * halfLen),
      Offset(pos.dx + nx * halfLen, pos.dy + ny * halfLen),
      paint,
    );
  }
  static void _drawTeeSymbol(
    Canvas canvas,
    AxonometryProjector projector,
    PipingNetwork network,
    Fitting fit,
    String? selectedNodeId,
    bool showCallouts,
    bool isVolumeMode,
  ) {
    final node = network.nodes[fit.nodeId];
    if (node == null) return;
    final connected = network.getConnectedSegments(fit.nodeId);
    if (connected.length < 3) return;

    final segRun1 = connected[0];
    final segRun2 = connected[1];
    final segBranch = connected[2];

    final sys = network.systems[segRun1.systemId];
    final color = sys != null ? Color(sys.colorValue) : Colors.black87;

    final other1 = network.nodes[segRun1.startNodeId == fit.nodeId ? segRun1.endNodeId : segRun1.startNodeId]!;
    final other2 = network.nodes[segRun2.startNodeId == fit.nodeId ? segRun2.endNodeId : segRun2.startNodeId]!;
    final otherBranch = network.nodes[segBranch.startNodeId == fit.nodeId ? segBranch.endNodeId : segBranch.startNodeId]!;

    final ptN = projector.project(node);

    final strokeWidth = _calcWidth(fit.dn, network, projector, isVolumeMode);

    if (isVolumeMode) {
      final pOut1 = PipePainter.calcPipeTrimmedPoint(
        network: network,
        nodeId: fit.nodeId,
        otherNodeId: other1.id,
        nodeScreen: ptN,
        otherScreen: projector.project(other1),
        seg: segRun1,
      );
      final pOut2 = PipePainter.calcPipeTrimmedPoint(
        network: network,
        nodeId: fit.nodeId,
        otherNodeId: other2.id,
        nodeScreen: ptN,
        otherScreen: projector.project(other2),
        seg: segRun2,
      );
      final pOutBranch = PipePainter.calcPipeTrimmedPoint(
        network: network,
        nodeId: fit.nodeId,
        otherNodeId: otherBranch.id,
        nodeScreen: ptN,
        otherScreen: projector.project(otherBranch),
        seg: segBranch,
      );

      final teeBodyPaint = Paint()
        ..color = color
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.square;

      canvas.drawLine(pOut1, pOut2, teeBodyPaint);

      final branchStroke = _calcWidth(segBranch.dn, network, projector, isVolumeMode);
      final branchPaint = Paint()
        ..color = color
        ..strokeWidth = branchStroke
        ..strokeCap = StrokeCap.square;
      canvas.drawLine(ptN, pOutBranch, branchPaint);

      final hubRadius = math.max(strokeWidth * 0.7, 4.5);
      final hubPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(ptN, hubRadius, hubPaint);

      final collarPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawCircle(ptN, hubRadius, collarPaint);

      _drawWeldTickAt(canvas, pOut1, ptN, strokeWidth);
      _drawWeldTickAt(canvas, pOut2, ptN, strokeWidth);
      _drawWeldTickAt(canvas, pOutBranch, ptN, branchStroke);
    } else {
      final teePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(ptN, math.max(7.0, strokeWidth * 0.9), teePaint);
    }

    if (showCallouts) {
      final name = fit.dnSecondary != null && fit.dnSecondary != fit.dn
          ? 'Тройник х'
          : 'Тройник Ду';
      final tp = TextPainter(
        text: TextSpan(
          text: name,
          style: TextStyle(
            color: color,
            fontSize: 9.0,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            backgroundColor: Colors.white.withValues(alpha: 0.9),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, ptN + const Offset(12, -14));
    }
  }
  static void _drawReducerSymbol(
    Canvas canvas, {
    required AxonometryProjector projector,
    required PipingNetwork network,
    required bool isVolumeMode,
    required Offset center,
    required double angle,
    required int dn1,
    required int dn2,
    required bool isEccentric,
    required Color color,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final w1 = _calcWidth(dn1, network, projector, isVolumeMode);
    final w2 = _calcWidth(dn2, network, projector, isVolumeMode);
    final len = isVolumeMode ? math.max(w1, w2) * 1.5 : 12.0;
    
    final paint = Paint()
      ..color = color
      ..style = isVolumeMode ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = isVolumeMode ? 0 : 2.0;

    final path = Path();
    if (isEccentric) {
      path.moveTo(-len / 2, -w1 / 2);
      path.lineTo(len / 2, -w2 / 2);
      path.lineTo(len / 2, w2 / 2);
      path.lineTo(-len / 2, w1 / 2);
      path.close();
    } else {
      path.moveTo(-len / 2, -w1 / 2);
      path.lineTo(len / 2, -w2 / 2);
      path.lineTo(len / 2, w2 / 2);
      path.lineTo(-len / 2, w1 / 2);
      path.close();
    }
    canvas.drawPath(path, paint);

    if (isVolumeMode) {
      final border = Paint()
        ..color = Colors.black54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawPath(path, border);
    }
    
    canvas.restore();
  }

  static void _drawFlangeSymbol(
    Canvas canvas, {
    required AxonometryProjector projector,
    required PipingNetwork network,
    required bool isVolumeMode,
    required Offset center,
    required double angle,
    required int dn,
    required FlangeConnectionType flangeConnectionType,
    required int pressurePn,
    required Color color,
    required bool showCallouts,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final halfH = math.max(8.0, _calcWidth(dn, network, projector, isVolumeMode) * 1.6);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.square;

    switch (flangeConnectionType) {
      case FlangeConnectionType.pipeToPipe:
        const gap = 3.0;
        canvas.drawLine(Offset(-gap, -halfH), Offset(-gap, halfH), paint);
        canvas.drawLine(Offset(gap, -halfH), Offset(gap, halfH), paint);
        final gasketPaint = Paint()
          ..color = Colors.amber.shade800
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset.zero, 2.0, gasketPaint);
        break;

      case FlangeConnectionType.toEquipment:
        canvas.drawLine(Offset(-2.0, -halfH), Offset(-2.0, halfH), paint);
        final gasketPaint = Paint()
          ..color = Colors.amber.shade800
          ..style = PaintingStyle.fill;
        canvas.drawCircle(const Offset(0.5, 0), 2.0, gasketPaint);

        final eqPaint = Paint()
          ..color = Colors.blueGrey.shade400
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8;
        canvas.drawLine(Offset(3.5, -halfH * 1.15), Offset(3.5, halfH * 1.15), eqPaint);
        canvas.drawRect(Rect.fromLTWH(3.5, -halfH * 0.6, 7.0, halfH * 1.2), eqPaint);
        break;

      case FlangeConnectionType.blindFlange:
        canvas.drawLine(Offset(-2.0, -halfH), Offset(-2.0, halfH), paint);
        final blindPaint = Paint()
          ..color = Colors.blueGrey.shade700
          ..style = PaintingStyle.fill;
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(1.5, -halfH * 1.05, 4.0, halfH * 2.1), const Radius.circular(1.0)),
          blindPaint,
        );
        break;

      case FlangeConnectionType.singleFlange:
        canvas.drawLine(Offset(0, -halfH), Offset(0, halfH), paint);
        break;
    }

    if (showCallouts) {
      final String label;
      switch (flangeConnectionType) {
        case FlangeConnectionType.toEquipment:
          label = 'Ру (к оборуд.)';
          break;
        case FlangeConnectionType.pipeToPipe:
          label = 'Ру (межтрубн.)';
          break;
        case FlangeConnectionType.blindFlange:
          label = 'Заглушка Ру';
          break;
        case FlangeConnectionType.singleFlange:
          label = 'Фланец Ру';
          break;
      }

      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: color,
            fontSize: 9.0,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            backgroundColor: Colors.white.withValues(alpha: 0.85),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(-tp.width / 2, -halfH - 13));
    }

    canvas.restore();
  }

  static void _drawDirectBranchSymbol(
    Canvas canvas, {
    required Offset center,
    required int dn,
    int? dnSecondary,
    required bool showCallouts,
  }) {
    final weldPaint = Paint()
      ..color = const Color(0xFF455A64)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, 7.0, weldPaint);

    if (showCallouts) {
      final tp = TextPainter(
        text: const TextSpan(
          text: 'У18',
          style: TextStyle(
            color: Color(0xFF37474F),
            fontSize: 9.0,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            backgroundColor: Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, center + const Offset(9, -12));
    }
  }

  static void _drawCapSymbol(
    Canvas canvas, {
    required AxonometryProjector projector,
    required PipingNetwork network,
    required bool isVolumeMode,
    required Offset center,
    required double angle,
    required int dn,
    required Color color,
  }) {
    final w = _calcWidth(dn, network, projector, isVolumeMode);
    
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    
    if (isVolumeMode) {
      final rect = Rect.fromCenter(center: Offset.zero, width: w * 0.8, height: w);
      final paint = Paint()
        ..style = PaintingStyle.fill
        ..shader = ui.Gradient.linear(
          Offset(0, -w / 2),
          Offset(0, w / 2),
          [
            color.withValues(alpha: 0.6),
            color.withValues(alpha: 0.9),
            color.withValues(alpha: 0.5),
          ],
          [0.0, 0.5, 1.0],
        );
      
      canvas.drawArc(rect, -math.pi / 2, math.pi, true, paint);
      
      final border = Paint()
        ..style = PaintingStyle.stroke
        ..color = color.withValues(alpha: 0.8)
        ..strokeWidth = 1.0;
      canvas.drawArc(rect, -math.pi / 2, math.pi, true, border);
    } else {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round;
        
      canvas.drawLine(Offset.zero, Offset(w * 0.5, 0), paint);
      
      final capEnd = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(w * 0.5, 0), w * 0.6, capEnd);
    }
    
    canvas.restore();
  }
}
