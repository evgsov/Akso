import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/math/axonometry_projector.dart';
import '../../../domain/enums/fitting_type.dart';
import '../../../domain/enums/projection_type.dart';
import '../../../domain/models/fitting.dart';
import '../../../domain/models/pipe_segment.dart';
import '../../../domain/models/piping_network.dart';
import '../smart_callout.dart';
import 'solid_3d_engine.dart';

class PipePainter {
  static void paint(
    Canvas canvas,
    Size size,
    AxonometryProjector projector,
    PipingNetwork network,
    String? selectedSegmentId,
    String? hoveredSegmentId,
    Map<String, Offset> screenPoints,
    bool showCallouts, [
    bool isVolumeMode = false,
    Set<String>? selectedSegmentIds,
  ]) {
    if (isVolumeMode) {
      // Честная 3D твердотельная модель с полигональными цилиндрами, Z-сортировкой и направленным освещением
      Solid3dEngine.renderNetwork(
        canvas,
        projector,
        network,
        selectedSegmentId: selectedSegmentId,
        selectedSegmentIds: selectedSegmentIds,
      );

      // Отрисовка бейджей выбранных труб и аннотаций
      for (final seg in network.segments.values) {
        final start = network.nodes[seg.startNodeId];
        final end = network.nodes[seg.endNodeId];
        if (start == null || end == null) continue;

        final isSelected = seg.id == selectedSegmentId ||
            (selectedSegmentIds != null && selectedSegmentIds.contains(seg.id));
        final p1 = screenPoints[start.id] ?? projector.project(start);
        final p2 = screenPoints[end.id] ?? projector.project(end);

        if (isSelected) {
          final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
          final lenMm = start.distanceTo(end);
          drawSelectedDimensionBadge(canvas, mid, lenMm, seg);
        }

        if (seg.slope > 0.0001 && showCallouts) {
          SmartCallout.drawSlopeCallout(canvas, p1: p1, p2: p2, slope: seg.slope);
        }
        if (showCallouts) {
          final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
          final sys = network.systems[seg.systemId];
          final color = sys != null ? Color(sys.colorValue) : Colors.blueGrey;
          SmartCallout.drawDiameterCallout(canvas, midPoint: mid, text: seg.shortCallout, color: color);
        }
      }
      return;
    }

    // 2D СПДС / ГОСТ режим: сортировка сегментов по глубине (Painter's algorithm)
    final sortedSegments = network.segments.values.toList()
      ..sort((a, b) {
        final startA = network.nodes[a.startNodeId];
        final endA = network.nodes[a.endNodeId];
        final depthA = (startA != null && endA != null)
            ? projector.computeDepth((startA.x + endA.x) / 2, (startA.y + endA.y) / 2, (startA.z + endA.z) / 2)
            : 0.0;
        final startB = network.nodes[b.startNodeId];
        final endB = network.nodes[b.endNodeId];
        final depthB = (startB != null && endB != null)
            ? projector.computeDepth((startB.x + endB.x) / 2, (startB.y + endB.y) / 2, (startB.z + endB.z) / 2)
            : 0.0;
        return depthB.compareTo(depthA);
      });

    for (final seg in sortedSegments) {
      final start = network.nodes[seg.startNodeId];
      final end = network.nodes[seg.endNodeId];
      if (start == null || end == null) continue;

      final p1 = screenPoints[start.id] ?? projector.project(start);
      final p2 = screenPoints[end.id] ?? projector.project(end);

      final isSelected = seg.id == selectedSegmentId ||
          (selectedSegmentIds != null && selectedSegmentIds.contains(seg.id));
      final sys = network.systems[seg.systemId];
      final color = sys != null ? Color(sys.colorValue) : Colors.blueGrey;

      // Толщина линии зависит от условного прохода DN
      double strokeWidth = calcStrokeWidth(seg.dn);
      if (isVolumeMode) {
        final dim = network.pipeCatalog.getDimension(seg.dn);
        final outerMm = dim != null ? dim.outerDiameterMm : seg.dn.toDouble();
        strokeWidth = outerMm * projector.scale;
        // Ограничиваем минимальную толщину для читаемости
        if (strokeWidth < 2.0) strokeWidth = 2.0;
      }

      // Отступы на концах труб, если в узлах установлены отводы / тройники / фитинги
      final drawP1 = calcPipeTrimmedPoint(
        network: network,
        nodeId: seg.startNodeId,
        otherNodeId: seg.endNodeId,
        nodeScreen: p1,
        otherScreen: p2,
        seg: seg,
      );
      final drawP2 = calcPipeTrimmedPoint(
        network: network,
        nodeId: seg.endNodeId,
        otherNodeId: seg.startNodeId,
        nodeScreen: p2,
        otherScreen: p1,
        seg: seg,
      );

      // Свечение/выделение, если сегмент выбран
      if (isSelected) {
        final highlightPaint = Paint()
          ..color = Colors.amber.withValues(alpha: 0.45)
          ..strokeWidth = strokeWidth + 8.0
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(drawP1, drawP2, highlightPaint);

        // Индикатор длины и диаметра выбранной трубы
        final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
        final lenMm = start.distanceTo(end);
        drawSelectedDimensionBadge(canvas, mid, lenMm, seg);
      }

      // Линия трубы
      final pipePaint = Paint()
        ..color = color
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
        
      if (isVolumeMode && strokeWidth > 3.0) {
        final dx = drawP2.dx - drawP1.dx;
        final dy = drawP2.dy - drawP1.dy;
        final len = math.sqrt(dx * dx + dy * dy);
        if (len > 0.1) {
          final nx = -dy / len;
          final ny = dx / len;
          final hw = strokeWidth / 2.0;
          
          final lightColor = Color.lerp(color, Colors.white, 0.45)!;
          final darkColor = Color.lerp(color, Colors.black, 0.35)!;
          
          pipePaint.shader = LinearGradient(
            colors: [darkColor, lightColor, darkColor],
            stops: const [0.0, 0.4, 1.0],
          ).createShader(Rect.fromPoints(
            Offset(drawP1.dx + nx * hw, drawP1.dy + ny * hw),
            Offset(drawP1.dx - nx * hw, drawP1.dy - ny * hw),
          ));
        }
      }

      canvas.drawLine(drawP1, drawP2, pipePaint);

      // В 3D-орбите добавляем объемный блик по центру трубы (только в каркасном режиме)
      if (!isVolumeMode && projector.projectionType == ProjectionType.orbit3d && strokeWidth > 3.0) {
        final sheenPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.35)
          ..strokeWidth = strokeWidth * 0.35
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(drawP1, drawP2, sheenPaint);
      }

      // Уклон трубы
      if (seg.slope > 0.0001 && showCallouts) {
        SmartCallout.drawSlopeCallout(
          canvas,
          p1: p1,
          p2: p2,
          slope: seg.slope,
        );
      }

      // Выноска диаметра трубы
      if (showCallouts) {
        final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
        SmartCallout.drawDiameterCallout(
          canvas,
          midPoint: mid,
          text: seg.shortCallout,
          color: color,
        );
      }
    }
  }

  static double calcStrokeWidth(int dn) {
    if (dn <= 20) return 2.8;
    if (dn <= 32) return 3.6;
    if (dn <= 50) return 4.6;
    if (dn <= 80) return 5.8;
    if (dn <= 100) return 7.0;
    return 8.5;
  }

  static Offset calcPipeTrimmedPoint({
    required PipingNetwork network,
    required String nodeId,
    required String otherNodeId,
    required Offset nodeScreen,
    required Offset otherScreen,
    required PipeSegment seg,
  }) {
    final fit = network.fittings[nodeId];
    if (fit == null) return nodeScreen;

    final dx = otherScreen.dx - nodeScreen.dx;
    final dy = otherScreen.dy - nodeScreen.dy;
    final screenDist = math.sqrt(dx * dx + dy * dy);
    if (screenDist <= 1.0) return nodeScreen;

    final dirX = dx / screenDist;
    final dirY = dy / screenDist;

    final node3d = network.nodes[nodeId];
    final other3d = network.nodes[otherNodeId];
    final dist3d = (node3d != null && other3d != null) ? node3d.distanceTo(other3d) : 0.0;

    double trimPx = 0.0;

    if (fit.fittingType == FittingType.elbow90 || fit.fittingType == FittingType.elbow45) {
      final t3d = calcElbowTangentLength(network, nodeId, fit);
      final frac3d = dist3d > 0 ? (t3d / dist3d) : 0.0;
      final physicalPx = screenDist * frac3d;
      // Обеспечиваем гарантированную читаемость отвода на экране (минимум 15px),
      // но не более 42% длины сегмента, чтобы не пересекать середину трубы
      const minScreenElbow = 15.0;
      const maxFrac = 0.42;
      trimPx = math.min(screenDist * maxFrac, math.max(physicalPx, minScreenElbow));
    } else if (fit.fittingType == FittingType.tee) {
      if (fit.cutsMainPipe) {
        // Тройник врезан в разрыв трубы (ГОСТ 17376) — все 3 патрубка имеют длину
        final arm3d = fit.dn * 1.0;
        final frac3d = dist3d > 0 ? (arm3d / dist3d) : 0.0;
        final physicalPx = screenDist * frac3d;
        const minScreenTee = 14.0;
        const maxFrac = 0.38;
        trimPx = math.min(screenDist * maxFrac, math.max(physicalPx, minScreenTee));
      } else {
        // Прямая врезка без разрезания магистрали: обрезается только сегмент ответвления
        final isBranch = isTeeBranchSegment(network, nodeId, seg.id);
        if (isBranch) {
          final strokeW = calcStrokeWidth(fit.dn);
          trimPx = math.max(strokeW * 0.5 + 2.0, math.min(12.0, screenDist * 0.35));
        }
      }
    } else if (fit.fittingType == FittingType.directBranch) {
      final isBranch = isTeeBranchSegment(network, nodeId, seg.id);
      if (isBranch) {
        final strokeW = calcStrokeWidth(fit.dn);
        trimPx = math.max(strokeW * 0.5 + 2.0, math.min(12.0, screenDist * 0.35));
      }
    } else if (fit.fittingType == FittingType.reducerConcentric ||
        fit.fittingType == FittingType.reducerEccentric) {
      final arm3d = fit.dn * 0.75;
      final frac3d = dist3d > 0 ? (arm3d / dist3d) : 0.0;
      final physicalPx = screenDist * frac3d;
      trimPx = math.max(physicalPx, math.min(12.0, screenDist * 0.35));
    } else if (fit.fittingType == FittingType.flange) {
      trimPx = math.min(8.0, screenDist * 0.25);
    }

    if (trimPx <= 0.0) return nodeScreen;
    return Offset(nodeScreen.dx + dirX * trimPx, nodeScreen.dy + dirY * trimPx);
  }

  static double calcElbowTangentLength(PipingNetwork network, String nodeId, Fitting fit) {
    final node = network.nodes[nodeId];
    if (node == null) return 0.0;
    final conn = network.getConnectedSegments(nodeId);
    if (conn.length != 2) return 0.0;

    final s1 = conn[0];
    final s2 = conn[1];
    final n1 = network.nodes[s1.startNodeId == nodeId ? s1.endNodeId : s1.startNodeId];
    final n2 = network.nodes[s2.startNodeId == nodeId ? s2.endNodeId : s2.startNodeId];
    if (n1 == null || n2 == null) return 0.0;

    final v1x = n1.x - node.x;
    final v1y = n1.y - node.y;
    final v1z = n1.z - node.z;
    final len1 = math.sqrt(v1x * v1x + v1y * v1y + v1z * v1z);

    final v2x = n2.x - node.x;
    final v2y = n2.y - node.y;
    final v2z = n2.z - node.z;
    final len2 = math.sqrt(v2x * v2x + v2y * v2y + v2z * v2z);

    if (len1 <= 0 || len2 <= 0) return 0.0;

    final dot = ((v1x * v2x + v1y * v2y + v1z * v2z) / (len1 * len2)).clamp(-1.0, 1.0);
    final bendAngleRad = math.pi - math.acos(dot);
    if (bendAngleRad <= 0.05) return 0.0;

    final radMm = fit.effectiveRadiusMm;
    final t = radMm * math.tan(bendAngleRad / 2.0);
    return t.clamp(0.0, math.min(len1, len2) * 0.45);
  }

  static bool isTeeBranchSegment(PipingNetwork network, String nodeId, String segmentId) {
    final conn = network.getConnectedSegments(nodeId);
    if (conn.length != 3) return false;
    final node = network.nodes[nodeId];
    if (node == null) return false;

    final unitVectors = <List<double>>[];
    for (final s in conn) {
      final other = network.nodes[s.startNodeId == nodeId ? s.endNodeId : s.startNodeId];
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
    return conn[branchIdx].id == segmentId;
  }

  static void drawSelectedDimensionBadge(Canvas canvas, Offset pos, double lengthMm, PipeSegment seg) {
    final text = 'L = ${lengthMm.round()} мм | ${seg.formattedSize}';
    final textSpan = TextSpan(
      text: text,
      style: const TextStyle(
        color: Colors.black87,
        fontSize: 11,
        fontWeight: FontWeight.bold,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    final badgeOffset = pos + const Offset(0, -22);
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: badgeOffset,
        width: textPainter.width + 14,
        height: textPainter.height + 8,
      ),
      const Radius.circular(6),
    );

    // Подложка бейджа
    canvas.drawRRect(
      rect,
      Paint()..color = const Color(0xFFFFD54F),
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..color = const Color(0xFFFFA000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    textPainter.paint(
      canvas,
      badgeOffset - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }
}
