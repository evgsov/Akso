import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/math/axonometry_projector.dart';
import '../../core/math/snap_engine.dart';
import '../../domain/enums/fitting_type.dart';
import '../../domain/enums/projection_type.dart';
import '../../domain/enums/weld_type.dart';
import '../../domain/models/fitting.dart';
import '../../domain/models/node_3d.dart';
import '../../domain/models/pipe_segment.dart';
import '../../domain/models/piping_network.dart';
import 'smart_callout.dart';
import 'valve_symbol_painter.dart';

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
      _drawGrid(canvas, size);
    }

    // Строительные оси здания
    _drawConstructionAxes(canvas);

    // 2. Оси координат в левом нижнем углу
    _drawCoordinateAxes(canvas, size);

    // 3. Отрисовка труб (сегментов)
    for (final seg in network.segments.values) {
      final start = network.nodes[seg.startNodeId];
      final end = network.nodes[seg.endNodeId];
      if (start == null || end == null) continue;

      final p1 = projector.project(start);
      final p2 = projector.project(end);

      final isSelected = seg.id == selectedSegmentId;
      final sys = network.systems[seg.systemId];
      final color = sys != null ? Color(sys.colorValue) : Colors.blueGrey;

      // Толщина линии зависит от условного прохода DN
      final strokeWidth = _calcStrokeWidth(seg.dn);

      // Отступы на концах труб, если в узлах установлены отводы / тройники / фитинги
      final drawP1 = _calcPipeTrimmedPoint(
        nodeId: seg.startNodeId,
        otherNodeId: seg.endNodeId,
        nodeScreen: p1,
        otherScreen: p2,
        seg: seg,
      );
      final drawP2 = _calcPipeTrimmedPoint(
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
        _drawSelectedDimensionBadge(canvas, mid, lenMm, seg);
      }

      // Линия трубы
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

  double _calcStrokeWidth(int dn) {
    if (dn <= 20) return 2.8;
    if (dn <= 32) return 3.6;
    if (dn <= 50) return 4.6;
    if (dn <= 80) return 5.8;
    if (dn <= 100) return 7.0;
    return 8.5;
  }

  double _calcValveSize(int dn) {
    if (dn <= 25) return 14.0;
    if (dn <= 50) return 18.0;
    if (dn <= 100) return 24.0;
    return 28.0;
  }

  void _drawGrid(Canvas canvas, Size size) {
    // 1. Адаптивный шаг мировой сетки в миллиметрах в зависимости от масштаба
    const standardStepsMm = [
      50.0,
      100.0,
      200.0,
      500.0,
      1000.0,
      2000.0,
      5000.0,
      10000.0,
      20000.0,
      50000.0,
    ];

    double stepMm = 1000.0;
    for (final s in standardStepsMm) {
      if (s * projector.scale >= 50.0) {
        stepMm = s;
        break;
      }
    }

    // 2. Определение видимого диапазона в мировых координатах на плоскости Z = currentElevationZ
    final pTL = projector.unproject(const Offset(-120, -120), currentElevationZ);
    final pTR = projector.unproject(Offset(size.width + 120, -120), currentElevationZ);
    final pBL = projector.unproject(Offset(-120, size.height + 120), currentElevationZ);
    final pBR = projector.unproject(Offset(size.width + 120, size.height + 120), currentElevationZ);
    final pCenter = projector.unproject(Offset(size.width / 2, size.height / 2), currentElevationZ);

    double minX = math.min(math.min(pTL.x, pTR.x), math.min(pBL.x, pBR.x));
    double maxX = math.max(math.max(pTL.x, pTR.x), math.max(pBL.x, pBR.x));
    double minY = math.min(math.min(pTL.y, pTR.y), math.min(pBL.y, pBR.y));
    double maxY = math.max(math.max(pTL.y, pTR.y), math.max(pBL.y, pBR.y));

    // В 3D-орбите ограничиваем радиус сетки вокруг фокуса камеры, чтобы линии не уходили в бесконечность
    if (projector.projectionType == ProjectionType.orbit3d) {
      final maxSpanMm = (size.longestSide / projector.scale) * 1.6;
      minX = math.max(minX, pCenter.x - maxSpanMm);
      maxX = math.min(maxX, pCenter.x + maxSpanMm);
      minY = math.max(minY, pCenter.y - maxSpanMm);
      maxY = math.min(maxY, pCenter.y + maxSpanMm);
    }

    // Защита от избыточного числа линий: увеличиваем шаг, если линий больше 80
    const maxLines = 80;
    while (((maxX - minX) / stepMm > maxLines || (maxY - minY) / stepMm > maxLines) &&
        stepMm < standardStepsMm.last) {
      final nextIdx = standardStepsMm.indexOf(stepMm) + 1;
      if (nextIdx < standardStepsMm.length) {
        stepMm = standardStepsMm[nextIdx];
      } else {
        break;
      }
    }

    final startX = (minX / stepMm).floor() * stepMm;
    final endX = (maxX / stepMm).ceil() * stepMm;
    final startY = (minY / stepMm).floor() * stepMm;
    final endY = (maxY / stepMm).ceil() * stepMm;

    // Стили линий сетки
    final regularPaint = Paint()
      ..color = Colors.blueGrey.withValues(alpha: 0.12)
      ..strokeWidth = 1.0;
    final majorPaint = Paint()
      ..color = Colors.blueGrey.withValues(alpha: 0.28)
      ..strokeWidth = 1.3;
    final axisXPaint = Paint()
      ..color = const Color(0xFFEF5350).withValues(alpha: 0.55)
      ..strokeWidth = 1.6; // Ось X (красная)
    final axisYPaint = Paint()
      ..color = const Color(0xFF66BB6A).withValues(alpha: 0.55)
      ..strokeWidth = 1.6; // Ось Y (зеленая)

    // 1. Линии сетки, параллельные оси Y (постоянный X)
    for (double x = startX; x <= endX + 1e-4; x += stepMm) {
      final p1 = projector.projectCoordinates(x, startY, currentElevationZ);
      final p2 = projector.projectCoordinates(x, endY, currentElevationZ);

      final index = (x / stepMm).round();
      final isAxis = index == 0;
      final isMajor = index % 5 == 0;

      final paint = isAxis ? axisYPaint : (isMajor ? majorPaint : regularPaint);
      canvas.drawLine(p1, p2, paint);
    }

    // 2. Линии сетки, параллельные оси X (постоянный Y)
    for (double y = startY; y <= endY + 1e-4; y += stepMm) {
      final p1 = projector.projectCoordinates(startX, y, currentElevationZ);
      final p2 = projector.projectCoordinates(endX, y, currentElevationZ);

      final index = (y / stepMm).round();
      final isAxis = index == 0;
      final isMajor = index % 5 == 0;

      final paint = isAxis ? axisXPaint : (isMajor ? majorPaint : regularPaint);
      canvas.drawLine(p1, p2, paint);
    }

    // 3. Маркер мирового центра координат (0, 0, Z)
    final origin = projector.projectCoordinates(0, 0, currentElevationZ);
    if (origin.dx >= -40 && origin.dx <= size.width + 40 &&
        origin.dy >= -40 && origin.dy <= size.height + 40) {
      final originPaint = Paint()
        ..color = const Color(0xFF546E7A)
        ..strokeWidth = 1.6;

      canvas.drawCircle(origin, 5.0, Paint()..color = Colors.white..style = PaintingStyle.fill);
      canvas.drawCircle(origin, 5.0, originPaint..style = PaintingStyle.stroke);
      canvas.drawLine(Offset(origin.dx - 8, origin.dy), Offset(origin.dx + 8, origin.dy), originPaint);
      canvas.drawLine(Offset(origin.dx, origin.dy - 8), Offset(origin.dx, origin.dy + 8), originPaint);

      final elevText = currentElevationZ != 0.0
          ? ' (∇${(currentElevationZ / 1000).toStringAsFixed(3)}м)'
          : '';
      final tp = TextPainter(
        text: TextSpan(
          text: '(0,0)$elevText',
          style: const TextStyle(
            color: Color(0xFF455A64),
            fontSize: 9.0,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            backgroundColor: Color(0xD0FFFFFF),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, origin + const Offset(7, 3));
    }

    // 4. Масштабная линейка (Scale Bar) внизу экрана
    final stepPx = stepMm * projector.scale;
    _drawScaleBar(canvas, size, stepMm, stepPx);
  }

  void _drawScaleBar(Canvas canvas, Size size, double stepMm, double stepPx) {
    const barLeft = 24.0;
    final barY = size.height - 105.0;

    final barPaint = Paint()
      ..color = const Color(0xFF546E7A)
      ..strokeWidth = 1.8;

    // Горизонтальная черта длиною stepPx
    canvas.drawLine(Offset(barLeft, barY), Offset(barLeft + stepPx, barY), barPaint);
    // Засечки по краям
    canvas.drawLine(Offset(barLeft, barY - 4), Offset(barLeft, barY + 4), barPaint);
    canvas.drawLine(Offset(barLeft + stepPx, barY - 4), Offset(barLeft + stepPx, barY + 4), barPaint);

    final label = stepMm >= 1000.0 ? '${(stepMm / 1000.0).toStringAsFixed(stepMm % 1000 == 0 ? 0 : 1)} м' : '${stepMm.round()} мм';
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xFF455A64),
          fontSize: 9.5,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
          backgroundColor: Color(0xD0F8F9FA),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(barLeft + (stepPx - tp.width) / 2, barY - 14));
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
    final w1 = _calcStrokeWidth(dn1) * 1.6;
    final w2 = _calcStrokeWidth(dn2) * 1.6;

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

  /// Вычисляет экранную точку обрезки трубы у узла [nodeId] в сторону [otherNodeId]
  /// с учетом геометрии установленного в узле фитинга (отвода, тройника, перехода и др.)
  Offset _calcPipeTrimmedPoint({
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
      final t3d = _calcElbowTangentLength(nodeId, fit);
      final frac3d = dist3d > 0 ? (t3d / dist3d) : 0.0;
      final physicalPx = screenDist * frac3d;
      // Обеспечиваем гарантированную читаемость отвода на экране (минимум 15px),
      // но не более 42% длины сегмента, чтобы не пересекать середину трубы
      const minScreenElbow = 15.0;
      const maxFrac = 0.42;
      trimPx = math.max(physicalPx, math.min(minScreenElbow, screenDist * maxFrac));
    } else if (fit.fittingType == FittingType.tee) {
      if (fit.cutsMainPipe) {
        // Тройник врезан в разрыв трубы (ГОСТ 17376) — все 3 патрубка имеют длину
        final arm3d = fit.dn * 1.0;
        final frac3d = dist3d > 0 ? (arm3d / dist3d) : 0.0;
        final physicalPx = screenDist * frac3d;
        const minScreenTee = 14.0;
        const maxFrac = 0.38;
        trimPx = math.max(physicalPx, math.min(minScreenTee, screenDist * maxFrac));
      } else {
        // Прямая врезка без разрезания магистрали: обрезается только сегмент ответвления
        final isBranch = _isTeeBranchSegment(nodeId, seg.id);
        if (isBranch) {
          final strokeW = _calcStrokeWidth(fit.dn);
          trimPx = math.max(strokeW * 0.5 + 2.0, math.min(12.0, screenDist * 0.35));
        }
      }
    } else if (fit.fittingType == FittingType.directBranch) {
      final isBranch = _isTeeBranchSegment(nodeId, seg.id);
      if (isBranch) {
        final strokeW = _calcStrokeWidth(fit.dn);
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

  /// Проверяет, является ли сегмент [segmentId] ответвлением тройника в узле [nodeId]
  bool _isTeeBranchSegment(String nodeId, String segmentId) {
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

  double _calcElbowTangentLength(String nodeId, Fitting fit) {
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

    final pt1 = _calcPipeTrimmedPoint(
      nodeId: fit.nodeId,
      otherNodeId: n1.id,
      nodeScreen: ptN,
      otherScreen: pOther1,
      seg: s1,
    );
    final pt2 = _calcPipeTrimmedPoint(
      nodeId: fit.nodeId,
      otherNodeId: n2.id,
      nodeScreen: ptN,
      otherScreen: pOther2,
      seg: s2,
    );

    final sys = network.systems[s1.systemId];
    final color = sys != null ? Color(sys.colorValue) : Colors.blueGrey;
    final strokeWidth = _calcStrokeWidth(fit.dn);
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
    final strokeWidth = _calcStrokeWidth(fit.dn);
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

      final pOut1 = _calcPipeTrimmedPoint(
        nodeId: fit.nodeId,
        otherNodeId: other1.id,
        nodeScreen: ptN,
        otherScreen: projector.project(other1),
        seg: segRun1,
      );
      final pOut2 = _calcPipeTrimmedPoint(
        nodeId: fit.nodeId,
        otherNodeId: other2.id,
        nodeScreen: ptN,
        otherScreen: projector.project(other2),
        seg: segRun2,
      );
      final pOutBranch = _calcPipeTrimmedPoint(
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
      final branchStroke = _calcStrokeWidth(segBranch.dn);
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

    final halfH = math.max(8.0, _calcStrokeWidth(dn) * 1.6);
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

  void _drawSelectedDimensionBadge(Canvas canvas, Offset pos, double lengthMm, PipeSegment seg) {
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

  @override
  bool shouldRepaint(covariant PipingCanvasPainter oldDelegate) {
    return true;
  }
}
