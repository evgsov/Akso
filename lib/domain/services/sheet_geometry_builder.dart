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
import '../models/drawing_sheet.dart';
import '../models/drawing_style_config.dart';
import '../models/equipment.dart';
import '../models/node_3d.dart';
import '../models/piping_network.dart';
import '../models/vector_scene.dart';
import 'custom_valve_catalog.dart';
import 'element_3d_geometry.dart';
import 'viewport_transform_service.dart';

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
  }) {
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
    _buildAxes(scene, network, vp, projector, styleConfig);

    // 2. Технологическое оборудование
    _buildEquipment(scene, network, vp, projector, styleConfig);

    // 3. Трассы трубопроводов (катушки / сегменты)
    _buildPipes(scene, network, vp, projector, styleConfig);

    // 4. Фасонные детали (отводы, тройники, переходы, фланцы, заглушки)
    _buildFittings(scene, network, vp, projector, styleConfig);

    // 5. Арматура
    _buildValves(scene, network, vp, projector, styleConfig, customValves);

    // 6. Опоры и подвески
    _buildSupports(scene, network, vp, projector, styleConfig);

    // 7. Сварные стыки (ГОСТ / 3D-кольца / засечки)
    _buildWelds(scene, network, vp, projector, styleConfig);

    // 8. Размеры (ГОСТ 2.307)
    _buildDimensions(scene, network, vp, projector, styleConfig);

    // 9. Выноски
    _buildCallouts(scene, network, vp, projector, styleConfig, calloutTemplates);

    // 10. Рамка листа (20-5-5-5) и штамп Форма 3 (ГОСТ 21.101-2020)
    _buildFrameAndStamp(scene, sheet, styleConfig);

    return scene;
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
    DrawingStyleConfig styleConfig,
  ) {
    if (network.spools.isNotEmpty) {
      for (final spool in network.spools.values) {
        final seg = network.segments[spool.segmentId];
        if (seg == null) continue;
        if (network.isButtJoint(seg.id)) continue;

        final isVisible = vp.visibleSystemIds == null || vp.visibleSystemIds!.contains(seg.systemId);
        if (!isVisible && !vp.ghostInactiveSystems) continue;

        final start = spool.startPoint ?? network.nodes[seg.startNodeId];
        final end = spool.endPoint ?? network.nodes[seg.endNodeId];
        if (start == null || end == null) continue;

        final sys = network.systems[seg.systemId];
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
      for (final seg in network.segments.values) {
        final isVisible = vp.visibleSystemIds == null || vp.visibleSystemIds!.contains(seg.systemId);
        if (!isVisible && !vp.ghostInactiveSystems) continue;

        final n1 = network.nodes[seg.startNodeId];
        final n2 = network.nodes[seg.endNodeId];
        if (n1 == null || n2 == null) continue;

        final sys = network.systems[seg.systemId];
        final color = isVisible ? (sys?.colorValue ?? 0xFF000000) : 0xFFBDBDBD;
        final strokeW = isVisible ? styleConfig.getPipeStrokeWidthMm(seg.dn) : styleConfig.thinLineWidthMm;

        final segValves = network.valves.values.where((v) => v.segmentId == seg.id).toList();
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

      final label = support.name.isNotEmpty ? support.name : support.type.shortCode;
      final pos = support.calculatePosition(start, end);
      final posMm = _projectPoint(pos.x, pos.y, pos.z, projector, vp);
      scene.addText(
        layer: VectorSceneLayer.supports,
        text: label,
        position: Offset(posMm.dx, posMm.dy - 2.5),
        fontSizePt: 5.5,
        colorValue: color,
        maskPaddingMm: 0.5,
        maskFillColorValue: 0xFFFFFFFF,
      );
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
    dynamic vp,
    AxonometryProjector projector,
    DrawingStyleConfig styleConfig,
    Map<String, String>? calloutTemplates,
  ) {
    for (final callout in network.callouts.values) {
      final anchor3D = CalloutPainter.getTarget3DPoint(network, callout);
      if (anchor3D == null) continue;

      final anchorMm = _projectPoint(anchor3D.x, anchor3D.y, anchor3D.z, projector, vp);
      const offsetScale = 0.35;
      final leaderEndMm = anchorMm + Offset(callout.screenOffsetX * offsetScale, callout.screenOffsetY * offsetScale);

      final isRight = callout.screenOffsetX >= 0;
      final templates = calloutTemplates ?? defaultCalloutTemplates;
      final topText = network.generateCalloutText(callout, templates);
      final bottomText = network.generateCalloutBottomText(callout, templates);

      final charWidthMm = callout.textHeight * 0.65;
      double shelfLengthMm = math.max(8.0, topText.length * charWidthMm + 3.0);
      if (bottomText != null && bottomText.trim().isNotEmpty) {
        shelfLengthMm = math.max(shelfLengthMm, bottomText.length * (charWidthMm * 0.9) + 3.0);
      }
      final shelfDir = isRight ? 1.0 : -1.0;
      final shelfEndMm = leaderEndMm + Offset(shelfLengthMm * shelfDir, 0);

      // Линия-выноска
      scene.addPolyline(
        layer: VectorSceneLayer.callouts,
        points: [anchorMm, leaderEndMm],
        strokeWidthMm: styleConfig.thinLineWidthMm,
        colorValue: 0xFF37474F,
        smoothJoin: true,
      );

      // Полка выноски
      scene.addPolyline(
        layer: VectorSceneLayer.callouts,
        points: [leaderEndMm, shelfEndMm],
        strokeWidthMm: styleConfig.thinLineWidthMm,
        colorValue: 0xFF37474F,
        smoothJoin: true,
      );

      // Точка-стрелка у объекта
      scene.addCircle(
        layer: VectorSceneLayer.callouts,
        center: anchorMm,
        radiusMm: 0.6,
        isFilled: true,
        strokeColorValue: 0xFF37474F,
        fillColorValue: 0xFF37474F,
      );

      // Текст над полкой
      if (topText.isNotEmpty) {
        scene.addText(
          layer: VectorSceneLayer.callouts,
          text: topText,
          position: Offset(isRight ? leaderEndMm.dx + 1.0 : shelfEndMm.dx + 1.0, leaderEndMm.dy - 1.2),
          fontSizePt: callout.textHeight * 2.83465,
          colorValue: 0xFF263238,
        );
      }
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

    // Белая подложка под штамп
    scene.addRect(
      layer: VectorSceneLayer.frameAndStamp,
      rect: Rect.fromLTWH(stampLeftMm, stampTopMm, 185.0, 55.0),
      fillColorValue: 0xFFFFFFFF,
      strokeWidthMm: styleConfig.stampBorderWidthMm,
      strokeColorValue: 0xFF000000,
    );

    // Разделитель таблицы изменений (65 мм слева)
    final xApprovalsEnd = stampLeftMm + 65.0;
    scene.addLine(
      layer: VectorSceneLayer.frameAndStamp,
      start: Offset(xApprovalsEnd, stampTopMm),
      end: Offset(xApprovalsEnd, stampTopMm + 55.0),
      strokeWidthMm: styleConfig.stampBorderWidthMm,
      colorValue: 0xFF000000,
      smoothJoin: false,
    );

    // Сквозная горизонтальная линия на 25 мм от верха штампа
    scene.addLine(
      layer: VectorSceneLayer.frameAndStamp,
      start: Offset(stampLeftMm, stampTopMm + 25.0),
      end: Offset(widthMm - frameRightMm, stampTopMm + 25.0),
      strokeWidthMm: styleConfig.stampBorderWidthMm,
      colorValue: 0xFF000000,
      smoothJoin: false,
    );

    // Строки изменений (4 строки по 5 мм вверху левого блока)
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

    // Вертикальные линии колонок изменений
    final revCols = [10.0, 20.0, 30.0, 40.0, 55.0];
    for (final col in revCols) {
      scene.addLine(
        layer: VectorSceneLayer.frameAndStamp,
        start: Offset(stampLeftMm + col, stampTopMm),
        end: Offset(stampLeftMm + col, stampTopMm + 25.0),
        strokeWidthMm: styleConfig.stampGridWidthMm,
        colorValue: 0xFF000000,
        smoothJoin: false,
      );
    }

    // Строки блока согласований (5 строк по 5 мм внизу левого блока)
    for (int i = 1; i <= 5; i++) {
      final y = stampTopMm + 25.0 + (i * 5.0);
      scene.addLine(
        layer: VectorSceneLayer.frameAndStamp,
        start: Offset(stampLeftMm, y),
        end: Offset(xApprovalsEnd, y),
        strokeWidthMm: styleConfig.stampGridWidthMm,
        colorValue: 0xFF000000,
        smoothJoin: false,
      );
    }

    // Вертикальные колонки блока согласований (Должн 17, Фамил 23, Подп 15, Дата 10)
    final apprCols = [17.0, 40.0, 55.0];
    for (final col in apprCols) {
      scene.addLine(
        layer: VectorSceneLayer.frameAndStamp,
        start: Offset(stampLeftMm + col, stampTopMm + 25.0),
        end: Offset(stampLeftMm + col, stampTopMm + 55.0),
        strokeWidthMm: styleConfig.stampGridWidthMm,
        colorValue: 0xFF000000,
        smoothJoin: false,
      );
    }

    // Разметка правого блока штампа (65..185 мм)
    final stampRightMm = widthMm - frameRightMm;
    final xStageStart = stampLeftMm + 135.0;

    // Графа 7, 8, 9 (Стадия 15 мм, Лист 15 мм, Листов 20 мм)
    scene.addLine(
      layer: VectorSceneLayer.frameAndStamp,
      start: Offset(xStageStart, stampTopMm + 25.0),
      end: Offset(xStageStart, stampTopMm + 40.0),
      strokeWidthMm: styleConfig.stampBorderWidthMm,
      colorValue: 0xFF000000,
      smoothJoin: false,
    );
    scene.addLine(
      layer: VectorSceneLayer.frameAndStamp,
      start: Offset(xStageStart, stampTopMm + 40.0),
      end: Offset(stampRightMm, stampTopMm + 40.0),
      strokeWidthMm: styleConfig.stampBorderWidthMm,
      colorValue: 0xFF000000,
      smoothJoin: false,
    );

    // Разделители колонок Стадия / Лист / Листов
    scene.addLine(
      layer: VectorSceneLayer.frameAndStamp,
      start: Offset(xStageStart + 15.0, stampTopMm + 30.0),
      end: Offset(xStageStart + 15.0, stampTopMm + 40.0),
      strokeWidthMm: styleConfig.stampGridWidthMm,
      colorValue: 0xFF000000,
      smoothJoin: false,
    );
    scene.addLine(
      layer: VectorSceneLayer.frameAndStamp,
      start: Offset(xStageStart + 30.0, stampTopMm + 30.0),
      end: Offset(xStageStart + 30.0, stampTopMm + 40.0),
      strokeWidthMm: styleConfig.stampGridWidthMm,
      colorValue: 0xFF000000,
      smoothJoin: false,
    );
    scene.addLine(
      layer: VectorSceneLayer.frameAndStamp,
      start: Offset(xStageStart, stampTopMm + 30.0),
      end: Offset(stampRightMm, stampTopMm + 30.0),
      strokeWidthMm: styleConfig.stampGridWidthMm,
      colorValue: 0xFF000000,
      smoothJoin: false,
    );
  }
}
