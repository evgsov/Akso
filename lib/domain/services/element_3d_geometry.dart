import 'dart:math' as math;
import '../../core/math/vector_3d.dart';
import '../enums/fitting_type.dart';
import '../models/fitting.dart';
import '../models/node_3d.dart';
import '../models/pipe_support.dart';
import '../models/piping_network.dart';
import '../models/valve.dart';
import '../models/weld_joint.dart';

/// Отрезок 3D пространственной каркасной линии (Wireframe) с указанием слоя
class WireframeSegment3D {
  final double x1;
  final double y1;
  final double z1;
  final double x2;
  final double y2;
  final double z2;
  final String layer;

  const WireframeSegment3D(
    this.x1,
    this.y1,
    this.z1,
    this.x2,
    this.y2,
    this.z2, {
    this.layer = '0',
  });

  Node3D get startNode => Node3D(id: '', x: x1, y: y1, z: z1);
  Node3D get endNode => Node3D(id: '', x: x2, y: y2, z: z2);
}

/// Ортонормированный 3D базис трубы
class PipeBasis3D {
  final Vector3D t; // Направление вдоль оси трубы
  final Vector3D u; // Нормаль (шпиндель / стойка)
  final Vector3D v; // Бинормаль (поперечная нормаль)

  const PipeBasis3D({
    required this.t,
    required this.u,
    required this.v,
  });

  factory PipeBasis3D.fromEndpoints(Node3D start, Node3D end, {double rotationAngleRad = 0.0}) {
    final vStart = Vector3D.fromNode(start);
    final vEnd = Vector3D.fromNode(end);
    final delta = vEnd - vStart;
    final len = delta.length;

    Vector3D t = len > 1e-6 ? delta / len : const Vector3D(1, 0, 0);

    Vector3D ref;
    if (t.z.abs() < 0.99) {
      ref = const Vector3D(0, 0, 1);
    } else {
      ref = const Vector3D(0, 1, 0);
    }

    Vector3D v = t.cross(ref).normalized();
    Vector3D u = v.cross(t).normalized();

    if (rotationAngleRad.abs() > 1e-6) {
      final cosA = math.cos(rotationAngleRad);
      final sinA = math.sin(rotationAngleRad);
      final rotatedU = u * cosA + v * sinA;
      final rotatedV = -u * sinA + v * cosA;
      u = rotatedU.normalized();
      v = rotatedV.normalized();
    }

    return PipeBasis3D(t: t, u: u, v: v);
  }
}

/// Сервис генерации честной 3D каркасной геометрии из линий (Wireframe 3D)
/// для арматуры, сварных стыков, опор, фланцев, переходов и заглушек.
class Element3dGeometry {
  static const String layerValves = 'АКСО_3D_АРМАТУРА';
  static const String layerWelds = 'АКСО_3D_СВАРНЫЕ_СТЫКИ';
  static const String layerSupports = 'АКСО_3D_ОПОРЫ';
  static const String layerFlanges = 'АКСО_3D_ФЛАНЦЫ';
  static const String layerReducers = 'АКСО_3D_ПЕРЕХОДЫ';
  static const String layerCaps = 'АКСО_3D_ЗАГЛУШКИ';

  /// Генерация 3D линий для арматуры (Valve):
  /// - Два встречных конуса корпуса (от торцов к центру)
  /// - Шпиндель (шток)
  /// - Штурвал (маховик) со спицами в поперечной плоскости
  /// - Фланцы на торцах (если isFlanged)
  static List<WireframeSegment3D> generateValve3d(
    Valve valve,
    Node3D start,
    Node3D end, {
    double? pipeOuterDiameter,
  }) {
    final lines = <WireframeSegment3D>[];
    final angleRad = valve.handleAngleDeg * math.pi / 180.0;
    final basis = PipeBasis3D.fromEndpoints(start, end, rotationAngleRad: angleRad);

    final vStart = Vector3D.fromNode(start);
    final vEnd = Vector3D.fromNode(end);
    final center = vStart + (vEnd - vStart) * valve.ratio;

    final r = math.max(12.0, ((pipeOuterDiameter ?? valve.dn.toDouble()) / 2.0));
    final halfL = math.max(15.0, valve.lengthMm / 2.0);

    final cIn = center - basis.t * halfL;
    final cOut = center + basis.t * halfL;

    // Входное и выходное кольца (12 сегментов)
    const int segments = 12;
    final inPts = <Vector3D>[];
    final outPts = <Vector3D>[];
    for (int i = 0; i < segments; i++) {
      final theta = 2.0 * math.pi * i / segments;
      final offset = basis.u * (r * math.cos(theta)) + basis.v * (r * math.sin(theta));
      inPts.add(cIn + offset);
      outPts.add(cOut + offset);
    }

    for (int i = 0; i < segments; i++) {
      final next = (i + 1) % segments;
      // Входное кольцо
      lines.add(WireframeSegment3D(
        inPts[i].x, inPts[i].y, inPts[i].z,
        inPts[next].x, inPts[next].y, inPts[next].z,
        layer: layerValves,
      ));
      // Выходное кольцо
      lines.add(WireframeSegment3D(
        outPts[i].x, outPts[i].y, outPts[i].z,
        outPts[next].x, outPts[next].y, outPts[next].z,
        layer: layerValves,
      ));
    }

    // Образующие конусов корпуса (8 генераторов от колец к центру)
    for (int i = 0; i < segments; i += (segments ~/ 8)) {
      lines.add(WireframeSegment3D(
        inPts[i].x, inPts[i].y, inPts[i].z,
        center.x, center.y, center.z,
        layer: layerValves,
      ));
      lines.add(WireframeSegment3D(
        outPts[i].x, outPts[i].y, outPts[i].z,
        center.x, center.y, center.z,
        layer: layerValves,
      ));
    }

    // Шпиндель (шток)
    final stemHeight = math.max(40.0, r * 2.2);
    final hwCenter = center + basis.u * stemHeight;
    lines.add(WireframeSegment3D(
      center.x, center.y, center.z,
      hwCenter.x, hwCenter.y, hwCenter.z,
      layer: layerValves,
    ));

    // Штурвал / маховик (окружность в плоскости T, V)
    final hwRadius = math.max(25.0, r * 1.4);
    final hwPts = <Vector3D>[];
    for (int i = 0; i < segments; i++) {
      final theta = 2.0 * math.pi * i / segments;
      final offset = basis.t * (hwRadius * math.cos(theta)) + basis.v * (hwRadius * math.sin(theta));
      hwPts.add(hwCenter + offset);
    }
    for (int i = 0; i < segments; i++) {
      final next = (i + 1) % segments;
      lines.add(WireframeSegment3D(
        hwPts[i].x, hwPts[i].y, hwPts[i].z,
        hwPts[next].x, hwPts[next].y, hwPts[next].z,
        layer: layerValves,
      ));
    }

    // 4 спицы штурвала
    for (int i = 0; i < segments; i += (segments ~/ 4)) {
      lines.add(WireframeSegment3D(
        hwCenter.x, hwCenter.y, hwCenter.z,
        hwPts[i].x, hwPts[i].y, hwPts[i].z,
        layer: layerValves,
      ));
    }

    // Если арматура фланцевая — добавляем фланцевые кольца
    if (valve.isFlanged) {
      final flangeR = r * 1.5;
      for (int i = 0; i < segments; i++) {
        final next = (i + 1) % segments;
        final th1 = 2.0 * math.pi * i / segments;
        final th2 = 2.0 * math.pi * next / segments;
        final off1 = basis.u * (flangeR * math.cos(th1)) + basis.v * (flangeR * math.sin(th1));
        final off2 = basis.u * (flangeR * math.cos(th2)) + basis.v * (flangeR * math.sin(th2));
        lines.add(WireframeSegment3D(
          (cIn + off1).x, (cIn + off1).y, (cIn + off1).z,
          (cIn + off2).x, (cIn + off2).y, (cIn + off2).z,
          layer: layerValves,
        ));
        lines.add(WireframeSegment3D(
          (cOut + off1).x, (cOut + off1).y, (cOut + off1).z,
          (cOut + off2).x, (cOut + off2).y, (cOut + off2).z,
          layer: layerValves,
        ));
      }
    }

    return lines;
  }

  /// Генерация 3D линий для сварного стыка (WeldJoint):
  /// - Пространственное кольцо усиления шва вокруг трубы
  /// - Засечки сварщика
  static List<WireframeSegment3D> generateWeld3d(
    WeldJoint weld,
    Node3D start,
    Node3D end, {
    double? pipeOuterDiameter,
  }) {
    final lines = <WireframeSegment3D>[];
    final basis = PipeBasis3D.fromEndpoints(start, end);

    final vStart = Vector3D.fromNode(start);
    final vEnd = Vector3D.fromNode(end);
    final center = vStart + (vEnd - vStart) * weld.ratio;

    final r = math.max(10.0, ((pipeOuterDiameter ?? 50.0) / 2.0) + 3.0);

    const int segments = 16;
    final ringPts = <Vector3D>[];
    for (int i = 0; i < segments; i++) {
      final theta = 2.0 * math.pi * i / segments;
      final offset = basis.u * (r * math.cos(theta)) + basis.v * (r * math.sin(theta));
      ringPts.add(center + offset);
    }

    for (int i = 0; i < segments; i++) {
      final next = (i + 1) % segments;
      lines.add(WireframeSegment3D(
        ringPts[i].x, ringPts[i].y, ringPts[i].z,
        ringPts[next].x, ringPts[next].y, ringPts[next].z,
        layer: layerWelds,
      ));
    }

    // 4 короткие поперечные засечки шва по ГОСТ 16037
    final tickLen = 6.0;
    for (int i = 0; i < segments; i += (segments ~/ 4)) {
      final p = ringPts[i];
      final pOut = p + (p - center).normalized() * tickLen;
      lines.add(WireframeSegment3D(
        p.x, p.y, p.z,
        pOut.x, pOut.y, pOut.z,
        layer: layerWelds,
      ));
    }

    return lines;
  }

  /// Генерация 3D линий для опоры трубопровода (PipeSupport):
  /// - Хомут вокруг трубы
  /// - Стойка / тяга к строительной конструкции
  /// - Опорная пластина (башмак)
  static List<WireframeSegment3D> generateSupport3d(
    PipeSupport support,
    Node3D start,
    Node3D end, {
    double? pipeOuterDiameter,
  }) {
    final lines = <WireframeSegment3D>[];
    final basis = PipeBasis3D.fromEndpoints(start, end);

    final vStart = Vector3D.fromNode(start);
    final vEnd = Vector3D.fromNode(end);
    final rRatio = support.distanceRatio.clamp(0.0, 1.0);
    final center = vStart + (vEnd - vStart) * rRatio;

    final r = math.max(10.0, ((pipeOuterDiameter ?? 50.0) / 2.0));
    final clampR = r + 4.0;

    // Хомут вокруг трубы (16 сегментов)
    const int segments = 16;
    final clampPts = <Vector3D>[];
    for (int i = 0; i < segments; i++) {
      final theta = 2.0 * math.pi * i / segments;
      final offset = basis.u * (clampR * math.cos(theta)) + basis.v * (clampR * math.sin(theta));
      clampPts.add(center + offset);
    }
    for (int i = 0; i < segments; i++) {
      final next = (i + 1) % segments;
      lines.add(WireframeSegment3D(
        clampPts[i].x, clampPts[i].y, clampPts[i].z,
        clampPts[next].x, clampPts[next].y, clampPts[next].z,
        layer: layerSupports,
      ));
    }

    // Направление стойки (вниз к полу или опорной конструкции)
    Vector3D downDir = const Vector3D(0, 0, -1);
    if (basis.t.z.abs() > 0.85) {
      // Для вертикальных труб стойка отходит перпендикулярно в сторону u
      downDir = -basis.u;
    }

    final strutLen = math.max(100.0, r * 2.5);
    final baseCenter = center + downDir * strutLen;

    // Центральная стойка
    lines.add(WireframeSegment3D(
      (center + downDir * clampR).x, (center + downDir * clampR).y, (center + downDir * clampR).z,
      baseCenter.x, baseCenter.y, baseCenter.z,
      layer: layerSupports,
    ));

    // Боковые ребра жесткости (подкосы)
    final ribW = math.max(30.0, r * 0.8);
    final ptA = center + basis.t * ribW + downDir * clampR;
    final ptB = center - basis.t * ribW + downDir * clampR;
    lines.add(WireframeSegment3D(
      ptA.x, ptA.y, ptA.z,
      baseCenter.x, baseCenter.y, baseCenter.z,
      layer: layerSupports,
    ));
    lines.add(WireframeSegment3D(
      ptB.x, ptB.y, ptB.z,
      baseCenter.x, baseCenter.y, baseCenter.z,
      layer: layerSupports,
    ));

    // Опорная плита (прямоугольник в основании)
    final plateW = ribW * 1.5;
    final plateL = math.max(40.0, r * 1.2);

    Vector3D dirX = basis.t;
    Vector3D dirY = basis.t.cross(downDir).normalized();

    final p1 = baseCenter - dirX * plateW - dirY * plateL;
    final p2 = baseCenter + dirX * plateW - dirY * plateL;
    final p3 = baseCenter + dirX * plateW + dirY * plateL;
    final p4 = baseCenter - dirX * plateW + dirY * plateL;

    lines.add(WireframeSegment3D(p1.x, p1.y, p1.z, p2.x, p2.y, p2.z, layer: layerSupports));
    lines.add(WireframeSegment3D(p2.x, p2.y, p2.z, p3.x, p3.y, p3.z, layer: layerSupports));
    lines.add(WireframeSegment3D(p3.x, p3.y, p3.z, p4.x, p4.y, p4.z, layer: layerSupports));
    lines.add(WireframeSegment3D(p4.x, p4.y, p4.z, p1.x, p1.y, p1.z, layer: layerSupports));

    return lines;
  }

  /// Генерация 3D линий для фланцев (FittingType.flange)
  static List<WireframeSegment3D> generateFlange3d(
    Fitting fitting,
    Node3D node,
    Node3D connectedNode, {
    double? pipeOuterDiameter,
  }) {
    final lines = <WireframeSegment3D>[];
    final basis = PipeBasis3D.fromEndpoints(node, connectedNode);

    final center = Vector3D.fromNode(node);
    final r = math.max(12.0, ((pipeOuterDiameter ?? fitting.dn.toDouble()) / 2.0));
    final flangeR = r * 1.55;

    const int segments = 16;
    final pts1 = <Vector3D>[];
    final pts2 = <Vector3D>[];
    final thickness = 12.0;

    final c1 = center;
    final c2 = center + basis.t * thickness;

    for (int i = 0; i < segments; i++) {
      final theta = 2.0 * math.pi * i / segments;
      final off = basis.u * (flangeR * math.cos(theta)) + basis.v * (flangeR * math.sin(theta));
      pts1.add(c1 + off);
      pts2.add(c2 + off);
    }

    for (int i = 0; i < segments; i++) {
      final next = (i + 1) % segments;
      lines.add(WireframeSegment3D(
        pts1[i].x, pts1[i].y, pts1[i].z,
        pts1[next].x, pts1[next].y, pts1[next].z,
        layer: layerFlanges,
      ));
      lines.add(WireframeSegment3D(
        pts2[i].x, pts2[i].y, pts2[i].z,
        pts2[next].x, pts2[next].y, pts2[next].z,
        layer: layerFlanges,
      ));
    }

    // 4 продольные стяжки диска фланца
    for (int i = 0; i < segments; i += (segments ~/ 4)) {
      lines.add(WireframeSegment3D(
        pts1[i].x, pts1[i].y, pts1[i].z,
        pts2[i].x, pts2[i].y, pts2[i].z,
        layer: layerFlanges,
      ));
    }

    return lines;
  }

  /// Генерация 3D линий для переходов диаметров (FittingType.reducerConcentric / reducerEccentric)
  static List<WireframeSegment3D> generateReducer3d(
    Fitting fitting,
    Node3D node,
    Node3D inNode,
    Node3D outNode, {
    double? d1,
    double? d2,
  }) {
    final lines = <WireframeSegment3D>[];
    final basis = PipeBasis3D.fromEndpoints(inNode, outNode);

    final center = Vector3D.fromNode(node);
    final r1 = math.max(10.0, ((d1 ?? fitting.dn.toDouble()) / 2.0));
    final r2 = math.max(8.0, ((d2 ?? fitting.dnSecondary?.toDouble() ?? fitting.dn.toDouble()) / 2.0));

    final length = 80.0;
    final cIn = center - basis.t * (length / 2.0);
    final cOut = center + basis.t * (length / 2.0);

    const int segments = 12;
    final inPts = <Vector3D>[];
    final outPts = <Vector3D>[];

    final isEccentric = fitting.fittingType == FittingType.reducerEccentric;
    final eccOffset = isEccentric ? basis.u * (r1 - r2) : const Vector3D(0, 0, 0);

    for (int i = 0; i < segments; i++) {
      final theta = 2.0 * math.pi * i / segments;
      final offIn = basis.u * (r1 * math.cos(theta)) + basis.v * (r1 * math.sin(theta));
      final offOut = (basis.u * (r2 * math.cos(theta)) + basis.v * (r2 * math.sin(theta))) + eccOffset;
      inPts.add(cIn + offIn);
      outPts.add(cOut + offOut);
    }

    for (int i = 0; i < segments; i++) {
      final next = (i + 1) % segments;
      lines.add(WireframeSegment3D(
        inPts[i].x, inPts[i].y, inPts[i].z,
        inPts[next].x, inPts[next].y, inPts[next].z,
        layer: layerReducers,
      ));
      lines.add(WireframeSegment3D(
        outPts[i].x, outPts[i].y, outPts[i].z,
        outPts[next].x, outPts[next].y, outPts[next].z,
        layer: layerReducers,
      ));
    }

    // 8 образующих конуса перехода
    for (int i = 0; i < segments; i += (segments ~/ 8)) {
      lines.add(WireframeSegment3D(
        inPts[i].x, inPts[i].y, inPts[i].z,
        outPts[i].x, outPts[i].y, outPts[i].z,
        layer: layerReducers,
      ));
    }

    return lines;
  }

  /// Генерация 3D линий для заглушки / днища (FittingType.cap)
  static List<WireframeSegment3D> generateCap3d(
    Fitting fitting,
    Node3D node,
    Node3D pipeNode, {
    double? pipeOuterDiameter,
  }) {
    final lines = <WireframeSegment3D>[];
    // Направление от конца трубы наружу к заглушке
    final basis = PipeBasis3D.fromEndpoints(pipeNode, node);

    final center = Vector3D.fromNode(node);
    final r = math.max(10.0, ((pipeOuterDiameter ?? fitting.dn.toDouble()) / 2.0));

    const int segments = 12;
    final basePts = <Vector3D>[];
    for (int i = 0; i < segments; i++) {
      final theta = 2.0 * math.pi * i / segments;
      final off = basis.u * (r * math.cos(theta)) + basis.v * (r * math.sin(theta));
      basePts.add(center + off);
    }

    // Окружность основания заглушки
    for (int i = 0; i < segments; i++) {
      final next = (i + 1) % segments;
      lines.add(WireframeSegment3D(
        basePts[i].x, basePts[i].y, basePts[i].z,
        basePts[next].x, basePts[next].y, basePts[next].z,
        layer: layerCaps,
      ));
    }

    // Сферический купол (эллиптическое днище)
    final domeApex = center + basis.t * (r * 0.55);
    for (int i = 0; i < segments; i += (segments ~/ 4)) {
      lines.add(WireframeSegment3D(
        basePts[i].x, basePts[i].y, basePts[i].z,
        domeApex.x, domeApex.y, domeApex.z,
        layer: layerCaps,
      ));
    }

    return lines;
  }

  /// Сборка всей 3D каркасной геометрии элементов сети (арматура, стыки, опоры, фитинги)
  static List<WireframeSegment3D> generateAllElements3d(PipingNetwork network) {
    final allLines = <WireframeSegment3D>[];

    // 1. Арматура
    for (final valve in network.valves.values) {
      final seg = network.segments[valve.segmentId];
      if (seg == null) continue;
      final s = network.nodes[seg.startNodeId];
      final e = network.nodes[seg.endNodeId];
      if (s == null || e == null) continue;
      allLines.addAll(generateValve3d(valve, s, e, pipeOuterDiameter: seg.outerDiameterMm));
    }

    // 2. Сварные стыки
    for (final weld in network.weldJoints.values) {
      final seg = network.segments[weld.segmentId];
      if (seg == null) continue;
      final s = network.nodes[seg.startNodeId];
      final e = network.nodes[seg.endNodeId];
      if (s == null || e == null) continue;
      allLines.addAll(generateWeld3d(weld, s, e, pipeOuterDiameter: seg.outerDiameterMm));
    }

    // 3. Опоры
    for (final support in network.supports.values) {
      final seg = network.segments[support.segmentId];
      if (seg == null) continue;
      final s = network.nodes[seg.startNodeId];
      final e = network.nodes[seg.endNodeId];
      if (s == null || e == null) continue;
      allLines.addAll(generateSupport3d(support, s, e, pipeOuterDiameter: seg.outerDiameterMm));
    }

    // 4. Фасонные детали (фланцы, переходы, заглушки)
    for (final fit in network.fittings.values) {
      final node = network.nodes[fit.nodeId];
      if (node == null) continue;
      final connectedSegs = network.getConnectedSegments(fit.nodeId);
      if (connectedSegs.isEmpty) continue;

      if (fit.fittingType == FittingType.flange) {
        final seg = connectedSegs.first;
        final otherNodeId = seg.startNodeId == fit.nodeId ? seg.endNodeId : seg.startNodeId;
        final otherNode = network.nodes[otherNodeId];
        if (otherNode != null) {
          allLines.addAll(generateFlange3d(fit, node, otherNode, pipeOuterDiameter: seg.outerDiameterMm));
        }
      } else if (fit.fittingType == FittingType.reducerConcentric || fit.fittingType == FittingType.reducerEccentric) {
        if (connectedSegs.length >= 2) {
          final seg1 = connectedSegs[0];
          final seg2 = connectedSegs[1];
          final other1 = network.nodes[seg1.startNodeId == fit.nodeId ? seg1.endNodeId : seg1.startNodeId];
          final other2 = network.nodes[seg2.startNodeId == fit.nodeId ? seg2.endNodeId : seg2.startNodeId];
          if (other1 != null && other2 != null) {
            allLines.addAll(generateReducer3d(
              fit,
              node,
              other1,
              other2,
              d1: seg1.outerDiameterMm,
              d2: seg2.outerDiameterMm,
            ));
          }
        }
      } else if (fit.fittingType == FittingType.cap) {
        final seg = connectedSegs.first;
        final otherNodeId = seg.startNodeId == fit.nodeId ? seg.endNodeId : seg.startNodeId;
        final otherNode = network.nodes[otherNodeId];
        if (otherNode != null) {
          allLines.addAll(generateCap3d(fit, node, otherNode, pipeOuterDiameter: seg.outerDiameterMm));
        }
      }
    }

    return allLines;
  }
}
