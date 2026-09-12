import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/math/axonometry_projector.dart';
import '../../core/math/snap_engine.dart';
import '../../domain/enums/fitting_type.dart';
import '../../domain/enums/projection_type.dart';
import '../../domain/enums/weld_type.dart';
import '../../domain/models/fitting.dart';
import '../../domain/models/node_3d.dart';

import '../../domain/models/piping_network.dart';
import 'smart_callout.dart';
import 'valve_symbol_painter.dart';
import 'painters/grid_painter.dart';
import 'painters/pipe_painter.dart';


/// Холст для визуализации и интерактивного черчения трубопроводной сети
class PipingCanvasPainter extends CustomPainter {
  final PipingNetwork network;
  final AxonometryProjector projector;
  final String? selectedNodeId;
  final String? selectedSegmentId;
  final String? activeSystemId;
  final Node3D? activeTraceStart;
  final Offset? activeTraceEnd;
  final Node3D? activeAxisStart;
  final SnapResult? snapResult;
  final bool showWelds;
  final bool showCallouts;
  final bool showGrid;
  final double currentElevationZ;

  PipingCanvasPainter({
    required this.network,
    required this.projector,
    this.selectedNodeId,
    this.selectedSegmentId,
    this.activeSystemId,
    this.activeTraceStart,
    this.activeTraceEnd,
    this.activeAxisStart,
    this.snapResult,
    this.showWelds = true,
    this.showCallouts = true,
    this.showGrid = true,
    this.currentElevationZ = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Сетка фона
    if (showGrid) {
      GridPainter.paint(canvas, size, projector, currentElevationZ);
    }

    // Строительные оси здания
    _drawConstructionAxes(canvas);

    // 2. Оси координат в левом нижнем углу
    _drawCoordinateAxes(canvas, size);

    // 3. Отрисовка труб (сегментов)
    final screenPoints = <String, Offset>{};
    for (final node in network.nodes.values) {
      screenPoints[node.id] = projector.project(node);
    }

    PipePainter.paint(
      canvas,
      size,
      projector,
      network,
      selectedSegmentId,
      null,
      screenPoints,
      showCallouts,
    );

    // 4. Отрисовка арматуры
    for (final valve in network.valves.values) {
      final seg = network.segments[valve.segmentId];
      if (seg == null) continue;
      final start = network.nodes[seg.startNodeId];
      final end = network.nodes[seg.endNodeId];
      if (start == null || end == null) continue;

      final p1 = projector.project(start);
      final p2 = projector.project(end);

      final valvePos = Offset(
        p1.dx + (p2.dx - p1.dx) * valve.ratio,
        p1.dy + (p2.dy - p1.dy) * valve.ratio,
      );

      final angle = math.atan2(p2.dy - p1.dy, p2.dx - p1.dx);
      final sys = network.systems[seg.systemId];
      final color = sys != null ? Color(sys.colorValue) : Colors.black87;

      ValveSymbolPainter.drawValve(
        canvas,
        center: valvePos,
        angleRad: angle,
        type: valve.valveType,
        color: color,
        size: _calcValveSize(valve.dn),
        isReversed: valve.isReversed,
      );
    }

    // 4.1. Отрисовка фасонных деталей (отводы, тройники, фланцы, переходы, врезки)
    for (final fit in network.fittings.values) {
      if (fit.fittingType == FittingType.elbow90 || fit.fittingType == FittingType.elbow45) {
        _drawElbowSymbol(canvas, fit);
      } else if (fit.fittingType == FittingType.tee) {
        _drawTeeSymbol(canvas, fit);
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
        // Отрисовка фланцевого соединения по ГОСТ 33259-2015
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
        );
      } else if (fit.fittingType == FittingType.directBranch) {
        // Отрисовка прямой врезки (ГОСТ 16037-80 У18)
        final node = network.nodes[fit.nodeId];
        if (node == null) continue;
        final center = projector.project(node);
        _drawDirectBranchSymbol(
          canvas,
          center: center,
          dn: fit.dn,
          dnSecondary: fit.dnSecondary,
        );
      }
    }

    // 5. Отрисовка сварных стыков и выносок
    if (showWelds) {
      for (final weld in network.weldJoints.values) {
        final seg = network.segments[weld.segmentId];
        if (seg == null) continue;
        final start = network.nodes[seg.startNodeId];
        final end = network.nodes[seg.endNodeId];
        if (start == null || end == null) continue;

        final p1 = projector.project(start);
        final p2 = projector.project(end);

        final weldPos = Offset(
          p1.dx + (p2.dx - p1.dx) * weld.ratio,
          p1.dy + (p2.dy - p1.dy) * weld.ratio,
        );

        SmartCallout.drawWeldCallout(
          canvas,
          weldPoint: weldPos,
          weldNumber: weld.number,
          stamp: weld.stamp,
          gostType: weld.weldType.shortName,
          color: const Color(0xFF37474F),
        );
      }
    }

    // 6. Отрисовка узлов сети и отметок уровней
    for (final node in network.nodes.values) {
      final screenPos = projector.project(node);
      final isSelected = node.id == selectedNodeId;
      final hasFitting = network.fittings.containsKey(node.id);
      final connected = network.getConnectedSegments(node.id);

      if (isSelected) {
        // Выбранный узел — янтарный ореол и яркая точка
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
        // Концевой свободный узел (торец трубы)
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
      // Если в узле установлен фитинг (отвод, тройник и т.д.) или это непрерывный
      // внутренний стык труб — не загромождаем чертеж черными точками!

      // Флажок высотной отметки
      if (showCallouts) {
        final connected = network.getConnectedSegments(node.id);
        // Показываем отметку, если это край трассы или вертикальный стояк
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

    // 7. Интерактивная линия трассировки (когда стилус ведет новую трубу)
    if (activeTraceStart != null && activeTraceEnd != null) {
      final pStart = projector.project(activeTraceStart!);
      final tracePaint = Paint()
        ..color = Colors.teal
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round;

      // Пунктирная направляющая
      canvas.drawLine(pStart, activeTraceEnd!, tracePaint);
      canvas.drawCircle(activeTraceEnd!, 5.0, tracePaint);
    }

    // 8. Интерактивная линия строительной оси
    if (activeAxisStart != null && activeTraceEnd != null) {
      final pAxisStart = projector.project(activeAxisStart!);
      final axisPreviewPaint = Paint()
        ..color = const Color(0xFF78909C)
        ..strokeWidth = 2.0;
      _drawDashedLine(canvas, pAxisStart, activeTraceEnd!, axisPreviewPaint);
      canvas.drawCircle(activeTraceEnd!, 5.0, axisPreviewPaint);
    }

    // 9. Индикатор магнитной привязки и полярных углов
    _drawSnapIndicator(canvas);
  }

  double _calcValveSize(int dn) {
    if (dn <= 25) return 14.0;
    if (dn <= 50) return 18.0;
    if (dn <= 100) return 24.0;
    return 28.0;
  }

  void _drawCoordinateAxes(Canvas canvas, Size size) {
    final origin = Offset(60, size.height - 60);
    const axisLen = 40.0;

    final p0 = const Node3D(id: '0', x: 0, y: 0, z: 0);
    final pX = const Node3D(id: 'x', x: axisLen * 10, y: 0, z: 0);
    final pY = const Node3D(id: 'y', x: 0, y: axisLen * 10, z: 0);
    final pZ = const Node3D(id: 'z', x: 0, y: 0, z: axisLen * 10);

    final s0 = projector.project(p0);
    final sX = projector.project(pX);
    final sY = projector.project(pY);
    final sZ = projector.project(pZ);

    final dirX = (sX - s0);
    final dirY = (sY - s0);
    final dirZ = (sZ - s0);

    final lenX = math.max(dirX.distance, 1.0);
    final lenY = math.max(dirY.distance, 1.0);
    final lenZ = math.max(dirZ.distance, 1.0);

    final endX = origin + (dirX / lenX) * axisLen;
    final endY = origin + (dirY / lenY) * axisLen;
    final endZ = origin + (dirZ / lenZ) * axisLen;

    _drawAxis(canvas, origin, endX, Colors.red, 'X');
    _drawAxis(canvas, origin, endY, Colors.green, 'Y');
    _drawAxis(canvas, origin, endZ, Colors.blue, 'Z');
  }

  void _drawAxis(Canvas canvas, Offset p1, Offset p2, Color color, String label) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0;
    canvas.drawLine(p1, p2, paint);

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, p2 + const Offset(3, -7));
  }

  void _drawReducerSymbol(
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
      // Концентрический переход: симметричная трапеция по ГОСТ
      path.moveTo(-halfL, -w1);
      path.lineTo(halfL, -w2);
      path.lineTo(halfL, w2);
      path.lineTo(-halfL, w1);
      path.close();
    } else {
      // Эксцентрический переход: прямая образующая по одной стороне
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

    // Подпись перехода по ГОСТ: "80×50"
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

  void _drawElbowSymbol(Canvas canvas, Fitting fit) {
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

    // Дуга отвода (Quadratic Bezier curve) от pt1 через ptN к pt2
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

    // Сварные стыки на торцах отвода (С17)
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

  void _drawWeldTickAt(Canvas canvas, Offset pWeld, Offset pCorner, double strokeWidth) {
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

  void _drawTeeSymbol(Canvas canvas, Fitting fit) {
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
      // Ищем магистральные патрубки и ответвление
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

      // 1. Тело магистрального прохода тройника (между pOut1 и pOut2)
      canvas.drawLine(pOut1, pOut2, teeBodyPaint);

      // 2. Тело ответвления тройника (от ptN к pOutBranch)
      final branchStroke = PipePainter.calcStrokeWidth(segBranch.dn);
      final branchPaint = Paint()
        ..color = color
        ..strokeWidth = branchStroke
        ..strokeCap = StrokeCap.square;
      canvas.drawLine(ptN, pOutBranch, branchPaint);

      // 3. Центральное усиление/воротник тройника
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

      // 4. Сварные стыки С17 на всех трех патрубках тройника
      _drawWeldTickAt(canvas, pOut1, ptN, strokeWidth);
      _drawWeldTickAt(canvas, pOut2, ptN, strokeWidth);
      _drawWeldTickAt(canvas, pOutBranch, ptN, branchStroke);
    } else {
      // Для узлов с 1 или 2 трубами, где пользователь явно назначил тройник:
      final teePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(ptN, math.max(7.0, strokeWidth * 0.9), teePaint);
    }

    // Текстовая выноска тройника
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

  void _drawFlangeSymbol(
    Canvas canvas, {
    required Offset center,
    required double angle,
    required int dn,
    required FlangeConnectionType flangeConnectionType,
    required int pressurePn,
    required Color color,
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
        // Межтрубная пара: 2 параллельные черты + прокладка между ними
        const gap = 3.0;
        canvas.drawLine(Offset(-gap, -halfH), Offset(-gap, halfH), paint);
        canvas.drawLine(Offset(gap, -halfH), Offset(gap, halfH), paint);
        final gasketPaint = Paint()
          ..color = Colors.amber.shade800
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset.zero, 2.0, gasketPaint);
        break;

      case FlangeConnectionType.toEquipment:
        // К оборудованию: 1 фланец на трубе + прокладка + контур ответного штуцера оборудования
        canvas.drawLine(Offset(-2.0, -halfH), Offset(-2.0, halfH), paint);
        final gasketPaint = Paint()
          ..color = Colors.amber.shade800
          ..style = PaintingStyle.fill;
        canvas.drawCircle(const Offset(0.5, 0), 2.0, gasketPaint);

        // Контур штуцера оборудования
        final eqPaint = Paint()
          ..color = Colors.blueGrey.shade400
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8;
        canvas.drawLine(Offset(3.5, -halfH * 1.15), Offset(3.5, halfH * 1.15), eqPaint);
        canvas.drawRect(Rect.fromLTWH(3.5, -halfH * 0.6, 7.0, halfH * 1.2), eqPaint);
        break;

      case FlangeConnectionType.blindFlange:
        // Заглушка: фланец трубы + сплошной глухой диск
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

  void _drawDirectBranchSymbol(
    Canvas canvas, {
    required Offset center,
    required int dn,
    int? dnSecondary,
  }) {
    // Круговой маркер шва врезки
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

  void _drawConstructionAxes(Canvas canvas) {
    for (final axis in network.axes.values) {
      final p1 = projector.project(axis.startPoint);
      final p2 = projector.project(axis.endPoint);

      final axisPaint = Paint()
        ..color = const Color(0xFF78909C)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;

      _drawDashedLine(canvas, p1, p2, axisPaint);

      if (axis.isBuildingGrid && axis.label.isNotEmpty) {
        _drawGridBubble(canvas, p1, axis.label);
        _drawGridBubble(canvas, p2, axis.label);
      }
    }
  }

  void _drawGridBubble(Canvas canvas, Offset center, String label) {
    const r = 13.0;
    canvas.drawCircle(center, r, Paint()..color = Colors.white..style = PaintingStyle.fill);
    canvas.drawCircle(center, r, Paint()..color = const Color(0xFF546E7A)..strokeWidth = 1.4..style = PaintingStyle.stroke);

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xFF37474F),
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    final dist = (p2 - p1).distance;
    if (dist <= 0) return;
    final unit = (p2 - p1) / dist;
    double current = 0.0;
    bool draw = true;
    while (current < dist) {
      final step = draw ? 12.0 : 6.0;
      final next = math.min(current + step, dist);
      if (draw) {
        canvas.drawLine(p1 + unit * current, p1 + unit * next, paint);
      }
      current = next;
      draw = !draw;
    }
  }

  void _drawSnapIndicator(Canvas canvas) {
    if (snapResult == null || snapResult!.type == SnapType.none) return;

    final pt = snapResult!.screenPoint;

    if (snapResult!.type == SnapType.node) {
      // Зеленый ромб с подсветкой
      final greenPaint = Paint()
        ..color = const Color(0xFF00C853)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      final path = Path()
        ..moveTo(pt.dx, pt.dy - 9)
        ..lineTo(pt.dx + 9, pt.dy)
        ..lineTo(pt.dx, pt.dy + 9)
        ..lineTo(pt.dx - 9, pt.dy)
        ..close();
      canvas.drawPath(path, greenPaint);
      canvas.drawCircle(pt, 14.0, Paint()..color = const Color(0xFF00C853).withValues(alpha: 0.2)..style = PaintingStyle.fill);

      _drawSnapBadge(canvas, pt + const Offset(14, -14), snapResult!.label, const Color(0xFF00C853));
    } else if (snapResult!.type == SnapType.segmentAxis) {
      // Бирюзовый крестик врезки
      final cyanPaint = Paint()
        ..color = const Color(0xFF00B0FF)
        ..strokeWidth = 2.0;
      canvas.drawLine(pt - const Offset(8, 8), pt + const Offset(8, 8), cyanPaint);
      canvas.drawLine(pt - const Offset(-8, 8), pt + const Offset(-8, 8), cyanPaint);
      canvas.drawCircle(pt, 12.0, Paint()..color = const Color(0xFF00B0FF).withValues(alpha: 0.15)..style = PaintingStyle.fill);

      _drawSnapBadge(canvas, pt + const Offset(14, -14), snapResult!.label, const Color(0xFF00B0FF));
    } else if (snapResult!.type == SnapType.polarAngle) {
      // Направляющий луч от начала трассировки
      if (activeTraceStart != null) {
        final startPt = projector.project(activeTraceStart!);
        final rayPaint = Paint()
          ..color = Colors.amber.shade700
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke;
        _drawDashedLine(canvas, startPt, pt, rayPaint);
      }
      final orangePaint = Paint()
        ..color = Colors.amber.shade800
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      canvas.drawRect(Rect.fromCenter(center: pt, width: 12, height: 12), orangePaint);

      _drawSnapBadge(canvas, pt + const Offset(14, -14), snapResult!.label, Colors.amber.shade900);
    }
  }

  void _drawSnapBadge(Canvas canvas, Offset pos, String text, Color accentColor) {
    if (text.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(pos.dx - 4, pos.dy - 2, tp.width + 8, tp.height + 4),
      const Radius.circular(4),
    );
    canvas.drawRRect(bgRect, Paint()..color = accentColor);
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(covariant PipingCanvasPainter oldDelegate) {
    return true;
  }
}
