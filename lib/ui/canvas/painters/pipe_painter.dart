import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/math/axonometry_projector.dart';
import '../../../domain/enums/fitting_type.dart';
import '../../../domain/enums/projection_type.dart';
import '../../../domain/models/drawing_style_config.dart';
import '../../../domain/models/fitting.dart';
import '../../../domain/models/node_3d.dart';
import '../../../domain/models/pipe_segment.dart';
import '../../../domain/models/pipe_spool.dart';
import '../../../domain/models/piping_network.dart';
import '../../../domain/enums/valve_type.dart';
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
    bool isCenterlineMode = false,
    String? selectedSpoolId,
    Set<String>? selectedSpoolIds,
    bool isZLocked = false,
    double activeElevationZ = 0.0,
    DrawingStyleConfig? styleConfig,
    double? sheetZoom,
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
        if (network.isButtJoint(seg.id)) continue;
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

      if (isCenterlineMode) {
        _drawCenterlineLayer(
          canvas,
          network,
          projector,
          screenPoints,
          selectedSegmentId,
          selectedSegmentIds,
        );
      }
      return;
    }

    // 2D СПДС / ГОСТ режим
    if (network.spools.isNotEmpty) {
      // Сортировка катушек по глубине (Painter's algorithm)
      // Оптимизация O(N): вычисляем глубину каждого элемента один раз перед сортировкой
      final spoolEntries = <({PipeSpool spool, double depth})>[];
      for (final spool in network.spools.values) {
        final seg = network.segments[spool.segmentId];
        final start = spool.startPoint ?? (seg != null ? network.nodes[seg.startNodeId] : null);
        final end = spool.endPoint ?? (seg != null ? network.nodes[seg.endNodeId] : null);
        final depth = (start != null && end != null)
            ? projector.computeDepth((start.x + end.x) / 2, (start.y + end.y) / 2, (start.z + end.z) / 2)
            : 0.0;
        spoolEntries.add((spool: spool, depth: depth));
      }
      spoolEntries.sort((a, b) => b.depth.compareTo(a.depth));

      for (final entry in spoolEntries) {
        final spool = entry.spool;
        final seg = network.segments[spool.segmentId];
        if (seg == null) continue;
        if (network.isButtJoint(seg.id)) continue;

        final start = spool.startPoint ?? network.nodes[seg.startNodeId];
        final end = spool.endPoint ?? network.nodes[seg.endNodeId];
        if (start == null || end == null) continue;

        final drawP1 = projector.project(start);
        final drawP2 = projector.project(end);

        final isSpoolSelected = (selectedSpoolId != null && spool.id == selectedSpoolId) ||
            (selectedSpoolIds != null && selectedSpoolIds.contains(spool.id));
        final isSegmentSelected = (selectedSegmentId != null && seg.id == selectedSegmentId) ||
            (selectedSegmentIds != null && selectedSegmentIds.contains(seg.id));
        final isSelected = isSpoolSelected || isSegmentSelected;

        final sys = network.systems[seg.systemId];
        final baseColor = sys != null ? Color(sys.colorValue) : Colors.blueGrey;
        final isOutOfPlane = isZLocked &&
            (start.z - activeElevationZ).abs() > 15.0 &&
            (end.z - activeElevationZ).abs() > 15.0;
        final color = isOutOfPlane ? baseColor.withValues(alpha: 0.40) : baseColor;

        final strokeWidth = calcStrokeWidth(spool.dn, styleConfig: styleConfig, sheetZoom: sheetZoom);

        // Свечение/выделение, если катушка или сегмент выбраны
        if (isSelected) {
          final highlightPaint = Paint()
            ..color = Colors.amber.withValues(alpha: 0.45)
            ..strokeWidth = strokeWidth + 8.0
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(drawP1, drawP2, highlightPaint);

          // Индикатор длины реза катушки и диаметра
          final mid = Offset((drawP1.dx + drawP2.dx) / 2, (drawP1.dy + drawP2.dy) / 2);
          final label = isSpoolSelected
              ? '${spool.number}: L = ${spool.cutLengthMm.round()} мм | Ду${spool.dn}'
              : null;
          drawSelectedDimensionBadge(canvas, mid, spool.cutLengthMm, seg, label);
        }

        // Линия катушки трубы
        final pipePaint = Paint()
          ..color = color
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round;

        canvas.drawLine(drawP1, drawP2, pipePaint);

        // В 3D-орбите добавляем объемный блик по центру трубы
        if (projector.projectionType == ProjectionType.orbit3d && strokeWidth > 3.0) {
          final sheenPaint = Paint()
            ..color = Colors.white.withValues(alpha: 0.35)
            ..strokeWidth = strokeWidth * 0.35
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(drawP1, drawP2, sheenPaint);
        }
      }

      // Выноски уклона и диаметра для сегментов (пропуская стыки отвод-отвод)
      for (final seg in network.segments.values) {
        if (network.isButtJoint(seg.id)) continue;
        final start = network.nodes[seg.startNodeId];
        final end = network.nodes[seg.endNodeId];
        if (start == null || end == null) continue;

        final p1 = screenPoints[start.id] ?? projector.project(start);
        final p2 = screenPoints[end.id] ?? projector.project(end);
        final sys = network.systems[seg.systemId];
        final color = sys != null ? Color(sys.colorValue) : Colors.blueGrey;

        if (seg.slope > 0.0001 && showCallouts) {
          SmartCallout.drawSlopeCallout(
            canvas,
            p1: p1,
            p2: p2,
            slope: seg.slope,
          );
        }

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
    } else {
      // Fallback на прямолинейные сегменты (до расчета катушек)
      // Оптимизация O(N): вычисляем глубину каждого сегмента один раз перед сортировкой
      final segmentEntries = <({PipeSegment segment, double depth})>[];
      for (final seg in network.segments.values) {
        final start = network.nodes[seg.startNodeId];
        final end = network.nodes[seg.endNodeId];
        final depth = (start != null && end != null)
            ? projector.computeDepth((start.x + end.x) / 2, (start.y + end.y) / 2, (start.z + end.z) / 2)
            : 0.0;
        segmentEntries.add((segment: seg, depth: depth));
      }
      segmentEntries.sort((a, b) => b.depth.compareTo(a.depth));

      for (final entry in segmentEntries) {
        final seg = entry.segment;
        final start = network.nodes[seg.startNodeId];
        final end = network.nodes[seg.endNodeId];
        if (start == null || end == null) continue;

        final p1 = screenPoints[start.id] ?? projector.project(start);
        final p2 = screenPoints[end.id] ?? projector.project(end);

        final isSelected = seg.id == selectedSegmentId ||
            (selectedSegmentIds != null && selectedSegmentIds.contains(seg.id));
        final sys = network.systems[seg.systemId];
        final baseColor = sys != null ? Color(sys.colorValue) : Colors.blueGrey;
        final isOutOfPlane = isZLocked &&
            (start.z - activeElevationZ).abs() > 15.0 &&
            (end.z - activeElevationZ).abs() > 15.0;
        final color = isOutOfPlane ? baseColor.withValues(alpha: 0.40) : baseColor;

        final strokeWidth = calcStrokeWidth(seg.dn, styleConfig: styleConfig, sheetZoom: sheetZoom);

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

        final subsegments = calcPipeDrawableSubsegments(
          drawP1: drawP1,
          drawP2: drawP2,
          startNode: start,
          endNode: end,
          seg: seg,
          network: network,
          projector: projector,
        );

        // Свечение/выделение, если сегмент выбран
        if (isSelected) {
          final highlightPaint = Paint()
            ..color = Colors.amber.withValues(alpha: 0.45)
            ..strokeWidth = strokeWidth + 8.0
            ..strokeCap = StrokeCap.round;
          for (final (subStart, subEnd) in subsegments) {
            canvas.drawLine(subStart, subEnd, highlightPaint);
          }

          final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
          final lenMm = start.distanceTo(end);
          drawSelectedDimensionBadge(canvas, mid, lenMm, seg);
        }

        // Линия трубы
        final pipePaint = Paint()
          ..color = color
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round;

        for (final (subStart, subEnd) in subsegments) {
          canvas.drawLine(subStart, subEnd, pipePaint);
        }

        if (projector.projectionType == ProjectionType.orbit3d && strokeWidth > 3.0) {
          final sheenPaint = Paint()
            ..color = Colors.white.withValues(alpha: 0.35)
            ..strokeWidth = strokeWidth * 0.35
            ..strokeCap = StrokeCap.round;
          for (final (subStart, subEnd) in subsegments) {
            canvas.drawLine(subStart, subEnd, sheenPaint);
          }
        }

        if (seg.slope > 0.0001 && showCallouts) {
          SmartCallout.drawSlopeCallout(
            canvas,
            p1: p1,
            p2: p2,
            slope: seg.slope,
          );
        }

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

    // Отрисовка осевой трассы (штрихпунктир ГОСТ 2.303 тип Г)
    if (isCenterlineMode) {
      _drawCenterlineLayer(
        canvas,
        network,
        projector,
        screenPoints,
        selectedSegmentId,
        selectedSegmentIds,
      );
    }
  }

  /// Отрисовка слоя пространственной осевой трассы
  static void _drawCenterlineLayer(
    Canvas canvas,
    PipingNetwork network,
    AxonometryProjector projector,
    Map<String, Offset> screenPoints,
    String? selectedSegmentId,
    Set<String>? selectedSegmentIds,
  ) {
    final centerlinePaint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    for (final seg in network.segments.values) {
      final start = network.nodes[seg.startNodeId];
      final end = network.nodes[seg.endNodeId];
      if (start == null || end == null) continue;

      final p1 = screenPoints[start.id] ?? projector.project(start);
      final p2 = screenPoints[end.id] ?? projector.project(end);

      final isSegSelected = seg.id == selectedSegmentId ||
          (selectedSegmentIds != null && selectedSegmentIds.contains(seg.id));

      if (isSegSelected) {
        final hl = Paint()
          ..color = Colors.amber.withValues(alpha: 0.55)
          ..strokeWidth = 6.0
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(p1, p2, hl);

        final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
        final lenMm = start.distanceTo(end);
        drawSelectedDimensionBadge(
          canvas,
          mid,
          lenMm,
          seg,
          'Ось: L = ${lenMm.round()} мм | ${seg.formattedSize}',
        );
      }

      drawDashDotLine(canvas, p1, p2, centerlinePaint);

      // Вершины узлов трассы
      final vertexPaint = Paint()
        ..color = isSegSelected ? Colors.amber : const Color(0xFF00E5FF)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(p1, 2.5, vertexPaint);
      canvas.drawCircle(p2, 2.5, vertexPaint);
    }
  }

  /// Отрисовка штрихпунктирной линии по ГОСТ 2.303 (тип Г - штрих-пунктирная тонкая)
  static void drawDashDotLine(
    Canvas canvas,
    Offset p1,
    Offset p2,
    Paint paint, {
    double dashLen = 14.0,
    double gapLen = 4.0,
    double dotLen = 2.0,
  }) {
    final dist = (p2 - p1).distance;
    if (dist <= 0) return;
    final unit = (p2 - p1) / dist;
    double current = 0.0;
    while (current < dist) {
      final dEnd = math.min(current + dashLen, dist);
      canvas.drawLine(p1 + unit * current, p1 + unit * dEnd, paint);
      current = dEnd + gapLen;
      if (current >= dist) break;
      final dotEnd = math.min(current + dotLen, dist);
      canvas.drawLine(p1 + unit * current, p1 + unit * dotEnd, paint);
      current = dotEnd + gapLen;
    }
  }

  /// Вычисляет подотрезки трубы между фитингами с вырезанием проходной арматуры
  static List<(Offset, Offset)> calcPipeDrawableSubsegments({
    required Offset drawP1,
    required Offset drawP2,
    required Node3D startNode,
    required Node3D endNode,
    required PipeSegment seg,
    required PipingNetwork network,
    required AxonometryProjector projector,
  }) {
    final segValves = network.valves.values
        .where((v) => v.segmentId == seg.id && v.valveType.isInline)
        .toList();
    if (segValves.isEmpty) {
      return [(drawP1, drawP2)];
    }

    final totalLen = startNode.distanceTo(endNode);
    if (totalLen < 1e-4) {
      return [(drawP1, drawP2)];
    }

    final dx = drawP2.dx - drawP1.dx;
    final dy = drawP2.dy - drawP1.dy;
    final dScreenSq = dx * dx + dy * dy;
    if (dScreenSq < 0.01) {
      return [(drawP1, drawP2)];
    }

    // Собираем интервалы вырезания арматуры в 3D (по расстоянию от startNode в мм)
    final cutIntervals = <(double, double)>[];
    for (final v in segValves) {
      final cDist = v.ratio * totalLen;
      final halfL = math.max(12.0, v.lengthMm / 2.0);
      final dIn = math.max(0.0, cDist - halfL);
      final dOut = math.min(totalLen, cDist + halfL);
      if (dOut > dIn + 0.1) {
        cutIntervals.add((dIn, dOut));
      }
    }

    if (cutIntervals.isEmpty) {
      return [(drawP1, drawP2)];
    }

    cutIntervals.sort((a, b) => a.$1.compareTo(b.$1));

    final uX = (endNode.x - startNode.x) / totalLen;
    final uY = (endNode.y - startNode.y) / totalLen;
    final uZ = (endNode.z - startNode.z) / totalLen;

    final screenCutIntervals = <(double, double)>[];
    for (final (dIn, dOut) in cutIntervals) {
      final nodeIn = Node3D(
        id: '',
        x: startNode.x + uX * dIn,
        y: startNode.y + uY * dIn,
        z: startNode.z + uZ * dIn,
      );
      final nodeOut = Node3D(
        id: '',
        x: startNode.x + uX * dOut,
        y: startNode.y + uY * dOut,
        z: startNode.z + uZ * dOut,
      );

      final pIn = projector.project(nodeIn);
      final pOut = projector.project(nodeOut);

      final tIn = (((pIn.dx - drawP1.dx) * dx + (pIn.dy - drawP1.dy) * dy) / dScreenSq).clamp(0.0, 1.0);
      final tOut = (((pOut.dx - drawP1.dx) * dx + (pOut.dy - drawP1.dy) * dy) / dScreenSq).clamp(0.0, 1.0);

      final tStart = math.min(tIn, tOut);
      final tEnd = math.max(tIn, tOut);
      if (tEnd > tStart + 0.001) {
        screenCutIntervals.add((tStart, tEnd));
      }
    }

    if (screenCutIntervals.isEmpty) {
      return [(drawP1, drawP2)];
    }

    final mergedCuts = <(double, double)>[];
    var currentMerged = screenCutIntervals.first;
    for (int i = 1; i < screenCutIntervals.length; i++) {
      final next = screenCutIntervals[i];
      if (next.$1 <= currentMerged.$2) {
        currentMerged = (currentMerged.$1, math.max(currentMerged.$2, next.$2));
      } else {
        mergedCuts.add(currentMerged);
        currentMerged = next;
      }
    }
    mergedCuts.add(currentMerged);

    final result = <(Offset, Offset)>[];
    var tCurr = 0.0;

    for (final (cutStart, cutEnd) in mergedCuts) {
      if (cutStart > tCurr + 0.002) {
        final pStart = Offset(drawP1.dx + dx * tCurr, drawP1.dy + dy * tCurr);
        final pEnd = Offset(drawP1.dx + dx * cutStart, drawP1.dy + dy * cutStart);
        result.add((pStart, pEnd));
      }
      tCurr = math.max(tCurr, cutEnd);
    }

    if (tCurr < 0.998) {
      final pStart = Offset(drawP1.dx + dx * tCurr, drawP1.dy + dy * tCurr);
      result.add((pStart, drawP2));
    }

    return result.isEmpty ? [(drawP1, drawP2)] : result;
  }

  static double calcStrokeWidth(int dn, {DrawingStyleConfig? styleConfig, double? sheetZoom}) {
    if (styleConfig != null && sheetZoom != null) {
      final strokeMm = styleConfig.getPipeStrokeWidthMm(dn);
      return math.max(0.75, strokeMm * sheetZoom);
    } else if (styleConfig != null) {
      final baseFactor = styleConfig.pipeLineWidthMm / 0.8;
      final double baseW;
      if (dn <= 20) {
        baseW = 2.8;
      } else if (dn <= 32) {
        baseW = 3.6;
      } else if (dn <= 50) {
        baseW = 4.6;
      } else if (dn <= 80) {
        baseW = 5.8;
      } else if (dn <= 100) {
        baseW = 7.0;
      } else {
        baseW = 8.5;
      }
      return math.max(1.0, baseW * baseFactor);
    } else {
      if (dn <= 20) return 2.8;
      if (dn <= 32) return 3.6;
      if (dn <= 50) return 4.6;
      if (dn <= 80) return 5.8;
      if (dn <= 100) return 7.0;
      return 8.5;
    }
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

    if (network.isButtJoint(seg.id)) {
      final d1 = network.getFittingDeduction(nodeId, seg.id);
      final d2 = network.getFittingDeduction(otherNodeId, seg.id);
      final sumD = d1 + d2;
      final ratio = sumD > 0 ? (d1 / sumD).clamp(0.0, 1.0) : 0.5;
      trimPx = screenDist * ratio;
      return Offset(nodeScreen.dx + dirX * trimPx, nodeScreen.dy + dirY * trimPx);
    }

    if (fit.fittingType == FittingType.elbow90 || fit.fittingType == FittingType.elbow45) {
      final t3d = calcElbowTangentLength(network, nodeId, fit);
      // Обычный отвод: жесткое плечо t3d
      final frac3d = dist3d > 0 ? (t3d / dist3d) : 0.0;
      final physicalPx = screenDist * frac3d;
      trimPx = math.min(screenDist * 0.95, physicalPx);
    } else if (fit.fittingType == FittingType.tee) {
      if (fit.cutsMainPipe) {
        // Тройник врезан в разрыв трубы (ГОСТ 17376)
        final isBranch = isTeeBranchSegment(network, nodeId, seg.id);
        final armLenMm = isBranch
            ? fit.effectiveBranchLengthMm
            : (fit.buildingLengthMm != null && fit.buildingLengthMm! > 0
                ? fit.buildingLengthMm! / 2.0
                : fit.dn * 1.0);
        final effectiveArm = math.min(armLenMm, dist3d * 0.45);
        final frac3d = dist3d > 0 ? (effectiveArm / dist3d) : 0.0;
        trimPx = screenDist * frac3d;
      } else {
        // Прямая врезка без разрезания магистрали: обрезается только сегмент ответвления
        final isBranch = isTeeBranchSegment(network, nodeId, seg.id);
        if (isBranch) {
          final strokeW = calcStrokeWidth(fit.dn);
          trimPx = math.min(strokeW * 0.5, screenDist * 0.4);
        }
      }
    } else if (fit.fittingType == FittingType.directBranch) {
      trimPx = 0.0; // Врезка У18: труба ответвления доходит до оси магистрали без зазора
    } else if (fit.fittingType == FittingType.cap) {
      trimPx = 0.0; // Днище приваривается встык к торцу трубы в узле
    } else if (fit.fittingType == FittingType.reducerConcentric ||
        fit.fittingType == FittingType.reducerEccentric) {
      final arm3d = fit.effectiveBuildingLengthMm / 2.0;
      final frac3d = dist3d > 0 ? (arm3d / dist3d) : 0.0;
      final physicalPx = screenDist * frac3d;
      const minScreen = 12.0;
      final maxTrim = screenDist * 0.45;
      trimPx = math.min(maxTrim, math.max(physicalPx, math.min(minScreen, maxTrim)));
    } else if (fit.fittingType == FittingType.flange) {
      trimPx = math.min(8.0, screenDist * 0.25);
    }

    if (trimPx <= 0.0) return nodeScreen;
    return Offset(nodeScreen.dx + dirX * trimPx, nodeScreen.dy + dirY * trimPx);
  }

  static double calcElbowTangentLength(PipingNetwork network, String nodeId, Fitting fit) {
    return network.getElbowTangentMm(nodeId);
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

  static void drawSelectedDimensionBadge(Canvas canvas, Offset pos, double lengthMm, PipeSegment seg, [String? customText]) {
    final text = customText ?? 'L = ${lengthMm.round()} мм | ${seg.formattedSize}';
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
