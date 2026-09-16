import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../../../core/math/axonometry_projector.dart';
import '../../../domain/enums/fitting_type.dart';
import '../../../domain/models/fitting.dart';
import '../../../domain/models/piping_network.dart';
import '../../../domain/services/element_3d_geometry.dart';
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
        final s2 = connected[1];
        final other1 = network.nodes[s1.startNodeId == fit.nodeId ? s1.endNodeId : s1.startNodeId]!;
        final other2 = network.nodes[s2.startNodeId == fit.nodeId ? s2.endNodeId : s2.startNodeId]!;

        final sys = network.systems[s1.systemId];
        final color = sys != null ? Color(sys.colorValue) : Colors.black87;

        if (!isVolumeMode) {
          final wireSegments = Element3dGeometry.generateReducerWireframe(
            fit,
            node,
            other1,
            other2,
            d1: s1.outerDiameterMm,
            d2: s2.outerDiameterMm,
          );

          final isSelected = fit.nodeId == selectedNodeId;
          final strokePaint = Paint()
            ..color = isSelected ? Colors.amber : color
            ..style = PaintingStyle.stroke
            ..strokeWidth = isSelected ? 2.5 : 1.8
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

        if (showCallouts) {
          final tp = TextPainter(
            text: TextSpan(
              text: fit.fittingType == FittingType.reducerEccentric
                  ? 'Переход Э ${s1.dn}х${s2.dn}'
                  : 'Переход К ${s1.dn}х${s2.dn}',
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
          tp.paint(canvas, center + const Offset(12, -14));
        }
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
          isVolumeMode: isVolumeMode,
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

        if (!isVolumeMode) {
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
      return;
    }

    final path = Path()
      ..moveTo(pOut1.dx, pOut1.dy)
      ..quadraticBezierTo(ptN.dx, ptN.dy, pOut2.dx, pOut2.dy);

    final isSelected = fit.nodeId == selectedNodeId;
    if (isSelected) {
      final glowPaint = Paint()
        ..color = Colors.amber.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + 6.0
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(path, glowPaint);
    }

    final elbowPaint = Paint()
      ..color = isSelected ? Colors.amber : color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, elbowPaint);

    final drawTick1 = !network.isButtJoint(s1.id) || fit.nodeId.compareTo(other1.id) <= 0;
    final drawTick2 = !network.isButtJoint(s2.id) || fit.nodeId.compareTo(other2.id) <= 0;
    if (drawTick1) _drawWeldTickAt(canvas, pOut1, ptN, strokeWidth);
    if (drawTick2) _drawWeldTickAt(canvas, pOut2, ptN, strokeWidth);

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

    final ptN = projector.project(node);
    final isSelected = fit.nodeId == selectedNodeId;
    
    // Determine main run color for the center dot and callout
    final segRun1 = connected[0];
    final mainSys = network.systems[segRun1.systemId];
    final mainColor = mainSys != null ? Color(mainSys.colorValue) : Colors.black87;

    if (isVolumeMode) {
      if (showCallouts) {
        final name = fit.name ??
            (fit.dnSecondary != null && fit.dnSecondary != fit.dn
                ? 'Тройник ${fit.dn}х${fit.dnSecondary}'
                : 'Тройник Ду${fit.dn}');
        final tp = TextPainter(
          text: TextSpan(
            text: name,
            style: TextStyle(
              color: mainColor,
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
      return;
    }

    final branchSeg = network.identifyBranchSegment(fit.nodeId, connected);

    for (int i = 0; i < 3; i++) {
      final seg = connected[i];
      final otherId = seg.startNodeId == fit.nodeId ? seg.endNodeId : seg.startNodeId;
      final otherNode = network.nodes[otherId];
      if (otherNode == null) continue;

      final isBranch = seg.id == branchSeg?.id;
      final armLenMm = isBranch
          ? fit.effectiveBranchLengthMm
          : (fit.buildingLengthMm != null && fit.buildingLengthMm! > 0
              ? fit.buildingLengthMm! / 2.0
              : fit.dn * 1.0);

      final vx = otherNode.x - node.x;
      final vy = otherNode.y - node.y;
      final vz = otherNode.z - node.z;
      final dist3d = math.sqrt(vx * vx + vy * vy + vz * vz);
      final uX = dist3d > 0 ? vx / dist3d : 0.0;
      final uY = dist3d > 0 ? vy / dist3d : 0.0;
      final uZ = dist3d > 0 ? vz / dist3d : 0.0;

      final effectiveArm = math.min(armLenMm, dist3d * 0.45);
      final pArmScreen = projector.projectCoordinates(
        node.x + uX * effectiveArm,
        node.y + uY * effectiveArm,
        node.z + uZ * effectiveArm,
      );

      final sys = network.systems[seg.systemId];
      final armColor = sys != null ? Color(sys.colorValue) : Colors.black87;
      final armStrokeWidth = _calcWidth(seg.dn, network, projector, isVolumeMode);

      // 1. Подсветка золотистым ореолом при выделении
      if (isSelected) {
        final glowPaint = Paint()
          ..color = Colors.amber.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = armStrokeWidth + 6.0
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(ptN, pArmScreen, glowPaint);
      }

      // 2. Отрисовка патрубка тройника
      final teePaint = Paint()
        ..color = isSelected ? Colors.amber : armColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = armStrokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(ptN, pArmScreen, teePaint);

      // 3. Монтажная засечка сварного стыка
      _drawWeldTickAt(canvas, pArmScreen, ptN, armStrokeWidth);
    }

    // 4. Узловой маркер центра тройника
    final mainStrokeWidth = _calcWidth(fit.dn, network, projector, isVolumeMode);
    final centerPaint = Paint()
      ..color = isSelected ? Colors.amber : mainColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(ptN, math.max(3.0, mainStrokeWidth * 0.35), centerPaint);

    // 5. Выноска с наименованием/диаметрами тройника
    if (showCallouts) {
      final name = fit.name ??
          (fit.dnSecondary != null && fit.dnSecondary != fit.dn
              ? 'Тройник ${fit.dn}х${fit.dnSecondary}'
              : 'Тройник Ду${fit.dn}');
      final tp = TextPainter(
        text: TextSpan(
          text: name,
          style: TextStyle(
            color: isSelected ? Colors.amber.shade900 : mainColor,
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

    if (!isVolumeMode) {
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
    bool isVolumeMode = false,
  }) {
    if (!isVolumeMode) {
      final weldPaint = Paint()
        ..color = const Color(0xFF455A64)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(center, 7.0, weldPaint);
    }

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
    final capRadius = math.max(w * 0.5, 4.0);
    final capDepth = math.max(w * 0.45, 5.0);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final capRect = Rect.fromCenter(center: Offset(capDepth * 0.3, 0), width: capDepth * 1.4, height: capRadius * 2);

    if (isVolumeMode) {
      final paint = Paint()
        ..style = PaintingStyle.fill
        ..shader = ui.Gradient.linear(
          Offset(0, -capRadius),
          Offset(0, capRadius),
          [
            color.withValues(alpha: 0.6),
            Colors.white.withValues(alpha: 0.8),
            color,
            color.withValues(alpha: 0.5),
          ],
          [0.0, 0.35, 0.7, 1.0],
        );

      canvas.drawArc(capRect, -math.pi / 2, math.pi, true, paint);

      final border = Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.black87
        ..strokeWidth = 1.0;
      canvas.drawArc(capRect, -math.pi / 2, math.pi, true, border);
    } else {
      // 2D СПДС / ГОСТ эллиптическое днище
      // Фоновая подложка
      canvas.drawArc(
        capRect,
        -math.pi / 2,
        math.pi,
        true,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill,
      );

      final strokePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.square;

      // Выпуклая дуга днища
      canvas.drawArc(capRect, -math.pi / 2, math.pi, false, strokePaint);

      // Приварной стык (основание днища)
      canvas.drawLine(Offset(capDepth * 0.3, -capRadius - 1.5), Offset(capDepth * 0.3, capRadius + 1.5), strokePaint);

      // Осевая риска
      canvas.drawLine(
        Offset(capDepth * 0.3 - 2.0, 0),
        Offset(capDepth * 0.3 + capDepth * 0.7 + 3.0, 0),
        Paint()
          ..color = color.withValues(alpha: 0.5)
          ..strokeWidth = 0.8,
      );
    }

    canvas.restore();
  }
}
