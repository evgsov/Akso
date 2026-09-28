import 'dart:math' as math;
import 'dart:ui';

import '../../core/math/axonometry_projector.dart';
import '../../core/math/vector_3d.dart';
import '../../ui/canvas/painters/callout_painter.dart';
import '../enums/fitting_type.dart';
import '../enums/projection_type.dart';
import '../enums/weld_joint_style.dart';
import '../models/callout.dart';
import '../models/custom_valve_definition.dart';
import '../models/detail_node.dart';
import '../models/drawing_sheet.dart';
import '../models/drawing_style_config.dart';
import '../models/equipment.dart';
import '../models/node_3d.dart';
import '../models/piping_network.dart';
import '../models/vector_scene.dart';
import 'custom_valve_catalog.dart';
import 'element_3d_geometry.dart';
import 'viewport_transform_service.dart';

/// Рассчитанная 2D-геометрия контура и выноски укрупненного узла в миллиметрах листа
class DetailNodeSheetGeometry {
  final DetailNode detailNode;
  final Rect boundsMm;
  final List<Offset> perimeterPointsMm;
  final List<Offset> polygonVerticesMm;
  final Offset contourAttachMm;
  final Offset shelfStartMm;
  final Offset shelfEndMm;
  final double shelfLengthMm;
  final bool isRight;
  final String topText;
  final String bottomText;

  const DetailNodeSheetGeometry({
    required this.detailNode,
    required this.boundsMm,
    required this.perimeterPointsMm,
    required this.polygonVerticesMm,
    required this.contourAttachMm,
    required this.shelfStartMm,
    required this.shelfEndMm,
    required this.shelfLengthMm,
    required this.isRight,
    required this.topText,
    required this.bottomText,
  });

  Offset get centerMm => boundsMm.center;
  Offset get leaderAttachMm => contourAttachMm;

  Rect get shelfHitRectMm {
    final left = math.min(shelfStartMm.dx, shelfEndMm.dx) - 1.0;
    final right = math.max(shelfStartMm.dx, shelfEndMm.dx) + 1.0;
    return Rect.fromLTRB(left, shelfStartMm.dy - 5.0, right, shelfStartMm.dy + 5.0);
  }
}

/// Единый строитель векторной геометрии чертежа (Single Source of Truth)
/// Преобразует топологическую 3D-модель сети и видовой экран листа оформления
/// в структурированный набор 2D векторных примитивов в миллиметрах листа.
class SheetGeometryBuilder {
  /// Строит полную векторную сцену чертежа со всеми слоями
  static VectorScene buildScene({
    required DrawingSheet sheet,
    required PipingNetwork network,
    DrawingStyleConfig styleConfig = const DrawingStyleConfig(),
    ProjectionType projectionType = ProjectionType.gostFrontal45,
    double orbitAzimuth = -math.pi / 4,
    double orbitElevation = math.pi / 6,
    Node3D targetCenter = const Node3D(id: 'center', x: 0, y: 0, z: 0),
    Map<String, CustomValveDefinition>? customValves,
    Map<String, String>? calloutTemplates,
    double Function(String text, double fontSizeMm, {bool isBold})? measureTextWidthMm,
  }) {
    final effectiveNetwork = sheet.getEffectiveNetwork(network);
    final widthMm = sheet.format.widthMm;
    final heightMm = sheet.format.heightMm;
    final scene = VectorScene(widthMm: widthMm, heightMm: heightMm);

    final vp = sheet.viewport;
    final projector = AxonometryProjector(
      projectionType: projectionType,
      orbitAzimuth: orbitAzimuth,
      orbitElevation: orbitElevation,
      targetCenter: targetCenter,
    );

    // 1. Строительные оси здания
    _buildAxes(scene, effectiveNetwork, vp, projector, styleConfig);

    // 1.1. Контекстные «хвосты» примыкающих магистралей (если это лист узла, Вариант 1)
    if (sheet.detailNodeId != null) {
      final dn = network.detailNodes[sheet.detailNodeId];
      if (dn != null) {
        _buildDetailContextStubs(scene, network, dn, vp, projector, styleConfig);
      }
    }

    // 2. Технологическое оборудование
    _buildEquipment(scene, effectiveNetwork, vp, projector, styleConfig);

    // 3. Трассы трубопроводов (катушки / сегменты)
    _buildPipes(scene, effectiveNetwork, vp, projector, styleConfig, rawNetwork: network);

    // 4. Фасонные детали (отводы, тройники, переходы, фланцы, заглушки)
    _buildFittings(scene, effectiveNetwork, vp, projector, styleConfig);

    // 5. Арматура
    _buildValves(scene, effectiveNetwork, vp, projector, styleConfig, customValves);

    // 6. Опоры и подвески
    _buildSupports(scene, effectiveNetwork, vp, projector, styleConfig);

    // 7. Сварные стыки (ГОСТ / 3D-кольца / засечки)
    _buildWelds(scene, effectiveNetwork, vp, projector, styleConfig);

    // 8. Размеры (ГОСТ 2.307)
    _buildDimensions(scene, effectiveNetwork, vp, projector, styleConfig);

    // 9. Выноски
    _buildCallouts(
      scene,
      effectiveNetwork,
      sheet,
      vp,
      projector,
      styleConfig,
      calloutTemplates,
      measureTextWidthMm: measureTextWidthMm,
    );

    // 9.1. Контуры обводки и ссылки выносных узлов (если это общий лист)
    if (sheet.detailNodeId == null && network.detailNodes.isNotEmpty) {
      _buildDetailNodeBoundaries(
        scene,
        network,
        effectiveNetwork,
        vp,
        projector,
        styleConfig,
        measureTextWidthMm: measureTextWidthMm,
      );
    }

    // 10. Рамка листа (20-5-5-5) и штамп Форма 3 (ГОСТ 21.101-2020)
    _buildFrameAndStamp(scene, sheet, styleConfig);

    return scene;
  }

  /// Точная оценка ширины строки в мм для пропорционального шрифта (Roboto / ГОСТ)
  static double estimateTextWidthMm(
    String text,
    double fontSizeMm, {
    bool isBold = false,
  }) {
    if (text.isEmpty) return 0.0;
    double units = 0.0;
    for (int i = 0; i < text.length; i++) {
      final ch = text[i];
      if ('.,:;!|iIl1\'"`'.contains(ch)) {
        units += 0.27;
      } else if (' -()/\\[]{}'.contains(ch)) {
        units += 0.33;
      } else if ('023456789'.contains(ch)) {
        units += 0.55;
      } else if ('ЖМШЩЮЫФДWM@#%&'.contains(ch)) {
        units += 0.74;
      } else if ('жмшщюыфwm'.contains(ch)) {
        units += 0.66;
      } else if (ch.toUpperCase() == ch && ch.toLowerCase() != ch) {
        units += 0.60;
      } else {
        units += 0.50;
      }
    }
    return units * fontSizeMm * (isBold ? 1.05 : 1.0);
  }

  static double _measureTextWidth(
    String text,
    double fontSizeMm, {
    bool isBold = false,
    double Function(String text, double fontSizeMm, {bool isBold})? measureTextWidthMm,
  }) {
    if (text.isEmpty) return 0.0;
    if (measureTextWidthMm != null) {
      return measureTextWidthMm(text, fontSizeMm, isBold: isBold);
    }
    return estimateTextWidthMm(text, fontSizeMm, isBold: isBold);
  }

  // --- Вспомогательный метод проекции 3D точки в 2D координаты листа (мм) ---
  static Offset _projectPoint(double x, double y, double z, AxonometryProjector projector, dynamic vp) {
    final raw = projector.projectRaw(x, y, z);
    return ViewportTransformService.model2dToSheetMm(raw, vp);
  }

  // --- 1. Строительные оси ---
  static void _buildAxes(
    VectorScene scene,
    PipingNetwork network,
    dynamic vp,
    AxonometryProjector projector,
    DrawingStyleConfig styleConfig,
  ) {
    for (final axis in network.axes.values) {
      final p1 = _projectPoint(axis.startPoint.x, axis.startPoint.y, axis.startPoint.z, projector, vp);
      final p2 = _projectPoint(axis.endPoint.x, axis.endPoint.y, axis.endPoint.z, projector, vp);

      scene.addPolyline(
        layer: VectorSceneLayer.axes,
        points: [p1, p2],
        strokeWidthMm: styleConfig.axisLineWidthMm,
        colorValue: 0xFF90A4AE, // blueGrey300
        smoothJoin: false,
        dashPattern: const [4.0, 2.0],
      );

      if (axis.isBuildingGrid && axis.label.isNotEmpty) {
        const r = 3.5;
        if (axis.showStartBubble) {
          scene.addCircle(
            layer: VectorSceneLayer.axes,
            center: p1,
            radiusMm: r,
            isFilled: true,
            strokeColorValue: 0xFF546E7A, // blueGrey600
            fillColorValue: 0xFFFFFFFF,
            strokeWidthMm: 0.35,
          );
          scene.addText(
            layer: VectorSceneLayer.axes,
            text: axis.label,
            position: p1,
            fontSizePt: 7.0,
            isBold: true,
            colorValue: 0xFF263238, // blueGrey800
          );
        }
        if (axis.showEndBubble) {
          scene.addCircle(
            layer: VectorSceneLayer.axes,
            center: p2,
            radiusMm: r,
            isFilled: true,
            strokeColorValue: 0xFF546E7A,
            fillColorValue: 0xFFFFFFFF,
            strokeWidthMm: 0.35,
          );
          scene.addText(
            layer: VectorSceneLayer.axes,
            text: axis.label,
            position: p2,
            fontSizePt: 7.0,
            isBold: true,
            colorValue: 0xFF263238,
          );
        }
      }
    }
  }

  // --- 2. Технологическое оборудование ---
  static void _buildEquipment(
    VectorScene scene,
    PipingNetwork network,
    dynamic vp,
    AxonometryProjector projector,
    DrawingStyleConfig styleConfig,
  ) {
    for (final eq in network.equipments.values) {
      final rad = eq.rotationAngleDeg * math.pi / 180.0;
      final cosA = math.cos(rad);
      final sinA = math.sin(rad);

      Offset rot(double lx, double ly) {
        return Offset(
          eq.x + lx * cosA - ly * sinA,
          eq.y + lx * sinA + ly * cosA,
        );
      }

      void addEdge(double x1, double y1, double z1, double x2, double y2, double z2) {
        final p1 = _projectPoint(x1, y1, z1, projector, vp);
        final p2 = _projectPoint(x2, y2, z2, projector, vp);
        scene.addPolyline(
          layer: VectorSceneLayer.equipment,
          points: [p1, p2],
          strokeWidthMm: styleConfig.fittingLineWidthMm,
          colorValue: 0xFF1565C0, // blue800
          smoothJoin: false,
        );
      }

      if (eq.type == EquipmentType.box) {
        final halfW = eq.width / 2.0;
        final halfL = eq.length / 2.0;
        final c = [
          rot(-halfW, -halfL),
          rot(halfW, -halfL),
          rot(halfW, halfL),
          rot(-halfW, halfL),
        ];
        final z1 = eq.z;
        final z2 = eq.z + eq.height;

        for (int i = 0; i < 4; i++) {
          final next = (i + 1) % 4;
          addEdge(c[i].dx, c[i].dy, z1, c[next].dx, c[next].dy, z1);
          addEdge(c[i].dx, c[i].dy, z2, c[next].dx, c[next].dy, z2);
          addEdge(c[i].dx, c[i].dy, z1, c[i].dx, c[i].dy, z2);
        }
      } else if (eq.type == EquipmentType.cylinderVertical) {
        final r = eq.width / 2.0;
        final z1 = eq.z;
        final z2 = eq.z + eq.height;
        const n = 12;
        final pts = <Offset>[];
        for (int i = 0; i < n; i++) {
          final a = i * 2.0 * math.pi / n;
          pts.add(rot(r * math.cos(a), r * math.sin(a)));
        }
        for (int i = 0; i < n; i++) {
          final next = (i + 1) % n;
          addEdge(pts[i].dx, pts[i].dy, z1, pts[next].dx, pts[next].dy, z1);
          addEdge(pts[i].dx, pts[i].dy, z2, pts[next].dx, pts[next].dy, z2);
          addEdge(pts[i].dx, pts[i].dy, z1, pts[i].dx, pts[i].dy, z2);
        }
      } else if (eq.type == EquipmentType.cylinderHorizontal) {
        final radius = eq.height / 2.0;
        final halfL = eq.length / 2.0;
        final centerZ = eq.z + radius;
        const n = 12;
        final startCap = <List<double>>[];
        final endCap = <List<double>>[];

        for (int i = 0; i < n; i++) {
          final angle = (2 * math.pi * i) / n;
          final lx = radius * math.cos(angle);
          final vz = centerZ + radius * math.sin(angle);
          final sx = eq.x + lx * cosA - (-halfL) * sinA;
          final sy = eq.y + lx * sinA + (-halfL) * cosA;
          startCap.add([sx, sy, vz]);

          final ex = eq.x + lx * cosA - halfL * sinA;
          final ey = eq.y + lx * sinA + halfL * cosA;
          endCap.add([ex, ey, vz]);
        }

        for (int i = 0; i < n; i++) {
          final next = (i + 1) % n;
          addEdge(startCap[i][0], startCap[i][1], startCap[i][2], startCap[next][0], startCap[next][1], startCap[next][2]);
          addEdge(endCap[i][0], endCap[i][1], endCap[i][2], endCap[next][0], endCap[next][1], endCap[next][2]);
          addEdge(startCap[i][0], startCap[i][1], startCap[i][2], endCap[i][0], endCap[i][1], endCap[i][2]);
        }
      }

      // Штуцера оборудования
      for (final noz in eq.nozzles) {
        final node = network.nodes[noz.id];
        final double wx, wy, wz;
        if (node != null) {
          wx = node.x;
          wy = node.y;
          wz = node.z;
        } else {
          wx = eq.x + noz.localX * cosA - noz.localY * sinA;
          wy = eq.y + noz.localX * sinA + noz.localY * cosA;
          wz = eq.z + noz.localZ;
        }

        final effDir = network.getNozzleEffectiveDirection(noz);
        final spudLenMm = network.getNozzleEffectiveSpudLength(noz, defaultSpudMm: 120.0);
        final wireframe = Element3dGeometry.generateNozzleWireframe(
          startX: wx,
          startY: wy,
          startZ: wz,
          dirX: effDir.x,
          dirY: effDir.y,
          dirZ: effDir.z,
          dn: noz.dn,
          spudLengthMm: spudLenMm,
          includeCounterFlange: noz.includeInMto,
        );

        for (int i = 0; i < wireframe.length; i++) {
          final seg = wireframe[i];
          final p1 = _projectPoint(seg.x1, seg.y1, seg.z1, projector, vp);
          final p2 = _projectPoint(seg.x2, seg.y2, seg.z2, projector, vp);
          scene.addPolyline(
            layer: VectorSceneLayer.equipment,
            points: [p1, p2],
            strokeWidthMm: i == 0 ? styleConfig.fittingLineWidthMm : styleConfig.pipeLineWidthMm,
            colorValue: 0xFF1565C0,
            smoothJoin: true,
          );
        }
      }
    }
  }

  // --- 3. Трассы трубопроводов ---
  static void _buildPipes(
    VectorScene scene,
    PipingNetwork network,
    dynamic vp,
    AxonometryProjector projector,
    DrawingStyleConfig styleConfig, {
    PipingNetwork? rawNetwork,
  }) {
    final net = (vp.ghostInactiveSystems && rawNetwork != null) ? rawNetwork : network;
    if (net.spools.isNotEmpty) {
      for (final spool in net.spools.values) {
        final seg = net.segments[spool.segmentId];
        if (seg == null) continue;
        if (net.isButtJoint(seg.id)) continue;

        final isVisible = vp.visibleSystemIds == null || vp.visibleSystemIds!.contains(seg.systemId);
        if (!isVisible && !vp.ghostInactiveSystems) continue;

        final start = spool.startPoint ?? net.nodes[seg.startNodeId];
        final end = spool.endPoint ?? net.nodes[seg.endNodeId];
        if (start == null || end == null) continue;

        final sys = net.systems[seg.systemId];
        final color = isVisible ? (sys?.colorValue ?? 0xFF000000) : 0xFFBDBDBD;
        final strokeW = isVisible ? styleConfig.getPipeStrokeWidthMm(spool.dn) : styleConfig.thinLineWidthMm;

        // Прямое соединение без ложных вырезов арматуры: SpoolCalculator уже вычел арматуру и фитинги!
        final p1 = _projectPoint(start.x, start.y, start.z, projector, vp);
        final p2 = _projectPoint(end.x, end.y, end.z, projector, vp);

        scene.addPolyline(
          layer: VectorSceneLayer.pipes,
          points: [p1, p2],
          strokeWidthMm: strokeW,
          colorValue: color,
          smoothJoin: true, // Включает скругленные окончания (round cap) для бесшовного стыка
        );
      }
    } else {
      // Fallback: отрисовка по сегментам сети
      for (final seg in net.segments.values) {
        final isVisible = vp.visibleSystemIds == null || vp.visibleSystemIds!.contains(seg.systemId);
        if (!isVisible && !vp.ghostInactiveSystems) continue;

        final n1 = net.nodes[seg.startNodeId];
        final n2 = net.nodes[seg.endNodeId];
        if (n1 == null || n2 == null) continue;

        final sys = net.systems[seg.systemId];
        final color = isVisible ? (sys?.colorValue ?? 0xFF000000) : 0xFFBDBDBD;
        final strokeW = isVisible ? styleConfig.getPipeStrokeWidthMm(seg.dn) : styleConfig.thinLineWidthMm;

        final segValves = net.valves.values.where((v) => v.segmentId == seg.id).toList();
        final intervals = Element3dGeometry.calcPipeDrawableIntervals3d(n1, n2, segValves);

        for (final interval in intervals) {
          final p1 = _projectPoint(interval.$1.x, interval.$1.y, interval.$1.z, projector, vp);
          final p2 = _projectPoint(interval.$2.x, interval.$2.y, interval.$2.z, projector, vp);
          scene.addPolyline(
            layer: VectorSceneLayer.pipes,
            points: [p1, p2],
            strokeWidthMm: strokeW,
            colorValue: color,
            smoothJoin: true,
          );
        }
      }
    }
  }

  // --- 4. Фасонные детали ---
  static void _buildFittings(
    VectorScene scene,
    PipingNetwork network,
    dynamic vp,
    AxonometryProjector projector,
    DrawingStyleConfig styleConfig,
  ) {
    for (final fit in network.fittings.values) {
      final node = network.nodes[fit.nodeId];
      if (node == null) continue;
      final connected = network.getConnectedSegments(fit.nodeId);
      if (connected.isEmpty) continue;

      final isVisible = vp.visibleSystemIds == null || connected.any((s) => vp.visibleSystemIds!.contains(s.systemId));
      if (!isVisible && !vp.ghostInactiveSystems) continue;

      final s1 = connected[0];
      final fitSys = network.systems[s1.systemId];
      final fitColor = isVisible ? (fitSys?.colorValue ?? 0xFF000000) : 0xFFBDBDBD;

      if (fit.fittingType == FittingType.elbow90 || fit.fittingType == FittingType.elbow45) {
        if (connected.length == 2) {
          final s2 = connected[1];
          final other1 = network.nodes[s1.startNodeId == fit.nodeId ? s1.endNodeId : s1.startNodeId];
          final other2 = network.nodes[s2.startNodeId == fit.nodeId ? s2.endNodeId : s2.startNodeId];
          if (other1 != null && other2 != null) {
            final wires = Element3dGeometry.generateElbowWireframe(
              fit,
              node,
              other1,
              other2,
              pipeOuterDiameter: s1.outerDiameterMm,
            );
            final strokeW = isVisible ? styleConfig.getPipeStrokeWidthMm(fit.dn) : styleConfig.thinLineWidthMm;

            // КРИТИЧЕСКИЙ РЕФАКТОРИНГ: собираем дугу отвода в единую непрерывную полилинию
            if (wires.isNotEmpty) {
              final elbowPoints = <Offset>[];
              final pStart = _projectPoint(wires.first.x1, wires.first.y1, wires.first.z1, projector, vp);
              elbowPoints.add(pStart);
              for (final w in wires) {
                final pt = _projectPoint(w.x2, w.y2, w.z2, projector, vp);
                elbowPoints.add(pt);
              }
              scene.addPolyline(
                layer: VectorSceneLayer.fittings,
                points: elbowPoints,
                strokeWidthMm: strokeW,
                colorValue: fitColor,
                smoothJoin: true, // Идеальное скругление дуги Безье без пикселей и ступеней!
              );
            }
          }
        }
      } else if (fit.fittingType == FittingType.tee) {
        if (connected.length >= 3) {
          final branchSeg = network.identifyBranchSegment(fit.nodeId, connected);
          final pN = _projectPoint(node.x, node.y, node.z, projector, vp);

          for (int i = 0; i < 3; i++) {
            final seg = connected[i];
            final otherId = seg.startNodeId == fit.nodeId ? seg.endNodeId : seg.startNodeId;
            final otherNode = network.nodes[otherId];
            if (otherNode == null) continue;

            final isBranch = seg.id == branchSeg?.id;
            final armLenMm = isBranch
                ? fit.effectiveBranchLengthMm
                : (fit.buildingLengthMm != null && fit.buildingLengthMm! > 0
                    ? fit.buildingLengthMm! / 2.0
                    : fit.dn * 1.0);

            final vx = otherNode.x - node.x;
            final vy = otherNode.y - node.y;
            final vz = otherNode.z - node.z;
            final dist3d = math.sqrt(vx * vx + vy * vy + vz * vz);
            final uX = dist3d > 0 ? vx / dist3d : 0.0;
            final uY = dist3d > 0 ? vy / dist3d : 0.0;
            final uZ = dist3d > 0 ? vz / dist3d : 0.0;

            final effectiveArm = math.min(armLenMm, dist3d * 0.45);
            final pArm = _projectPoint(node.x + uX * effectiveArm, node.y + uY * effectiveArm, node.z + uZ * effectiveArm, projector, vp);

            final segSys = network.systems[seg.systemId];
            final armColor = isVisible ? (segSys?.colorValue ?? fitColor) : 0xFFBDBDBD;
            final armStrokeW = isVisible ? styleConfig.getPipeStrokeWidthMm(seg.dn) : styleConfig.thinLineWidthMm;

            scene.addPolyline(
              layer: VectorSceneLayer.fittings,
              points: [pN, pArm],
              strokeWidthMm: armStrokeW,
              colorValue: armColor,
              smoothJoin: true,
            );
          }

          if (styleConfig.showTeeNodes) {
            final centerR = math.max(0.25, styleConfig.getPipeStrokeWidthMm(fit.dn) * 0.2);
            scene.addCircle(
              layer: VectorSceneLayer.fittings,
              center: pN,
              radiusMm: centerR,
              isFilled: true,
              strokeColorValue: fitColor,
              fillColorValue: fitColor,
            );
          }
        }
      } else if (fit.fittingType == FittingType.reducerConcentric || fit.fittingType == FittingType.reducerEccentric) {
        if (connected.length == 2) {
          final s2 = connected[1];
          final other1 = network.nodes[s1.startNodeId == fit.nodeId ? s1.endNodeId : s1.startNodeId];
          final other2 = network.nodes[s2.startNodeId == fit.nodeId ? s2.endNodeId : s2.startNodeId];
          if (other1 != null && other2 != null) {
            final wires = Element3dGeometry.generateReducerWireframe(
              fit,
              node,
              other1,
              other2,
              d1: s1.outerDiameterMm,
              d2: s2.outerDiameterMm,
            );
            final strokeW = isVisible ? styleConfig.fittingLineWidthMm : styleConfig.thinLineWidthMm;
            for (final wire in wires) {
              final p1 = _projectPoint(wire.x1, wire.y1, wire.z1, projector, vp);
              final p2 = _projectPoint(wire.x2, wire.y2, wire.z2, projector, vp);
              scene.addPolyline(
                layer: VectorSceneLayer.fittings,
                points: [p1, p2],
                strokeWidthMm: strokeW,
                colorValue: fitColor,
                smoothJoin: true,
              );
            }
          }
        }
      } else if (fit.fittingType == FittingType.flange) {
        final other1 = network.nodes[s1.startNodeId == fit.nodeId ? s1.endNodeId : s1.startNodeId];
        if (other1 != null) {
          final wires = Element3dGeometry.generateFlangeWireframe(
            fit,
            node,
            other1,
            pipeOuterDiameter: s1.outerDiameterMm,
          );
          final strokeW = isVisible ? styleConfig.fittingLineWidthMm : styleConfig.thinLineWidthMm;
          for (final wire in wires) {
            final p1 = _projectPoint(wire.x1, wire.y1, wire.z1, projector, vp);
            final p2 = _projectPoint(wire.x2, wire.y2, wire.z2, projector, vp);
            scene.addPolyline(
              layer: VectorSceneLayer.fittings,
              points: [p1, p2],
              strokeWidthMm: strokeW,
              colorValue: fitColor,
              smoothJoin: true,
            );
          }
        }
      } else if (fit.fittingType == FittingType.cap) {
        final other1 = network.nodes[s1.startNodeId == fit.nodeId ? s1.endNodeId : s1.startNodeId];
        if (other1 != null) {
          final wires = Element3dGeometry.generateCapWireframe(
            fit,
            node,
            other1,
            pipeOuterDiameter: s1.outerDiameterMm,
          );
          final strokeW = isVisible ? styleConfig.fittingLineWidthMm : styleConfig.thinLineWidthMm;
          for (final wire in wires) {
            final p1 = _projectPoint(wire.x1, wire.y1, wire.z1, projector, vp);
            final p2 = _projectPoint(wire.x2, wire.y2, wire.z2, projector, vp);
            scene.addPolyline(
              layer: VectorSceneLayer.fittings,
              points: [p1, p2],
              strokeWidthMm: strokeW,
              colorValue: fitColor,
              smoothJoin: true,
            );
          }
        }
      } else if (fit.fittingType == FittingType.directBranch) {
        if (connected.length == 3) {
          final branchSeg = network.identifyBranchSegment(fit.nodeId, connected);
          if (branchSeg != null) {
            final otherNodeId = branchSeg.startNodeId == fit.nodeId ? branchSeg.endNodeId : branchSeg.startNodeId;
            final otherNode = network.nodes[otherNodeId];
            final mainSegs = connected.where((s) => s.id != branchSeg.id).toList();
            if (otherNode != null && mainSegs.isNotEmpty) {
              final wires = Element3dGeometry.generateDirectBranch3d(
                fit,
                node,
                otherNode,
                mainOuterDiameter: mainSegs[0].outerDiameterMm,
                branchOuterDiameter: branchSeg.outerDiameterMm,
              );
              final strokeW = isVisible ? styleConfig.thinLineWidthMm : styleConfig.thinLineWidthMm * 0.8;
              for (final wire in wires) {
                final p1 = _projectPoint(wire.x1, wire.y1, wire.z1, projector, vp);
                final p2 = _projectPoint(wire.x2, wire.y2, wire.z2, projector, vp);
                scene.addPolyline(
                  layer: VectorSceneLayer.fittings,
                  points: [p1, p2],
                  strokeWidthMm: strokeW,
                  colorValue: fitColor,
                  smoothJoin: true,
                );
              }
              if (styleConfig.showDirectBranchNodes) {
                final pN = _projectPoint(node.x, node.y, node.z, projector, vp);
                final centerR = math.max(0.25, styleConfig.getPipeStrokeWidthMm(fit.dn) * 0.2);
                scene.addCircle(
                  layer: VectorSceneLayer.fittings,
                  center: pN,
                  radiusMm: centerR,
                  isFilled: true,
                  strokeColorValue: fitColor,
                  fillColorValue: fitColor,
                );
              }
            }
          }
        }
      }
    }
  }

  // --- 5. Арматура ---
  static void _buildValves(
    VectorScene scene,
    PipingNetwork network,
    dynamic vp,
    AxonometryProjector projector,
    DrawingStyleConfig styleConfig,
    Map<String, CustomValveDefinition>? customValves,
  ) {
    for (final valve in network.valves.values) {
      final seg = network.segments[valve.segmentId];
      if (seg == null) continue;
      final start = network.nodes[seg.startNodeId];
      final end = network.nodes[seg.endNodeId];
      if (start == null || end == null) continue;

      final isVisible = vp.visibleSystemIds == null || vp.visibleSystemIds!.contains(seg.systemId);
      if (!isVisible && !vp.ghostInactiveSystems) continue;

      final customDef = valve.customDefinitionId != null
          ? (customValves?[valve.customDefinitionId!] ?? CustomValveCatalog.instance.getById(valve.customDefinitionId!))
          : null;

      final wireSegments = Element3dGeometry.generateValveWireframe(
        valve,
        start,
        end,
        pipeOuterDiameter: seg.outerDiameterMm,
        customDefinition: customDef,
      );

      final sys = network.systems[seg.systemId];
      final color = isVisible ? (sys?.colorValue ?? 0xFF000000) : 0xFFBDBDBD;
      final strokeW = styleConfig.fittingLineWidthMm;
      final handleStrokeW = math.max(0.1, strokeW * 0.45);

      for (final wire in wireSegments) {
        final w = wire.layer == Element3dGeometry.layerHandles ? handleStrokeW : strokeW;
        final p1 = _projectPoint(wire.x1, wire.y1, wire.z1, projector, vp);
        final p2 = _projectPoint(wire.x2, wire.y2, wire.z2, projector, vp);
        scene.addPolyline(
          layer: VectorSceneLayer.valves,
          points: [p1, p2],
          strokeWidthMm: w,
          colorValue: color,
          smoothJoin: true,
        );
      }
    }
  }

  // --- 6. Опоры и подвески ---
  static void _buildSupports(
    VectorScene scene,
    PipingNetwork network,
    dynamic vp,
    AxonometryProjector projector,
    DrawingStyleConfig styleConfig,
  ) {
    for (final support in network.supports.values) {
      final seg = network.segments[support.segmentId];
      if (seg == null) continue;
      final start = network.nodes[seg.startNodeId];
      final end = network.nodes[seg.endNodeId];
      if (start == null || end == null) continue;

      final isVisible = vp.visibleSystemIds == null || vp.visibleSystemIds!.contains(seg.systemId);
      if (!isVisible && !vp.ghostInactiveSystems) continue;

      final wireSegments = Element3dGeometry.generateSupportWireframe(
        support,
        start,
        end,
        pipeOuterDiameter: seg.outerDiameterMm,
      );

      final strokeW = styleConfig.thinLineWidthMm;
      final color = isVisible ? 0xFF37474F : 0xFFBDBDBD;
      for (final wire in wireSegments) {
        final p1 = _projectPoint(wire.x1, wire.y1, wire.z1, projector, vp);
        final p2 = _projectPoint(wire.x2, wire.y2, wire.z2, projector, vp);
        scene.addPolyline(
          layer: VectorSceneLayer.supports,
          points: [p1, p2],
          strokeWidthMm: strokeW,
          colorValue: color,
          smoothJoin: true,
        );
      }

      if (support.name.isNotEmpty) {
        final hasSupportCallout = network.callouts.values.any(
          (c) =>
              !c.isHidden &&
              c.targetType == CalloutTargetType.support &&
              (c.targetId == support.id || c.additionalTargetIds.contains(support.id)),
        );
        if (!hasSupportCallout) {
          final pos = support.calculatePosition(start, end);
          final posMm = _projectPoint(pos.x, pos.y, pos.z, projector, vp);
          scene.addText(
            layer: VectorSceneLayer.supports,
            text: support.name,
            position: Offset(posMm.dx, posMm.dy - 2.5),
            fontSizePt: 5.5,
            colorValue: color,
          );
        }
      }
    }
  }

  // --- 7. Сварные стыки (ГОСТ и 3D-кольца) ---
  static void _buildWelds(
    VectorScene scene,
    PipingNetwork network,
    dynamic vp,
    AxonometryProjector projector,
    DrawingStyleConfig styleConfig,
  ) {
    if (!styleConfig.showWeldJoints) return;

    for (final joint in network.weldJoints.values) {
      final seg = network.segments[joint.segmentId];
      if (seg == null) continue;
      final isVisible = vp.visibleSystemIds == null || vp.visibleSystemIds!.contains(seg.systemId);
      if (!isVisible) continue;

      final n1 = network.nodes[seg.startNodeId];
      final n2 = network.nodes[seg.endNodeId];
      if (n1 == null || n2 == null) continue;

      final style = joint.getEffectiveStyle(network.defaultWeldStyle);
      final effectiveTickSize = joint.getEffectiveTickSize(network.defaultWeldTickSizeMm, seg.outerDiameterMm);

      // Определение ориентации врезки
      Vector3D? directBranchMainDir3d;
      final nearNodeId = joint.ratio < 0.5 ? seg.startNodeId : seg.endNodeId;
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

      if (style == WeldJointStyle.tick) {
        final center3d = Vector3D.fromNode(joint.calculatePosition(n1, n2));
        final halfLenMm = effectiveTickSize * 0.5;
        final Vector3D p13d;
        final Vector3D p23d;

        if (directBranchMainDir3d != null) {
          p13d = center3d - directBranchMainDir3d * halfLenMm;
          p23d = center3d + directBranchMainDir3d * halfLenMm;
        } else {
          final vStart = Vector3D.fromNode(n1);
          final vEnd = Vector3D.fromNode(n2);
          final dx = vEnd.x - vStart.x;
          final dy = vEnd.y - vStart.y;
          final lenXy = math.sqrt(dx * dx + dy * dy);
          final Vector3D tickDir;
          if (lenXy > 1e-4) {
            tickDir = Vector3D(-dy / lenXy, dx / lenXy, 0.0);
          } else {
            tickDir = const Vector3D(0.0, 1.0, 0.0);
          }
          p13d = center3d - tickDir * halfLenMm;
          p23d = center3d + tickDir * halfLenMm;
        }

        var p1Mm = _projectPoint(p13d.x, p13d.y, p13d.z, projector, vp);
        var p2Mm = _projectPoint(p23d.x, p23d.y, p23d.z, projector, vp);

        final dist = (p2Mm - p1Mm).distance;
        if (dist < 1.5 && dist > 1e-4) {
          final mid = (p1Mm + p2Mm) * 0.5;
          final dir = (p2Mm - p1Mm) / dist;
          p1Mm = mid - dir * 0.75;
          p2Mm = mid + dir * 0.75;
        }

        scene.addPolyline(
          layer: VectorSceneLayer.welds,
          points: [p1Mm, p2Mm],
          strokeWidthMm: styleConfig.thinLineWidthMm,
          colorValue: 0xFF000000,
          smoothJoin: true,
        );
      } else if (style == WeldJointStyle.ring3d) {
        // Честное 3D-кольцо из Element3dGeometry
        final ringWires = Element3dGeometry.generateWeld3d(
          joint,
          n1,
          n2,
          pipeOuterDiameter: seg.outerDiameterMm,
          style: WeldJointStyle.ring3d,
          tickSizeMm: effectiveTickSize,
        );
        for (final wire in ringWires) {
          final p1 = _projectPoint(wire.x1, wire.y1, wire.z1, projector, vp);
          final p2 = _projectPoint(wire.x2, wire.y2, wire.z2, projector, vp);
          scene.addPolyline(
            layer: VectorSceneLayer.welds,
            points: [p1, p2],
            strokeWidthMm: styleConfig.thinLineWidthMm,
            colorValue: 0xFF000000,
            smoothJoin: true,
          );
        }
      } else if (style == WeldJointStyle.circle) {
        final center3d = joint.calculatePosition(n1, n2);
        final pMm = _projectPoint(center3d.x, center3d.y, center3d.z, projector, vp);
        scene.addCircle(
          layer: VectorSceneLayer.welds,
          center: pMm,
          radiusMm: math.max(0.6, effectiveTickSize * 0.25 * vp.viewScale),
          isFilled: false,
          strokeColorValue: 0xFF000000,
          strokeWidthMm: styleConfig.thinLineWidthMm,
        );
      } else if (style == WeldJointStyle.dot) {
        final center3d = joint.calculatePosition(n1, n2);
        final pMm = _projectPoint(center3d.x, center3d.y, center3d.z, projector, vp);
        scene.addCircle(
          layer: VectorSceneLayer.welds,
          center: pMm,
          radiusMm: 0.8,
          isFilled: true,
          strokeColorValue: 0xFF000000,
          fillColorValue: 0xFF000000,
        );
      }
    }
  }

  // --- 8. Размеры по ГОСТ 2.307 ---
  static void _buildDimensions(
    VectorScene scene,
    PipingNetwork network,
    dynamic vp,
    AxonometryProjector projector,
    DrawingStyleConfig styleConfig,
  ) {
    for (final dim in network.dimensions.values) {
      final p1Mm = _projectPoint(dim.startPoint.x, dim.startPoint.y, dim.startPoint.z, projector, vp);
      final p2Mm = _projectPoint(dim.endPoint.x, dim.endPoint.y, dim.endPoint.z, projector, vp);

      final delta = p2Mm - p1Mm;
      final dist2d = delta.distance;
      if (dist2d < 1.0) continue;

      final u = delta / dist2d;
      final n = Offset(-u.dy, u.dx);
      final offsetDist = (dim.offsetDistance == 0.0 ? 10.0 : dim.offsetDistance * vp.viewScale);
      final offsetVec = n * offsetDist;

      final dimP1 = p1Mm + offsetVec;
      final dimP2 = p2Mm + offsetVec;
      final overshoot = (offsetDist >= 0 ? 2.0 : -2.0);
      final extStart1 = p1Mm;
      final extStart2 = p2Mm;
      final extEnd1 = dimP1 + n * overshoot;
      final extEnd2 = dimP2 + n * overshoot;

      // Выносные линии
      scene.addPolyline(
        layer: VectorSceneLayer.dimensions,
        points: [extStart1, extEnd1],
        strokeWidthMm: styleConfig.thinLineWidthMm,
        colorValue: 0xFF37474F,
        smoothJoin: false,
      );
      scene.addPolyline(
        layer: VectorSceneLayer.dimensions,
        points: [extStart2, extEnd2],
        strokeWidthMm: styleConfig.thinLineWidthMm,
        colorValue: 0xFF37474F,
        smoothJoin: false,
      );

      // Размерная линия
      scene.addPolyline(
        layer: VectorSceneLayer.dimensions,
        points: [dimP1, dimP2],
        strokeWidthMm: styleConfig.thinLineWidthMm,
        colorValue: 0xFF37474F,
        smoothJoin: false,
      );

      // Засечки 45 градусов
      const tickLen = 1.8;
      final tickDir = (u + n) / math.sqrt(2) * tickLen;
      scene.addPolyline(
        layer: VectorSceneLayer.dimensions,
        points: [dimP1 - tickDir, dimP1 + tickDir],
        strokeWidthMm: styleConfig.pipeLineWidthMm,
        colorValue: 0xFF37474F,
        smoothJoin: true,
      );
      scene.addPolyline(
        layer: VectorSceneLayer.dimensions,
        points: [dimP2 - tickDir, dimP2 + tickDir],
        strokeWidthMm: styleConfig.pipeLineWidthMm,
        colorValue: 0xFF37474F,
        smoothJoin: true,
      );

      // Размерное число
      final label = dim.displayText;
      final mid = (dimP1 + dimP2) * 0.5 + n * (offsetDist >= 0 ? 1.5 : -2.5);
      scene.addText(
        layer: VectorSceneLayer.dimensions,
        text: label,
        position: mid,
        fontSizePt: 7.0,
        isBold: true,
        colorValue: 0xFF263238,
        maskPaddingMm: 0.5,
        maskFillColorValue: 0xFFFFFFFF,
      );
    }
  }

  // --- 9. Умные выноски ---
  static void _buildCallouts(
    VectorScene scene,
    PipingNetwork network,
    DrawingSheet sheet,
    dynamic vp,
    AxonometryProjector projector,
    DrawingStyleConfig styleConfig,
    Map<String, String>? calloutTemplates, {
    double Function(String text, double fontSizeMm, {bool isBold})? measureTextWidthMm,
  }) {
    final templates = calloutTemplates ?? defaultCalloutTemplates;
    const offsetScale = 0.35;
    const padXMm = 1.0;

    final drawItems = <_SheetCalloutDrawItem>[];
    for (final callout in network.callouts.values) {
      if (!sheet.isCalloutVisible(callout, network)) continue;

      final anchor3D = CalloutPainter.getTarget3DPoint(network, callout);
      if (anchor3D == null) continue;

      final anchorMm = _projectPoint(anchor3D.x, anchor3D.y, anchor3D.z, projector, vp);
      final effOffsetX = callout.getEffectiveOffsetX(sheet.id);
      final effOffsetY = callout.getEffectiveOffsetY(sheet.id);

      final isRight = callout.shelfDirection == ShelfDirection.right
          ? true
          : (callout.shelfDirection == ShelfDirection.left
              ? false
              : effOffsetX >= 0);
      final topText = network.generateCalloutText(callout, templates);
      final bottomText = network.generateCalloutBottomText(callout, templates);

      final topWidthMm = _measureTextWidth(
        topText,
        callout.textHeight,
        measureTextWidthMm: measureTextWidthMm,
      );
      final bottomWidthMm = (bottomText != null && bottomText.trim().isNotEmpty)
          ? _measureTextWidth(
              bottomText,
              callout.textHeight * 0.85,
              measureTextWidthMm: measureTextWidthMm,
            )
          : 0.0;
      final maxTextWidthMm = math.max(topWidthMm, bottomWidthMm);
      final shelfLengthMm = math.max(3.0, maxTextWidthMm + padXMm * 2.0);
      final shelfDir = isRight ? 1.0 : -1.0;

      final isElevation = callout.targetType == CalloutTargetType.node || callout.elevationStyle != null;
      if (isElevation) {
        final styleName = templates['elevation_style'];
        final defaultStyle = ElevationMarkStyleExt.fromString(styleName, fallback: ElevationMarkStyle.gostOutline);
        final effectiveStyle = callout.elevationStyle ?? defaultStyle;

        final flagH = callout.textHeight * 1.15;
        final flagW = callout.textHeight * 0.58;
        if (callout.arrowOnNode) {
          final shelfY = anchorMm.dy + effOffsetY * offsetScale;
          final isAbove = shelfY <= anchorMm.dy;
          final flagBaseY = isAbove ? anchorMm.dy - flagH : anchorMm.dy + flagH;
          final leaderEndMm = Offset(anchorMm.dx, shelfY);
          final shelfEndMm = leaderEndMm + Offset(shelfLengthMm * shelfDir, 0);

          _addElevationMarkSymbol(
            scene: scene,
            tipMm: anchorMm,
            flagBaseY: flagBaseY,
            shelfY: shelfY,
            flagW: flagW,
            isAbove: isAbove,
            style: effectiveStyle,
            strokeWidthMm: styleConfig.thinLineWidthMm,
            colorValue: callout.textColor,
          );
          // Полочка
          scene.addPolyline(
            layer: VectorSceneLayer.callouts,
            points: [leaderEndMm, shelfEndMm],
            strokeWidthMm: styleConfig.thinLineWidthMm,
            colorValue: callout.textColor,
            smoothJoin: true,
          );

          drawItems.add(_SheetCalloutDrawItem(
            callout: callout,
            anchorMm: anchorMm,
            leaderEndMm: leaderEndMm,
            shelfEndMm: shelfEndMm,
            shelfLengthMm: shelfLengthMm,
            isRight: isRight,
            topText: topText,
            bottomText: bottomText,
          ));
        } else {
          final leaderEndMm = anchorMm + Offset(effOffsetX * offsetScale, effOffsetY * offsetScale);
          final flagTopY = leaderEndMm.dy - flagH;
          final shelfY = effectiveStyle == ElevationMarkStyle.compactFlag
              ? leaderEndMm.dy - (callout.textHeight * 1.6)
              : flagTopY - 1.5;
          final shelfStartMm = Offset(leaderEndMm.dx, shelfY);
          final shelfEndMm = shelfStartMm + Offset(shelfLengthMm * shelfDir, 0);

          // Выносная ножка от объекта к стрелке
          if ((anchorMm - leaderEndMm).distance > 0.5) {
            scene.addPolyline(
              layer: VectorSceneLayer.callouts,
              points: [anchorMm, leaderEndMm],
              strokeWidthMm: styleConfig.thinLineWidthMm,
              colorValue: callout.textColor,
              smoothJoin: true,
            );
          }

          _addElevationMarkSymbol(
            scene: scene,
            tipMm: leaderEndMm,
            flagBaseY: flagTopY,
            shelfY: shelfY,
            flagW: flagW,
            isAbove: true,
            style: effectiveStyle,
            strokeWidthMm: styleConfig.thinLineWidthMm,
            colorValue: callout.textColor,
          );

          // Полочка
          scene.addPolyline(
            layer: VectorSceneLayer.callouts,
            points: [shelfStartMm, shelfEndMm],
            strokeWidthMm: styleConfig.thinLineWidthMm,
            colorValue: callout.textColor,
            smoothJoin: true,
          );

          drawItems.add(_SheetCalloutDrawItem(
            callout: callout,
            anchorMm: anchorMm,
            leaderEndMm: shelfStartMm,
            shelfEndMm: shelfEndMm,
            shelfLengthMm: shelfLengthMm,
            isRight: isRight,
            topText: topText,
            bottomText: bottomText,
          ));
        }
      } else {
        final leaderEndMm = anchorMm + Offset(effOffsetX * offsetScale, effOffsetY * offsetScale);
        final shelfEndMm = leaderEndMm + Offset(shelfLengthMm * shelfDir, 0);

        // Линия выноски
        scene.addPolyline(
          layer: VectorSceneLayer.callouts,
          points: [anchorMm, leaderEndMm],
          strokeWidthMm: styleConfig.thinLineWidthMm,
          colorValue: callout.textColor,
          smoothJoin: true,
        );
        // Горизонтальная полка
        scene.addPolyline(
          layer: VectorSceneLayer.callouts,
          points: [leaderEndMm, shelfEndMm],
          strokeWidthMm: styleConfig.thinLineWidthMm,
          colorValue: callout.textColor,
          smoothJoin: true,
        );
        // Засечка/точка привязки
        scene.addCircle(
          layer: VectorSceneLayer.callouts,
          center: anchorMm,
          radiusMm: 0.5,
          isFilled: true,
          strokeColorValue: callout.textColor,
          fillColorValue: callout.textColor,
        );

        // Дополнительные ножки для объединенных вилочных выносок ("Ласточкин хвост / Звезда")
        if (callout.additionalTargetIds.isNotEmpty) {
          for (final addTargetId in callout.additionalTargetIds) {
            final addAnchor3D = CalloutPainter.getTarget3DPointForTarget(network, callout.targetType, addTargetId);
            if (addAnchor3D != null) {
              final addAnchorMm = _projectPoint(addAnchor3D.x, addAnchor3D.y, addAnchor3D.z, projector, vp);
              scene.addPolyline(
                layer: VectorSceneLayer.callouts,
                points: [addAnchorMm, leaderEndMm],
                strokeWidthMm: styleConfig.thinLineWidthMm,
                colorValue: callout.textColor,
                smoothJoin: true,
              );
              scene.addCircle(
                layer: VectorSceneLayer.callouts,
                center: addAnchorMm,
                radiusMm: 0.5,
                isFilled: true,
                strokeColorValue: callout.textColor,
                fillColorValue: callout.textColor,
              );
            }
          }
        }

        drawItems.add(_SheetCalloutDrawItem(
          callout: callout,
          anchorMm: anchorMm,
          leaderEndMm: leaderEndMm,
          shelfEndMm: shelfEndMm,
          shelfLengthMm: shelfLengthMm,
          isRight: isRight,
          topText: topText,
          bottomText: bottomText,
        ));
      }
    }

    // Отрисовываем тексты выносок (без белой заливки, чтобы не закрашивать полку и элементы позади)
    for (final item in drawItems) {
      _renderVectorCalloutTexts(scene, item);
    }
  }

  static void _addElevationMarkSymbol({
    required VectorScene scene,
    required Offset tipMm,
    required double flagBaseY,
    required double shelfY,
    required double flagW,
    required bool isAbove,
    required ElevationMarkStyle style,
    required double strokeWidthMm,
    required int colorValue,
  }) {
    switch (style) {
      case ElevationMarkStyle.gostOutline:
        scene.addPolyline(
          layer: VectorSceneLayer.callouts,
          points: [
            tipMm,
            Offset(tipMm.dx - flagW, flagBaseY),
            Offset(tipMm.dx + flagW, flagBaseY),
            tipMm,
          ],
          strokeWidthMm: strokeWidthMm,
          colorValue: colorValue,
          smoothJoin: false,
          isClosed: true,
        );
        scene.addPolyline(
          layer: VectorSceneLayer.callouts,
          points: [Offset(tipMm.dx, flagBaseY), Offset(tipMm.dx, shelfY)],
          strokeWidthMm: strokeWidthMm,
          colorValue: colorValue,
          smoothJoin: false,
        );
        break;

      case ElevationMarkStyle.gostFilled:
        scene.addItem(
          VectorSceneLayer.callouts,
          VectorPath(
            commands: [
              VectorPathMoveTo(tipMm),
              VectorPathLineTo(Offset(tipMm.dx - flagW, flagBaseY)),
              VectorPathLineTo(Offset(tipMm.dx + flagW, flagBaseY)),
              const VectorPathClose(),
            ],
            fillColorValue: colorValue,
            strokeColorValue: colorValue,
            strokeWidthMm: strokeWidthMm,
            smoothJoin: false,
          ),
        );
        scene.addPolyline(
          layer: VectorSceneLayer.callouts,
          points: [Offset(tipMm.dx, flagBaseY), Offset(tipMm.dx, shelfY)],
          strokeWidthMm: strokeWidthMm,
          colorValue: colorValue,
          smoothJoin: false,
        );
        break;

      case ElevationMarkStyle.compactFlag:
        scene.addPolyline(
          layer: VectorSceneLayer.callouts,
          points: [tipMm, Offset(tipMm.dx, shelfY)],
          strokeWidthMm: strokeWidthMm,
          colorValue: colorValue,
          smoothJoin: false,
        );
        scene.addPolyline(
          layer: VectorSceneLayer.callouts,
          points: [
            Offset(tipMm.dx - 1.2, tipMm.dy + 1.2),
            Offset(tipMm.dx + 1.2, tipMm.dy - 1.2),
          ],
          strokeWidthMm: strokeWidthMm,
          colorValue: colorValue,
          smoothJoin: false,
        );
        break;

      case ElevationMarkStyle.isoCircle:
        const circleR = 1.5;
        scene.addCircle(
          layer: VectorSceneLayer.callouts,
          center: tipMm,
          radiusMm: circleR,
          isFilled: false,
          strokeColorValue: colorValue,
          strokeWidthMm: strokeWidthMm,
        );
        scene.addPolyline(
          layer: VectorSceneLayer.callouts,
          points: [Offset(tipMm.dx - circleR, tipMm.dy), Offset(tipMm.dx + circleR, tipMm.dy)],
          strokeWidthMm: strokeWidthMm,
          colorValue: colorValue,
          smoothJoin: false,
        );
        scene.addPolyline(
          layer: VectorSceneLayer.callouts,
          points: [Offset(tipMm.dx, tipMm.dy - circleR), Offset(tipMm.dx, tipMm.dy + circleR)],
          strokeWidthMm: strokeWidthMm,
          colorValue: colorValue,
          smoothJoin: false,
        );
        final edgeY = isAbove ? tipMm.dy - circleR : tipMm.dy + circleR;
        scene.addPolyline(
          layer: VectorSceneLayer.callouts,
          points: [Offset(tipMm.dx, edgeY), Offset(tipMm.dx, shelfY)],
          strokeWidthMm: strokeWidthMm,
          colorValue: colorValue,
          smoothJoin: false,
        );
        break;
    }
  }

  static void _renderVectorCalloutTexts(VectorScene scene, _SheetCalloutDrawItem item) {
    final shelfLeftX = math.min(item.leaderEndMm.dx, item.shelfEndMm.dx);
    final textX = shelfLeftX + 1.0;
    final shelfY = item.leaderEndMm.dy;
    final topBaselineMm = shelfY - 0.55;
    final bottomAscentMm = (item.callout.textHeight * 0.85) * 0.78;
    final bottomBaselineMm = shelfY + 0.55 + bottomAscentMm;

    if (item.topText.isNotEmpty) {
      scene.addText(
        layer: VectorSceneLayer.callouts,
        text: item.topText,
        position: Offset(textX, topBaselineMm),
        fontSizePt: item.callout.textHeight * 2.83465,
        colorValue: item.callout.textColor,
        isLeftAligned: true,
      );
    }
    if (item.bottomText != null && item.bottomText!.trim().isNotEmpty) {
      scene.addText(
        layer: VectorSceneLayer.callouts,
        text: item.bottomText!,
        position: Offset(textX, bottomBaselineMm),
        fontSizePt: item.callout.textHeight * 0.85 * 2.83465,
        colorValue: item.callout.textColor,
        isLeftAligned: true,
      );
    }
  }

  // --- 10. Рамка и штамп по ГОСТ 21.101-2020 Форма 3 ---
  static void _buildFrameAndStamp(
    VectorScene scene,
    DrawingSheet sheet,
    DrawingStyleConfig styleConfig,
  ) {
    final widthMm = sheet.format.widthMm;
    final heightMm = sheet.format.heightMm;
    final frameLeftMm = sheet.format.frameLeftMm;
    final frameTopMm = sheet.format.frameTopMm;
    final frameRightMm = sheet.format.frameRightMm;
    final frameBottomMm = sheet.format.frameBottomMm;
    final printableW = sheet.format.printableWidthMm;
    final printableH = sheet.format.printableHeightMm;

    // Внешняя основная рамка листа (20-5-5-5)
    scene.addRect(
      layer: VectorSceneLayer.frameAndStamp,
      rect: Rect.fromLTWH(frameLeftMm, frameTopMm, printableW, printableH),
      strokeWidthMm: styleConfig.frameLineWidthMm,
      strokeColorValue: 0xFF000000,
    );

    // Штамп Форма 3 (185х55 мм) в правом нижнем углу
    final stampLeftMm = widthMm - frameRightMm - 185.0;
    final stampTopMm = heightMm - frameBottomMm - 55.0;
    final stampRightMm = widthMm - frameRightMm;
    final stampBottomMm = heightMm - frameBottomMm;

    // Белая подложка под штамп и внешняя рамка штампа
    scene.addRect(
      layer: VectorSceneLayer.frameAndStamp,
      rect: Rect.fromLTWH(stampLeftMm, stampTopMm, 185.0, 55.0),
      fillColorValue: 0xFFFFFFFF,
      strokeWidthMm: styleConfig.stampBorderWidthMm,
      strokeColorValue: 0xFF000000,
    );

    // Основной вертикальный разделитель: X = 65 мм слева (блок согласований/изменений)
    final xApprovalsEnd = stampLeftMm + 65.0;
    scene.addLine(
      layer: VectorSceneLayer.frameAndStamp,
      start: Offset(xApprovalsEnd, stampTopMm),
      end: Offset(xApprovalsEnd, stampBottomMm),
      strokeWidthMm: styleConfig.stampBorderWidthMm,
      colorValue: 0xFF000000,
      smoothJoin: false,
    );

    // Сквозная горизонтальная линия на 25 мм от верха штампа (по всей ширине 0..185 мм)
    final yMid25 = stampTopMm + 25.0;
    scene.addLine(
      layer: VectorSceneLayer.frameAndStamp,
      start: Offset(stampLeftMm, yMid25),
      end: Offset(stampRightMm, yMid25),
      strokeWidthMm: styleConfig.stampBorderWidthMm,
      colorValue: 0xFF000000,
      smoothJoin: false,
    );

    // --- ЛЕВЫЙ БЛОК (0..65 мм) ---
    // Строки изменений (4 строки по 5 мм вверху левого блока: Y = 5, 10, 15, 20 мм)
    for (int i = 1; i <= 4; i++) {
      final y = stampTopMm + (i * 5.0);
      scene.addLine(
        layer: VectorSceneLayer.frameAndStamp,
        start: Offset(stampLeftMm, y),
        end: Offset(xApprovalsEnd, y),
        strokeWidthMm: styleConfig.stampGridWidthMm,
        colorValue: 0xFF000000,
        smoothJoin: false,
      );
    }

    // Вертикальные линии колонок изменений (X = 10, 20, 30, 40, 55 мм)
    const revCols = [10.0, 20.0, 30.0, 40.0, 55.0];
    for (final col in revCols) {
      scene.addLine(
        layer: VectorSceneLayer.frameAndStamp,
        start: Offset(stampLeftMm + col, stampTopMm),
        end: Offset(stampLeftMm + col, yMid25),
        strokeWidthMm: styleConfig.stampGridWidthMm,
        colorValue: 0xFF000000,
        smoothJoin: false,
      );
    }

    // Строки блока согласований (5 горизонтальных линий через каждые 5 мм внизу левого блока: Y = 30..50 мм)
    for (int i = 1; i <= 5; i++) {
      final y = yMid25 + (i * 5.0);
      scene.addLine(
        layer: VectorSceneLayer.frameAndStamp,
        start: Offset(stampLeftMm, y),
        end: Offset(xApprovalsEnd, y),
        strokeWidthMm: styleConfig.stampGridWidthMm,
        colorValue: 0xFF000000,
        smoothJoin: false,
      );
    }

    // Вертикальные колонки блока согласований (Должность 20 мм, Фамилия 20 мм, Подпись 15 мм, Дата 10 мм)
    const apprCols = [20.0, 40.0, 55.0];
    for (final col in apprCols) {
      scene.addLine(
        layer: VectorSceneLayer.frameAndStamp,
        start: Offset(stampLeftMm + col, yMid25),
        end: Offset(stampLeftMm + col, stampBottomMm),
        strokeWidthMm: styleConfig.stampGridWidthMm,
        colorValue: 0xFF000000,
        smoothJoin: false,
      );
    }

    // --- ПРАВЫЙ БЛОК (65..185 мм, ширина 120 мм) ---
    // Строка 1 (Y = 0..10 мм): Графа 4 (Шифр документа) — горизонтальный разделитель на Y = 10 мм
    final yRow1 = stampTopMm + 10.0;
    scene.addLine(
      layer: VectorSceneLayer.frameAndStamp,
      start: Offset(xApprovalsEnd, yRow1),
      end: Offset(stampRightMm, yRow1),
      strokeWidthMm: styleConfig.stampBorderWidthMm,
      colorValue: 0xFF000000,
      smoothJoin: false,
    );

    // Вертикальный разделитель между центральной частью (65..135 мм, ширина 70 мм)
    // и правой частью (135..185 мм, ширина 50 мм) от Y = 25 мм до самого низа штампа (Y = 55 мм)
    final xStageStart = stampLeftMm + 135.0;
    scene.addLine(
      layer: VectorSceneLayer.frameAndStamp,
      start: Offset(xStageStart, yMid25),
      end: Offset(xStageStart, stampBottomMm),
      strokeWidthMm: styleConfig.stampBorderWidthMm,
      colorValue: 0xFF000000,
      smoothJoin: false,
    );

    // Сквозной горизонтальный разделитель строк 3 и 4 в правом блоке при Y = 40 мм (от X = 65 до X = 185 мм)
    final yRow3 = stampTopMm + 40.0;
    scene.addLine(
      layer: VectorSceneLayer.frameAndStamp,
      start: Offset(xApprovalsEnd, yRow3),
      end: Offset(stampRightMm, yRow3),
      strokeWidthMm: styleConfig.stampBorderWidthMm,
      colorValue: 0xFF000000,
      smoothJoin: false,
    );

    // Горизонтальная линия шапки «Стадия | Лист | Листов» при Y = 30 мм (от X = 135 до X = 185 мм)
    final yStageHeader = stampTopMm + 30.0;
    scene.addLine(
      layer: VectorSceneLayer.frameAndStamp,
      start: Offset(xStageStart, yStageHeader),
      end: Offset(stampRightMm, yStageHeader),
      strokeWidthMm: styleConfig.stampGridWidthMm,
      colorValue: 0xFF000000,
      smoothJoin: false,
    );

    // Вертикальные разделители колонок «Стадия» (15 мм), «Лист» (15 мм), «Листов» (20 мм) от Y = 25 до Y = 40 мм
    scene.addLine(
      layer: VectorSceneLayer.frameAndStamp,
      start: Offset(xStageStart + 15.0, yMid25),
      end: Offset(xStageStart + 15.0, yRow3),
      strokeWidthMm: styleConfig.stampBorderWidthMm,
      colorValue: 0xFF000000,
      smoothJoin: false,
    );
    scene.addLine(
      layer: VectorSceneLayer.frameAndStamp,
      start: Offset(xStageStart + 30.0, yMid25),
      end: Offset(xStageStart + 30.0, yRow3),
      strokeWidthMm: styleConfig.stampBorderWidthMm,
      colorValue: 0xFF000000,
      smoothJoin: false,
    );
  }

  // --- 1.1. Контекстные «хвосты» примыкающих магистралей на листе узла (Вариант 1) ---
  static void _buildDetailContextStubs(
    VectorScene scene,
    PipingNetwork network,
    DetailNode detailNode,
    dynamic vp,
    AxonometryProjector projector,
    DrawingStyleConfig styleConfig,
  ) {
    final stubs = network.getDetailNodeAdjacentStubs(detailNode);
    for (final stub in stubs) {
      final p1 = _projectPoint(stub.startX, stub.startY, stub.startZ, projector, vp);
      final p2 = _projectPoint(stub.endX, stub.endY, stub.endZ, projector, vp);

      scene.addPolyline(
        layer: VectorSceneLayer.pipes,
        points: [p1, p2],
        strokeWidthMm: math.max(0.25, styleConfig.getPipeStrokeWidthMm(stub.dn) * 0.65),
        colorValue: 0xFF90A4AE, // Бледно-серый контекст основной магистрали
        smoothJoin: true,
        dashPattern: const [3.0, 1.5],
      );

      // Зигзагообразная засечка обрыва трубы на конце контекстного участка (ГОСТ 2.303)
      final dir = p2 - p1;
      final dist = dir.distance;
      if (dist > 1.5) {
        final u = dir / dist;
        final n = Offset(-u.dy, u.dx);
        const w = 1.8;
        const z = 0.7;
        scene.addPolyline(
          layer: VectorSceneLayer.pipes,
          points: [
            p2 - n * w,
            p2 - n * (w * 0.3) + u * z,
            p2 + n * (w * 0.3) - u * z,
            p2 + n * w,
          ],
          strokeWidthMm: styleConfig.thinLineWidthMm,
          colorValue: 0xFF78909C,
          smoothJoin: true,
        );
      }
    }
  }

  /// Вычисляет 2D-геометрию контура обводки и полки выноски укрупненного узла в мм листа
  static DetailNodeSheetGeometry? computeDetailNodeSheetGeometry({
    required DetailNode detailNode,
    required PipingNetwork network,
    required SheetViewport viewport,
    required AxonometryProjector projector,
    double Function(String text, double fontSizeMm, {bool isBold})? measureTextWidthMm,
  }) {
    final hasAnySegment = detailNode.segmentIds.any((sId) => network.segments.containsKey(sId));
    if (!hasAnySegment) return null;

    final rawBounds = detailNode.calculateModel2dBounds(network, projector);
    if (rawBounds == null) return null;

    final p1 = ViewportTransformService.model2dToSheetMm(rawBounds.topLeft, viewport);
    final p2 = ViewportTransformService.model2dToSheetMm(rawBounds.bottomRight, viewport);
    final baseRectMm = Rect.fromLTRB(
      math.min(p1.dx, p2.dx),
      math.min(p1.dy, p2.dy),
      math.max(p1.dx, p2.dx),
      math.max(p1.dy, p2.dy),
    );
    final paddedRectMm = baseRectMm.inflate(math.max(2.0, detailNode.paddingMm));

    late final Rect boundsMm;
    final perimeterPointsMm = <Offset>[];
    final polygonVerticesMm = <Offset>[];

    switch (detailNode.boundaryShape) {
      case DetailBoundaryShape.polygon:
        final marginModel = math.max(2.0, detailNode.paddingMm) / math.max(0.0005, viewport.viewScale);
        final rawPoly = detailNode.getEffectivePolygonModel2d(
          network,
          projector,
          marginModelUnits: marginModel,
        );
        double minX = double.infinity, maxX = -double.infinity;
        double minY = double.infinity, maxY = -double.infinity;
        for (final pt in rawPoly) {
          final mm = ViewportTransformService.model2dToSheetMm(pt, viewport);
          polygonVerticesMm.add(mm);
          perimeterPointsMm.add(mm);
          if (mm.dx < minX) minX = mm.dx;
          if (mm.dx > maxX) maxX = mm.dx;
          if (mm.dy < minY) minY = mm.dy;
          if (mm.dy > maxY) maxY = mm.dy;
        }
        boundsMm = minX.isFinite
            ? Rect.fromLTRB(minX, minY, maxX, maxY)
            : paddedRectMm;
        break;

      case DetailBoundaryShape.circle:
        final r = math.max(4.0, math.max(paddedRectMm.width, paddedRectMm.height) / 2.0);
        final c = paddedRectMm.center;
        boundsMm = Rect.fromCircle(center: c, radius: r);
        const int n = 24;
        for (int i = 0; i < n; i++) {
          final a = (2.0 * math.pi * i) / n;
          perimeterPointsMm.add(Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a)));
        }
        break;

      case DetailBoundaryShape.oval:
        final rx = math.max(4.0, (paddedRectMm.width * 1.15) / 2.0);
        final ry = math.max(4.0, (paddedRectMm.height * 1.15) / 2.0);
        final c = paddedRectMm.center;
        boundsMm = Rect.fromCenter(center: c, width: rx * 2.0, height: ry * 2.0);
        const int n = 24;
        for (int i = 0; i < n; i++) {
          final a = (2.0 * math.pi * i) / n;
          perimeterPointsMm.add(Offset(c.dx + rx * math.cos(a), c.dy + ry * math.sin(a)));
        }
        break;

      case DetailBoundaryShape.roundedRect:
        boundsMm = paddedRectMm;
        final cr = math.min(3.5, math.min(boundsMm.width, boundsMm.height) * 0.25);
        // Сэмплируем скругленные углы в контур
        final corners = [
          (Offset(boundsMm.right - cr, boundsMm.top + cr), -math.pi / 2, 0.0),
          (Offset(boundsMm.right - cr, boundsMm.bottom - cr), 0.0, math.pi / 2),
          (Offset(boundsMm.left + cr, boundsMm.bottom - cr), math.pi / 2, math.pi),
          (Offset(boundsMm.left + cr, boundsMm.top + cr), math.pi, 1.5 * math.pi),
        ];
        for (final corner in corners) {
          const int steps = 4;
          for (int s = 0; s <= steps; s++) {
            final a = corner.$2 + (corner.$3 - corner.$2) * (s / steps);
            perimeterPointsMm.add(Offset(
              corner.$1.dx + cr * math.cos(a),
              corner.$1.dy + cr * math.sin(a),
            ));
          }
        }
        break;
    }

    final Offset shelfStartMm = detailNode.shelfPositionModel2d != null
        ? ViewportTransformService.model2dToSheetMm(detailNode.shelfPositionModel2d!, viewport)
        : Offset(boundsMm.right + 6.0, boundsMm.top - 5.0);

    final isRight = shelfStartMm.dx >= boundsMm.center.dx;
    final topText = detailNode.effectiveTitle;
    final bottomText = detailNode.effectiveSheetLabel;
    final topW = _measureTextWidth(topText, 3.0, isBold: true, measureTextWidthMm: measureTextWidthMm);
    final botW = _measureTextWidth(bottomText, 2.54, isBold: false, measureTextWidthMm: measureTextWidthMm);
    final shelfLenMm = math.max(10.0, math.max(topW, botW) + 2.0);
    final shelfEndMm = shelfStartMm + Offset(isRight ? shelfLenMm : -shelfLenMm, 0.0);
    final contourAttachMm = DetailNode.findClosestPointOnPolygon(shelfStartMm, perimeterPointsMm);

    return DetailNodeSheetGeometry(
      detailNode: detailNode,
      boundsMm: boundsMm,
      perimeterPointsMm: perimeterPointsMm,
      polygonVerticesMm: polygonVerticesMm,
      contourAttachMm: contourAttachMm,
      shelfStartMm: shelfStartMm,
      shelfEndMm: shelfEndMm,
      shelfLengthMm: shelfLenMm,
      isRight: isRight,
      topText: topText,
      bottomText: bottomText,
    );
  }

  // --- 9.1. Отрисовка контуров и выносок укрупненных узлов на общих листах ---
  static void _buildDetailNodeBoundaries(
    VectorScene scene,
    PipingNetwork fullNetwork,
    PipingNetwork effectiveNetwork,
    SheetViewport vp,
    AxonometryProjector projector,
    DrawingStyleConfig styleConfig, {
    double Function(String text, double fontSizeMm, {bool isBold})? measureTextWidthMm,
  }) {
    for (final dn in fullNetwork.detailNodes.values) {
      final hasVisibleSeg = dn.segmentIds.any((sId) => effectiveNetwork.segments.containsKey(sId));
      if (!hasVisibleSeg) continue;

      final geom = computeDetailNodeSheetGeometry(
        detailNode: dn,
        network: fullNetwork,
        viewport: vp,
        projector: projector,
        measureTextWidthMm: measureTextWidthMm,
      );
      if (geom == null) continue;

      const contourColor = 0xFF1565C0; // Синий ГОСТ-акцент контура узла
      final strokeW = math.max(0.25, styleConfig.thinLineWidthMm * 1.25);

      switch (dn.boundaryShape) {
        case DetailBoundaryShape.circle:
          scene.addCircle(
            layer: VectorSceneLayer.annotations,
            center: geom.boundsMm.center,
            radiusMm: geom.boundsMm.width / 2.0,
            isFilled: false,
            strokeColorValue: contourColor,
            strokeWidthMm: strokeW,
          );
          break;
        case DetailBoundaryShape.oval:
          scene.addEllipse(
            layer: VectorSceneLayer.annotations,
            center: geom.boundsMm.center,
            radiusXMm: geom.boundsMm.width / 2.0,
            radiusYMm: geom.boundsMm.height / 2.0,
            isFilled: false,
            strokeColorValue: contourColor,
            strokeWidthMm: strokeW,
          );
          break;
        case DetailBoundaryShape.roundedRect:
        case DetailBoundaryShape.polygon:
          if (geom.perimeterPointsMm.length >= 3) {
            scene.addPolyline(
              layer: VectorSceneLayer.annotations,
              points: geom.perimeterPointsMm,
              strokeWidthMm: strokeW,
              colorValue: contourColor,
              smoothJoin: true,
              isClosed: true,
              dashPattern: const [4.0, 2.0],
            );
          }
          break;
      }

      // Выносная линия от контура к полке и сама полка
      scene.addPolyline(
        layer: VectorSceneLayer.callouts,
        points: [geom.contourAttachMm, geom.shelfStartMm, geom.shelfEndMm],
        strokeWidthMm: strokeW,
        colorValue: contourColor,
        smoothJoin: true,
      );

      // Текст над полкой ("Узел А") и под полкой ("Лист 2") без непрозрачного заднего фона
      final shelfLeftX = math.min(geom.shelfStartMm.dx, geom.shelfEndMm.dx);
      final textX = shelfLeftX + 1.0;
      final shelfY = geom.shelfStartMm.dy;
      scene.addText(
        layer: VectorSceneLayer.callouts,
        text: geom.topText,
        position: Offset(textX, shelfY - 0.6),
        fontSizePt: 8.5,
        isBold: true,
        colorValue: contourColor,
        isLeftAligned: true,
      );
      if (geom.bottomText.isNotEmpty) {
        scene.addText(
          layer: VectorSceneLayer.callouts,
          text: geom.bottomText,
          position: Offset(textX, shelfY + 2.6),
          fontSizePt: 7.2,
          isBold: false,
          colorValue: 0xFF37474F,
          isLeftAligned: true,
        );
      }
    }
  }
}

class _SheetCalloutDrawItem {
  final Callout callout;
  final Offset anchorMm;
  final Offset leaderEndMm;
  final Offset shelfEndMm;
  final double shelfLengthMm;
  final bool isRight;
  final String topText;
  final String? bottomText;

  _SheetCalloutDrawItem({
    required this.callout,
    required this.anchorMm,
    required this.leaderEndMm,
    required this.shelfEndMm,
    required this.shelfLengthMm,
    required this.isRight,
    required this.topText,
    this.bottomText,
  });
}
