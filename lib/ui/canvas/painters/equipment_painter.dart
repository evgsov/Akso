import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/math/axonometry_projector.dart';
import '../../../domain/models/equipment.dart';
import '../../../domain/models/piping_network.dart';

/// Отрисовщик технологического оборудования и штуцеров на аксонометрическом холсте
class EquipmentPainter {
  static void paint(
    Canvas canvas,
    AxonometryProjector projector,
    PipingNetwork network, {
    String? selectedEquipmentId,
    String? selectedNodeId,
  }) {
    if (network.equipments.isEmpty) return;

    for (final eq in network.equipments.values) {
      final isSelected = eq.id == selectedEquipmentId ||
          (selectedNodeId != null &&
              network.nodes[selectedNodeId]?.equipmentId == eq.id);

      _paintEquipmentBody(canvas, projector, eq, isSelected);
      _paintNozzles(canvas, projector, eq, selectedNodeId);
      _paintEquipmentLabel(canvas, projector, eq, isSelected);
    }
  }

  static void _paintEquipmentBody(
    Canvas canvas,
    AxonometryProjector projector,
    Equipment eq,
    bool isSelected,
  ) {
    final fillPaint = Paint()
      ..color = isSelected
          ? const Color(0x3500BCD4)
          : const Color(0x201565C0)
      ..style = PaintingStyle.fill;

    final edgePaint = Paint()
      ..color = isSelected
          ? const Color(0xFF00ACC1)
          : const Color(0xFF1565C0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = isSelected ? 2.0 : 1.4;

    switch (eq.type) {
      case EquipmentType.box:
        _paintBox(canvas, projector, eq, fillPaint, edgePaint);
        break;
      case EquipmentType.cylinderVertical:
        _paintVerticalCylinder(canvas, projector, eq, fillPaint, edgePaint);
        break;
      case EquipmentType.cylinderHorizontal:
        _paintHorizontalCylinder(canvas, projector, eq, fillPaint, edgePaint);
        break;
    }
  }

  static void _paintBox(
    Canvas canvas,
    AxonometryProjector projector,
    Equipment eq,
    Paint fillPaint,
    Paint edgePaint,
  ) {
    final x1 = eq.x - eq.width / 2;
    final x2 = eq.x + eq.width / 2;
    final y1 = eq.y - eq.length / 2;
    final y2 = eq.y + eq.length / 2;
    final z1 = eq.z;
    final z2 = eq.z + eq.height;

    final p0 = projector.projectCoordinates(x1, y1, z1);
    final p1 = projector.projectCoordinates(x2, y1, z1);
    final p2 = projector.projectCoordinates(x2, y2, z1);
    final p3 = projector.projectCoordinates(x1, y2, z1);

    final p4 = projector.projectCoordinates(x1, y1, z2);
    final p5 = projector.projectCoordinates(x2, y1, z2);
    final p6 = projector.projectCoordinates(x2, y2, z2);
    final p7 = projector.projectCoordinates(x1, y2, z2);

    void drawQuad(Offset a, Offset b, Offset c, Offset d) {
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy)
        ..lineTo(c.dx, c.dy)
        ..lineTo(d.dx, d.dy)
        ..close();
      canvas.drawPath(path, fillPaint);
    }

    // Грани параллелепипеда
    drawQuad(p0, p1, p2, p3); // низ
    drawQuad(p4, p5, p6, p7); // верх
    drawQuad(p0, p1, p5, p4); // перед
    drawQuad(p1, p2, p6, p5); // право
    drawQuad(p2, p3, p7, p6); // зад
    drawQuad(p3, p0, p4, p7); // лево

    // 12 ребер
    final edges = [
      (p0, p1), (p1, p2), (p2, p3), (p3, p0),
      (p4, p5), (p5, p6), (p6, p7), (p7, p4),
      (p0, p4), (p1, p5), (p2, p6), (p3, p7),
    ];
    for (final edge in edges) {
      canvas.drawLine(edge.$1, edge.$2, edgePaint);
    }
  }

  static void _paintVerticalCylinder(
    Canvas canvas,
    AxonometryProjector projector,
    Equipment eq,
    Paint fillPaint,
    Paint edgePaint,
  ) {
    final radius = eq.width / 2;
    final segments = 16;
    final bottomPts = <Offset>[];
    final topPts = <Offset>[];

    for (int i = 0; i < segments; i++) {
      final angle = (2 * math.pi * i) / segments;
      final vx = eq.x + radius * math.cos(angle);
      final vy = eq.y + radius * math.sin(angle);
      bottomPts.add(projector.projectCoordinates(vx, vy, eq.z));
      topPts.add(projector.projectCoordinates(vx, vy, eq.z + eq.height));
    }

    // Заливка боковых секторов
    for (int i = 0; i < segments; i++) {
      final next = (i + 1) % segments;
      final quad = Path()
        ..moveTo(bottomPts[i].dx, bottomPts[i].dy)
        ..lineTo(bottomPts[next].dx, bottomPts[next].dy)
        ..lineTo(topPts[next].dx, topPts[next].dy)
        ..lineTo(topPts[i].dx, topPts[i].dy)
        ..close();
      canvas.drawPath(quad, fillPaint);
    }

    // Заливка оснований
    final bottomCap = Path()..addPolygon(bottomPts, true);
    final topCap = Path()..addPolygon(topPts, true);
    canvas.drawPath(bottomCap, fillPaint);
    canvas.drawPath(topCap, fillPaint);

    // Линии оснований
    canvas.drawPath(bottomCap, edgePaint);
    canvas.drawPath(topCap, edgePaint);

    // Вертикальные образующие ребра
    for (int i = 0; i < segments; i += segments ~/ 4) {
      canvas.drawLine(bottomPts[i], topPts[i], edgePaint);
    }
  }

  static void _paintHorizontalCylinder(
    Canvas canvas,
    AxonometryProjector projector,
    Equipment eq,
    Paint fillPaint,
    Paint edgePaint,
  ) {
    // Горизонтальный цилиндр по оси Y
    final radius = eq.height / 2;
    final segments = 16;
    final yStart = eq.y - eq.length / 2;
    final yEnd = eq.y + eq.length / 2;
    final centerZ = eq.z + radius;

    final startCapPts = <Offset>[];
    final endCapPts = <Offset>[];

    for (int i = 0; i < segments; i++) {
      final angle = (2 * math.pi * i) / segments;
      final vx = eq.x + radius * math.cos(angle);
      final vz = centerZ + radius * math.sin(angle);
      startCapPts.add(projector.projectCoordinates(vx, yStart, vz));
      endCapPts.add(projector.projectCoordinates(vx, yEnd, vz));
    }

    for (int i = 0; i < segments; i++) {
      final next = (i + 1) % segments;
      final quad = Path()
        ..moveTo(startCapPts[i].dx, startCapPts[i].dy)
        ..lineTo(startCapPts[next].dx, startCapPts[next].dy)
        ..lineTo(endCapPts[next].dx, endCapPts[next].dy)
        ..lineTo(endCapPts[i].dx, endCapPts[i].dy)
        ..close();
      canvas.drawPath(quad, fillPaint);
    }

    final startCap = Path()..addPolygon(startCapPts, true);
    final endCap = Path()..addPolygon(endCapPts, true);
    canvas.drawPath(startCap, fillPaint);
    canvas.drawPath(endCap, fillPaint);
    canvas.drawPath(startCap, edgePaint);
    canvas.drawPath(endCap, edgePaint);

    for (int i = 0; i < segments; i += segments ~/ 4) {
      canvas.drawLine(startCapPts[i], endCapPts[i], edgePaint);
    }
  }

  static void _paintNozzles(
    Canvas canvas,
    AxonometryProjector projector,
    Equipment eq,
    String? selectedNodeId,
  ) {
    final nozzlePaint = Paint()
      ..color = const Color(0xFF00838F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final flangePaint = Paint()
      ..color = const Color(0xFF006064)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;

    final nodeFillPaint = Paint()
      ..color = const Color(0xFF00ACC1)
      ..style = PaintingStyle.fill;

    for (final nozzle in eq.nozzles) {
      final isNodeSelected = nozzle.id == selectedNodeId;

      final nx = eq.x + nozzle.localX;
      final ny = eq.y + nozzle.localY;
      final nz = eq.z + nozzle.localZ;
      final pNozzle = projector.projectCoordinates(nx, ny, nz);

      // Отрезок штуцера наружу (200 мм)
      final dLen = math.sqrt(
          nozzle.dirX * nozzle.dirX + nozzle.dirY * nozzle.dirY + nozzle.dirZ * nozzle.dirZ);
      final ndx = dLen > 0 ? nozzle.dirX / dLen : 0.0;
      final ndy = dLen > 0 ? nozzle.dirY / dLen : 0.0;
      final ndz = dLen > 0 ? nozzle.dirZ / dLen : 1.0;

      final endX = nx + ndx * 200.0;
      final endY = ny + ndy * 200.0;
      final endZ = nz + ndz * 200.0;
      final pEnd = projector.projectCoordinates(endX, endY, endZ);

      // Рисуем патрубок
      canvas.drawLine(pNozzle, pEnd, nozzlePaint);

      // Засечка фланца на конце патрубка
      final stubDx = pEnd.dx - pNozzle.dx;
      final stubDy = pEnd.dy - pNozzle.dy;
      final stubLen = math.sqrt(stubDx * stubDx + stubDy * stubDy);
      if (stubLen > 1.0) {
        final perpX = -stubDy / stubLen * 6.0;
        final perpY = stubDx / stubLen * 6.0;
        canvas.drawLine(
          Offset(pEnd.dx + perpX, pEnd.dy + perpY),
          Offset(pEnd.dx - perpX, pEnd.dy - perpY),
          flangePaint,
        );
      }

      // Маркер штуцера в точке подключения (pNozzle)
      if (isNodeSelected) {
        final haloPaint = Paint()
          ..color = const Color(0xFFFFB300)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0;
        canvas.drawCircle(pNozzle, 7.0, haloPaint);
      }

      canvas.drawCircle(pNozzle, 4.0, nodeFillPaint);
      canvas.drawCircle(
        pNozzle,
        4.0,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );

      // Подпись штуцера: "Ш-1 (Ду50)"
      _drawNozzleText(
        canvas,
        pNozzle + const Offset(10, -14),
        '${nozzle.name} (Ду${nozzle.dn})',
        isNodeSelected,
      );
    }
  }

  static void _paintEquipmentLabel(
    Canvas canvas,
    AxonometryProjector projector,
    Equipment eq,
    bool isSelected,
  ) {
    final topCenter = projector.projectCoordinates(eq.x, eq.y, eq.z + eq.height);
    final textSpan = TextSpan(
      text: eq.name,
      style: TextStyle(
        color: isSelected ? const Color(0xFF006064) : const Color(0xFF0D47A1),
        fontSize: 11,
        fontWeight: FontWeight.bold,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    final bgRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: topCenter - const Offset(0, 16),
        width: textPainter.width + 12,
        height: textPainter.height + 6,
      ),
      const Radius.circular(4),
    );

    final bgPaint = Paint()
      ..color = isSelected ? const Color(0xFFE0F7FA) : const Color(0xEEF5F9FF)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = isSelected ? const Color(0xFF00ACC1) : const Color(0xFF90CAF9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawRRect(bgRect, bgPaint);
    canvas.drawRRect(bgRect, borderPaint);

    textPainter.paint(
      canvas,
      Offset(
        bgRect.left + 6,
        bgRect.top + 3,
      ),
    );
  }

  static void _drawNozzleText(
    Canvas canvas,
    Offset position,
    String text,
    bool isSelected,
  ) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: isSelected ? const Color(0xFFE65100) : const Color(0xFF006064),
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        position.dx - 4,
        position.dy - 2,
        textPainter.width + 8,
        textPainter.height + 4,
      ),
      const Radius.circular(3),
    );

    canvas.drawRRect(
      bgRect,
      Paint()
        ..color = const Color(0xEEFFFFFF)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      bgRect,
      Paint()
        ..color = isSelected ? const Color(0xFFFFB300) : const Color(0xFFB2EBF2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    textPainter.paint(canvas, position);
  }
}
