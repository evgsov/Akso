import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../core/math/axonometry_projector.dart';
import '../../../core/math/vector_3d.dart';
import '../../../domain/enums/fitting_type.dart';
import '../../../domain/enums/weld_joint_style.dart';
import '../../../domain/models/callout.dart';
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

        // Определение направления магистрали для врезки (если стык относится к врезке)
        Vector3D? directBranchMainDir3d;
        final nearNodeId = weld.ratio < 0.5 ? seg.startNodeId : seg.endNodeId;
        final fit = network.fittings[nearNodeId];
        if (fit?.fittingType == FittingType.directBranch) {
          final conn = network.getConnectedSegments(nearNodeId);
          final bSeg = network.identifyBranchSegment(nearNodeId, conn);
          if (bSeg?.id == seg.id) {
            final mainSegs = conn.where((s) => s.id != bSeg?.id).toList();
            if (mainSegs.isNotEmpty) {
              final m0 = mainSegs[0];
              final nStart = network.nodes[m0.startNodeId];
              final nEnd = network.nodes[m0.endNodeId];
              if (nStart != null && nEnd != null) {
                final vm = Vector3D.fromNode(nEnd) - Vector3D.fromNode(nStart);
                if (vm.length > 1e-4) {
                  directBranchMainDir3d = vm.normalized();
                }
              }
            }
          }
        }

        final center3d = Vector3D.fromNode(weld.calculatePosition(start, end));
        final weldPos = projector.projectCoordinates(center3d.x, center3d.y, center3d.z);

        final isSelected = weld.id == selectedWeldId;
        final style = weld.getEffectiveStyle(network.defaultWeldStyle);
        final strokeColor = isSelected ? Colors.amber : const Color(0xFF37474F);

        // Отрисовка символа стыка в выбранном стиле (засечка, 3D-кольцо, кружок, точка)
        switch (style) {
          case WeldJointStyle.tick:
            // Засечка, строго лежащая в плоскости X, Y (под 0° по оси Z)
            // и ориентированная перпендикулярно оси трубы (или вдоль магистрали для врезки)
            final effectiveTickSize = weld.getEffectiveTickSize(
              network.defaultWeldTickSizeMm,
              seg.outerDiameterMm,
            );
            final halfLenMm = effectiveTickSize * 0.5;

            final Vector3D p13d;
            final Vector3D p23d;

            if (directBranchMainDir3d != null) {
              p13d = center3d - directBranchMainDir3d * halfLenMm;
              p23d = center3d + directBranchMainDir3d * halfLenMm;
            } else {
              final vStart = Vector3D.fromNode(start);
              final vEnd = Vector3D.fromNode(end);
              final dx = vEnd.x - vStart.x;
              final dy = vEnd.y - vStart.y;
              final lenXy = math.sqrt(dx * dx + dy * dy);

              final Vector3D tickDir;
              if (lenXy > 1e-4) {
                // Перпендикуляр к трубе в горизонтальной плоскости X, Y (под 0° по Z)
                tickDir = Vector3D(-dy / lenXy, dx / lenXy, 0.0);
              } else {
                // Стояк вдоль Z: горизонтальная засечка в плоскости X, Y (под 0° по Z)
                tickDir = const Vector3D(0.0, 1.0, 0.0);
              }

              p13d = center3d - tickDir * halfLenMm;
              p23d = center3d + tickDir * halfLenMm;
            }

            var lp1 = projector.projectCoordinates(p13d.x, p13d.y, p13d.z);
            var lp2 = projector.projectCoordinates(p23d.x, p23d.y, p23d.z);

            // Минимальный защитный порог видимости при сильном отдалении
            final screenDist = (lp2 - lp1).distance;
            if (screenDist < 8.0 && screenDist > 1e-4) {
              final mid = (lp1 + lp2) * 0.5;
              final dir = (lp2 - lp1) / screenDist;
              lp1 = mid - dir * 4.0;
              lp2 = mid + dir * 4.0;
            }

            if (isSelected) {
              final glowPaint = Paint()
                ..color = Colors.amber.withValues(alpha: 0.35)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 6.0
                ..strokeCap = StrokeCap.round;
              canvas.drawLine(lp1, lp2, glowPaint);
            }

            final tickPaint = Paint()
              ..color = strokeColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = isSelected ? 2.5 : 1.8
              ..strokeCap = StrokeCap.round;
            canvas.drawLine(lp1, lp2, tickPaint);
            break;

          case WeldJointStyle.ring3d:
            // 3D-кольцо (пространственный тороидальный контур)
            final ringLines = Element3dGeometry.generateWeld3d(
              weld,
              start,
              end,
              pipeOuterDiameter: seg.outerDiameterMm,
              style: WeldJointStyle.ring3d,
              tickSizeMm: weld.getEffectiveTickSize(network.defaultWeldTickSizeMm, seg.outerDiameterMm),
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
        final hasCallout = network.callouts.values.any(
          (c) => c.targetType == CalloutTargetType.node && c.targetId == node.id,
        );
        if (!hasCallout) {
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
}
