import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../core/math/axonometry_projector.dart';
import '../../../core/math/vector_3d.dart';
import '../../../domain/enums/fitting_type.dart';
import '../../../domain/models/callout.dart';
import '../../../domain/models/fitting.dart';
import '../../../domain/models/piping_network.dart';
import '../../../domain/models/drawing_style_config.dart';
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
    DrawingStyleConfig? styleConfig,
    double? sheetZoom,
  }) {
    for (final fit in network.fittings.values) {
      if (fit.fittingType == FittingType.elbow90 || fit.fittingType == FittingType.elbow45) {
        _drawElbowSymbol(
          canvas,
          projector,
          network,
          fit,
          selectedNodeId,
          showCallouts,
          isVolumeMode,
          styleConfig: styleConfig,
          sheetZoom: sheetZoom,
        );
      } else if (fit.fittingType == FittingType.tee) {
        _drawTeeSymbol(
          canvas,
          projector,
          network,
          fit,
          selectedNodeId,
          showCallouts,
          isVolumeMode,
          styleConfig: styleConfig,
          sheetZoom: sheetZoom,
        );
      } else if (fit.fittingType == FittingType.reducerConcentric ||
          fit.fittingType == FittingType.reducerEccentric) {
        final node = network.nodes[fit.nodeId];
        if (node == null) continue;
        final connected = network.getConnectedSegments(fit.nodeId);
        if (connected.length != 2) continue;

        final center = projector.project(node);
        final s1 = connected[0];
        final s2 = connected[1];
        final other1 = network.nodes[s1.startNodeId == fit.nodeId ? s1.endNodeId : s1.startNodeId];
        final other2 = network.nodes[s2.startNodeId == fit.nodeId ? s2.endNodeId : s2.startNodeId];
        if (other1 == null || other2 == null) continue;

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
          final fittingStroke = (styleConfig != null && sheetZoom != null)
              ? math.max(0.5, styleConfig.fittingLineWidthMm * sheetZoom)
              : (isSelected ? 2.5 : 1.8);
          final strokePaint = Paint()
            ..color = isSelected ? Colors.amber : color
            ..style = PaintingStyle.stroke
            ..strokeWidth = fittingStroke
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

        if (showCallouts && !_hasCallout(network, fit)) {
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
        final other1 = network.nodes[s1.startNodeId == fit.nodeId ? s1.endNodeId : s1.startNodeId];
        if (other1 == null) continue;

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
          final fittingStroke = (styleConfig != null && sheetZoom != null)
              ? math.max(0.5, styleConfig.fittingLineWidthMm * sheetZoom)
              : (isSelected ? 2.5 : 1.8);
          final strokePaint = Paint()
            ..color = isSelected ? Colors.amber : color
            ..style = PaintingStyle.stroke
            ..strokeWidth = fittingStroke
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

        if (showCallouts && !_hasCallout(network, fit)) {
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
          styleConfig: styleConfig,
          sheetZoom: sheetZoom,
        );
      } else if (fit.fittingType == FittingType.cap) {
        final node = network.nodes[fit.nodeId];
        if (node == null) continue;
        final connected = network.getConnectedSegments(fit.nodeId);
        if (connected.isEmpty) continue;

        final center = projector.project(node);
        final s1 = connected[0];
        final other1 = network.nodes[s1.startNodeId == fit.nodeId ? s1.endNodeId : s1.startNodeId];
        if (other1 == null) continue;

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
          final capStroke = (styleConfig != null && sheetZoom != null)
              ? math.max(0.5, styleConfig.fittingLineWidthMm * sheetZoom)
              : (isSelected ? 2.5 : 1.8);
          final strokePaint = Paint()
            ..color = isSelected ? Colors.amber : color
            ..style = PaintingStyle.stroke
            ..strokeWidth = capStroke
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

        if (showCallouts && !_hasCallout(network, fit)) {
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

  static bool _hasCallout(PipingNetwork network, Fitting fit) {
    if (network.callouts.isNotEmpty) return true;
    return network.callouts.values.any((c) =>
        c.targetType == CalloutTargetType.fitting &&
        (c.targetId == fit.id || c.targetId == fit.nodeId));
  }

  static double _calcWidth(
    int dn,
    PipingNetwork network,
    AxonometryProjector projector,
    bool isVolumeMode, {
    DrawingStyleConfig? styleConfig,
    double? sheetZoom,
  }) {
    double w = PipePainter.calcStrokeWidth(dn, styleConfig: styleConfig, sheetZoom: sheetZoom);
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
    bool isVolumeMode, {
    DrawingStyleConfig? styleConfig,
    double? sheetZoom,
  }) {
    final node = network.nodes[fit.nodeId];
    if (node == null) return;
    final connected = network.getConnectedSegments(fit.nodeId);
    if (connected.length != 2) return;

    final sys = network.systems[connected[0].systemId];
    final color = sys != null ? Color(sys.colorValue) : Colors.black87;

    final s1 = connected[0];
    final s2 = connected[1];

    final other1 = network.nodes[s1.startNodeId == fit.nodeId ? s1.endNodeId : s1.startNodeId];
    final other2 = network.nodes[s2.startNodeId == fit.nodeId ? s2.endNodeId : s2.startNodeId];
    if (other1 == null || other2 == null) return;

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

    final strokeWidth = _calcWidth(
      fit.dn,
      network,
      projector,
      isVolumeMode,
      styleConfig: styleConfig,
      sheetZoom: sheetZoom,
    );

    if (isVolumeMode) {
      if (showCallouts && !_hasCallout(network, fit)) {
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

    if (showCallouts && !_hasCallout(network, fit)) {
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

  static void _drawTeeSymbol(
    Canvas canvas,
    AxonometryProjector projector,
    PipingNetwork network,
    Fitting fit,
    String? selectedNodeId,
    bool showCallouts,
    bool isVolumeMode, {
    DrawingStyleConfig? styleConfig,
    double? sheetZoom,
  }) {
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
      if (showCallouts && !_hasCallout(network, fit)) {
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
      final armStrokeWidth = _calcWidth(
        seg.dn,
        network,
        projector,
        isVolumeMode,
        styleConfig: styleConfig,
        sheetZoom: sheetZoom,
      );

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

    }

    // 4. Узловой маркер центра тройника
    final mainStrokeWidth = _calcWidth(
      fit.dn,
      network,
      projector,
      isVolumeMode,
      styleConfig: styleConfig,
      sheetZoom: sheetZoom,
    );
    final centerPaint = Paint()
      ..color = isSelected ? Colors.amber : mainColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(ptN, math.max(1.5, mainStrokeWidth * 0.35), centerPaint);

    // 5. Выноска с наименованием/диаметрами тройника
    if (showCallouts && !_hasCallout(network, fit)) {
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
    DrawingStyleConfig? styleConfig,
    double? sheetZoom,
  }) {
    final isSelected = fit.nodeId == selectedNodeId;
    final strokeColor = isSelected ? Colors.amber : const Color(0xFF37474F);

    // 1. Осевая штрихпунктирная линия сопряжения (ГОСТ 2.303 тип Г):
    // от центра узла магистрали (center) до образующей контакта патрубка с магистралью
    final node = network.nodes[fit.nodeId];
    if (node != null) {
      final connected = network.getConnectedSegments(fit.nodeId);
      if (connected.length == 3) {
        final branchSeg = network.identifyBranchSegment(fit.nodeId, connected);
        final mainSegs = connected.where((s) => s.id != branchSeg?.id).toList();
        if (branchSeg != null && mainSegs.isNotEmpty) {
          final otherNodeId = branchSeg.startNodeId == fit.nodeId
              ? branchSeg.endNodeId
              : branchSeg.startNodeId;
          final otherNode = network.nodes[otherNodeId];
          if (otherNode != null) {
            final vBranch = Vector3D.fromNode(otherNode) - Vector3D.fromNode(node);
            if (vBranch.length > 1e-4) {
              final dir3d = vBranch.normalized();
              final dimMain = network.pipeCatalog.getDimension(mainSegs[0].dn);
              final rMain = (dimMain?.outerDiameterMm ?? mainSegs[0].dn.toDouble()) * 0.5;
              final pJoint3d = Vector3D.fromNode(node) + dir3d * rMain;

              final pNodeScreen = center;
              final pJointScreen = projector.projectCoordinates(pJoint3d.x, pJoint3d.y, pJoint3d.z);

              final screenDist = (pJointScreen - pNodeScreen).distance;
              if (screenDist > 0.5) {
                final sys = network.systems[branchSeg.systemId] ?? network.systems[mainSegs[0].systemId];
                final lineColor = sys != null ? Color(sys.colorValue) : strokeColor;

                if (isSelected) {
                  final glowPaint = Paint()
                    ..color = Colors.amber.withValues(alpha: 0.35)
                    ..strokeWidth = 5.0
                    ..strokeCap = StrokeCap.round
                    ..style = PaintingStyle.stroke;
                  canvas.drawLine(pNodeScreen, pJointScreen, glowPaint);
                }

                final dashDotPaint = Paint()
                  ..color = isSelected ? Colors.amber : lineColor
                  ..strokeWidth = isSelected ? 2.0 : 1.3
                  ..style = PaintingStyle.stroke
                  ..strokeCap = StrokeCap.round;

                final effDash = screenDist < 20.0 ? math.max(3.0, screenDist * 0.35) : 6.0;
                final effGap = screenDist < 20.0 ? math.max(1.5, screenDist * 0.15) : 2.5;
                final effDot = screenDist < 20.0 ? math.max(1.0, screenDist * 0.1) : 1.5;

                PipePainter.drawDashDotLine(
                  canvas,
                  pNodeScreen,
                  pJointScreen,
                  dashDotPaint,
                  dashLen: effDash,
                  gapLen: effGap,
                  dotLen: effDot,
                );
              }
            }
          }
        }
      }
    }

    // 2. Узловой маркер центра врезки
    final mainStrokeWidth = _calcWidth(
      fit.dn,
      network,
      projector,
      isVolumeMode,
      styleConfig: styleConfig,
      sheetZoom: sheetZoom,
    );
    final centerPaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, math.max(1.5, mainStrokeWidth * 0.35), centerPaint);

    // 3. Выноска с наименованием врезки (только если нет сгенерированных Callout)
    if (showCallouts && !_hasCallout(network, fit)) {
      final name = fit.name ??
          (fit.dnSecondary != null && fit.dnSecondary != fit.dn
              ? 'Врезка ${fit.dn}х${fit.dnSecondary}'
              : 'Врезка Ду${fit.dn}');
      final tp = TextPainter(
        text: TextSpan(
          text: name,
          style: TextStyle(
            color: isSelected ? Colors.amber.shade900 : const Color(0xFF263238),
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

