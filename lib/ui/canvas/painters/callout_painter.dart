import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../core/math/axonometry_projector.dart';
import '../../../domain/models/callout.dart';
import '../../../domain/models/drawing_sheet.dart';
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
  final Set<CalloutTargetType>? hiddenTypes;

  const CalloutPainter({
    required this.network,
    required this.projector,
    this.project,
    this.templates,
    this.selectedCalloutId,
    this.hiddenTypes,
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
      hiddenTypes: hiddenTypes,
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
    double annotationScale = 1.0,
    bool isPaperSpace = false,
    String? activeSheetId,
    Set<CalloutTargetType>? hiddenTypes,
  }) {
    if (network.callouts.isEmpty) return;

    final effectiveTemplates = templates ?? project?.calloutTemplates ?? defaultCalloutTemplates;

    if (!isPaperSpace) {
      // В 3D-пространстве модели отрисовываем выноски независимо
      for (final callout in network.callouts.values) {
        if (callout.isHidden) continue;
        if (hiddenTypes != null && hiddenTypes.contains(callout.targetType)) continue;

        final anchor3D = getTarget3DPoint(network, callout);
        if (anchor3D == null) continue;

        final anchorScreen = projector.project(anchor3D);
        final isSelected = callout.id == selectedCalloutId;

        _paintSingleCallout(
          canvas,
          projector,
          network,
          callout,
          anchorScreen,
          effectiveTemplates,
          isSelected,
          annotationScale: annotationScale,
          isPaperSpace: false,
          activeSheetId: activeSheetId,
        );
      }
      return;
    }

    // В пространстве чертежного листа: группируем этажерки по ГОСТ 2.316
    final canvasItems = <_CanvasCalloutDrawItem>[];
    for (final callout in network.callouts.values) {
      if (callout.isHidden) continue;
      if (hiddenTypes != null && hiddenTypes.contains(callout.targetType)) continue;

      final anchor3D = getTarget3DPoint(network, callout);
      if (anchor3D == null) continue;

      final anchorScreen = projector.project(anchor3D);
      final isSelected = callout.id == selectedCalloutId;

      final effOffsetX = activeSheetId != null ? callout.getEffectiveOffsetX(activeSheetId) : callout.screenOffsetX;
      final effOffsetY = activeSheetId != null ? callout.getEffectiveOffsetY(activeSheetId) : callout.screenOffsetY;
      final scaledOffsetX = effOffsetX * 0.35 * annotationScale;
      final scaledOffsetY = effOffsetY * 0.35 * annotationScale;
      final textPos = Offset(
        anchorScreen.dx + scaledOffsetX,
        anchorScreen.dy + scaledOffsetY,
      );
      final isRight = callout.shelfDirection == ShelfDirection.right
          ? true
          : (callout.shelfDirection == ShelfDirection.left
              ? false
              : scaledOffsetX >= 0);

      canvasItems.add(_CanvasCalloutDrawItem(
        callout: callout,
        anchorScreen: anchorScreen,
        textPos: textPos,
        isSelected: isSelected,
        isRight: isRight,
      ));
    }

    // Отрисовываем каждую выноску индивидуально с собственной стрелкой-ножкой
    for (int i = 0; i < canvasItems.length; i++) {
      final item = canvasItems[i];
      _paintSingleCallout(
        canvas,
        projector,
        network,
        item.callout,
        item.anchorScreen,
        effectiveTemplates,
        item.isSelected,
        annotationScale: annotationScale,
        isPaperSpace: true,
        activeSheetId: activeSheetId,
      );
    }
  }

  /// Вычисляет абсолютную 3D-точку привязки для выноски:
  /// - для узла — координаты узла;
  /// - для сегмента — геометрическая середина сегмента;
  /// - для арматуры/стыка/опоры — положение на сегменте по ratio;
  /// - для оборудования — центр оборудования.
  static Node3D? getTarget3DPoint(PipingNetwork network, Callout callout) {
    return getTarget3DPointForTarget(network, callout.targetType, callout.targetId);
  }

  /// Вычисляет абсолютную 3D-точку привязки для целевого объекта сети по типу и ID
  static Node3D? getTarget3DPointForTarget(
    PipingNetwork network,
    CalloutTargetType targetType,
    String targetId,
  ) {
    switch (targetType) {
      case CalloutTargetType.node:
        return network.nodes[targetId];

      case CalloutTargetType.segment:
        // 1. Проверяем, не привязана ли выноска напрямую к физической катушке
        final spool = network.spools[targetId];
        if (spool != null && spool.startPoint != null && spool.endPoint != null) {
          return Node3D(
            id: 'anchor_$targetId',
            x: (spool.startPoint!.x + spool.endPoint!.x) / 2.0,
            y: (spool.startPoint!.y + spool.endPoint!.y) / 2.0,
            z: (spool.startPoint!.z + spool.endPoint!.z) / 2.0,
          );
        }

        final seg = network.segments[targetId] ??
            (spool != null ? network.segments[spool.segmentId] : null);
        if (seg == null) return null;

        // 2. Если выноска привязана к сегменту, у которого ровно одна катушка —
        // привязываем стрелку к геометрической середине физической трубы катушки
        final segSpools = network.spools.values.where((s) => s.segmentId == seg.id).toList();
        if (segSpools.length == 1 &&
            segSpools.first.startPoint != null &&
            segSpools.first.endPoint != null) {
          final s = segSpools.first;
          return Node3D(
            id: 'anchor_$targetId',
            x: (s.startPoint!.x + s.endPoint!.x) / 2.0,
            y: (s.startPoint!.y + s.endPoint!.y) / 2.0,
            z: (s.startPoint!.z + s.endPoint!.z) / 2.0,
          );
        }

        // 3. Иначе привязываем к середине осевой линии сегмента
        final start = network.nodes[seg.startNodeId];
        final end = network.nodes[seg.endNodeId];
        if (start == null || end == null) return null;
        return Node3D(
          id: 'anchor_$targetId',
          x: (start.x + end.x) / 2.0,
          y: (start.y + end.y) / 2.0,
          z: (start.z + end.z) / 2.0,
        );

      case CalloutTargetType.valve:
        final valve = network.valves[targetId];
        if (valve == null) return null;
        final seg = network.segments[valve.segmentId];
        if (seg == null) return null;
        final start = network.nodes[seg.startNodeId];
        final end = network.nodes[seg.endNodeId];
        if (start == null || end == null) return null;
        return Node3D(
          id: 'anchor_$targetId',
          x: start.x + (end.x - start.x) * valve.ratio,
          y: start.y + (end.y - start.y) * valve.ratio,
          z: start.z + (end.z - start.z) * valve.ratio,
        );

      case CalloutTargetType.weld:
        final weld = network.weldJoints[targetId];
        if (weld == null) return null;
        final seg = network.segments[weld.segmentId];
        if (seg == null) return null;
        final start = network.nodes[seg.startNodeId];
        final end = network.nodes[seg.endNodeId];
        if (start == null || end == null) return null;
        return Node3D(
          id: 'anchor_$targetId',
          x: start.x + (end.x - start.x) * weld.ratio,
          y: start.y + (end.y - start.y) * weld.ratio,
          z: start.z + (end.z - start.z) * weld.ratio,
        );

      case CalloutTargetType.support:
        final sup = network.supports[targetId];
        if (sup == null) return null;
        final seg = network.segments[sup.segmentId];
        if (seg == null) return null;
        final start = network.nodes[seg.startNodeId];
        final end = network.nodes[seg.endNodeId];
        if (start == null || end == null) return null;
        final r = sup.distanceRatio.clamp(0.0, 1.0);
        return Node3D(
          id: 'anchor_$targetId',
          x: start.x + (end.x - start.x) * r,
          y: start.y + (end.y - start.y) * r,
          z: start.z + (end.z - start.z) * r,
        );

      case CalloutTargetType.equipment:
        final eq = network.equipments[targetId];
        if (eq == null) return null;
        return Node3D(
          id: 'anchor_$targetId',
          x: eq.x,
          y: eq.y,
          z: eq.z + eq.height / 2.0,
        );

      case CalloutTargetType.nozzle:
        final node = network.nodes[targetId];
        if (node != null) return node;
        for (final eq in network.equipments.values) {
          for (final noz in eq.nozzles) {
            if (noz.id == targetId) {
              final rad = eq.rotationAngleDeg * math.pi / 180.0;
              final cosA = math.cos(rad);
              final sinA = math.sin(rad);
              final wx = eq.x + noz.localX * cosA - noz.localY * sinA;
              final wy = eq.y + noz.localX * sinA + noz.localY * cosA;
              final wz = eq.z + noz.localZ;
              return Node3D(id: 'anchor_$targetId', x: wx, y: wy, z: wz);
            }
          }
        }
        return null;

      case CalloutTargetType.fitting:
        return network.getFittingAnchorPointById(targetId);
    }
  }

  /// Получение экранных границ (bounding box) текста и полочки выноски для hit-test
  static Rect? getCalloutBounds(
    PipingNetwork network,
    AxonometryProjector projector,
    Callout callout, {
    Map<String, String>? templates,
    ProjectModel? project,
    bool isPaperSpace = false,
    double annotationScale = 1.0,
    String? activeSheetId,
  }) {
    final anchor3D = getTarget3DPoint(network, callout);
    if (anchor3D == null) return null;

    final anchorScreen = projector.project(anchor3D);
    final effOffsetX = activeSheetId != null ? callout.getEffectiveOffsetX(activeSheetId) : callout.screenOffsetX;
    final effOffsetY = activeSheetId != null ? callout.getEffectiveOffsetY(activeSheetId) : callout.screenOffsetY;
    final scaledOffsetX = isPaperSpace
        ? effOffsetX * 0.35 * annotationScale
        : effOffsetX * annotationScale;
    final scaledOffsetY = isPaperSpace
        ? effOffsetY * 0.35 * annotationScale
        : effOffsetY * annotationScale;
    final textPos = Offset(
      anchorScreen.dx + scaledOffsetX,
      anchorScreen.dy + scaledOffsetY,
    );

    final effectiveTemplates = templates ?? project?.calloutTemplates ?? defaultCalloutTemplates;
    final topText = network.generateCalloutText(callout, effectiveTemplates);
    final bottomText = network.generateCalloutBottomText(callout, effectiveTemplates);

    final fontSize = isPaperSpace
        ? callout.textHeight * annotationScale
        : (callout.textHeight * 4.4) * annotationScale;
    final bottomFontSize = isPaperSpace
        ? callout.textHeight * 0.85 * annotationScale
        : (callout.textHeight * 3.8) * annotationScale;

    final topTp = TextPainter(
      text: TextSpan(
        text: topText,
        style: TextStyle(
          fontSize: fontSize,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    double bottomHeight = 0.0;
    double maxTextWidth = topTp.width;
    if (bottomText != null && bottomText.trim().isNotEmpty) {
      final bottomTp = TextPainter(
        text: TextSpan(
          text: bottomText,
          style: TextStyle(
            fontSize: bottomFontSize,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final padY = isPaperSpace ? 0.4 * annotationScale : 2.0 * annotationScale;
      bottomHeight = bottomTp.height + padY * 2.0;
      maxTextWidth = math.max(maxTextWidth, bottomTp.width);
    }

    final isRight = callout.shelfDirection == ShelfDirection.right
        ? true
        : (callout.shelfDirection == ShelfDirection.left
            ? false
            : scaledOffsetX >= 0);

    final padX = isPaperSpace ? 1.0 * annotationScale : 4.0 * annotationScale;
    final padY = isPaperSpace ? 0.4 * annotationScale : 2.0 * annotationScale;
    final shelfLength = maxTextWidth + padX * 2.0;

    if (callout.targetType == CalloutTargetType.node || callout.elevationStyle != null) {
      if (callout.arrowOnNode) {
        final shelfY = anchorScreen.dy + scaledOffsetY;
        final bgTop = shelfY - topTp.height - padY * 2.0;
        final totalTextH = topTp.height + padY * 2.0 + bottomHeight;
        final minY = math.min(bgTop, math.min(shelfY, anchorScreen.dy)) - 2.0;
        final maxY = math.max(bgTop + totalTextH, math.max(shelfY, anchorScreen.dy)) + 2.0;
        if (isRight) {
          return Rect.fromLTRB(
            anchorScreen.dx - 8.0,
            minY,
            anchorScreen.dx + shelfLength + 4.0,
            maxY,
          );
        } else {
          return Rect.fromLTRB(
            anchorScreen.dx - shelfLength - 4.0,
            minY,
            anchorScreen.dx + 8.0,
            maxY,
          );
        }
      }

      final flagSize = isPaperSpace
          ? (callout.textHeight * 1.5) * annotationScale
          : 8.0 * annotationScale;
      final flagH = flagSize * 1.3;
      final shelfY = textPos.dy - flagH - padY * 2.0;
      final bgTop = shelfY - topTp.height - padY * 2.0;
      final totalHeight = (textPos.dy - bgTop) + (bottomHeight > 0 ? bottomHeight : padY * 2.0);
      if (isRight) {
        return Rect.fromLTWH(
          textPos.dx - 8.0,
          bgTop,
          shelfLength + 10.0,
          totalHeight,
        );
      } else {
        return Rect.fromLTWH(
          textPos.dx - shelfLength - 2.0,
          bgTop,
          shelfLength + 10.0,
          totalHeight,
        );
      }
    }

    final bgTopPad = padY * 2.0;
    final totalHeight = topTp.height + bgTopPad + (bottomHeight > 0 ? bottomHeight : bgTopPad);
    final bgTop = textPos.dy - topTp.height - bgTopPad;
    if (isRight) {
      return Rect.fromLTWH(
        textPos.dx,
        bgTop,
        shelfLength,
        totalHeight,
      );
    } else {
      return Rect.fromLTWH(
        textPos.dx - shelfLength,
        bgTop,
        shelfLength,
        totalHeight,
      );
    }
  }

  static double _distanceToRect(Offset p, Rect r) {
    if (r.contains(p)) return 0.0;
    final dx = math.max(0.0, math.max(r.left - p.dx, p.dx - r.right));
    final dy = math.max(0.0, math.max(r.top - p.dy, p.dy - r.bottom));
    return math.sqrt(dx * dx + dy * dy);
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final ap = p - a;
    final lengthSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lengthSq <= 1e-6) return (p - a).distance;
    final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / lengthSq).clamp(0.0, 1.0);
    final projection = Offset(a.dx + t * ab.dx, a.dy + t * ab.dy);
    return (p - projection).distance;
  }

  /// Проверка попадания клика в текст, полку или ножку выноски (hit test)
  /// с выбором наиболее близкой выноски к курсору (минимальное расстояние)
  /// и абсолютным приоритетом прямого клика по тексту или полочке.
  static String? hitTest(
    Offset screenPos,
    PipingNetwork network,
    AxonometryProjector projector, {
    Map<String, String>? templates,
    ProjectModel? project,
    double hitTolerance = 12.0,
    bool isPaperSpace = false,
    double annotationScale = 1.0,
    String? activeSheetId,
    DrawingSheet? activeSheet,
    String? selectedCalloutId,
    Set<CalloutTargetType>? hiddenTypes,
  }) {
    if (network.callouts.isEmpty) return null;

    final candidates = <_CalloutHitCandidate>[];

    for (final callout in network.callouts.values) {
      if (callout.isHidden) continue;
      if (hiddenTypes != null && hiddenTypes.contains(callout.targetType)) continue;
      // 1. Фильтрация по видимости на активном листе чертежа
      if (activeSheet != null && !activeSheet.isCalloutVisible(callout, network)) {
        continue;
      }

      final bounds = getCalloutBounds(
        network,
        projector,
        callout,
        templates: templates,
        project: project,
        isPaperSpace: isPaperSpace,
        annotationScale: annotationScale,
        activeSheetId: activeSheetId,
      );

      final anchor3D = getTarget3DPoint(network, callout);
      if (anchor3D == null) continue;

      final anchorScreen = projector.project(anchor3D);
      final effOffsetX = activeSheetId != null ? callout.getEffectiveOffsetX(activeSheetId) : callout.screenOffsetX;
      final effOffsetY = activeSheetId != null ? callout.getEffectiveOffsetY(activeSheetId) : callout.screenOffsetY;
      final scaledOffsetX = isPaperSpace ? effOffsetX * 0.35 * annotationScale : effOffsetX * annotationScale;
      final scaledOffsetY = isPaperSpace ? effOffsetY * 0.35 * annotationScale : effOffsetY * annotationScale;
      final textPos = Offset(anchorScreen.dx + scaledOffsetX, anchorScreen.dy + scaledOffsetY);

      final isRight = callout.shelfDirection == ShelfDirection.right
          ? true
          : (callout.shelfDirection == ShelfDirection.left ? false : scaledOffsetX >= 0);

      // Проверяем прямое попадание в прямоугольник текста
      final bool isInsideText = bounds != null && bounds.contains(screenPos);
      final double distToBounds = bounds != null ? _distanceToRect(screenPos, bounds) : double.infinity;
      final double distToCenter = bounds != null ? (screenPos - bounds.center).distance : double.infinity;

      // Вычисляем линию горизонтальной полочки
      Offset shelfStart = textPos;
      Offset shelfEnd;
      if (bounds != null) {
        shelfEnd = Offset(isRight ? textPos.dx + bounds.width : textPos.dx - bounds.width, textPos.dy);
      } else {
        shelfEnd = Offset(isRight ? textPos.dx + 40.0 : textPos.dx - 40.0, textPos.dy);
      }

      if (callout.targetType == CalloutTargetType.node || callout.elevationStyle != null) {
        if (callout.arrowOnNode) {
          final shelfY = anchorScreen.dy + scaledOffsetY;
          shelfStart = Offset(anchorScreen.dx, shelfY);
          final shelfLen = bounds?.width ?? 40.0;
          shelfEnd = Offset(isRight ? anchorScreen.dx + shelfLen : anchorScreen.dx - shelfLen, shelfY);
        } else {
          const flagH = 14.4;
          final shelfY = textPos.dy - flagH - 4.0;
          shelfStart = Offset(textPos.dx, shelfY);
          final shelfLen = bounds?.width ?? 40.0;
          shelfEnd = Offset(isRight ? textPos.dx + shelfLen : textPos.dx - shelfLen, shelfY);
        }
      }

      final double distToShelf = _distanceToSegment(screenPos, shelfStart, shelfEnd);

      // Минимальное расстояние до геометрии выноски
      double minDist = math.min(distToBounds, distToShelf);

      // Линия-ножка и точка привязки
      if (!callout.arrowOnNode) {
        final double distToLeader = _distanceToSegment(screenPos, anchorScreen, textPos);
        final double distToAnchorDot = (screenPos - anchorScreen).distance;
        minDist = math.min(minDist, math.min(distToLeader, distToAnchorDot));
      } else {
        final double distToStem = _distanceToSegment(screenPos, anchorScreen, shelfStart);
        minDist = math.min(minDist, distToStem);
      }

      // Дополнительные ножки объединенной вилочной выноски ("Ласточкин хвост" по ГОСТ 2.316)
      if (callout.additionalTargetIds.isNotEmpty) {
        for (final addTargetId in callout.additionalTargetIds) {
          final addAnchor3D = getTarget3DPointForTarget(network, callout.targetType, addTargetId);
          if (addAnchor3D != null) {
            final addAnchorScreen = projector.project(addAnchor3D);
            final double distToForkLeg = _distanceToSegment(screenPos, addAnchorScreen, textPos);
            final double distToForkDot = (screenPos - addAnchorScreen).distance;
            minDist = math.min(minDist, math.min(distToForkLeg, distToForkDot));
          }
        }
      }

      // Прямой клик по тексту или горизонтальной полке (<= 4.5 px от полки)
      final bool isDirectHit = isInsideText || distToShelf <= 4.5;

      if (isDirectHit || minDist <= hitTolerance) {
        candidates.add(_CalloutHitCandidate(
          calloutId: callout.id,
          isDirectHit: isDirectHit,
          distance: minDist,
          distToCenter: distToCenter,
          isSelected: callout.id == selectedCalloutId,
        ));
      }
    }

    if (candidates.isEmpty) return null;

    // Сортировка: прямой клик всегда побеждает клик по фоновой линии;
    // при равном типе попадания выбирается строго ближайший элемент.
    candidates.sort((a, b) {
      if (a.isDirectHit && !b.isDirectHit) return -1;
      if (!a.isDirectHit && b.isDirectHit) return 1;

      if (a.isDirectHit && b.isDirectHit) {
        if (a.isSelected && !b.isSelected && (a.distToCenter - b.distToCenter).abs() < 12.0) return -1;
        if (!a.isSelected && b.isSelected && (a.distToCenter - b.distToCenter).abs() < 12.0) return 1;
        return a.distToCenter.compareTo(b.distToCenter);
      }

      if (a.isSelected && !b.isSelected && (a.distance - b.distance).abs() < 1.5) return -1;
      if (!a.isSelected && b.isSelected && (a.distance - b.distance).abs() < 1.5) return 1;

      return a.distance.compareTo(b.distance);
    });

    return candidates.first.calloutId;
  }

  static void _paintSingleCallout(
    Canvas canvas,
    AxonometryProjector projector,
    PipingNetwork network,
    Callout callout,
    Offset anchorScreen,
    Map<String, String> templates,
    bool isSelected, {
    double annotationScale = 1.0,
    bool isPaperSpace = false,
    String? activeSheetId,
    bool skipLeaderLineAndDot = false,
  }) {
    final effOffsetX = activeSheetId != null ? callout.getEffectiveOffsetX(activeSheetId) : callout.screenOffsetX;
    final effOffsetY = activeSheetId != null ? callout.getEffectiveOffsetY(activeSheetId) : callout.screenOffsetY;
    final scaledOffsetX = isPaperSpace
        ? effOffsetX * 0.35 * annotationScale
        : effOffsetX * annotationScale;
    final scaledOffsetY = isPaperSpace
        ? effOffsetY * 0.35 * annotationScale
        : effOffsetY * annotationScale;
    final textPos = Offset(
      anchorScreen.dx + scaledOffsetX,
      anchorScreen.dy + scaledOffsetY,
    );

    final topText = network.generateCalloutText(callout, templates);
    final bottomText = network.generateCalloutBottomText(callout, templates);
    final isRight = callout.shelfDirection == ShelfDirection.right
        ? true
        : (callout.shelfDirection == ShelfDirection.left
            ? false
            : scaledOffsetX >= 0);

    final primaryColor = isSelected ? const Color(0xFF2563EB) : Color(callout.textColor);

    final linePaint = Paint()
      ..color = primaryColor
      ..strokeWidth = isPaperSpace
          ? math.max(0.6, (isSelected ? 0.5 : 0.25) * annotationScale)
          : (isSelected ? 2.0 : 1.2) * annotationScale
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter;

    final fontSize = isPaperSpace
        ? callout.textHeight * annotationScale
        : (callout.textHeight * 4.4) * annotationScale;
    final bottomFontSize = isPaperSpace
        ? callout.textHeight * 0.85 * annotationScale
        : (callout.textHeight * 3.8) * annotationScale;

    final topTp = TextPainter(
      text: TextSpan(
        text: topText,
        style: TextStyle(
          color: primaryColor,
          fontSize: fontSize,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    TextPainter? bottomTp;
    if (bottomText != null && bottomText.trim().isNotEmpty) {
      bottomTp = TextPainter(
        text: TextSpan(
          text: bottomText,
          style: TextStyle(
            color: primaryColor.withValues(alpha: 0.9),
            fontSize: bottomFontSize,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    }

    final padX = isPaperSpace ? 1.0 * annotationScale : 4.0 * annotationScale;
    final padY = isPaperSpace ? 0.4 * annotationScale : 2.0 * annotationScale;
    final maxTextWidth = math.max(topTp.width, bottomTp?.width ?? 0.0);
    final shelfLength = maxTextWidth + padX * 2.0;
    final shelfEnd = Offset(
      isRight ? textPos.dx + shelfLength : textPos.dx - shelfLength,
      textPos.dy,
    );

    if (callout.targetType == CalloutTargetType.node || callout.elevationStyle != null) {
      final styleName = templates['elevation_style'];
      final defaultStyle = ElevationMarkStyleExt.fromString(styleName, fallback: ElevationMarkStyle.gostOutline);
      final effectiveStyle = callout.elevationStyle ?? defaultStyle;

      final flagSize = isPaperSpace
          ? (callout.textHeight * 1.5) * annotationScale
          : 8.0 * annotationScale;
      final flagH = flagSize * 1.3;
      final flagW = flagSize * 0.75;

      if (callout.arrowOnNode) {
        // --- РЕЖИМ 1: Стрелка знака отметки установлена строго на узле (по ГОСТ 21.101) ---
        final shelfY = anchorScreen.dy + scaledOffsetY;
        final isAbove = shelfY <= anchorScreen.dy;
        final flagBaseY = isAbove ? anchorScreen.dy - flagH : anchorScreen.dy + flagH;

        switch (effectiveStyle) {
          case ElevationMarkStyle.gostOutline:
            final flagPath = Path()
              ..moveTo(anchorScreen.dx, anchorScreen.dy)
              ..lineTo(anchorScreen.dx - flagW, flagBaseY)
              ..lineTo(anchorScreen.dx + flagW, flagBaseY)
              ..close();
            canvas.drawPath(flagPath, linePaint);
            canvas.drawLine(Offset(anchorScreen.dx, flagBaseY), Offset(anchorScreen.dx, shelfY), linePaint);
            break;

          case ElevationMarkStyle.gostFilled:
            final flagPath = Path()
              ..moveTo(anchorScreen.dx, anchorScreen.dy)
              ..lineTo(anchorScreen.dx - flagW, flagBaseY)
              ..lineTo(anchorScreen.dx + flagW, flagBaseY)
              ..close();
            final fillPaint = Paint()
              ..color = primaryColor
              ..style = PaintingStyle.fill;
            canvas.drawPath(flagPath, fillPaint);
            canvas.drawPath(flagPath, linePaint);
            canvas.drawLine(Offset(anchorScreen.dx, flagBaseY), Offset(anchorScreen.dx, shelfY), linePaint);
            break;

          case ElevationMarkStyle.compactFlag:
            final tick = isPaperSpace ? 1.2 * annotationScale : 3.5 * annotationScale;
            canvas.drawLine(anchorScreen, Offset(anchorScreen.dx, shelfY), linePaint);
            canvas.drawLine(
              Offset(anchorScreen.dx - tick, anchorScreen.dy + tick),
              Offset(anchorScreen.dx + tick, anchorScreen.dy - tick),
              linePaint,
            );
            break;

          case ElevationMarkStyle.isoCircle:
            final circleR = isPaperSpace ? 1.5 * annotationScale : 4.5 * annotationScale;
            final circlePaint = Paint()
              ..color = primaryColor
              ..strokeWidth = linePaint.strokeWidth
              ..style = PaintingStyle.stroke;
            canvas.drawCircle(anchorScreen, circleR, circlePaint);
            canvas.drawLine(Offset(anchorScreen.dx - circleR, anchorScreen.dy), Offset(anchorScreen.dx + circleR, anchorScreen.dy), linePaint);
            canvas.drawLine(Offset(anchorScreen.dx, anchorScreen.dy - circleR), Offset(anchorScreen.dx, anchorScreen.dy + circleR), linePaint);
            final circleEdgeY = isAbove ? anchorScreen.dy - circleR : anchorScreen.dy + circleR;
            canvas.drawLine(Offset(anchorScreen.dx, circleEdgeY), Offset(anchorScreen.dx, shelfY), linePaint);
            break;
        }

        final shelfStart = Offset(anchorScreen.dx, shelfY);
        final shelfEnd = Offset(
          isRight ? anchorScreen.dx + shelfLength : anchorScreen.dx - shelfLength,
          shelfY,
        );

        final bgTop = shelfY - topTp.height - padY * 2.0;
        final totalHeight = topTp.height + padY * 2.0 + (bottomTp != null ? bottomTp.height + padY * 2.0 : 0.0);
        final bgRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            isRight ? anchorScreen.dx : anchorScreen.dx - shelfLength,
            bgTop,
            shelfLength,
            totalHeight,
          ),
          const Radius.circular(2.0),
        );

        canvas.drawLine(shelfStart, shelfEnd, linePaint);

        final textLeft = isRight ? anchorScreen.dx + padX : anchorScreen.dx - shelfLength + padX;
        topTp.paint(canvas, Offset(textLeft, shelfY - topTp.height - padY));

        if (bottomTp != null) {
          bottomTp.paint(canvas, Offset(textLeft, shelfY + padY));
        }

        if (isSelected) {
          final borderPaint = Paint()
            ..color = const Color(0xFF2563EB).withValues(alpha: 0.75)
            ..strokeWidth = 1.2
            ..style = PaintingStyle.stroke;
          canvas.drawRRect(bgRect, borderPaint);

          final gripPaint = Paint()
            ..color = const Color(0xFF2563EB)
            ..style = PaintingStyle.fill;
          canvas.drawRect(
            Rect.fromCenter(center: shelfStart, width: 6.0, height: 6.0),
            gripPaint,
          );
        }
        return;
      }

      // --- РЕЖИМ 2: Стрелка на выносной ножке (со смещением от узла) ---
      final flagTopY = textPos.dy - flagH;
      final stemH = isPaperSpace ? 1.4 * annotationScale : 4.0 * annotationScale;
      final shelfY = effectiveStyle == ElevationMarkStyle.compactFlag
          ? textPos.dy - (isPaperSpace ? 4.2 * annotationScale : 12.0 * annotationScale)
          : flagTopY - stemH;

      // 1. Выносная ножка от объекта к основанию стрелки отметки
      if ((anchorScreen - textPos).distance > 2.0) {
        canvas.drawLine(anchorScreen, textPos, linePaint);
      }

      // 2. Отрисовка знака отметки в соответствии со стилем
      switch (effectiveStyle) {
        case ElevationMarkStyle.gostOutline:
          final flagPath = Path()
            ..moveTo(textPos.dx, textPos.dy)
            ..lineTo(textPos.dx - flagW, flagTopY)
            ..lineTo(textPos.dx + flagW, flagTopY)
            ..close();
          canvas.drawPath(flagPath, linePaint);
          canvas.drawLine(Offset(textPos.dx, flagTopY), Offset(textPos.dx, shelfY), linePaint);
          break;

        case ElevationMarkStyle.gostFilled:
          final flagPath = Path()
            ..moveTo(textPos.dx, textPos.dy)
            ..lineTo(textPos.dx - flagW, flagTopY)
            ..lineTo(textPos.dx + flagW, flagTopY)
            ..close();
          final fillPaint = Paint()
            ..color = primaryColor
            ..style = PaintingStyle.fill;
          canvas.drawPath(flagPath, fillPaint);
          canvas.drawPath(flagPath, linePaint);
          canvas.drawLine(Offset(textPos.dx, flagTopY), Offset(textPos.dx, shelfY), linePaint);
          break;

        case ElevationMarkStyle.compactFlag:
          final tick = isPaperSpace ? 1.2 * annotationScale : 3.5 * annotationScale;
          canvas.drawLine(textPos, Offset(textPos.dx, shelfY), linePaint);
          canvas.drawLine(
            Offset(textPos.dx - tick, textPos.dy + tick),
            Offset(textPos.dx + tick, textPos.dy - tick),
            linePaint,
          );
          break;

        case ElevationMarkStyle.isoCircle:
          final circleR = isPaperSpace ? 1.5 * annotationScale : 4.5 * annotationScale;
          final circlePaint = Paint()
            ..color = primaryColor
            ..strokeWidth = linePaint.strokeWidth
            ..style = PaintingStyle.stroke;
          canvas.drawCircle(textPos, circleR, circlePaint);
          canvas.drawLine(Offset(textPos.dx - circleR, textPos.dy), Offset(textPos.dx + circleR, textPos.dy), linePaint);
          canvas.drawLine(Offset(textPos.dx, textPos.dy - circleR), Offset(textPos.dx, textPos.dy + circleR), linePaint);
          canvas.drawLine(Offset(textPos.dx, textPos.dy - circleR), Offset(textPos.dx, shelfY), linePaint);
          break;
      }

      // 3. Горизонтальная полочка
      final shelfEnd = Offset(
        isRight ? textPos.dx + shelfLength : textPos.dx - shelfLength,
        shelfY,
      );

      final bgTop = shelfY - topTp.height - padY * 2.0;
      final totalHeight = topTp.height + padY * 2.0 + (bottomTp != null ? bottomTp.height + padY * 2.0 : 0.0);
      final bgRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          isRight ? textPos.dx : textPos.dx - shelfLength,
          bgTop,
          shelfLength,
          totalHeight,
        ),
        const Radius.circular(2.0),
      );

      canvas.drawLine(Offset(textPos.dx, shelfY), shelfEnd, linePaint);

      final textLeft = isRight ? textPos.dx + padX : textPos.dx - shelfLength + padX;
      topTp.paint(canvas, Offset(textLeft, shelfY - topTp.height - padY));

      if (bottomTp != null) {
        bottomTp.paint(canvas, Offset(textLeft, shelfY + padY));
      }

      if (isSelected) {
        final borderPaint = Paint()
          ..color = const Color(0xFF2563EB).withValues(alpha: 0.75)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke;
        canvas.drawRRect(bgRect, borderPaint);

        final gripPaint = Paint()
          ..color = const Color(0xFF2563EB)
          ..style = PaintingStyle.fill;
        canvas.drawRect(
          Rect.fromCenter(center: textPos, width: 6.0, height: 6.0),
          gripPaint,
        );
      }
      return;
    }

    // 1. Точка привязки (кружок на 3D объекте по ГОСТ)
    if (!skipLeaderLineAndDot) {
      final dotPaint = Paint()
        ..color = primaryColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        anchorScreen,
        isPaperSpace ? math.max(0.8, 0.45 * annotationScale) : 3.0 * annotationScale,
        dotPaint,
      );

      // 2. Наклонная линия-ножка от объекта до излома (textPos)
      canvas.drawLine(anchorScreen, textPos, linePaint);

      // Дополнительные ножки для объединенных вилочных выносок ("Ласточкин хвост / Звезда" по ГОСТ 2.316)
      if (callout.additionalTargetIds.isNotEmpty) {
        for (final addTargetId in callout.additionalTargetIds) {
          final addAnchor3D = getTarget3DPointForTarget(network, callout.targetType, addTargetId);
          if (addAnchor3D != null) {
            final addAnchorScreen = projector.project(addAnchor3D);
            canvas.drawCircle(
              addAnchorScreen,
              isPaperSpace ? math.max(0.8, 0.45 * annotationScale) : 3.0 * annotationScale,
              dotPaint,
            );
            canvas.drawLine(addAnchorScreen, textPos, linePaint);
          }
        }
      }
    }

    // 3. Область текста над и под полочкой (без непрозрачной белой заливки, чтобы не перекрывать трубы)
    final bgTopPad = padY * 2.0;
    final bgTop = textPos.dy - topTp.height - bgTopPad;
    final totalHeight = topTp.height + bgTopPad + (bottomTp != null ? bottomTp.height + bgTopPad : 0.0);
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        isRight ? textPos.dx : textPos.dx - shelfLength,
        bgTop,
        shelfLength,
        totalHeight,
      ),
      const Radius.circular(2.0),
    );

    // 4. Горизонтальная полочка выноски (по ГОСТ 2.316)
    canvas.drawLine(textPos, shelfEnd, linePaint);

    // Отрисовка текста над полочкой
    final textLeft = isRight ? textPos.dx + padX : textPos.dx - shelfLength + padX;
    final textTop = textPos.dy - topTp.height - padY;
    topTp.paint(canvas, Offset(textLeft, textTop));

    // Отрисовка текста под полочкой (если есть)
    if (bottomTp != null) {
      final bottomTextTop = textPos.dy + padY;
      bottomTp.paint(canvas, Offset(textLeft, bottomTextTop));
    }

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

  /// Вычисление единичного вектора нормали в плоскости экрана к трубе, примыкающей к узлу.
  /// Работает для прямых углов (90°), наклонных (45°, 30°) и произвольных уклонов.
  static Offset computeNodeNormalVector(
    PipingNetwork network,
    AxonometryProjector projector,
    String nodeId,
  ) {
    final connected = network.getConnectedSegments(nodeId);
    if (connected.isEmpty) {
      return const Offset(1.0, 0.0);
    }
    final seg = connected.first;
    final s = network.nodes[seg.startNodeId];
    final e = network.nodes[seg.endNodeId];
    if (s == null || e == null) {
      return const Offset(1.0, 0.0);
    }
    final p1 = projector.project(s);
    final p2 = projector.project(e);
    final v = Offset(p2.dx - p1.dx, p2.dy - p1.dy);
    final len = v.distance;
    if (len < 0.001) {
      return const Offset(1.0, 0.0);
    }
    var n = Offset(-v.dy / len, v.dx / len);
    if (n.dx < 0 || (n.dx == 0 && n.dy > 0)) {
      n = -n;
    }
    return n;
  }
}

class _CanvasCalloutDrawItem {
  final Callout callout;
  final Offset anchorScreen;
  final Offset textPos;
  final bool isSelected;
  final bool isRight;

  _CanvasCalloutDrawItem({
    required this.callout,
    required this.anchorScreen,
    required this.textPos,
    required this.isSelected,
    required this.isRight,
  });
}

class _CalloutHitCandidate {
  final String calloutId;
  final bool isDirectHit;
  final double distance;
  final double distToCenter;
  final bool isSelected;

  const _CalloutHitCandidate({
    required this.calloutId,
    required this.isDirectHit,
    required this.distance,
    required this.distToCenter,
    required this.isSelected,
  });
}
