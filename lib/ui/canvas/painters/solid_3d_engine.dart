import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../core/math/axonometry_projector.dart';
import '../../../domain/enums/fitting_type.dart';
import '../../../domain/models/pipe_segment.dart';
import '../../../domain/models/pipe_support.dart';
import '../../../domain/models/piping_network.dart';
import '../../../domain/models/weld_joint.dart';
import '../../../domain/enums/weld_joint_style.dart';
export '../../../core/math/vector_3d.dart';
import '../../../core/math/vector_3d.dart';
import '../../../domain/services/element_3d_geometry.dart';
import 'pipe_painter.dart';

/// 3D полигон твердотельного тела с нормалью и цветом
class Polygon3D {
  final List<Vector3D> vertices;
  final Vector3D normal;
  final Color baseColor;
  final double depth;
  final Color shadedColor;

  const Polygon3D({
    required this.vertices,
    required this.normal,
    required this.baseColor,
    required this.depth,
    required this.shadedColor,
  });
}

/// Параметрический 3D CAD движок твердотельных тел (Software 3D Solid Engine)
/// Осуществляет фасетизацию цилиндров, отводов, конусов и арматуры,
/// глубинную Z-сортировку (Painter's algorithm) и направленное освещение.
class Solid3dEngine {
  // Направление основного источника света (сверху-слева-спереди)
  static final Vector3D lightDir = const Vector3D(0.4, -0.6, 0.7).normalized();

  /// Генерация и отрисовка всей объемной твердотельной сети труб с Z-сортировкой
  static void renderNetwork(
    Canvas canvas,
    AxonometryProjector projector,
    PipingNetwork network, {
    String? selectedSegmentId,
    Set<String>? selectedSegmentIds,
    int cylinderFacets = 12,
  }) {
    final polygons = <Polygon3D>[];

    // 1. Сборка цилиндров труб с учетом обрезки у фитингов (отводов, переходов, фланцев, тройников)
    for (final seg in network.segments.values) {
      final start = network.nodes[seg.startNodeId];
      final end = network.nodes[seg.endNodeId];
      if (start == null || end == null) continue;

      final isSelected = seg.id == selectedSegmentId ||
          (selectedSegmentIds != null && selectedSegmentIds.contains(seg.id));
      final sys = network.systems[seg.systemId];
      var baseColor = sys != null ? Color(sys.colorValue) : const Color(0xFF607D8B);
      if (isSelected) {
        baseColor = Color.lerp(baseColor, Colors.amber, 0.55)!;
      }

      final dim = network.pipeCatalog.getDimension(seg.dn);
      final outerRadius = ((dim != null ? dim.outerDiameterMm : seg.dn.toDouble()) / 2.0)
          .clamp(5.0, 1000.0);

      final vStart = Vector3D.fromNode(start);
      final vEnd = Vector3D.fromNode(end);
      final axis = vEnd - vStart;
      final segLen = axis.length;
      if (segLen < 1e-4) continue;

      final trimStart = _calcNodeTrimLength(network, seg.startNodeId, seg).clamp(0.0, segLen * 0.45);
      final trimEnd = _calcNodeTrimLength(network, seg.endNodeId, seg).clamp(0.0, segLen * 0.45);

      final segValves = network.valves.values.where((v) => v.segmentId == seg.id).toList();
      final intervals = Element3dGeometry.calcPipeDrawableIntervals3d(
        start,
        end,
        segValves,
        trimStartMm: trimStart,
        trimEndMm: trimEnd,
      );

      for (final (pStart, pEnd) in intervals) {
        if ((pEnd - pStart).length > 1.0) {
          _buildCylinderMesh(
            polygons: polygons,
            projector: projector,
            start: pStart,
            end: pEnd,
            radius: outerRadius,
            color: baseColor,
            facets: cylinderFacets,
          );
        }
      }
    }

    // 2. Сборка фитингов (отводы, переходы, днища, тройники, фланцы)
    for (final fit in network.fittings.values) {
      final node = network.nodes[fit.nodeId];
      if (node == null) continue;

      final connected = network.getConnectedSegments(fit.nodeId);
      final sys = connected.isNotEmpty ? network.systems[connected.first.systemId] : null;
      final baseColor = sys != null ? Color(sys.colorValue) : const Color(0xFF455A64);

      if (fit.fittingType == FittingType.elbow90 || fit.fittingType == FittingType.elbow45) {
        if (connected.length == 2) {
          final s1 = connected[0];
          final s2 = connected[1];
          final other1 = network.nodes[s1.startNodeId == fit.nodeId ? s1.endNodeId : s1.startNodeId];
          final other2 = network.nodes[s2.startNodeId == fit.nodeId ? s2.endNodeId : s2.startNodeId];
          if (other1 == null || other2 == null) continue;

          final r1 = (network.pipeCatalog.getDimension(s1.dn)?.outerDiameterMm ?? s1.dn.toDouble()) / 2.0;
          final r2 = (network.pipeCatalog.getDimension(s2.dn)?.outerDiameterMm ?? s2.dn.toDouble()) / 2.0;
          final pipeRadius = (r1 + r2) / 2.0;
          final elbowRadius = fit.effectiveRadiusMm > 0 ? fit.effectiveRadiusMm : 1.5 * fit.dn.toDouble();

          _buildTorusElbowMesh(
            polygons: polygons,
            projector: projector,
            node: Vector3D.fromNode(node),
            other1: Vector3D.fromNode(other1),
            other2: Vector3D.fromNode(other2),
            pipeRadius: pipeRadius,
            elbowRadius: elbowRadius,
            color: baseColor,
            facets: cylinderFacets,
          );
        }
      } else if (fit.fittingType == FittingType.reducerConcentric ||
          fit.fittingType == FittingType.reducerEccentric) {
        if (connected.length == 2) {
          final s1 = connected[0];
          final s2 = connected[1];
          final other1 = network.nodes[s1.startNodeId == fit.nodeId ? s1.endNodeId : s1.startNodeId];
          final other2 = network.nodes[s2.startNodeId == fit.nodeId ? s2.endNodeId : s2.startNodeId];
          if (other1 == null || other2 == null) continue;

          final dir1 = (Vector3D.fromNode(other1) - Vector3D.fromNode(node)).normalized();
          final dir2 = (Vector3D.fromNode(other2) - Vector3D.fromNode(node)).normalized();

          final r1 = (network.pipeCatalog.getDimension(s1.dn)?.outerDiameterMm ?? s1.dn.toDouble()) / 2.0;
          final r2 = (network.pipeCatalog.getDimension(s2.dn)?.outerDiameterMm ?? s2.dn.toDouble()) / 2.0;

          final len = fit.buildingLengthMm ?? (math.max(r1, r2) * 1.6);
          final pStart = Vector3D.fromNode(node) + dir1 * (len / 2.0);
          final pEnd = Vector3D.fromNode(node) + dir2 * (len / 2.0);

          _buildConeMesh(
            polygons: polygons,
            projector: projector,
            start: pStart,
            end: pEnd,
            radius1: r1,
            radius2: r2,
            isEccentric: fit.fittingType == FittingType.reducerEccentric,
            color: baseColor,
            facets: cylinderFacets,
          );
        }
      } else if (fit.fittingType == FittingType.flange) {
        if (connected.isNotEmpty) {
          final s = connected[0];
          final other = network.nodes[s.startNodeId == fit.nodeId ? s.endNodeId : s.startNodeId];
          if (other == null) continue;
          final dir = (Vector3D.fromNode(node) - Vector3D.fromNode(other)).normalized();
          final r = (network.pipeCatalog.getDimension(fit.dn)?.outerDiameterMm ?? fit.dn.toDouble()) / 2.0;

          _buildFlangeMesh(
            polygons: polygons,
            projector: projector,
            center: Vector3D.fromNode(node),
            axisDir: dir,
            radius: r,
            isFlangePair: fit.isFlangePair,
            color: baseColor,
            facets: cylinderFacets,
          );
        }
      } else if (fit.fittingType == FittingType.cap) {
        if (connected.isNotEmpty) {
          final s = connected[0];
          final other = network.nodes[s.startNodeId == fit.nodeId ? s.endNodeId : s.startNodeId];
          if (other == null) continue;
          final dir = (Vector3D.fromNode(node) - Vector3D.fromNode(other)).normalized();
          final r = (network.pipeCatalog.getDimension(s.dn)?.outerDiameterMm ?? s.dn.toDouble()) / 2.0;

          // Стыковочное сварное кольцо у основания днища
          _buildWeldRingMesh(
            polygons: polygons,
            projector: projector,
            center: Vector3D.fromNode(node),
            axisDir: dir,
            radius: r,
            facets: cylinderFacets,
          );

          // Выпуклый купол эллиптического днища
          _buildCapDomeMesh(
            polygons: polygons,
            projector: projector,
            center: Vector3D.fromNode(node),
            outwardDir: dir,
            radius: r,
            color: baseColor,
            facets: cylinderFacets,
          );
        }
      } else if (fit.fittingType == FittingType.directBranch) {
        if (connected.length == 3) {
          final branchSeg = network.identifyBranchSegment(fit.nodeId, connected);
          final mainSegs = connected.where((s) => s.id != branchSeg?.id).toList();
          if (branchSeg != null && mainSegs.isNotEmpty) {
            // Находим шов ответвления и проверяем стиль
            WeldJoint? branchWeld;
            for (final w in network.weldJoints.values) {
              if (w.segmentId == branchSeg.id) {
                final r = branchSeg.startNodeId == fit.nodeId ? 0.0 : 1.0;
                if ((w.ratio - r).abs() < 0.05) {
                  branchWeld = w;
                  break;
                }
              }
            }
            final effStyle = branchWeld?.getEffectiveStyle(network.defaultWeldStyle) ?? network.defaultWeldStyle;
            if (effStyle == WeldJointStyle.ring3d) {
              final otherBranch = network.nodes[branchSeg.startNodeId == fit.nodeId ? branchSeg.endNodeId : branchSeg.startNodeId];
              if (otherBranch != null) {
                final dirBranch = (Vector3D.fromNode(otherBranch) - Vector3D.fromNode(node)).normalized();
                final rMain = (network.pipeCatalog.getDimension(mainSegs[0].dn)?.outerDiameterMm ?? mainSegs[0].dn.toDouble()) / 2.0;
                final rBranch = (network.pipeCatalog.getDimension(branchSeg.dn)?.outerDiameterMm ?? branchSeg.dn.toDouble()) / 2.0;

                final pJoint = Vector3D.fromNode(node) + dirBranch * rMain;

                // Валик углового шва У18 вокруг врезанного патрубка (только для стиля ring3d)
                _buildWeldRingMesh(
                  polygons: polygons,
                  projector: projector,
                  center: pJoint,
                  axisDir: dirBranch,
                  radius: rBranch,
                  facets: cylinderFacets,
                );
              }
            }
          }
        }
      } else if (fit.fittingType == FittingType.tee) {
        if (connected.length >= 3) {
          final r = (network.pipeCatalog.getDimension(fit.dn)?.outerDiameterMm ?? fit.dn.toDouble()) / 2.0;
          final branchSeg = network.identifyBranchSegment(fit.nodeId, connected);
          if (branchSeg != null) {
            final otherBranch = network.nodes[branchSeg.startNodeId == fit.nodeId ? branchSeg.endNodeId : branchSeg.startNodeId];
            if (otherBranch == null) continue;
            final dirBranch = (Vector3D.fromNode(otherBranch) - Vector3D.fromNode(node)).normalized();
            final armBranch = fit.effectiveBranchLengthMm;
            final pArm = Vector3D.fromNode(node) + dirBranch * math.min(armBranch, 60.0);
            _buildWeldRingMesh(
              polygons: polygons,
              projector: projector,
              center: pArm,
              axisDir: dirBranch,
              radius: r,
              facets: cylinderFacets,
            );
          }
        }
      }
    }

    // 3. Сборка арматуры (задвижки, краны) в виде 3D тел
    for (final valve in network.valves.values) {
      final seg = network.segments[valve.segmentId];
      if (seg == null) continue;
      final start = network.nodes[seg.startNodeId];
      final end = network.nodes[seg.endNodeId];
      if (start == null || end == null) continue;

      final vStart = Vector3D.fromNode(start);
      final vEnd = Vector3D.fromNode(end);
      final vPos = vStart + (vEnd - vStart) * valve.ratio;
      final dir = (vEnd - vStart).normalized();

      final r = (network.pipeCatalog.getDimension(valve.dn)?.outerDiameterMm ?? valve.dn.toDouble()) / 2.0;
      final sys = network.systems[seg.systemId];
      final baseColor = sys != null ? Color(sys.colorValue) : const Color(0xFF1E88E5);

      _buildValveSolidMesh(
        polygons: polygons,
        projector: projector,
        center: vPos,
        axisDir: dir,
        radius: r,
        length: valve.lengthMm,
        color: baseColor,
        isFlanged: valve.isFlanged,
      );
    }

    // 4. Сборка сварных стыков (WeldJoint) в виде объемных валиков шва (только для стиля ring3d)
    for (final weld in network.weldJoints.values) {
      if (weld.getEffectiveStyle(network.defaultWeldStyle) != WeldJointStyle.ring3d) {
        continue;
      }
      final seg = network.segments[weld.segmentId];
      if (seg == null) continue;
      final start = network.nodes[seg.startNodeId];
      final end = network.nodes[seg.endNodeId];
      if (start == null || end == null) continue;

      final vStart = Vector3D.fromNode(start);
      final vEnd = Vector3D.fromNode(end);
      final axis = vEnd - vStart;
      final len = axis.length;
      if (len < 1e-4) continue;
      final dir = axis / len;

      final vPos = vStart + axis * weld.ratio.clamp(0.0, 1.0);
      final r = (network.pipeCatalog.getDimension(seg.dn)?.outerDiameterMm ?? seg.dn.toDouble()) / 2.0;

      _buildWeldBeadMesh(
        polygons: polygons,
        projector: projector,
        center: vPos,
        axisDir: dir,
        radius: r,
        facets: cylinderFacets,
      );
    }

    // 5. Сборка опор и подвесок трубопровода (PipeSupport) в виде 3D тел
    for (final support in network.supports.values) {
      final seg = network.segments[support.segmentId];
      if (seg == null) continue;
      final start = network.nodes[seg.startNodeId];
      final end = network.nodes[seg.endNodeId];
      if (start == null || end == null) continue;

      final vStart = Vector3D.fromNode(start);
      final vEnd = Vector3D.fromNode(end);
      final axis = vEnd - vStart;
      final len = axis.length;
      if (len < 1e-4) continue;
      final dir = axis / len;

      final vPos = vStart + axis * support.distanceRatio.clamp(0.0, 1.0);
      final r = (network.pipeCatalog.getDimension(seg.dn)?.outerDiameterMm ?? seg.dn.toDouble()) / 2.0;

      _buildSupportSolidMesh(
        polygons: polygons,
        projector: projector,
        center: vPos,
        axisDir: dir,
        pipeRadius: r,
        type: support.type,
        facets: cylinderFacets,
      );
    }

    // 4. Z-СОРТИРОВКА (Painter's algorithm):
    // Полигоны с наибольшей глубиной (дальние) рисуются первыми, ближние — последними (поверх).
    polygons.sort((a, b) => b.depth.compareTo(a.depth));

    // 5. РАСТЕРИЗАЦИЯ НА ХОЛСТЕ FLUTTER
    final fillPaint = Paint()..style = PaintingStyle.fill;
    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = Colors.black26;

    for (final poly in polygons) {
      if (poly.vertices.length < 3) continue;

      final path = Path();
      final p0 = projector.projectCoordinates(poly.vertices[0].x, poly.vertices[0].y, poly.vertices[0].z);
      path.moveTo(p0.dx, p0.dy);

      for (int i = 1; i < poly.vertices.length; i++) {
        final pt = projector.projectCoordinates(poly.vertices[i].x, poly.vertices[i].y, poly.vertices[i].z);
        path.lineTo(pt.dx, pt.dy);
      }
      path.close();

      fillPaint.color = poly.shadedColor;
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, edgePaint);
    }
  }

  /// Расчет пространственного отступа (мм) для обрезки цилиндра трубы у узла [nodeId]
  /// для корректного сопряжения с отводами, переходами, тройниками и фланцами
  static double _calcNodeTrimLength(PipingNetwork network, String nodeId, PipeSegment seg) {
    final fit = network.fittings[nodeId];
    if (fit != null) {
      if (fit.fittingType == FittingType.elbow90 || fit.fittingType == FittingType.elbow45) {
        return PipePainter.calcElbowTangentLength(network, nodeId, fit);
      } else if (fit.fittingType == FittingType.reducerConcentric ||
          fit.fittingType == FittingType.reducerEccentric) {
        final connected = network.getConnectedSegments(nodeId);
        if (connected.length == 2) {
          final s1 = connected[0];
          final s2 = connected[1];
          final r1 = (network.pipeCatalog.getDimension(s1.dn)?.outerDiameterMm ?? s1.dn.toDouble()) / 2.0;
          final r2 = (network.pipeCatalog.getDimension(s2.dn)?.outerDiameterMm ?? s2.dn.toDouble()) / 2.0;
          final len = fit.buildingLengthMm ?? (math.max(r1, r2) * 1.6);
          return len / 2.0;
        }
      } else if (fit.fittingType == FittingType.flange) {
        return fit.buildingLengthMm ?? (fit.isFlangePair ? 20.0 : 16.0);
      } else if (fit.fittingType == FittingType.tee) {
        if (fit.cutsMainPipe) {
          return fit.branchLengthMm ?? (fit.dn * 0.8);
        } else {
          final isBranch = PipePainter.isTeeBranchSegment(network, nodeId, seg.id);
          if (isBranch) {
            final connected = network.getConnectedSegments(nodeId);
            final mainSeg = connected.firstWhere((s) => s.id != seg.id, orElse: () => seg);
            final rMain = (network.pipeCatalog.getDimension(mainSeg.dn)?.outerDiameterMm ?? mainSeg.dn.toDouble()) / 2.0;
            return rMain;
          }
        }
      } else if (fit.fittingType == FittingType.directBranch) {
        final isBranch = PipePainter.isTeeBranchSegment(network, nodeId, seg.id);
        if (isBranch) {
          final connected = network.getConnectedSegments(nodeId);
          final mainSeg = connected.firstWhere((s) => s.id != seg.id, orElse: () => seg);
          final rMain = (network.pipeCatalog.getDimension(mainSeg.dn)?.outerDiameterMm ?? mainSeg.dn.toDouble()) / 2.0;
          return rMain;
        }
      }
    } else {
      // Прямое Т-образное пересечение без явного объекта Fitting
      final connected = network.getConnectedSegments(nodeId);
      if (connected.length == 3) {
        final isBranch = PipePainter.isTeeBranchSegment(network, nodeId, seg.id);
        if (isBranch) {
          final mainSeg = connected.firstWhere((s) => s.id != seg.id, orElse: () => seg);
          final rMain = (network.pipeCatalog.getDimension(mainSeg.dn)?.outerDiameterMm ?? mainSeg.dn.toDouble()) / 2.0;
          return rMain;
        }
      }
    }
    return 0.0;
  }

  /// Построение фасеточного 3D-цилиндра трубы
  static void _buildCylinderMesh({
    required List<Polygon3D> polygons,
    required AxonometryProjector projector,
    required Vector3D start,
    required Vector3D end,
    required double radius,
    required Color color,
    required int facets,
  }) {
    final axis = end - start;
    final len = axis.length;
    if (len < 1e-4) return;
    final dir = axis / len;

    // Ортонормированный базис (u, v) перпендикулярно оси цилиндра
    Vector3D arb = const Vector3D(0, 0, 1);
    if ((dir.dot(arb)).abs() > 0.9) {
      arb = const Vector3D(0, 1, 0);
    }
    final u = dir.cross(arb).normalized();
    final v = dir.cross(u).normalized();

    final ringStart = <Vector3D>[];
    final ringEnd = <Vector3D>[];
    final normals = <Vector3D>[];

    final step = (2.0 * math.pi) / facets;
    for (int i = 0; i < facets; i++) {
      final angle = i * step;
      final radial = u * math.cos(angle) + v * math.sin(angle);
      normals.add(radial);
      ringStart.add(start + radial * radius);
      ringEnd.add(end + radial * radius);
    }

    // Создание боковых граней (квадов)
    for (int i = 0; i < facets; i++) {
      final next = (i + 1) % facets;
      final midAngle = (i + 0.5) * step;
      final faceNormal = (u * math.cos(midAngle) + v * math.sin(midAngle)).normalized();

      final v0 = ringStart[i];
      final v1 = ringStart[next];
      final v2 = ringEnd[next];
      final v3 = ringEnd[i];

      final center = (v0 + v1 + v2 + v3) * 0.25;
      final depth = projector.computeDepth(center.x, center.y, center.z);
      final shaded = computeLighting(faceNormal, color);

      polygons.add(Polygon3D(
        vertices: [v0, v1, v2, v3],
        normal: faceNormal,
        baseColor: color,
        depth: depth,
        shadedColor: shaded,
      ));
    }
  }

  /// Построение настоящего 3D тороидального отвода (Elbow 90° / 45°)
  static void _buildTorusElbowMesh({
    required List<Polygon3D> polygons,
    required AxonometryProjector projector,
    required Vector3D node,
    required Vector3D other1,
    required Vector3D other2,
    required double pipeRadius,
    required double elbowRadius,
    required Color color,
    required int facets,
  }) {
    final u1 = (other1 - node).normalized();
    final u2 = (other2 - node).normalized();
    final dot = u1.dot(u2).clamp(-0.9999, 0.9999);
    final angleBetween = math.acos(dot);
    final bendAngle = math.pi - angleBetween;
    if (bendAngle < 0.01) return;

    final len1 = (other1 - node).length;
    final len2 = (other2 - node).length;
    final maxT = math.min(len1, len2) * 0.45;

    var rBend = elbowRadius;
    var t = rBend * math.tan(bendAngle / 2.0);
    if (t > maxT && t > 1e-4) {
      t = maxT;
      rBend = t / math.tan(bendAngle / 2.0);
    }

    final bisector = (u1 + u2).normalized();
    final cosHalf = math.cos(bendAngle / 2.0);
    if (cosHalf.abs() < 1e-4) return;
    final center = node + bisector * (rBend / cosHalf);

    final p1 = node + u1 * t;
    final p2 = node + u2 * t;

    final e1 = (p1 - center).normalized();
    final r2 = (p2 - center).normalized();
    final e2 = (r2 - e1 * e1.dot(r2)).normalized();
    final nPlane = e1.cross(e2).normalized();

    final arcSteps = math.max(6, (facets * (bendAngle / (math.pi / 2.0))).round());
    final ringPoints = <List<Vector3D>>[];

    final phiStep = (2.0 * math.pi) / facets;

    for (int j = 0; j <= arcSteps; j++) {
      final frac = j / arcSteps;
      final curAngle = frac * bendAngle;
      final rCur = e1 * math.cos(curAngle) + e2 * math.sin(curAngle);
      final pCenter = center + rCur * rBend;

      final ring = <Vector3D>[];
      for (int i = 0; i < facets; i++) {
        final phi = i * phiStep;
        final radial = (rCur * math.cos(phi) + nPlane * math.sin(phi)).normalized();
        ring.add(pCenter + radial * pipeRadius);
      }
      ringPoints.add(ring);
    }

    for (int j = 0; j < arcSteps; j++) {
      for (int i = 0; i < facets; i++) {
        final nextI = (i + 1) % facets;
        final v0 = ringPoints[j][i];
        final v1 = ringPoints[j][nextI];
        final v2 = ringPoints[j + 1][nextI];
        final v3 = ringPoints[j + 1][i];

        final midFrac = (j + 0.5) / arcSteps;
        final midArc = midFrac * bendAngle;
        final midR = e1 * math.cos(midArc) + e2 * math.sin(midArc);
        final midPhi = (i + 0.5) * phiStep;
        final faceNormal = (midR * math.cos(midPhi) + nPlane * math.sin(midPhi)).normalized();

        final cQuad = (v0 + v1 + v2 + v3) * 0.25;
        final depth = projector.computeDepth(cQuad.x, cQuad.y, cQuad.z);
        final shaded = computeLighting(faceNormal, color);

        polygons.add(Polygon3D(
          vertices: [v0, v1, v2, v3],
          normal: faceNormal,
          baseColor: color,
          depth: depth,
          shadedColor: shaded,
        ));
      }
    }

    // Сварные стыки на концах отвода
    _buildWeldRingMesh(
      polygons: polygons,
      projector: projector,
      center: p1,
      axisDir: u1,
      radius: pipeRadius,
      facets: facets,
    );
    _buildWeldRingMesh(
      polygons: polygons,
      projector: projector,
      center: p2,
      axisDir: u2,
      radius: pipeRadius,
      facets: facets,
    );
  }

  /// Построение усеченного конуса перехода (концентрического или эксцентрического)
  /// с безупречным выравниванием нижнего лотка (flat bottom) по ГОСТ 17378
  static void _buildConeMesh({
    required List<Polygon3D> polygons,
    required AxonometryProjector projector,
    required Vector3D start,
    required Vector3D end,
    required double radius1,
    required double radius2,
    required bool isEccentric,
    required Color color,
    required int facets,
  }) {
    final axis = end - start;
    final len = axis.length;
    if (len < 1e-4) return;
    final dir = axis / len;

    // Нормаль к оси трубы с учетом вектора вертикали Z (в Akso Z направлен вверх)
    var up = const Vector3D(0, 0, 1) - dir * dir.z;
    if (up.length < 1e-4) {
      up = const Vector3D(1, 0, 0) - dir * dir.x;
    }
    up = up.normalized();
    final side = dir.cross(up).normalized();

    // Эксцентрическое смещение лотка вниз (flat bottom)
    // start - up * radius1 должно идеально совпадать с end + offset - up * radius2
    final eccentricOffset = isEccentric ? -up * (radius1 - radius2) : const Vector3D(0, 0, 0);

    final step = (2.0 * math.pi) / facets;
    for (int i = 0; i < facets; i++) {
      final next = (i + 1) % facets;
      final angle1 = i * step;
      final angle2 = next * step;

      final rad1A = side * math.cos(angle1) + up * math.sin(angle1);
      final rad1B = side * math.cos(angle2) + up * math.sin(angle2);

      final rad2A = side * math.cos(angle1) + up * math.sin(angle1);
      final rad2B = side * math.cos(angle2) + up * math.sin(angle2);

      final v0 = start + rad1A * radius1;
      final v1 = start + rad1B * radius1;
      final v2 = end + eccentricOffset + rad2B * radius2;
      final v3 = end + eccentricOffset + rad2A * radius2;

      final midAngle = (i + 0.5) * step;
      final midRadial = (side * math.cos(midAngle) + up * math.sin(midAngle)).normalized();
      var faceNormal = ((v3 - v0).cross(v1 - v0)).normalized();
      if (faceNormal.dot(midRadial) < 0) {
        faceNormal = faceNormal * -1.0;
      }

      final center = (v0 + v1 + v2 + v3) * 0.25;
      final depth = projector.computeDepth(center.x, center.y, center.z);
      final shaded = computeLighting(faceNormal, color);

      polygons.add(Polygon3D(
        vertices: [v0, v1, v2, v3],
        normal: faceNormal,
        baseColor: color,
        depth: depth,
        shadedColor: shaded,
      ));
    }

    // Стыковочные сварные кольца по концам перехода
    _buildWeldRingMesh(
      polygons: polygons,
      projector: projector,
      center: start,
      axisDir: dir,
      radius: radius1,
      facets: facets,
    );
    _buildWeldRingMesh(
      polygons: polygons,
      projector: projector,
      center: end + eccentricOffset,
      axisDir: dir,
      radius: radius2,
      facets: facets,
    );
  }

  /// Построение объемного фланцевого соединения (одиночный фланец или фланцевая пара с прокладкой)
  static void _buildFlangeMesh({
    required List<Polygon3D> polygons,
    required AxonometryProjector projector,
    required Vector3D center,
    required Vector3D axisDir,
    required double radius,
    required bool isFlangePair,
    required Color color,
    required int facets,
  }) {
    final dir = axisDir.normalized();
    final rFlange = radius * 1.55;
    final flangeColor = Color.lerp(color, Colors.blueGrey.shade900, 0.35)!;

    if (isFlangePair) {
      const discT = 16.0;
      const gasketT = 3.0;

      // Фланец 1
      _buildCylinderMesh(
        polygons: polygons,
        projector: projector,
        start: center - dir * (discT + gasketT * 0.5),
        end: center - dir * (gasketT * 0.5),
        radius: rFlange,
        color: flangeColor,
        facets: facets,
      );

      // Прокладка (паронит / графит)
      _buildCylinderMesh(
        polygons: polygons,
        projector: projector,
        start: center - dir * (gasketT * 0.5),
        end: center + dir * (gasketT * 0.5),
        radius: rFlange * 0.95,
        color: const Color(0xFF263238),
        facets: facets,
      );

      // Фланец 2
      _buildCylinderMesh(
        polygons: polygons,
        projector: projector,
        start: center + dir * (gasketT * 0.5),
        end: center + dir * (discT + gasketT * 0.5),
        radius: rFlange,
        color: flangeColor,
        facets: facets,
      );

      // Воротники шейки фланцев (tapered neck hubs)
      _buildConeMesh(
        polygons: polygons,
        projector: projector,
        start: center - dir * (discT + gasketT * 0.5 + 14.0),
        end: center - dir * (discT + gasketT * 0.5),
        radius1: radius,
        radius2: rFlange * 0.8,
        isEccentric: false,
        color: color,
        facets: facets,
      );
      _buildConeMesh(
        polygons: polygons,
        projector: projector,
        start: center + dir * (discT + gasketT * 0.5 + 14.0),
        end: center + dir * (discT + gasketT * 0.5),
        radius1: radius,
        radius2: rFlange * 0.8,
        isEccentric: false,
        color: color,
        facets: facets,
      );
    } else {
      const discT = 18.0;
      _buildCylinderMesh(
        polygons: polygons,
        projector: projector,
        start: center - dir * discT,
        end: center,
        radius: rFlange,
        color: flangeColor,
        facets: facets,
      );
      _buildConeMesh(
        polygons: polygons,
        projector: projector,
        start: center - dir * (discT + 14.0),
        end: center - dir * discT,
        radius1: radius,
        radius2: rFlange * 0.8,
        isEccentric: false,
        color: color,
        facets: facets,
      );
    }
  }

  /// Построение объемного сварного шва трубы (WeldJoint)
  static void _buildWeldBeadMesh({
    required List<Polygon3D> polygons,
    required AxonometryProjector projector,
    required Vector3D center,
    required Vector3D axisDir,
    required double radius,
    required int facets,
  }) {
    final dir = axisDir.normalized();
    const halfW = 3.5;
    final rBead = radius + 2.2;
    const beadColor = Color(0xFFCFD8DC);

    _buildCylinderMesh(
      polygons: polygons,
      projector: projector,
      start: center - dir * halfW,
      end: center + dir * halfW,
      radius: rBead,
      color: beadColor,
      facets: facets,
    );
  }

  /// Построение аккуратного стыковочного сварного кольца
  static void _buildWeldRingMesh({
    required List<Polygon3D> polygons,
    required AxonometryProjector projector,
    required Vector3D center,
    required Vector3D axisDir,
    required double radius,
    required int facets,
  }) {
    final dir = axisDir.normalized();
    const halfW = 2.5;
    final rBead = radius + 1.8;
    const beadColor = Color(0xFFB0BEC5);

    _buildCylinderMesh(
      polygons: polygons,
      projector: projector,
      start: center - dir * halfW,
      end: center + dir * halfW,
      radius: rBead,
      color: beadColor,
      facets: facets,
    );
  }

  /// Построение объемной 3D опоры или подвески трубопровода (хомут + стойка/башмак или подвеска)
  static void _buildSupportSolidMesh({
    required List<Polygon3D> polygons,
    required AxonometryProjector projector,
    required Vector3D center,
    required Vector3D axisDir,
    required double pipeRadius,
    required PipeSupportType type,
    required int facets,
  }) {
    final dir = axisDir.normalized();
    final clampR = pipeRadius + 3.5;
    const clampW = 26.0;
    const clampColor = Color(0xFF37474F);

    // 1. Хомут вокруг трубы
    _buildCylinderMesh(
      polygons: polygons,
      projector: projector,
      start: center - dir * (clampW * 0.5),
      end: center + dir * (clampW * 0.5),
      radius: clampR,
      color: clampColor,
      facets: facets,
    );

    // 2. Стойка или тяга
    if (type == PipeSupportType.spring) {
      const up = Vector3D(0, 0, 1);
      final rodStart = center + up * clampR;
      final rodEnd = rodStart + up * 120.0;
      _buildCylinderMesh(
        polygons: polygons,
        projector: projector,
        start: rodStart,
        end: rodEnd,
        radius: 4.0,
        color: const Color(0xFF78909C),
        facets: 6,
      );
      final canMid = rodStart + up * 60.0;
      _buildCylinderMesh(
        polygons: polygons,
        projector: projector,
        start: canMid - up * 25.0,
        end: canMid + up * 25.0,
        radius: 16.0,
        color: const Color(0xFF455A64),
        facets: 8,
      );
    } else {
      const down = Vector3D(0, 0, -1);
      final shoeTop = center + down * clampR;
      final shoeHeight = math.max(60.0, pipeRadius * 0.9);
      final shoeBottom = shoeTop + down * shoeHeight;

      _buildCylinderMesh(
        polygons: polygons,
        projector: projector,
        start: shoeTop,
        end: shoeBottom,
        radius: math.max(10.0, pipeRadius * 0.35),
        color: const Color(0xFF455A64),
        facets: 6,
      );

      final plateColor = type == PipeSupportType.sliding
          ? const Color(0xFF90A4AE)
          : const Color(0xFF263238);

      _buildCylinderMesh(
        polygons: polygons,
        projector: projector,
        start: shoeBottom,
        end: shoeBottom + down * 10.0,
        radius: math.max(25.0, pipeRadius * 0.9),
        color: plateColor,
        facets: 8,
      );
    }
  }

  /// Построение выпуклого днища (Cap Dome)
  static void _buildCapDomeMesh({
    required List<Polygon3D> polygons,
    required AxonometryProjector projector,
    required Vector3D center,
    required Vector3D outwardDir,
    required double radius,
    required Color color,
    required int facets,
  }) {
    Vector3D arb = const Vector3D(0, 0, 1);
    if ((outwardDir.dot(arb)).abs() > 0.9) {
      arb = const Vector3D(0, 1, 0);
    }
    final u = outwardDir.cross(arb).normalized();
    final v = outwardDir.cross(u).normalized();

    final apex = center + outwardDir * (radius * 0.6);
    final step = (2.0 * math.pi) / facets;

    for (int i = 0; i < facets; i++) {
      final next = (i + 1) % facets;
      final a1 = i * step;
      final a2 = next * step;

      final v0 = center + (u * math.cos(a1) + v * math.sin(a1)) * radius;
      final v1 = center + (u * math.cos(a2) + v * math.sin(a2)) * radius;
      final v2 = apex;

      final midA = (i + 0.5) * step;
      final nBase = (u * math.cos(midA) + v * math.sin(midA));
      final faceNormal = (nBase + outwardDir * 0.7).normalized();

      final c = (v0 + v1 + v2) / 3.0;
      final depth = projector.computeDepth(c.x, c.y, c.z);
      final shaded = computeLighting(faceNormal, color);

      polygons.add(Polygon3D(
        vertices: [v0, v1, v2],
        normal: faceNormal,
        baseColor: color,
        depth: depth,
        shadedColor: shaded,
      ));
    }
  }

  /// Построение объемной модели арматуры (корпус, фланцы, шток, штурвал)
  static void _buildValveSolidMesh({
    required List<Polygon3D> polygons,
    required AxonometryProjector projector,
    required Vector3D center,
    required Vector3D axisDir,
    required double radius,
    required double length,
    required Color color,
    required bool isFlanged,
  }) {
    final halfL = length / 2.0;
    final vStart = center - axisDir * halfL;
    final vEnd = center + axisDir * halfL;

    // 1. Корпус задвижки (центральный цилиндр увеличенного диаметра)
    final bodyRadius = radius * 1.35;
    _buildCylinderMesh(
      polygons: polygons,
      projector: projector,
      start: center - axisDir * (halfL * 0.5),
      end: center + axisDir * (halfL * 0.5),
      radius: bodyRadius,
      color: color,
      facets: 8,
    );

    // 2. Торцевые фланцы (если фланцевая)
    if (isFlanged) {
      final flangeR = radius * 1.55;
      final flangeW = length * 0.12;
      final flangeColor = Color.lerp(color, Colors.black87, 0.25)!;

      _buildCylinderMesh(
        polygons: polygons,
        projector: projector,
        start: vStart,
        end: vStart + axisDir * flangeW,
        radius: flangeR,
        color: flangeColor,
        facets: 8,
      );
      _buildCylinderMesh(
        polygons: polygons,
        projector: projector,
        start: vEnd - axisDir * flangeW,
        end: vEnd,
        radius: flangeR,
        color: flangeColor,
        facets: 8,
      );
    }

    // 3. Вертикальный шток / шпиндель
    final upDir = const Vector3D(0, 0, 1);
    final stemLen = radius * 2.2;
    final stemTop = center + upDir * stemLen;
    _buildCylinderMesh(
      polygons: polygons,
      projector: projector,
      start: center,
      end: stemTop,
      radius: radius * 0.35,
      color: Colors.grey.shade400,
      facets: 6,
    );

    // 4. Штурвал (маховик) наверху
    final wheelRadius = radius * 1.4;
    _buildCylinderMesh(
      polygons: polygons,
      projector: projector,
      start: stemTop - upDir * (radius * 0.2),
      end: stemTop + upDir * (radius * 0.2),
      radius: wheelRadius,
      color: Colors.red.shade700,
      facets: 8,
    );
  }

  /// Расчет направленного освещения (Lambertian Diffuse + Specular Highlight)
  static Color computeLighting(Vector3D normal, Color baseColor) {
    const ambient = 0.38;
    const diffuseWeight = 0.52;
    const specularWeight = 0.25;

    final dot = math.max(0.0, normal.dot(lightDir));
    final intensity = (ambient + diffuseWeight * dot).clamp(0.0, 1.0);

    // Блик отражения (Phong approximation)
    // Вектор отражения R = 2*(N · L)*N - L
    final r = (normal * (2.0 * dot) - lightDir).normalized();
    final viewDir = const Vector3D(0, -1, 1).normalized();
    final specDot = math.max(0.0, r.dot(viewDir));
    final spec = math.pow(specDot, 12).toDouble() * specularWeight;

    // В Flutter 3.27+ Color.r / Color.g / Color.b возвращают double 0.0-1.0
    final rCol = ((baseColor.r * intensity + spec) * 255).clamp(0, 255).toInt();
    final gCol = ((baseColor.g * intensity + spec) * 255).clamp(0, 255).toInt();
    final bCol = ((baseColor.b * intensity + spec) * 255).clamp(0, 255).toInt();

    return Color.fromARGB(255, rCol, gCol, bCol);
  }
}
