import 'dart:math' as math;
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
    bool showCallouts,
  ) {
    for (final fit in network.fittings.values) {
      if (fit.fittingType == FittingType.elbow90 || fit.fittingType == FittingType.elbow45) {
        _drawElbowSymbol(canvas, projector, network, fit, selectedNodeId, showCallouts);
      } else if (fit.fittingType == FittingType.tee) {
        _drawTeeSymbol(canvas, projector, network, fit, selectedNodeId, showCallouts);
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
        final color = sys != null ? Color(sys.colorValue) : const Color(0xFF1976D2);

        _drawFlangeSymbol(
          canvas,
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
      }
    }
  }

  static void _drawReducerSymbol(
    Canvas canvas, {
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

    const halfL = 12.0;
    final w1 = PipePainter.calcStrokeWidth(dn1) * 1.6;
    final w2 = PipePainter.calcStrokeWidth(dn2) * 1.6;

    final path = Path();
    if (!isEccentric) {
      path.moveTo(-halfL, -w1);
      path.lineTo(halfL, -w2);
      path.lineTo(halfL, w2);
      path.lineTo(-halfL, w1);
      path.close();
    } else {
      path.moveTo(-halfL, w1);
      path.lineTo(halfL, w1);
      path.lineTo(halfL, w1 - w2 * 2);
      path.lineTo(-halfL, -w1);
      path.close();
    }

    final fillPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, strokePaint);

    final tp = TextPainter(
      text: TextSpan(
        text: '$dn1×$dn2',
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
          backgroundColor: Colors.white.withValues(alpha: 0.8),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(-tp.width / 2, -w1 - 14));

    canvas.restore();
  }

  static void _drawElbowSymbol(Canvas canvas, AxonometryProjector projector, PipingNetwork network, Fitting fit, String? selectedNodeId, bool showCallouts) {
    final node = network.nodes[fit.nodeId];
    if (node == null) return;
    final conn = network.getConnectedSegments(fit.nodeId);
    if (conn.length != 2) return;

    final s1 = conn[0];
    final s2 = conn[1];
    final n1 = network.nodes[s1.startNodeId == fit.nodeId ? s1.endNodeId : s1.startNodeId];
    final n2 = network.nodes[s2.startNodeId == fit.nodeId ? s2.endNodeId : s2.startNodeId];
    if (n1 == null || n2 == null) return;

    final ptN = projector.project(node);
    final pOther1 = projector.project(n1);
    final pOther2 = projector.project(n2);

    final pt1 = PipePainter.calcPipeTrimmedPoint(
      network: network,
      nodeId: fit.nodeId,
      otherNodeId: n1.id,
      nodeScreen: ptN,
      otherScreen: pOther1,
      seg: s1,
    );
    final pt2 = PipePainter.calcPipeTrimmedPoint(
      network: network,
      nodeId: fit.nodeId,
      otherNodeId: n2.id,
      nodeScreen: ptN,
      otherScreen: pOther2,
      seg: s2,
    );

    final sys = network.systems[s1.systemId];
    final color = sys != null ? Color(sys.colorValue) : Colors.blueGrey;
    final strokeWidth = PipePainter.calcStrokeWidth(fit.dn);
    final isSelected = fit.nodeId == selectedNodeId;

    final arcPath = Path()
      ..moveTo(pt1.dx, pt1.dy)
      ..quadraticBezierTo(ptN.dx, ptN.dy, pt2.dx, pt2.dy);

    if (isSelected) {
      final glowPaint = Paint()
        ..color = Colors.amber.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + 8.0
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(arcPath, glowPaint);
    }

    final elbowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(arcPath, elbowPaint);

    if (projector.projectionType == ProjectionType.orbit3d && strokeWidth > 3.0) {
      final sheenPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 0.35
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(arcPath, sheenPaint);
    }

    _drawWeldTickAt(canvas, pt1, ptN, strokeWidth);
    _drawWeldTickAt(canvas, pt2, ptN, strokeWidth);

    if (showCallouts) {
      final midArc = Offset((pt1.dx + 2 * ptN.dx + pt2.dx) / 4, (pt1.dy + 2 * ptN.dy + pt2.dy) / 4);
      final radMm = fit.effectiveRadiusMm;
      final angleStr = fit.fittingType == FittingType.elbow45 ? '45°' : '90°';
      final label = '∠$angleStr R${radMm.round()}';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: color,
            fontSize: 9.0,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            backgroundColor: Colors.white.withValues(alpha: 0.88),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, midArc - Offset(tp.width / 2, tp.height + 3.0));
    }
  }

  static void _drawWeldTickAt(Canvas canvas, Offset pWeld, Offset pCorner, double strokeWidth) {
    final dx = pWeld.dx - pCorner.dx;
    final dy = pWeld.dy - pCorner.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len <= 0) return;

    final perpX = -dy / len;
    final perpY = dx / len;
    final tickHalfLen = math.max(4.5, strokeWidth * 0.85);

    final tickPaint = Paint()
      ..color = const Color(0xFF263238)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.square;

    canvas.drawLine(
      Offset(pWeld.dx - perpX * tickHalfLen, pWeld.dy - perpY * tickHalfLen),
      Offset(pWeld.dx + perpX * tickHalfLen, pWeld.dy + perpY * tickHalfLen),
      tickPaint,
    );
  }

  static void _drawTeeSymbol(Canvas canvas, AxonometryProjector projector, PipingNetwork network, Fitting fit, String? selectedNodeId, bool showCallouts) {
    final node = network.nodes[fit.nodeId];
    if (node == null) return;
    final conn = network.getConnectedSegments(fit.nodeId);
    if (conn.isEmpty) return;

    final ptN = projector.project(node);
    final strokeWidth = PipePainter.calcStrokeWidth(fit.dn);
    final isSelected = fit.nodeId == selectedNodeId;

    final sys = network.systems[conn.first.systemId];
    final color = sys != null ? Color(sys.colorValue) : Colors.blueGrey;

    if (isSelected) {
      canvas.drawCircle(
        ptN,
        strokeWidth + 10.0,
        Paint()
          ..color = Colors.amber.withValues(alpha: 0.45)
          ..style = PaintingStyle.fill,
      );
    }

    if (conn.length == 3) {
      final unitVectors = <List<double>>[];
      for (final s in conn) {
        final other = network.nodes[s.startNodeId == fit.nodeId ? s.endNodeId : s.startNodeId];
        if (other != null) {
          final vx = other.x - node.x;
          final vy = other.y - node.y;
          final vz = other.z - node.z;
          final len = math.sqrt(vx * vx + vy * vy + vz * vz);
          if (len > 0) {
            unitVectors.add([vx / len, vy / len, vz / len]);
          } else {
            unitVectors.add([0.0, 0.0, 0.0]);
          }
        } else {
          unitVectors.add([0.0, 0.0, 0.0]);
        }
      }

      double minDot = 1.0;
      int run1Idx = 0;
      int run2Idx = 1;
      for (int i = 0; i < 3; i++) {
        for (int j = i + 1; j < 3; j++) {
          final dot = unitVectors[i][0] * unitVectors[j][0] +
              unitVectors[i][1] * unitVectors[j][1] +
              unitVectors[i][2] * unitVectors[j][2];
          if (dot < minDot) {
            minDot = dot;
            run1Idx = i;
            run2Idx = j;
          }
        }
      }

      final branchIdx = 3 - run1Idx - run2Idx;
      final segRun1 = conn[run1Idx];
      final segRun2 = conn[run2Idx];
      final segBranch = conn[branchIdx];

      final other1 = network.nodes[segRun1.startNodeId == fit.nodeId ? segRun1.endNodeId : segRun1.startNodeId]!;
      final other2 = network.nodes[segRun2.startNodeId == fit.nodeId ? segRun2.endNodeId : segRun2.startNodeId]!;
      final otherBranch = network.nodes[segBranch.startNodeId == fit.nodeId ? segBranch.endNodeId : segBranch.startNodeId]!;

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

      final branchStroke = PipePainter.calcStrokeWidth(segBranch.dn);
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
          ? 'Тройник ${fit.dn}х${fit.dnSecondary}'
          : 'Тройник Ду${fit.dn}';
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

  static void _drawFlangeSymbol(
    Canvas canvas, {
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

    final halfH = math.max(8.0, PipePainter.calcStrokeWidth(dn) * 1.6);
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
          label = 'Ру$pressurePn (к оборуд.)';
          break;
        case FlangeConnectionType.pipeToPipe:
          label = 'Ру$pressurePn (межтрубн.)';
          break;
        case FlangeConnectionType.blindFlange:
          label = 'Заглушка Ру$pressurePn';
          break;
        case FlangeConnectionType.singleFlange:
          label = 'Фланец Ру$pressurePn';
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
}
