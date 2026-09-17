import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../core/math/axonometry_projector.dart';
import '../../../core/math/vector_3d.dart';
import '../../../domain/enums/fitting_type.dart';
import '../../../domain/enums/weld_joint_style.dart';
import '../../../domain/enums/weld_type.dart';
import '../../../domain/models/piping_network.dart';
import '../../../domain/services/element_3d_geometry.dart';
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

        var pipeVector = p2 - p1;
        final pipeLen = pipeVector.distance;
        final pipeDir = pipeLen > 0.001
            ? pipeVector / pipeLen
            : const Offset(1, 0);

        // Позиция стыка на экране: если это ответвление прямой врезки,
        // стык позиционируется на наружной образующей магистрали (P = node + u * R_маг)
        Offset? directBranchScreenPoint;
        if (weld.ratio < 0.05) {
          final fit = network.fittings[seg.startNodeId];
          if (fit?.fittingType == FittingType.directBranch) {
            final conn = network.getConnectedSegments(fit!.nodeId);
            final bSeg = network.identifyBranchSegment(fit.nodeId, conn);
            if (bSeg?.id == seg.id) {
              final mainSegs = conn.where((s) => s.id != bSeg?.id).toList();
              final mainDia = mainSegs.isNotEmpty ? mainSegs[0].outerDiameterMm : fit.dn.toDouble();
              final rMain = mainDia / 2.0;
              final start3d = Vector3D.fromNode(start);
              final end3d = Vector3D.fromNode(end);
              final u = (end3d - start3d).normalized();
              final contact3d = start3d + u * rMain;
              directBranchScreenPoint = projector.projectCoordinates(contact3d.x, contact3d.y, contact3d.z);
            }
          }
        } else if (weld.ratio > 0.95) {
          final fit = network.fittings[seg.endNodeId];
          if (fit?.fittingType == FittingType.directBranch) {
            final conn = network.getConnectedSegments(fit!.nodeId);
            final bSeg = network.identifyBranchSegment(fit.nodeId, conn);
            if (bSeg?.id == seg.id) {
              final mainSegs = conn.where((s) => s.id != bSeg?.id).toList();
              final mainDia = mainSegs.isNotEmpty ? mainSegs[0].outerDiameterMm : fit.dn.toDouble();
              final rMain = mainDia / 2.0;
              final start3d = Vector3D.fromNode(start);
              final end3d = Vector3D.fromNode(end);
              final u = (start3d - end3d).normalized();
              final contact3d = end3d + u * rMain;
              directBranchScreenPoint = projector.projectCoordinates(contact3d.x, contact3d.y, contact3d.z);
            }
          }
        }

        final weldPos = directBranchScreenPoint ?? Offset(
          p1.dx + (p2.dx - p1.dx) * weld.ratio,
          p1.dy + (p2.dy - p1.dy) * weld.ratio,
        );

        final isSelected = weld.id == selectedWeldId;
        final style = weld.getEffectiveStyle(network.defaultWeldStyle);
        final strokeColor = isSelected ? Colors.amber : const Color(0xFF37474F);

        // Отрисовка символа стыка в выбранном стиле (засечка, 3D-кольцо, кружок, точка)
        switch (style) {
          case WeldJointStyle.tick:
            // Перпендикулярная засечка по ГОСТу
            final normal = Offset(-pipeDir.dy, pipeDir.dx);
            final strokeWidth = math.max(seg.dn * 0.1, 2.0);
            final halfLen = math.max(strokeWidth * 3.5, 7.0);

            if (isSelected) {
              final glowPaint = Paint()
                ..color = Colors.amber.withValues(alpha: 0.35)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 6.0
                ..strokeCap = StrokeCap.round;
              canvas.drawLine(weldPos - normal * halfLen, weldPos + normal * halfLen, glowPaint);
            }

            final tickPaint = Paint()
              ..color = strokeColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = isSelected ? 2.5 : 1.8
              ..strokeCap = StrokeCap.round;
            canvas.drawLine(weldPos - normal * halfLen, weldPos + normal * halfLen, tickPaint);
            break;

          case WeldJointStyle.ring3d:
            // 3D-кольцо (пространственный тороидальный контур)
            final ringLines = Element3dGeometry.generateWeld3d(
              weld,
              start,
              end,
              pipeOuterDiameter: seg.outerDiameterMm,
              style: WeldJointStyle.ring3d,
            );

            if (isSelected) {
              final glowPaint = Paint()
                ..color = Colors.amber.withValues(alpha: 0.35)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 5.0
                ..strokeCap = StrokeCap.round;
              for (final line in ringLines) {
                final lp1 = projector.project(line.startNode);
                final lp2 = projector.project(line.endNode);
                canvas.drawLine(lp1, lp2, glowPaint);
              }
            }

            final ringPaint = Paint()
              ..color = strokeColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = isSelected ? 2.0 : 1.4
              ..strokeCap = StrokeCap.round;
            for (final line in ringLines) {
              final lp1 = projector.project(line.startNode);
              final lp2 = projector.project(line.endNode);
              canvas.drawLine(lp1, lp2, ringPaint);
            }
            break;

          case WeldJointStyle.circle:
            // Кружок (контурный маркер монтажного шва)
            const r = 4.5;
            if (isSelected) {
              final glowPaint = Paint()
                ..color = Colors.amber.withValues(alpha: 0.35)
                ..style = PaintingStyle.fill;
              canvas.drawCircle(weldPos, r + 4.0, glowPaint);
            }
            final bgPaint = Paint()
              ..color = Colors.white
              ..style = PaintingStyle.fill;
            canvas.drawCircle(weldPos, r, bgPaint);

            final circlePaint = Paint()
              ..color = strokeColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = isSelected ? 2.2 : 1.5;
            canvas.drawCircle(weldPos, r, circlePaint);
            break;

          case WeldJointStyle.dot:
            // Точка (компактный маркер)
            const r = 3.5;
            if (isSelected) {
              final glowPaint = Paint()
                ..color = Colors.amber.withValues(alpha: 0.35)
                ..style = PaintingStyle.fill;
              canvas.drawCircle(weldPos, r + 4.0, glowPaint);
            }
            final dotPaint = Paint()
              ..color = strokeColor
              ..style = PaintingStyle.fill;
            canvas.drawCircle(weldPos, r, dotPaint);

            final borderPaint = Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.0;
            canvas.drawCircle(weldPos, r, borderPaint);
            break;
        }

        SmartCallout.drawWeldCallout(
          canvas,
          weldPoint: weldPos,
          weldNumber: weld.number,
          stamp: weld.stamp,
          gostType: weld.weldType.shortName,
          color: const Color(0xFF37474F),
          drawMarker: false,
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
