import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../core/math/axonometry_projector.dart';
import '../../../domain/enums/fitting_type.dart';
import '../../../domain/enums/weld_joint_style.dart';
import '../../../domain/models/fitting.dart';
import '../../../domain/models/pipe_segment.dart';
import '../../../domain/models/piping_network.dart';
import '../../../domain/models/weld_joint.dart';
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

        final sys = network.systems[s1.systemId];
        final color = sys != null ? Color(sys.colorValue) : Colors.black87;

        if (!isVolumeMode) {
          final wireSegments = Element3dGeometry.generateFlangeWireframe(
            fit,
            node,
            other1,
            pipeOuterDiameter: s1.outerDiameterMm,
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
          final String label;
          switch (fit.flangeConnectionType) {
            case FlangeConnectionType.toEquipment:
              label = 'Фланец к оборуд. Ду${fit.dn} Ру${fit.pressurePn}';
              break;
            case FlangeConnectionType.pipeToPipe:
              label = 'Фланцевая пара Ду${fit.dn} Ру${fit.pressurePn}';
              break;
            case FlangeConnectionType.blindFlange:
              label = 'Заглушка фланцевая Ду${fit.dn} Ру${fit.pressurePn}';
              break;
            case FlangeConnectionType.singleFlange:
              label = 'Фланец Ду${fit.dn} Ру${fit.pressurePn}';
              break;
          }

          final isSelected = fit.nodeId == selectedNodeId;
          final tp = TextPainter(
            text: TextSpan(
              text: fit.name ?? label,
              style: TextStyle(
                color: isSelected ? Colors.amber.shade900 : color,
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
      } else if (fit.fittingType == FittingType.directBranch) {
        final node = network.nodes[fit.nodeId];
        if (node == null) continue;
        final center = projector.project(node);
        _drawDirectBranchSymbol(
          canvas,
          network: network,
          projector: projector,
          fit: fit,
          center: center,
          dn: fit.dn,
          dnSecondary: fit.dnSecondary,
          selectedNodeId: selectedNodeId,
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

        final sys = network.systems[s1.systemId];
        final color = sys != null ? Color(sys.colorValue) : Colors.black87;

        if (!isVolumeMode) {
          final wireSegments = Element3dGeometry.generateCapWireframe(
            fit,
            node,
            other1,
            pipeOuterDiameter: s1.outerDiameterMm,
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
          final isSelected = fit.nodeId == selectedNodeId;
          final tp = TextPainter(
            text: TextSpan(
              text: fit.name ?? 'Заглушка Ду${fit.dn}',
              style: TextStyle(
                color: isSelected ? Colors.amber.shade900 : color,
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



  static void _drawDirectBranchSymbol(
    Canvas canvas, {
    required PipingNetwork network,
    required AxonometryProjector projector,
    required Fitting fit,
    required Offset center,
    required int dn,
    int? dnSecondary,
    String? selectedNodeId,
    required bool showCallouts,
    bool isVolumeMode = false,
  }) {
    final connected = network.getConnectedSegments(fit.nodeId);
    final branchDn = dnSecondary ?? dn;

    Offset pJoint = center;
    Offset vMain = const Offset(1, 0);
    double angleMain = 0.0;
    bool hasBranch = false;
    PipeSegment? branchSeg;

    if (connected.length == 3) {
      branchSeg = network.identifyBranchSegment(fit.nodeId, connected);
      final mainSegs = connected.where((s) => s.id != branchSeg?.id).toList();

      if (branchSeg != null && mainSegs.length == 2) {
        hasBranch = true;
        final otherBranch = network.nodes[branchSeg.startNodeId == fit.nodeId ? branchSeg.endNodeId : branchSeg.startNodeId]!;
        final otherMain1 = network.nodes[mainSegs[0].startNodeId == fit.nodeId ? mainSegs[0].endNodeId : mainSegs[0].startNodeId]!;
        final otherMain2 = network.nodes[mainSegs[1].startNodeId == fit.nodeId ? mainSegs[1].endNodeId : mainSegs[1].startNodeId]!;

        final pBranch = projector.project(otherBranch);
        final pMain1 = projector.project(otherMain1);
        final pMain2 = projector.project(otherMain2);

        var vm = pMain2 - pMain1;
        if (vm.distance > 0.001) vMain = vm / vm.distance;
        angleMain = math.atan2(vMain.dy, vMain.dx);

        var vBranch = pBranch - center;
        if (vBranch.distance > 0.001) vBranch = vBranch / vBranch.distance;

        final wMain = _calcWidth(dn, network, projector, isVolumeMode);
        final rMainScreen = wMain * 0.5;
        pJoint = center + vBranch * rMainScreen;
      }
    }

    final wBranch = _calcWidth(branchDn, network, projector, isVolumeMode);
    final isSelected = fit.nodeId == selectedNodeId;
    final strokeColor = isSelected ? Colors.amber : const Color(0xFF37474F);

    // Находим сварной шов ответвления, если он существует
    WeldJoint? branchWeld;
    if (branchSeg != null) {
      for (final w in network.weldJoints.values) {
        if (w.segmentId == branchSeg.id) {
          final r = branchSeg.startNodeId == fit.nodeId ? 0.0 : 1.0;
          if ((w.ratio - r).abs() < 0.05) {
            branchWeld = w;
            break;
          }
        }
      }
    }

    final effectiveStyle = branchWeld?.getEffectiveStyle(network.defaultWeldStyle) ?? network.defaultWeldStyle;

    if (hasBranch) {
      switch (effectiveStyle) {
        case WeldJointStyle.tick:
          // Засечка, ориентированная вдоль образующей магистрали
          final halfLen = math.max(wBranch * 0.7, 5.0);
          if (isSelected) {
            final glowPaint = Paint()
              ..color = Colors.amber.withValues(alpha: 0.35)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 6.0
              ..strokeCap = StrokeCap.round;
            canvas.drawLine(pJoint - vMain * halfLen, pJoint + vMain * halfLen, glowPaint);
          }
          final tickPaint = Paint()
            ..color = strokeColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = isSelected ? 2.5 : 1.8
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(pJoint - vMain * halfLen, pJoint + vMain * halfLen, tickPaint);
          break;

        case WeldJointStyle.ring3d:
          canvas.save();
          canvas.translate(pJoint.dx, pJoint.dy);
          canvas.rotate(angleMain);
          final collarW = math.max(wBranch * 1.3, 8.0);
          final collarH = math.max(wBranch * 0.7, 4.5);
          final collarRect = Rect.fromCenter(center: Offset.zero, width: collarW, height: collarH);
          if (isSelected) {
            final glowPaint = Paint()
              ..color = Colors.amber.withValues(alpha: 0.35)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 5.0;
            canvas.drawOval(collarRect, glowPaint);
          }
          final ringPaint = Paint()
            ..color = strokeColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = isSelected ? 2.0 : 1.5;
          canvas.drawOval(collarRect, ringPaint);
          canvas.restore();
          break;

        case WeldJointStyle.circle:
          const r = 4.5;
          if (isSelected) {
            final glowPaint = Paint()
              ..color = Colors.amber.withValues(alpha: 0.35)
              ..style = PaintingStyle.fill;
            canvas.drawCircle(pJoint, r + 4.0, glowPaint);
          }
          final bgPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
          canvas.drawCircle(pJoint, r, bgPaint);
          final strokePaint = Paint()
            ..color = strokeColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = isSelected ? 2.2 : 1.5;
          canvas.drawCircle(pJoint, r, strokePaint);
          break;

        case WeldJointStyle.dot:
          const r = 3.5;
          if (isSelected) {
            final glowPaint = Paint()
              ..color = Colors.amber.withValues(alpha: 0.35)
              ..style = PaintingStyle.fill;
            canvas.drawCircle(pJoint, r + 4.0, glowPaint);
          }
          final dotPaint = Paint()..color = strokeColor..style = PaintingStyle.fill;
          canvas.drawCircle(pJoint, r, dotPaint);
          final borderPaint = Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0;
          canvas.drawCircle(pJoint, r, borderPaint);
          break;
      }
    } else {
      final centerPaint = Paint()
        ..color = strokeColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, 4.0, centerPaint);
    }

    if (showCallouts && branchWeld == null) {
      // Полочка-выноска ГОСТ с обозначением шва У18 (если нет отдельной выноски шва)
      final leaderOffset = const Offset(14.0, -14.0);
      final pShelfStart = pJoint + leaderOffset;
      const shelfLen = 30.0;
      final pShelfEnd = pShelfStart + const Offset(shelfLen, 0);

      final leaderPaint = Paint()
        ..color = const Color(0xFF546E7A)
        ..strokeWidth = 1.0;
      canvas.drawLine(pJoint, pShelfStart, leaderPaint);
      canvas.drawLine(pShelfStart, pShelfEnd, leaderPaint);

      final tp = TextPainter(
        text: const TextSpan(
          text: 'У18',
          style: TextStyle(
            color: Color(0xFF263238),
            fontSize: 9.0,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pShelfStart + const Offset(4.0, -12.0));
    }
  }

}

