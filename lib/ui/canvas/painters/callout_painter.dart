import 'package:flutter/material.dart';

import '../../../core/math/axonometry_projector.dart';
import '../../../domain/models/callout.dart';
import '../../../domain/models/node_3d.dart';
import '../../../domain/models/piping_network.dart';
import '../../../domain/models/project_model.dart';

/// Отрисовщик умных выносок (Callout) на аксонометрическом холсте
/// с экранным автовыравниванием по ГОСТ 2.316 / ГОСТ 21.101.
class CalloutPainter {
  final PipingNetwork network;
  final AxonometryProjector projector;
  final ProjectModel? project;
  final Map<String, String>? templates;
  final String? selectedCalloutId;

  const CalloutPainter({
    required this.network,
    required this.projector,
    this.project,
    this.templates,
    this.selectedCalloutId,
  });

  /// Отрисовка всех выносок через экземпляр класса
  void paintCallouts(Canvas canvas) {
    paint(
      canvas,
      projector,
      network,
      project: project,
      templates: templates ?? project?.calloutTemplates,
      selectedCalloutId: selectedCalloutId,
    );
  }

  /// Статический метод отрисовки умных выносок сети
  static void paint(
    Canvas canvas,
    AxonometryProjector projector,
    PipingNetwork network, {
    ProjectModel? project,
    Map<String, String>? templates,
    String? selectedCalloutId,
  }) {
    if (network.callouts.isEmpty) return;

    final effectiveTemplates = templates ?? project?.calloutTemplates ?? defaultCalloutTemplates;

    for (final callout in network.callouts.values) {
      final anchor3D = getTarget3DPoint(network, callout);
      if (anchor3D == null) continue;

      final anchorScreen = projector.project(anchor3D);
      final isSelected = callout.id == selectedCalloutId;

      _paintSingleCallout(
        canvas,
        network,
        callout,
        anchorScreen,
        effectiveTemplates,
        isSelected,
      );
    }
  }

  /// Вычисляет абсолютную 3D-точку привязки для выноски:
  /// - для узла — координаты узла;
  /// - для сегмента — геометрическая середина сегмента;
  /// - для арматуры/стыка/опоры — положение на сегменте по ratio;
  /// - для оборудования — центр оборудования.
  static Node3D? getTarget3DPoint(PipingNetwork network, Callout callout) {
    switch (callout.targetType) {
      case CalloutTargetType.node:
        return network.nodes[callout.targetId];

      case CalloutTargetType.segment:
        final seg = network.segments[callout.targetId];
        if (seg == null) return null;
        final start = network.nodes[seg.startNodeId];
        final end = network.nodes[seg.endNodeId];
        if (start == null || end == null) return null;
        return Node3D(
          id: 'anchor_${callout.id}',
          x: (start.x + end.x) / 2.0,
          y: (start.y + end.y) / 2.0,
          z: (start.z + end.z) / 2.0,
        );

      case CalloutTargetType.valve:
        final valve = network.valves[callout.targetId];
        if (valve == null) return null;
        final seg = network.segments[valve.segmentId];
        if (seg == null) return null;
        final start = network.nodes[seg.startNodeId];
        final end = network.nodes[seg.endNodeId];
        if (start == null || end == null) return null;
        return Node3D(
          id: 'anchor_${callout.id}',
          x: start.x + (end.x - start.x) * valve.ratio,
          y: start.y + (end.y - start.y) * valve.ratio,
          z: start.z + (end.z - start.z) * valve.ratio,
        );

      case CalloutTargetType.weld:
        final weld = network.weldJoints[callout.targetId];
        if (weld == null) return null;
        final seg = network.segments[weld.segmentId];
        if (seg == null) return null;
        final start = network.nodes[seg.startNodeId];
        final end = network.nodes[seg.endNodeId];
        if (start == null || end == null) return null;
        return Node3D(
          id: 'anchor_${callout.id}',
          x: start.x + (end.x - start.x) * weld.ratio,
          y: start.y + (end.y - start.y) * weld.ratio,
          z: start.z + (end.z - start.z) * weld.ratio,
        );

      case CalloutTargetType.support:
        final sup = network.supports[callout.targetId];
        if (sup == null) return null;
        final seg = network.segments[sup.segmentId];
        if (seg == null) return null;
        final start = network.nodes[seg.startNodeId];
        final end = network.nodes[seg.endNodeId];
        if (start == null || end == null) return null;
        final r = sup.distanceRatio.clamp(0.0, 1.0);
        return Node3D(
          id: 'anchor_${callout.id}',
          x: start.x + (end.x - start.x) * r,
          y: start.y + (end.y - start.y) * r,
          z: start.z + (end.z - start.z) * r,
        );

      case CalloutTargetType.equipment:
        final eq = network.equipments[callout.targetId];
        if (eq == null) return null;
        return Node3D(
          id: 'anchor_${callout.id}',
          x: eq.x,
          y: eq.y,
          z: eq.z + eq.height / 2.0,
        );

      case CalloutTargetType.fitting:
        final fit = network.fittings[callout.targetId] ??
            network.fittings.values.where((f) => f.id == callout.targetId).firstOrNull;
        if (fit == null) return null;
        return network.nodes[fit.nodeId];
    }
  }

  /// Получение экранных границ (bounding box) текста и полочки выноски для hit-test
  static Rect? getCalloutBounds(
    PipingNetwork network,
    AxonometryProjector projector,
    Callout callout, {
    Map<String, String>? templates,
    ProjectModel? project,
  }) {
    final anchor3D = getTarget3DPoint(network, callout);
    if (anchor3D == null) return null;

    final anchorScreen = projector.project(anchor3D);
    final textPos = Offset(
      anchorScreen.dx + callout.screenOffsetX,
      anchorScreen.dy + callout.screenOffsetY,
    );

    final effectiveTemplates = templates ?? project?.calloutTemplates ?? defaultCalloutTemplates;
    final text = network.generateCalloutText(callout, effectiveTemplates);

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: callout.textHeight,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final isRight = callout.screenOffsetX >= 0;
    if (isRight) {
      return Rect.fromLTWH(
        textPos.dx,
        textPos.dy - tp.height - 4.0,
        tp.width + 10.0,
        tp.height + 6.0,
      );
    } else {
      return Rect.fromLTWH(
        textPos.dx - tp.width - 10.0,
        textPos.dy - tp.height - 4.0,
        tp.width + 10.0,
        tp.height + 6.0,
      );
    }
  }

  /// Проверка попадания клика в текст выноски (hit test)
  static String? hitTest(
    Offset screenPos,
    PipingNetwork network,
    AxonometryProjector projector, {
    Map<String, String>? templates,
    ProjectModel? project,
    double hitTolerance = 6.0,
  }) {
    // Проверяем в обратном порядке (верхние выноски первыми)
    final calloutList = network.callouts.values.toList().reversed;
    for (final callout in calloutList) {
      final bounds = getCalloutBounds(
        network,
        projector,
        callout,
        templates: templates,
        project: project,
      );
      if (bounds != null && bounds.inflate(hitTolerance).contains(screenPos)) {
        return callout.id;
      }
    }
    return null;
  }

  static void _paintSingleCallout(
    Canvas canvas,
    PipingNetwork network,
    Callout callout,
    Offset anchorScreen,
    Map<String, String> templates,
    bool isSelected,
  ) {
    final textPos = Offset(
      anchorScreen.dx + callout.screenOffsetX,
      anchorScreen.dy + callout.screenOffsetY,
    );

    final text = network.generateCalloutText(callout, templates);
    final isRight = callout.screenOffsetX >= 0;

    final primaryColor = isSelected ? const Color(0xFF2563EB) : Color(callout.textColor);

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: primaryColor,
          fontSize: callout.textHeight,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final shelfLength = tp.width + 8.0;
    final shelfEnd = Offset(
      isRight ? textPos.dx + shelfLength : textPos.dx - shelfLength,
      textPos.dy,
    );

    // 1. Точка привязки (кружок на 3D объекте по ГОСТ)
    final dotPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(anchorScreen, 3.0, dotPaint);

    // 2. Наклонная линия-ножка от объекта до излома (textPos)
    final linePaint = Paint()
      ..color = primaryColor
      ..strokeWidth = isSelected ? 2.0 : 1.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawLine(anchorScreen, textPos, linePaint);

    // 3. Горизонтальная полочка выноски (подчеркивание текста по ГОСТ 2.316)
    canvas.drawLine(textPos, shelfEnd, linePaint);

    // 4. Прямоугольник текста и фон (чтобы линии чертежа сзади не мешали чтению)
    final textLeft = isRight ? textPos.dx + 4.0 : textPos.dx - shelfLength + 4.0;
    final textTop = textPos.dy - tp.height - 2.0;

    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        isRight ? textPos.dx : textPos.dx - shelfLength,
        textPos.dy - tp.height - 4.0,
        shelfLength,
        tp.height + 4.0,
      ),
      const Radius.circular(3.0),
    );

    canvas.drawRRect(
      bgRect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.88)
        ..style = PaintingStyle.fill,
    );

    // Отрисовка текста над полочкой
    tp.paint(canvas, Offset(textLeft, textTop));

    // 5. Визуальный маркер выделения выноски (CAD handle/grip)
    if (isSelected) {
      final borderPaint = Paint()
        ..color = const Color(0xFF2563EB).withValues(alpha: 0.75)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      canvas.drawRRect(bgRect, borderPaint);

      // Ручка перетаскивания (Grip point) в точке излома
      final gripPaint = Paint()
        ..color = const Color(0xFF2563EB)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(textPos, 3.5, gripPaint);
      canvas.drawCircle(
        textPos,
        3.5,
        Paint()
          ..color = Colors.white
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke,
      );
    }
  }
}
