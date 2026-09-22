import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/math/axonometry_projector.dart';
import '../../core/math/snap_engine.dart';
import '../../domain/models/acquired_tracking_point.dart';
import '../../domain/models/node_3d.dart';

import '../../domain/models/linear_dimension.dart';
import '../../domain/models/piping_network.dart';
import 'painters/grid_painter.dart';
import 'painters/pipe_painter.dart';
import 'painters/fitting_painter.dart';
import 'painters/valve_painter.dart';
import 'painters/support_painter.dart';
import 'painters/annotation_painter.dart';
import 'painters/equipment_painter.dart';
import 'painters/callout_painter.dart';
import 'painters/dimension_painter.dart';
import 'input_controller.dart' show CanvasTool;



/// Данные о длине и угле отрезка трассировки для отображения в HUD
class TraceHudInfo {
  final double lengthMm;
  final int angleDegrees;
  final String text;

  const TraceHudInfo({
    required this.lengthMm,
    required this.angleDegrees,
    required this.text,
  });
}

/// Холст для визуализации и интерактивного черчения трубопроводной сети
class PipingCanvasPainter extends CustomPainter {
  final PipingNetwork network;
  final AxonometryProjector projector;
  final String? selectedNodeId;
  final String? selectedSegmentId;
  final String? selectedEquipmentId;
  final String? selectedCalloutId;
  final String? selectedValveId;
  final String? selectedSupportId;
  final String? selectedWeldId;
  final Map<String, String>? calloutTemplates;
  final String? activeSystemId;
  final Node3D? activeTraceStart;
  final Offset? activeTraceEnd;
  final Node3D? activeAxisStart;
  final SnapResult? snapResult;
  final bool showWelds;
  final bool showCallouts;
  final bool showGrid;
  final bool isVolumeMode;
  final bool isCenterlineMode;
  final String? selectedSpoolId;
  final Set<String>? selectedSpoolIds;
  final double currentElevationZ;
  final String? selectedDimensionId;
  final String? selectedAxisId;
  final LinearDimension? previewDimension;
  final Set<String>? selectedNodeIds;
  final Set<String>? selectedSegmentIds;
  final Set<String>? selectedEquipmentIds;
  final Set<String>? selectedAxisIds;
  final Set<String>? selectedDimensionIds;
  final Node3D? modifyBasePointWorld;
  final Offset? modifyCurrentPointScreen;
  final CanvasTool? currentTool;
  final Rect? selectionBoxRect;
  final bool isCrossingSelection;
  final List<AcquiredTrackingPoint>? acquiredPoints;
  final bool isZLocked;
  final bool showZPlaneGrid;

  PipingCanvasPainter({
    required this.network,
    required this.projector,
    this.selectedNodeId,
    this.selectedSegmentId,
    this.selectedEquipmentId,
    this.selectedCalloutId,
    this.selectedValveId,
    this.selectedSupportId,
    this.selectedWeldId,
    this.selectedDimensionId,
    this.selectedAxisId,
    this.previewDimension,
    this.selectedNodeIds,
    this.selectedSegmentIds,
    this.selectedEquipmentIds,
    this.selectedAxisIds,
    this.selectedDimensionIds,
    this.modifyBasePointWorld,
    this.modifyCurrentPointScreen,
    this.currentTool,
    this.selectionBoxRect,
    this.isCrossingSelection = false,
    this.calloutTemplates,
    this.activeSystemId,
    this.activeTraceStart,
    this.activeTraceEnd,
    this.activeAxisStart,
    this.snapResult,
    this.showWelds = true,
    this.showCallouts = true,
    this.showGrid = true,
    this.isVolumeMode = false,
    this.isCenterlineMode = false,
    this.selectedSpoolId,
    this.selectedSpoolIds,
    this.currentElevationZ = 0.0,
    this.acquiredPoints,
    this.isZLocked = false,
    this.showZPlaneGrid = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Сетка фона
    if (showGrid) {
      GridPainter.paint(canvas, size, projector, currentElevationZ);
    }

    // 1.1. Координатная сетка активной плоскости Z (Z-Plane Grid)
    if (showZPlaneGrid) {
      _drawZPlaneGrid(canvas, size);
    }

    // Строительные оси здания
    _drawConstructionAxes(canvas);

    // 2. Оси координат в левом нижнем углу
    _drawCoordinateAxes(canvas, size);

    // 2.1. Отрисовка технологического оборудования и штуцеров
    EquipmentPainter.paint(
      canvas,
      projector,
      network,
      selectedEquipmentId: selectedEquipmentId,
      selectedEquipmentIds: selectedEquipmentIds,
      selectedNodeId: selectedNodeId,
    );

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
      isVolumeMode,
      selectedSegmentIds,
      isCenterlineMode,
      selectedSpoolId,
      selectedSpoolIds,
      isZLocked,
      currentElevationZ,
    );

    // 4. Отрисовка арматуры
    ValvePainter.paint(
      canvas,
      projector,
      network,
      isVolumeMode: isVolumeMode,
      selectedValveId: selectedValveId,
    );

    // 4.1. Отрисовка опор и подвесок
    SupportPainter.paint(
      canvas,
      projector,
      network,
      isVolumeMode: isVolumeMode,
      selectedSupportId: selectedSupportId,
    );

    // 4.2. Отрисовка фасонных деталей
    FittingPainter.paint(
      canvas,
      projector,
      network,
      selectedNodeId,
      showCallouts,
      isVolumeMode: isVolumeMode,
    );

    // 5 & 6. Отрисовка сварных стыков, узлов сети и отметок
    AnnotationPainter.paint(
      canvas,
      projector,
      network,
      selectedNodeId,
      showWelds,
      showCallouts,
      selectedWeldId: selectedWeldId,
    );

    // 6.1. Отрисовка умных выносок сети (Callout) поверх графа
    if (showCallouts) {
      CalloutPainter.paint(
        canvas,
        projector,
        network,
        templates: calloutTemplates,
        selectedCalloutId: selectedCalloutId,
      );
    }

    // 6.2. Отрисовка линейных размеров по ГОСТ 2.307
    DimensionPainter.paint(
      canvas,
      projector,
      network,
      previewDimension: previewDimension,
      selectedDimensionId: selectedDimensionId,
      selectedDimensionIds: selectedDimensionIds,
    );

    // 6.3. Подсветка группы выбранных элементов при множественном выборе
    if (selectedNodeIds != null && selectedNodeIds!.length > 1) {
      final multiGlow = Paint()
        ..color = Colors.amber.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill;
      final multiRing = Paint()
        ..color = Colors.amber.shade700
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      for (final nId in selectedNodeIds!) {
        final n = network.nodes[nId];
        if (n != null) {
          final pt = projector.project(n);
          canvas.drawCircle(pt, 8.0, multiGlow);
          canvas.drawCircle(pt, 5.0, multiRing);
        }
      }
    }

    // 7. Интерактивная линия трассировки (когда стилус ведет новую трубу)
    if (activeTraceStart != null && activeTraceEnd != null) {
      final pStart = projector.project(activeTraceStart!);
      final effectiveScreenEnd = (snapResult != null && snapResult!.type != SnapType.none)
          ? snapResult!.screenPoint
          : activeTraceEnd!;
      final tracePaint = Paint()
        ..color = Colors.teal
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round;

      // Если активна врезка под 90° в разновысотную трубу (Smart Drop/Riser):
      if (snapResult != null &&
          snapResult!.isElevationTransition &&
          snapResult!.intermediateTurnPoint != null) {
        final pTurn = projector.project(snapResult!.intermediateTurnPoint!);
        final horizDist = (snapResult!.intermediateTurnPoint!.x - activeTraceStart!.x).abs() +
            (snapResult!.intermediateTurnPoint!.y - activeTraceStart!.y).abs();

        if (horizDist > 15.0) {
          // 1. Горизонтальная линия на текущей отметке Z
          canvas.drawLine(pStart, pTurn, tracePaint);
          // Маркер угла 90° (Отвод)
          canvas.drawCircle(pTurn, 5.0, Paint()..color = Colors.amber.shade700);
          canvas.drawCircle(pTurn, 3.0, Paint()..color = Colors.white);
          // 2. Вертикальный стояк/опуск к целевой трубе
          final riserPaint = Paint()
            ..color = Colors.amber.shade700
            ..strokeWidth = 2.8
            ..strokeCap = StrokeCap.round;
          _drawDashedLine(canvas, pTurn, effectiveScreenEnd, riserPaint);
        } else {
          // Прямой стояк без горизонтали
          final riserPaint = Paint()
            ..color = Colors.amber.shade700
            ..strokeWidth = 3.0
            ..strokeCap = StrokeCap.round;
          _drawDashedLine(canvas, pStart, effectiveScreenEnd, riserPaint);
        }
        canvas.drawCircle(effectiveScreenEnd, 6.0, Paint()..color = Colors.amber.shade800);
      } else {
        // Обычная направляющая
        canvas.drawLine(pStart, effectiveScreenEnd, tracePaint);
        canvas.drawCircle(effectiveScreenEnd, 5.0, tracePaint);
      }
    }

    // 8. Интерактивная линия строительной оси
    if (activeAxisStart != null && activeTraceEnd != null) {
      final pAxisStart = projector.project(activeAxisStart!);
      final effectiveScreenEnd = (snapResult != null && snapResult!.type != SnapType.none)
          ? snapResult!.screenPoint
          : activeTraceEnd!;
      final axisPreviewPaint = Paint()
        ..color = const Color(0xFF78909C)
        ..strokeWidth = 2.0;
      _drawDashedLine(canvas, pAxisStart, effectiveScreenEnd, axisPreviewPaint);
      canvas.drawCircle(effectiveScreenEnd, 5.0, axisPreviewPaint);
    }

    // 8.1. Захваченные опорные точки отслеживания AutoCAD OTRACK (+)
    if (currentTool == CanvasTool.trace ||
        currentTool == CanvasTool.drawAxis ||
        currentTool == CanvasTool.move ||
        currentTool == CanvasTool.copy) {
      _drawAcquiredTrackingPoints(canvas);
    }

    // 9. Индикатор магнитной привязки и полярных углов
    _drawSnapIndicator(canvas);

    // 10. HUD длины и угла активного отрезка трассировки
    _drawTraceHud(canvas, size);

    // 11. Рамка множественного выбора (Selection Box)
    if (selectionBoxRect != null) {
      _drawSelectionBox(canvas, selectionBoxRect!, isCrossingSelection);
    }

    // 12. Призрак интерактивной модификации (Перемещение, Копирование, Разворот)
    if (modifyBasePointWorld != null && modifyCurrentPointScreen != null) {
      _drawModifyGhostPreview(canvas, size);
    }
  }

  void _drawModifyGhostPreview(Canvas canvas, Size size) {
    if (modifyBasePointWorld == null || modifyCurrentPointScreen == null) return;

    final pBase = projector.project(modifyBasePointWorld!);
    final pTarget = modifyCurrentPointScreen!;
    final dScreen = pTarget - pBase;

    // 1. Направляющая линия от базовой точки к курсору
    final isCopy = currentTool == CanvasTool.copy;
    final isRotate = currentTool == CanvasTool.rotate;
    final accentColor = isRotate
        ? const Color(0xFFAB47BC) // Фиолетовый для разворота
        : (isCopy ? const Color(0xFF00E5FF) : Colors.amber.shade700);

    final guidePaint = Paint()
      ..color = accentColor.withValues(alpha: 0.85)
      ..strokeWidth = 1.5;
    _drawDashedLine(canvas, pBase, pTarget, guidePaint);

    // Маркеры базовой точки и целевой точки
    final markerPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pBase, 4.5, markerPaint);
    canvas.drawCircle(
      pBase,
      7.0,
      Paint()
        ..color = accentColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    canvas.drawCircle(pTarget, 3.5, markerPaint);

    // 2. HUD-бейдж расстояния или угла
    final currentWorld = projector.unproject(pTarget, modifyBasePointWorld!.z);
    final dx = currentWorld.x - modifyBasePointWorld!.x;
    final dy = currentWorld.y - modifyBasePointWorld!.y;
    final dz = currentWorld.z - modifyBasePointWorld!.z;
    final distMm = math.sqrt(dx * dx + dy * dy + dz * dz);

    String hudText;
    if (isRotate) {
      double angleDeg = math.atan2(dy, dx) * 180.0 / math.pi;
      if (angleDeg < 0) angleDeg += 360.0;
      hudText = '∡ Угол: ${angleDeg.toStringAsFixed(1)}°';
    } else {
      hudText = '${isCopy ? "Копия" : "Смещение"}: ${distMm.toStringAsFixed(0)} мм';
    }

    final tp = TextPainter(
      text: TextSpan(
        text: hudText,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final midScreen = Offset((pBase.dx + pTarget.dx) / 2, (pBase.dy + pTarget.dy) / 2);
    final badgePos = computeBadgePosition(
      cursorOffset: midScreen,
      badgeSize: Size(tp.width + 16, tp.height + 8),
      canvasSize: size,
      offsetDistance: 12.0,
    );
    final badgeRect = Rect.fromLTWH(badgePos.dx, badgePos.dy, tp.width + 16, tp.height + 8);
    final rrect = RRect.fromRectAndRadius(badgeRect, const Radius.circular(5));
    canvas.drawShadow(Path()..addRRect(rrect), Colors.black.withValues(alpha: 0.4), 3.0, false);
    canvas.drawRRect(rrect, Paint()..color = const Color(0xE6263238));
    canvas.drawRRect(rrect, Paint()..color = accentColor..style = PaintingStyle.stroke..strokeWidth = 1.2);
    tp.paint(canvas, Offset(badgePos.dx + 8, badgePos.dy + 4));

    // 3. Фантомный контур (призрак) перемещаемых / копируемых объектов сети
    if (!isRotate && dScreen.distance > 2.0) {
      final ghostStroke = Paint()
        ..color = accentColor.withValues(alpha: 0.7)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;

      // Призрак сегментов
      final segsToGhost = Set<String>.from(selectedSegmentIds ?? const <String>{});
      if (selectedSegmentId != null) segsToGhost.add(selectedSegmentId!);

      for (final segId in segsToGhost) {
        final seg = network.segments[segId];
        if (seg != null) {
          final sNode = network.nodes[seg.startNodeId];
          final eNode = network.nodes[seg.endNodeId];
          if (sNode != null && eNode != null) {
            final p1 = projector.project(sNode) + dScreen;
            final p2 = projector.project(eNode) + dScreen;
            _drawDashedLine(canvas, p1, p2, ghostStroke);
            canvas.drawCircle(p1, 3.0, Paint()..color = accentColor.withValues(alpha: 0.7));
            canvas.drawCircle(p2, 3.0, Paint()..color = accentColor.withValues(alpha: 0.7));
          }
        }
      }

      // Призрак изолированных узлов
      final nodesToGhost = Set<String>.from(selectedNodeIds ?? const <String>{});
      if (selectedNodeId != null) nodesToGhost.add(selectedNodeId!);
      for (final nId in nodesToGhost) {
        final node = network.nodes[nId];
        if (node != null) {
          final p = projector.project(node) + dScreen;
          canvas.drawCircle(p, 4.5, Paint()..color = accentColor.withValues(alpha: 0.7));
        }
      }

      // Призрак строительных осей
      final axesToGhost = Set<String>.from(selectedAxisIds ?? const <String>{});
      if (selectedAxisId != null) axesToGhost.add(selectedAxisId!);
      for (final axId in axesToGhost) {
        final axis = network.axes[axId];
        if (axis != null) {
          final p1 = projector.project(axis.startPoint) + dScreen;
          final p2 = projector.project(axis.endPoint) + dScreen;
          _drawDashedLine(canvas, p1, p2, ghostStroke);
        }
      }

      // Призрак оборудования
      final eqToGhost = Set<String>.from(selectedEquipmentIds ?? const <String>{});
      if (selectedEquipmentId != null) eqToGhost.add(selectedEquipmentId!);
      for (final eqId in eqToGhost) {
        final eq = network.equipments[eqId];
        if (eq != null) {
          final p = projector.project(Node3D(id: 'ghost_eq', x: eq.x, y: eq.y, z: eq.z)) + dScreen;
          canvas.drawCircle(p, 10.0, Paint()..color = accentColor.withValues(alpha: 0.35));
          canvas.drawCircle(p, 10.0, ghostStroke);
        }
      }
    }
  }

  void _drawSelectionBox(Canvas canvas, Rect rect, bool isCrossing) {
    final fillColor = isCrossing
        ? const Color(0x224CAF50) // Зеленый для секущей рамки (справа-налево)
        : const Color(0x222196F3); // Синий для обычной рамки (слева-направо)
    final strokeColor = isCrossing ? const Color(0xFF4CAF50) : const Color(0xFF2196F3);

    final bgPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, bgPaint);

    final borderPaint = Paint()
      ..color = strokeColor
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    if (isCrossing) {
      _drawDashedLine(canvas, rect.topLeft, rect.topRight, borderPaint);
      _drawDashedLine(canvas, rect.topRight, rect.bottomRight, borderPaint);
      _drawDashedLine(canvas, rect.bottomRight, rect.bottomLeft, borderPaint);
      _drawDashedLine(canvas, rect.bottomLeft, rect.topLeft, borderPaint);
    } else {
      canvas.drawRect(rect, borderPaint);
    }
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

  void _drawConstructionAxes(Canvas canvas) {
    for (final axis in network.axes.values) {
      final p1 = projector.project(axis.startPoint);
      final p2 = projector.project(axis.endPoint);

      final isSelected = axis.id == selectedAxisId ||
          (selectedAxisIds != null && selectedAxisIds!.contains(axis.id));
      final axisPaint = Paint()
        ..color = isSelected ? Colors.amber.shade700 : const Color(0xFF78909C)
        ..strokeWidth = isSelected ? 2.4 : 1.2
        ..style = PaintingStyle.stroke;

      _drawDashedLine(canvas, p1, p2, axisPaint);

      if (axis.isBuildingGrid && axis.label.isNotEmpty) {
        _drawGridBubble(canvas, p1, axis.label, isSelected: isSelected);
        _drawGridBubble(canvas, p2, axis.label, isSelected: isSelected);
      }

      if (isSelected) {
        _drawGripHandle(canvas, p1);
        _drawGripHandle(canvas, p2);
      }
    }
  }

  void _drawGripHandle(Canvas canvas, Offset pt) {
    const size = 8.0;
    final rect = Rect.fromCenter(center: pt, width: size, height: size);
    canvas.drawRect(rect, Paint()..color = Colors.white..style = PaintingStyle.fill);
    canvas.drawRect(rect, Paint()..color = Colors.amber.shade900..strokeWidth = 1.5..style = PaintingStyle.stroke);
  }

  void _drawGridBubble(Canvas canvas, Offset center, String label, {bool isSelected = false}) {
    const r = 13.0;
    canvas.drawCircle(center, r, Paint()..color = isSelected ? Colors.amber.shade50 : Colors.white..style = PaintingStyle.fill);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = isSelected ? Colors.amber.shade800 : const Color(0xFF546E7A)
        ..strokeWidth = isSelected ? 2.0 : 1.4
        ..style = PaintingStyle.stroke,
    );

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: isSelected ? Colors.amber.shade900 : const Color(0xFF37474F),
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
      // Зеленый ромб с подсветкой (Endpoint)
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
    } else if (snapResult!.type == SnapType.endpoint) {
      // Зеленый квадрат AutoCAD (Endpoint / Край оси или опорной линии)
      const epColor = Color(0xFF00C853);
      final epPaint = Paint()
        ..color = epColor
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke;
      final rect = Rect.fromCenter(center: pt, width: 14.0, height: 14.0);
      canvas.drawRect(rect, epPaint);
      canvas.drawRect(
        rect,
        Paint()
          ..color = epColor.withValues(alpha: 0.2)
          ..style = PaintingStyle.fill,
      );
      _drawSnapBadge(canvas, pt + const Offset(14, -14), snapResult!.label, epColor);
    } else if (snapResult!.type == SnapType.midpoint) {
      // Изумрудно-зеленый треугольник (Midpoint)
      const midColor = Color(0xFF00E676);
      final midPaint = Paint()
        ..color = midColor
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke;
      final path = Path()
        ..moveTo(pt.dx, pt.dy - 10)
        ..lineTo(pt.dx + 9, pt.dy + 6)
        ..lineTo(pt.dx - 9, pt.dy + 6)
        ..close();
      canvas.drawPath(path, midPaint);
      canvas.drawPath(
        path,
        Paint()
          ..color = midColor.withValues(alpha: 0.25)
          ..style = PaintingStyle.fill,
      );
      _drawSnapBadge(canvas, pt + const Offset(14, -14), snapResult!.label, midColor);
    } else if (snapResult!.type == SnapType.intersection) {
      // Ярко-желтый крест пересечения (Intersection)
      const interColor = Color(0xFFFFD600);
      final interPaint = Paint()
        ..color = interColor
        ..strokeWidth = 2.4;
      canvas.drawLine(pt - const Offset(8, 8), pt + const Offset(8, 8), interPaint);
      canvas.drawLine(pt - const Offset(-8, 8), pt + const Offset(-8, 8), interPaint);
      canvas.drawCircle(pt, 12.0, Paint()..color = interColor.withValues(alpha: 0.18)..style = PaintingStyle.fill);
      _drawSnapBadge(canvas, pt + const Offset(14, -14), snapResult!.label, interColor);
    } else if (snapResult!.type == SnapType.perpendicular) {
      // Значок прямого угла AutoCAD Perpendicular (L-угол с внутренним квадратиком)
      const perpColor = Color(0xFF00E5FF);
      final perpPaint = Paint()
        ..color = perpColor
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke;

      // Отрисовка направляющей перпендикулярной линии от начального узла к точке привязки
      final startNode = activeTraceStart ?? activeAxisStart ?? modifyBasePointWorld;
      if (startNode != null) {
        final startPt = projector.project(startNode);
        final guidePaint = Paint()
          ..color = perpColor.withValues(alpha: 0.7)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke;
        _drawDashedLine(canvas, startPt, pt, guidePaint);
      }

      // Символ прямого угла AutoCAD: две перпендикулярные стороны и маленький квадрат в углу
      final path = Path()
        ..moveTo(pt.dx - 8, pt.dy - 8)
        ..lineTo(pt.dx - 8, pt.dy + 8)
        ..lineTo(pt.dx + 8, pt.dy + 8);
      path
        ..moveTo(pt.dx - 8, pt.dy + 2)
        ..lineTo(pt.dx - 2, pt.dy + 2)
        ..lineTo(pt.dx - 2, pt.dy + 8);
      canvas.drawPath(path, perpPaint);
      canvas.drawCircle(pt, 12.0, Paint()..color = perpColor.withValues(alpha: 0.18)..style = PaintingStyle.fill);

      _drawSnapBadge(canvas, pt + const Offset(14, -14), snapResult!.label, perpColor);
    } else if (snapResult!.type == SnapType.segmentAxis) {
      // Бирюзовые «песочные часы» (AutoCAD Nearest / Trajectory)
      const cyanColor = Color(0xFF00B0FF);
      final cyanPaint = Paint()
        ..color = cyanColor
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      final path = Path()
        ..moveTo(pt.dx - 7, pt.dy - 7)
        ..lineTo(pt.dx + 7, pt.dy + 7)
        ..lineTo(pt.dx - 7, pt.dy + 7)
        ..lineTo(pt.dx + 7, pt.dy - 7)
        ..close();
      canvas.drawPath(path, cyanPaint);
      canvas.drawCircle(pt, 12.0, Paint()..color = cyanColor.withValues(alpha: 0.15)..style = PaintingStyle.fill);

      _drawSnapBadge(canvas, pt + const Offset(14, -14), snapResult!.label, cyanColor);
    } else if (snapResult!.type == SnapType.gridAxis) {
      // Фиолетово-пурпурный маркер привязки к строительной/опорной оси
      const axisColor = Color(0xFF9C27B0);
      final purplePaint = Paint()
        ..color = axisColor
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;

      final path = Path()
        ..moveTo(pt.dx - 7, pt.dy - 7)
        ..lineTo(pt.dx + 7, pt.dy + 7)
        ..lineTo(pt.dx - 7, pt.dy + 7)
        ..lineTo(pt.dx + 7, pt.dy - 7)
        ..close();
      canvas.drawPath(path, purplePaint);
      canvas.drawCircle(pt, 12.0, Paint()..color = axisColor.withValues(alpha: 0.15)..style = PaintingStyle.fill);

      _drawSnapBadge(canvas, pt + const Offset(14, -14), snapResult!.label, axisColor);
    } else if (snapResult!.type == SnapType.equipmentFace) {
      // Маркер грани оборудования: круг с перекрестием и ореолом (бирюзовый/cyan)
      const eqSnapColor = Color(0xFF00BCD4);
      final eqPaint = Paint()
        ..color = eqSnapColor
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(pt, 9.0, eqPaint);
      canvas.drawLine(pt - const Offset(6, 0), pt + const Offset(6, 0), eqPaint);
      canvas.drawLine(pt - const Offset(0, 6), pt + const Offset(0, 6), eqPaint);
      canvas.drawCircle(pt, 14.0, Paint()..color = eqSnapColor.withValues(alpha: 0.2)..style = PaintingStyle.fill);

      _drawSnapBadge(canvas, pt + const Offset(16, -14), snapResult!.label, eqSnapColor);
    } else if (snapResult!.type == SnapType.polarAngle) {
      // Направляющий луч от начала трассировки
      final startNode = activeTraceStart ?? activeAxisStart;
      if (startNode != null) {
        final startPt = projector.project(startNode);
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

      // Если HUD не активен, рисуем компактный бейдж полярной привязки
      if (activeTraceStart == null && activeAxisStart == null) {
        _drawSnapBadge(canvas, pt + const Offset(14, -14), snapResult!.label, Colors.amber.shade900);
      }
    } else if (snapResult!.type == SnapType.smartElevationBranch) {
      // Маркер умной разновысотной врезки под 90° (Оранжево-янтарный перпендикуляр + стояк)
      final branchColor = Colors.orange.shade800;
      final branchPaint = Paint()
        ..color = branchColor
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke;

      // Если есть промежуточная точка поворота (отвод 90° на текущей отметке Z)
      if (snapResult!.intermediateTurnPoint != null) {
        final pTurn = projector.project(snapResult!.intermediateTurnPoint!);
        final turnPaint = Paint()
          ..color = branchColor
          ..strokeWidth = 1.8
          ..style = PaintingStyle.stroke;
        // Пунктир вертикального стояка между точкой поворота и точкой врезки в трубу
        _drawDashedLine(canvas, pTurn, pt, turnPaint);
        // Символ угла 90° (отвода) в точке поворота
        canvas.drawCircle(pTurn, 5.0, Paint()..color = Colors.amber.shade600..style = PaintingStyle.fill);
        canvas.drawCircle(pTurn, 5.0, branchPaint);
      }

      // Символ прямого угла и врезки в целевую трубу
      final path = Path()
        ..moveTo(pt.dx - 8, pt.dy - 8)
        ..lineTo(pt.dx - 8, pt.dy + 8)
        ..lineTo(pt.dx + 8, pt.dy + 8);
      path
        ..moveTo(pt.dx - 8, pt.dy + 2)
        ..lineTo(pt.dx - 2, pt.dy + 2)
        ..lineTo(pt.dx - 2, pt.dy + 8);
      canvas.drawPath(path, branchPaint);
      canvas.drawCircle(pt, 13.0, Paint()..color = branchColor.withValues(alpha: 0.22)..style = PaintingStyle.fill);

      _drawSnapBadge(canvas, pt + const Offset(14, -14), snapResult!.label, branchColor);
    } else if (snapResult!.type == SnapType.extensionRay) {
      // AutoCAD OTRACK Extension: продление оси существующей трубы в створе или вертикальный стояк
      final isVerticalRiser = snapResult!.isElevationTransition;
      final rayColor = isVerticalRiser ? Colors.amber.shade700 : const Color(0xFF00E5FF);
      final rayPaint = Paint()
        ..color = rayColor
        ..strokeWidth = isVerticalRiser ? 2.0 : 1.5
        ..style = PaintingStyle.stroke;

      if (snapResult!.trackingSourcePoint != null) {
        final sourcePt = projector.project(snapResult!.trackingSourcePoint!);
        // Пунктирный створ от узла-источника до текущей точки курсора
        _drawDashedLine(canvas, sourcePt, pt, rayPaint);

        // Исходный маркер OTRACK (маленький крестик в начале луча)
        final srcPaint = Paint()
          ..color = rayColor
          ..strokeWidth = 2.0;
        canvas.drawLine(sourcePt - const Offset(5, 0), sourcePt + const Offset(5, 0), srcPaint);
        canvas.drawLine(sourcePt - const Offset(0, 5), sourcePt + const Offset(0, 5), srcPaint);
      }

      // Маркер привязки в створе (AutoCAD Extension Glyph или Vertical Riser Glyph)
      final markerPaint = Paint()
        ..color = rayColor
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;

      if (isVerticalRiser) {
        canvas.drawCircle(pt, 7.0, markerPaint);
        canvas.drawCircle(pt, 13.0, Paint()..color = rayColor.withValues(alpha: 0.2)..style = PaintingStyle.fill);
        // Стрелка направления стояка (вверх или вниз)
        final isUp = (snapResult!.elevationDeltaMm ?? 0.0) >= 0;
        final arrowPath = Path();
        if (isUp) {
          arrowPath.moveTo(pt.dx, pt.dy - 4);
          arrowPath.lineTo(pt.dx - 3, pt.dy + 2);
          arrowPath.lineTo(pt.dx + 3, pt.dy + 2);
        } else {
          arrowPath.moveTo(pt.dx, pt.dy + 4);
          arrowPath.lineTo(pt.dx - 3, pt.dy - 2);
          arrowPath.lineTo(pt.dx + 3, pt.dy - 2);
        }
        arrowPath.close();
        canvas.drawPath(arrowPath, Paint()..color = rayColor..style = PaintingStyle.fill);
      } else {
        canvas.drawLine(pt - const Offset(6, 6), pt + const Offset(6, 6), markerPaint);
        canvas.drawLine(pt - const Offset(-6, 6), pt + const Offset(-6, 6), markerPaint);
        canvas.drawCircle(pt, 12.0, Paint()..color = rayColor.withValues(alpha: 0.18)..style = PaintingStyle.fill);
      }

      _drawSnapBadge(canvas, pt + const Offset(14, -14), snapResult!.label, rayColor);
    } else if (snapResult!.type == SnapType.alignmentGuide) {
      // AutoCAD/Revit OTRACK Alignment: ортогональная направляющая от ключевого узла
      const alignColor = Color(0xFF00E5FF); // Яркий бирюзовый Cyan
      final alignPaint = Paint()
        ..color = alignColor
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke;

      if (snapResult!.trackingSourcePoint != null) {
        final sourcePt = projector.project(snapResult!.trackingSourcePoint!);
        // Направляющая линия от узла-ориентира
        _drawDashedLine(canvas, sourcePt, pt, alignPaint);

        // Маркер захвата узла OTRACK (маленький прямой крестик +)
        final srcPaint = Paint()
          ..color = alignColor
          ..strokeWidth = 2.0;
        canvas.drawLine(sourcePt - const Offset(5, 0), sourcePt + const Offset(5, 0), srcPaint);
        canvas.drawLine(sourcePt - const Offset(0, 5), sourcePt + const Offset(0, 5), srcPaint);
      }

      // Маркер выравнивания в точке курсора (перекрестие с точкой)
      final markerPaint = Paint()
        ..color = alignColor
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(pt, 6.0, markerPaint);
      canvas.drawCircle(pt, 2.0, Paint()..color = alignColor..style = PaintingStyle.fill);
      canvas.drawCircle(pt, 12.0, Paint()..color = alignColor.withValues(alpha: 0.18)..style = PaintingStyle.fill);

      _drawSnapBadge(canvas, pt + const Offset(14, -14), snapResult!.label, const Color(0xFF00B0FF));
    }
  }

  /// Вычисление информации о длине и угле для HUD трассировки
  static TraceHudInfo computeTraceHudInfo(Node3D startNode, Node3D endNode) {
    final lengthMm = startNode.distanceTo(endNode);

    final dx = endNode.x - startNode.x;
    final dy = endNode.y - startNode.y;
    double angleDeg = 0.0;
    if (dx.abs() > 0.001 || dy.abs() > 0.001) {
      angleDeg = math.atan2(dy, dx) * 180.0 / math.pi;
      if (angleDeg < 0) {
        angleDeg += 360.0;
      }
    }
    final angleInt = angleDeg.round() % 360;
    final text = 'L: ${lengthMm.round()} мм | ∠: $angleInt°';

    return TraceHudInfo(
      lengthMm: lengthMm,
      angleDegrees: angleInt,
      text: text,
    );
  }

  /// Вычисление экранной позиции бейджа HUD с защитой от перекрытия курсора и выхода за границы экрана
  static Offset computeBadgePosition({
    required Offset cursorOffset,
    required Size badgeSize,
    required Size canvasSize,
    double offsetDistance = 16.0,
  }) {
    double posX = cursorOffset.dx + offsetDistance;
    double posY = cursorOffset.dy + offsetDistance;

    if (canvasSize.width.isFinite && posX + badgeSize.width > canvasSize.width - 8) {
      posX = cursorOffset.dx - offsetDistance - badgeSize.width;
    }
    if (canvasSize.height.isFinite && posY + badgeSize.height > canvasSize.height - 8) {
      posY = cursorOffset.dy - offsetDistance - badgeSize.height;
    }
    if (posX < 8) posX = 8;
    if (posY < 8) posY = 8;

    return Offset(posX, posY);
  }

  void _drawTraceHud(Canvas canvas, Size size) {
    final startNode = activeTraceStart ?? activeAxisStart;
    if (startNode == null || activeTraceEnd == null) return;

    final endNode = (snapResult != null && snapResult!.type != SnapType.none)
        ? snapResult!.worldPoint
        : projector.unproject(activeTraceEnd!, currentElevationZ);

    final hudInfo = computeTraceHudInfo(startNode, endNode);
    final isPolarLocked = snapResult?.type == SnapType.polarAngle;

    final tp = TextPainter(
      text: TextSpan(
        text: hudInfo.text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const paddingH = 8.0;
    const paddingV = 4.0;
    final badgeSize = Size(tp.width + paddingH * 2, tp.height + paddingV * 2);

    final effectiveScreenEnd = (snapResult != null && snapResult!.type != SnapType.none)
        ? snapResult!.screenPoint
        : activeTraceEnd!;

    final badgePos = computeBadgePosition(
      cursorOffset: effectiveScreenEnd,
      badgeSize: badgeSize,
      canvasSize: size,
    );

    final badgeRect = Rect.fromLTWH(badgePos.dx, badgePos.dy, badgeSize.width, badgeSize.height);
    final rrect = RRect.fromRectAndRadius(badgeRect, const Radius.circular(6.0));

    // Тень бейджа для читаемости на любом фоне холста
    canvas.drawShadow(
      Path()..addRRect(rrect),
      Colors.black.withValues(alpha: 0.45),
      4.0,
      false,
    );

    // Полупрозрачный темный фон
    final bgPaint = Paint()
      ..color = const Color(0xE61E293B) // Slate 800 с 90% непрозрачностью
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, bgPaint);

    // Рамка бейджа (золотистая при фиксации полярного угла, полупрозрачная белая в обычном режиме)
    final borderPaint = Paint()
      ..color = isPolarLocked ? Colors.amber.shade600 : const Color(0x33FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(rrect, borderPaint);

    // Отрисовка текста
    tp.paint(canvas, Offset(badgePos.dx + paddingH, badgePos.dy + paddingV));
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

  void _drawAcquiredTrackingPoints(Canvas canvas) {
    if (acquiredPoints == null || acquiredPoints!.isEmpty) return;

    final crossPaint = Paint()
      ..color = Colors.amber.shade700
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;

    final bgGlow = Paint()
      ..color = Colors.amber.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    for (final acq in acquiredPoints!) {
      final pt = projector.project(acq.worldPoint);
      canvas.drawCircle(pt, 9.0, bgGlow);
      // Прямой крестик CAD (+) с центральным разрывом
      canvas.drawLine(pt - const Offset(7, 0), pt - const Offset(2, 0), crossPaint);
      canvas.drawLine(pt + const Offset(2, 0), pt + const Offset(7, 0), crossPaint);
      canvas.drawLine(pt - const Offset(0, 7), pt - const Offset(0, 2), crossPaint);
      canvas.drawLine(pt + const Offset(0, 2), pt + const Offset(0, 7), crossPaint);
    }
  }

  void _drawZPlaneGrid(Canvas canvas, Size size) {
    final pCenter = projector.unproject(Offset(size.width / 2, size.height / 2), currentElevationZ);
    final spanMm = (size.longestSide / projector.scale) * 0.9;
    const stepMm = 1000.0;

    final minX = ((pCenter.x - spanMm) / stepMm).floor() * stepMm;
    final maxX = ((pCenter.x + spanMm) / stepMm).ceil() * stepMm;
    final minY = ((pCenter.y - spanMm) / stepMm).floor() * stepMm;
    final maxY = ((pCenter.y + spanMm) / stepMm).ceil() * stepMm;

    final gridPaint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.12)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final borderPaint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.40)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;

    final gridPath = Path();
    for (double x = minX; x <= maxX + 1e-4; x += stepMm) {
      final p1 = projector.projectCoordinates(x, minY, currentElevationZ);
      final p2 = projector.projectCoordinates(x, maxY, currentElevationZ);
      gridPath.moveTo(p1.dx, p1.dy);
      gridPath.lineTo(p2.dx, p2.dy);
    }
    for (double y = minY; y <= maxY + 1e-4; y += stepMm) {
      final p1 = projector.projectCoordinates(minX, y, currentElevationZ);
      final p2 = projector.projectCoordinates(maxX, y, currentElevationZ);
      gridPath.moveTo(p1.dx, p1.dy);
      gridPath.lineTo(p2.dx, p2.dy);
    }
    canvas.drawPath(gridPath, gridPaint);

    // Внешняя рамка активной рабочей плоскости
    final c1 = projector.projectCoordinates(minX, minY, currentElevationZ);
    final c2 = projector.projectCoordinates(maxX, minY, currentElevationZ);
    final c3 = projector.projectCoordinates(maxX, maxY, currentElevationZ);
    final c4 = projector.projectCoordinates(minX, maxY, currentElevationZ);
    final borderPath = Path()
      ..moveTo(c1.dx, c1.dy)
      ..lineTo(c2.dx, c2.dy)
      ..lineTo(c3.dx, c3.dy)
      ..lineTo(c4.dx, c4.dy)
      ..close();
    canvas.drawPath(borderPath, borderPaint);

    // Информационный бейдж рабочей плоскости
    final elevM = (currentElevationZ / 1000.0).toStringAsFixed(3);
    final sign = currentElevationZ >= 0 ? '+' : '';
    final label = 'Рабочая плоскость Z: ∇$sign$elevM м';
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xFF00E5FF),
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.4,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final badgePos = c1 + const Offset(12, 12);
    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(badgePos.dx - 6, badgePos.dy - 3, tp.width + 12, tp.height + 6),
      const Radius.circular(4),
    );
    canvas.drawRRect(badgeRect, Paint()..color = const Color(0xCC002B36));
    canvas.drawRRect(
      badgeRect,
      Paint()
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    tp.paint(canvas, badgePos);
  }

  @override
  bool shouldRepaint(covariant PipingCanvasPainter oldDelegate) {
    return true;
  }
}
