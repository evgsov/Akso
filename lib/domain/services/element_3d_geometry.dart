import 'dart:math' as math;
import '../../core/math/vector_3d.dart';
import '../enums/fitting_type.dart';
import '../enums/valve_type.dart';
import '../enums/weld_joint_style.dart';
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
  static const String layerDirectBranches = 'АКСО_ВРЕЗКИ';

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

        if (valve.includeCounterFlanges) {
          final cInC = cIn - basis.t * 8.0;
          final cOutC = cOut + basis.t * 8.0;
          lines.add(WireframeSegment3D(
            (cInC + off1).x, (cInC + off1).y, (cInC + off1).z,
            (cInC + off2).x, (cInC + off2).y, (cInC + off2).z,
            layer: layerValves,
          ));
          lines.add(WireframeSegment3D(
            (cOutC + off1).x, (cOutC + off1).y, (cOutC + off1).z,
            (cOutC + off2).x, (cOutC + off2).y, (cOutC + off2).z,
            layer: layerValves,
          ));
        }
      }
    }

    return lines;
  }

  /// Генерация 3D линий для сварного стыка (WeldJoint) в соответствии с выбранным стилем
  static List<WireframeSegment3D> generateWeld3d(
    WeldJoint weld,
    Node3D start,
    Node3D end, {
    double? pipeOuterDiameter,
    WeldJointStyle style = WeldJointStyle.ring3d,
    double? tickSizeMm,
    String layer = layerWelds,
  }) {
    final lines = <WireframeSegment3D>[];
    final basis = PipeBasis3D.fromEndpoints(start, end);

    final vStart = Vector3D.fromNode(start);
    final vEnd = Vector3D.fromNode(end);
    final center = vStart + (vEnd - vStart) * weld.ratio;

    // Эффективный диаметр/размер: заданный пользователем размер либо диаметр трубы
    final effectiveD = (tickSizeMm != null && tickSizeMm > 0)
        ? tickSizeMm
        : (pipeOuterDiameter ?? 50.0);
    final r = math.max(6.0, effectiveD / 2.0);

    if (style == WeldJointStyle.tick || style == WeldJointStyle.dot) {
      // Засечка/точка строго лежит в горизонтальной плоскости X, Y (под 0° по оси Z)
      // и ориентирована перпендикулярно оси трубы
      Vector3D tickDir;
      final dx = vEnd.x - vStart.x;
      final dy = vEnd.y - vStart.y;
      final lenXy = math.sqrt(dx * dx + dy * dy);

      if (lenXy > 1e-4) {
        // Перпендикуляр к трубе на плоскости X, Y (z = 0, строго под 0° к горизонту)
        tickDir = Vector3D(-dy / lenXy, dx / lenXy, 0.0);
      } else {
        // Стояк вдоль оси Z: горизонтальная засечка на плоскости X, Y (под 0° по Z)
        tickDir = const Vector3D(0.0, 1.0, 0.0);
      }

      final halfLen = style == WeldJointStyle.tick ? r : 3.0;
      final p1 = center - tickDir * halfLen;
      final p2 = center + tickDir * halfLen;
      lines.add(WireframeSegment3D(
        p1.x, p1.y, p1.z,
        p2.x, p2.y, p2.z,
        layer: layer,
      ));
      return lines;
    }

    // Для ring3d и circle: пространственное кольцо (16 сегментов)
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
        layer: layer,
      ));
    }

    return lines;
  }

  /// Генерация 3D линий для опоры трубопровода (PipeSupport):
  /// - Хомут вокруг трубы
  /// Генерация пространственного 3D-проволочного каркаса опоры или подвески трубопровода
  static List<WireframeSegment3D> generateSupportWireframe(
    PipeSupport support,
    Node3D start,
    Node3D end, {
    double? pipeOuterDiameter,
    String layer = layerSupports,
  }) {
    return generateSupport3d(
      support,
      start,
      end,
      pipeOuterDiameter: pipeOuterDiameter,
      layer: layer,
    );
  }

  /// Генерация 3D линий для опор трубопровода:
  /// - Хомут вокруг трубы
  /// - Стойка / тяга к строительной конструкции
  /// - Опорная пластина (башмак)
  static List<WireframeSegment3D> generateSupport3d(
    PipeSupport support,
    Node3D start,
    Node3D end, {
    double? pipeOuterDiameter,
    String layer = layerSupports,
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

    if (support.type == PipeSupportType.spring) {
      // Пружинная опора: спиральная пружина вокруг стойки
      final springTop = center + downDir * clampR;
      final springBottom = baseCenter - downDir * 15.0;
      final springLen = (springBottom - springTop).length;
      const int coils = 5;
      const int stepsPerCoil = 8;
      final totalSteps = coils * stepsPerCoil;
      final springPts = <Vector3D>[];
      for (int i = 0; i <= totalSteps; i++) {
        final t = i / totalSteps;
        final angle = 2.0 * math.pi * coils * t;
        final springRadius = r * 0.7;
        final pos = springTop + downDir * (springLen * t) +
            basis.u * (springRadius * math.cos(angle)) +
            basis.v * (springRadius * math.sin(angle));
        springPts.add(pos);
      }
      for (int i = 0; i < springPts.length - 1; i++) {
        lines.add(WireframeSegment3D(
          springPts[i].x, springPts[i].y, springPts[i].z,
          springPts[i + 1].x, springPts[i + 1].y, springPts[i + 1].z,
          layer: layerSupports,
        ));
      }
    } else {
      // Центральная стойка
      lines.add(WireframeSegment3D(
        (center + downDir * clampR).x, (center + downDir * clampR).y, (center + downDir * clampR).z,
        baseCenter.x, baseCenter.y, baseCenter.z,
        layer: layerSupports,
      ));
    }

    // Боковые ребра жесткости (подкосы) только у неподвижной опоры
    final ribW = math.max(30.0, r * 0.8);
    if (support.type == PipeSupportType.fixed) {
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
    }

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

    // Направляющая опора: вертикальные направляющие бортики
    if (support.type == PipeSupportType.guide) {
      final guideH = plateL * 0.6;
      final g1 = p1 - downDir * guideH;
      final g2 = p2 - downDir * guideH;
      final g3 = p3 - downDir * guideH;
      final g4 = p4 - downDir * guideH;
      lines.add(WireframeSegment3D(p1.x, p1.y, p1.z, g1.x, g1.y, g1.z, layer: layerSupports));
      lines.add(WireframeSegment3D(p2.x, p2.y, p2.z, g2.x, g2.y, g2.z, layer: layerSupports));
      lines.add(WireframeSegment3D(p3.x, p3.y, p3.z, g3.x, g3.y, g3.z, layer: layerSupports));
      lines.add(WireframeSegment3D(p4.x, p4.y, p4.z, g4.x, g4.y, g4.z, layer: layerSupports));
    }

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
    final angleRad = fitting.rotationAngleDeg * math.pi / 180.0;
    final basis = PipeBasis3D.fromEndpoints(inNode, outNode, rotationAngleRad: angleRad);

    final center = Vector3D.fromNode(node);
    final r1 = math.max(10.0, ((d1 ?? fitting.dn.toDouble()) / 2.0));
    final r2 = math.max(8.0, ((d2 ?? fitting.dnSecondary?.toDouble() ?? fitting.dn.toDouble()) / 2.0));

    final distIn = node.distanceTo(inNode);
    final distOut = node.distanceTo(outNode);
    final maxAllowedHalfL = math.min(distIn, distOut) * 0.45;
    final halfL = (fitting.effectiveBuildingLengthMm / 2.0).clamp(10.0, math.max(10.0, maxAllowedHalfL)).toDouble();
    final cIn = center - basis.t * halfL;
    final cOut = center + basis.t * halfL;

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

  /// Генерация 3D линий для прямой врезки патрубка в трубу (FittingType.directBranch, шов У18)
  static List<WireframeSegment3D> generateDirectBranch3d(
    Fitting fitting,
    Node3D node,
    Node3D branchOtherNode, {
    double? mainOuterDiameter,
    double? branchOuterDiameter,
    String layer = layerDirectBranches,
  }) {
    final lines = <WireframeSegment3D>[];
    final basis = PipeBasis3D.fromEndpoints(node, branchOtherNode);

    final rMain = (mainOuterDiameter ?? fitting.dn.toDouble()) / 2.0;
    final rBranch = (branchOuterDiameter ?? (fitting.dnSecondary ?? fitting.dn).toDouble()) / 2.0;

    // Точка сопряжения патрубка с образующей магистрали
    final center = Vector3D.fromNode(node) + basis.t * rMain;

    // Сварное кольцо шва У18 вокруг патрубка
    const int segments = 12;
    final basePts = <Vector3D>[];
    for (int i = 0; i < segments; i++) {
      final theta = 2.0 * math.pi * i / segments;
      final off = basis.u * (rBranch * 1.05 * math.cos(theta)) + basis.v * (rBranch * 1.05 * math.sin(theta));
      basePts.add(center + off);
    }

    for (int i = 0; i < segments; i++) {
      final next = (i + 1) % segments;
      lines.add(WireframeSegment3D(
        basePts[i].x, basePts[i].y, basePts[i].z,
        basePts[next].x, basePts[next].y, basePts[next].z,
        layer: layer,
      ));
    }

    // Осевая линия сопряжения от центра узла магистрали до шва контакта
    lines.add(WireframeSegment3D(
      node.x, node.y, node.z,
      center.x, center.y, center.z,
      layer: layer,
    ));

    return lines;
  }

  /// Генерация 3D-векторного обозначения перехода диаметров (треугольник вдоль оси трубы)
  /// Вершина треугольника указывает в сторону заужения (меньшего диаметра).
  /// Основание треугольника находится на стороне большего диаметра.
  static List<WireframeSegment3D> generateReducerWireframe(
    Fitting fitting,
    Node3D node,
    Node3D inNode,
    Node3D outNode, {
    double? d1,
    double? d2,
    String layer = layerReducers,
  }) {
    final lines = <WireframeSegment3D>[];
    final angleRad = fitting.rotationAngleDeg * math.pi / 180.0;
    final basis = PipeBasis3D.fromEndpoints(inNode, outNode, rotationAngleRad: angleRad);

    final center = Vector3D.fromNode(node);
    final len = fitting.effectiveBuildingLengthMm;
    final distIn = node.distanceTo(inNode);
    final distOut = node.distanceTo(outNode);
    final maxAllowedHalfL = math.min(distIn, distOut) * 0.45;
    final halfL = (len / 2.0).clamp(10.0, math.max(10.0, maxAllowedHalfL)).toDouble();

    final cIn = center - basis.t * halfL;
    final cOut = center + basis.t * halfL;

    final dnIn = d1 ?? fitting.dn.toDouble();
    final dnOut = d2 ?? (fitting.dnSecondary?.toDouble() ?? fitting.dn.toDouble());

    // Определяем, с какой стороны основание (больший диаметр), а с какой вершина (меньший)
    final bool inIsBigger = dnIn >= dnOut;
    final cBase = inIsBigger ? cIn : cOut;
    final cApex = inIsBigger ? cOut : cIn;
    final maxDn = math.max(dnIn, dnOut);
    final minDn = math.min(dnIn, dnOut);

    // Полуширина основания треугольника
    final w = math.max(16.0, maxDn * 0.45);
    final isEccentric = fitting.fittingType == FittingType.reducerEccentric;

    // Используем поперечный вектор basis.v как основной в плоскости сети при угле 0°,
    // чтобы треугольник лежал в горизонтальной плоскости (XY) и был идеально виден в плане и аксонометрии.
    // При вращении («Поворот +90°») basis.v поворачивается в вертикальную плоскость Z.
    final transverse = basis.v;

    if (!isEccentric) {
      // Концентрический переход: равнобедренный треугольник со схождением на оси трубы
      final pB1 = cBase + transverse * w;
      final pB2 = cBase - transverse * w;
      final pApex = cApex;

      // Основание
      lines.add(WireframeSegment3D(pB1.x, pB1.y, pB1.z, pB2.x, pB2.y, pB2.z, layer: layer));
      // Две боковые образующие
      lines.add(WireframeSegment3D(pB1.x, pB1.y, pB1.z, pApex.x, pApex.y, pApex.z, layer: layer));
      lines.add(WireframeSegment3D(pB2.x, pB2.y, pB2.z, pApex.x, pApex.y, pApex.z, layer: layer));
      // Поперечная засечка на вершине (торец меньшей трубы)
      final tipW = math.max(6.0, minDn * 0.25);
      lines.add(WireframeSegment3D(
        (pApex + transverse * tipW).x, (pApex + transverse * tipW).y, (pApex + transverse * tipW).z,
        (pApex - transverse * tipW).x, (pApex - transverse * tipW).y, (pApex - transverse * tipW).z,
        layer: layer,
      ));
    } else {
      // Эксцентрический переход: одна сторона прямая (по образующей), вторая наклонная
      // Смещение задается вектором transverse (который вращается на fitting.rotationAngleDeg)
      final pFlatBase = cBase - transverse * (w * 0.35);
      final pFlatApex = cApex - transverse * (w * 0.35);
      final pSlopeBase = cBase + transverse * (w * 1.65);

      // Основание
      lines.add(WireframeSegment3D(pFlatBase.x, pFlatBase.y, pFlatBase.z, pSlopeBase.x, pSlopeBase.y, pSlopeBase.z, layer: layer));
      // Прямая образующая
      lines.add(WireframeSegment3D(pFlatBase.x, pFlatBase.y, pFlatBase.z, pFlatApex.x, pFlatApex.y, pFlatApex.z, layer: layer));
      // Наклонная образующая
      lines.add(WireframeSegment3D(pSlopeBase.x, pSlopeBase.y, pSlopeBase.z, pFlatApex.x, pFlatApex.y, pFlatApex.z, layer: layer));
      // Поперечная засечка на вершине
      final tipW = math.max(6.0, minDn * 0.25);
      lines.add(WireframeSegment3D(
        pFlatApex.x, pFlatApex.y, pFlatApex.z,
        (pFlatApex + transverse * tipW).x, (pFlatApex + transverse * tipW).y, (pFlatApex + transverse * tipW).z,
        layer: layer,
      ));
    }

    return lines;
  }

  /// Генерация 3D-векторного обозначения арматуры (встречные треугольники «песочные часы»)
  static List<WireframeSegment3D> generateValveWireframe(
    Valve valve,
    Node3D start,
    Node3D end, {
    double? pipeOuterDiameter,
    String layer = layerValves,
  }) {
    final lines = <WireframeSegment3D>[];
    final angleRad = valve.handleAngleDeg * math.pi / 180.0;
    final basis = PipeBasis3D.fromEndpoints(start, end, rotationAngleRad: angleRad);

    final vStart = Vector3D.fromNode(start);
    final vEnd = Vector3D.fromNode(end);
    final center = vStart + (vEnd - vStart) * valve.ratio;

    final halfL = math.max(12.0, valve.lengthMm / 2.0);
    final cIn = center - basis.t * halfL;
    final cOut = center + basis.t * halfL;

    final w = math.max(10.0, ((pipeOuterDiameter ?? valve.dn.toDouble()) / 2.0));

    // Входной треугольник: основание cIn +/- basis.u * w, вершина в center
    final pIn1 = cIn + basis.u * w;
    final pIn2 = cIn - basis.u * w;
    lines.add(WireframeSegment3D(pIn1.x, pIn1.y, pIn1.z, pIn2.x, pIn2.y, pIn2.z, layer: layer));
    lines.add(WireframeSegment3D(pIn1.x, pIn1.y, pIn1.z, center.x, center.y, center.z, layer: layer));
    lines.add(WireframeSegment3D(pIn2.x, pIn2.y, pIn2.z, center.x, center.y, center.z, layer: layer));

    // Выходной треугольник: основание cOut +/- basis.u * w, вершина в center
    final pOut1 = cOut + basis.u * w;
    final pOut2 = cOut - basis.u * w;
    lines.add(WireframeSegment3D(pOut1.x, pOut1.y, pOut1.z, pOut2.x, pOut2.y, pOut2.z, layer: layer));
    lines.add(WireframeSegment3D(pOut1.x, pOut1.y, pOut1.z, center.x, center.y, center.z, layer: layer));
    lines.add(WireframeSegment3D(pOut2.x, pOut2.y, pOut2.z, center.x, center.y, center.z, layer: layer));

    // Шток (шпиндель)
    final stemH = w * 1.55;
    final hwCenter = center + basis.u * stemH;
    lines.add(WireframeSegment3D(center.x, center.y, center.z, hwCenter.x, hwCenter.y, hwCenter.z, layer: layer));

    // Маховик / рукоятка в зависимости от типа арматуры
    switch (valve.valveType) {
      case ValveType.gateValve:
        // Маховик (перекрестие спиц)
        final hwR = w * 0.8;
        lines.add(WireframeSegment3D(
          (hwCenter - basis.t * hwR).x, (hwCenter - basis.t * hwR).y, (hwCenter - basis.t * hwR).z,
          (hwCenter + basis.t * hwR).x, (hwCenter + basis.t * hwR).y, (hwCenter + basis.t * hwR).z,
          layer: layer,
        ));
        lines.add(WireframeSegment3D(
          (hwCenter - basis.v * hwR).x, (hwCenter - basis.v * hwR).y, (hwCenter - basis.v * hwR).z,
          (hwCenter + basis.v * hwR).x, (hwCenter + basis.v * hwR).y, (hwCenter + basis.v * hwR).z,
          layer: layer,
        ));
        break;

      case ValveType.ballValve:
        // Рукоятка-рычаг вдоль трубы
        final leverLen = w * 1.4;
        lines.add(WireframeSegment3D(
          hwCenter.x, hwCenter.y, hwCenter.z,
          (hwCenter + basis.t * leverLen).x, (hwCenter + basis.t * leverLen).y, (hwCenter + basis.t * leverLen).z,
          layer: layer,
        ));
        break;

      case ValveType.butterflyValve:
        // Диск по центру и рукоятка
        lines.add(WireframeSegment3D(
          (center - basis.u * w).x, (center - basis.u * w).y, (center - basis.u * w).z,
          (center + basis.u * w).x, (center + basis.u * w).y, (center + basis.u * w).z,
          layer: layer,
        ));
        final leverEnd = hwCenter + (basis.t * 0.8 + basis.u * 0.3) * w;
        lines.add(WireframeSegment3D(hwCenter.x, hwCenter.y, hwCenter.z, leverEnd.x, leverEnd.y, leverEnd.z, layer: layer));
        break;

      case ValveType.checkValve:
        // Наклонное седло клапана
        lines.add(WireframeSegment3D(
          (center - basis.t * (halfL * 0.3) - basis.u * (w * 0.75)).x, (center - basis.t * (halfL * 0.3) - basis.u * (w * 0.75)).y, (center - basis.t * (halfL * 0.3) - basis.u * (w * 0.75)).z,
          (center + basis.t * (halfL * 0.3) + basis.u * (w * 0.75)).x, (center + basis.t * (halfL * 0.3) + basis.u * (w * 0.75)).y, (center + basis.t * (halfL * 0.3) + basis.u * (w * 0.75)).z,
          layer: layer,
        ));
        // Стрелка направления
        final dir = valve.isReversed ? -basis.t : basis.t;
        final arrowTip = center + dir * (halfL * 0.7);
        final arrowBase = center - dir * (halfL * 0.2);
        lines.add(WireframeSegment3D(arrowBase.x, arrowBase.y, arrowBase.z, arrowTip.x, arrowTip.y, arrowTip.z, layer: layer));
        lines.add(WireframeSegment3D(
          arrowTip.x, arrowTip.y, arrowTip.z,
          (arrowTip - dir * (w * 0.35) + basis.u * (w * 0.25)).x, (arrowTip - dir * (w * 0.35) + basis.u * (w * 0.25)).y, (arrowTip - dir * (w * 0.35) + basis.u * (w * 0.25)).z,
          layer: layer,
        ));
        lines.add(WireframeSegment3D(
          arrowTip.x, arrowTip.y, arrowTip.z,
          (arrowTip - dir * (w * 0.35) - basis.u * (w * 0.25)).x, (arrowTip - dir * (w * 0.35) - basis.u * (w * 0.25)).y, (arrowTip - dir * (w * 0.35) - basis.u * (w * 0.25)).z,
          layer: layer,
        ));
        break;

      case ValveType.strainer:
        // Фильтр-грязевик: наклонная колба под 45 градусов вниз
        final flaskDir = (-basis.t * 0.707 - basis.u * 0.707).normalized();
        final flaskEnd = center + flaskDir * (w * 1.8);
        lines.add(WireframeSegment3D(center.x, center.y, center.z, flaskEnd.x, flaskEnd.y, flaskEnd.z, layer: layer));
        // Крышка отстойника
        final capDir = flaskDir.cross(basis.v).normalized();
        final cap1 = flaskEnd + capDir * (w * 0.4);
        final cap2 = flaskEnd - capDir * (w * 0.4);
        lines.add(WireframeSegment3D(cap1.x, cap1.y, cap1.z, cap2.x, cap2.y, cap2.z, layer: layer));
        break;

      case ValveType.balancingValve:
        // Балансировочный клапан: шток с настроечной головкой
        final mimW = w * 1.2;
        lines.add(WireframeSegment3D(
          (hwCenter - basis.t * mimW).x, (hwCenter - basis.t * mimW).y, (hwCenter - basis.t * mimW).z,
          (hwCenter + basis.t * mimW).x, (hwCenter + basis.t * mimW).y, (hwCenter + basis.t * mimW).z,
          layer: layer,
        ));
        final mimTop = hwCenter + basis.u * (w * 0.5);
        lines.add(WireframeSegment3D((hwCenter - basis.t * mimW).x, (hwCenter - basis.t * mimW).y, (hwCenter - basis.t * mimW).z, mimTop.x, mimTop.y, mimTop.z, layer: layer));
        lines.add(WireframeSegment3D((hwCenter + basis.t * mimW).x, (hwCenter + basis.t * mimW).y, (hwCenter + basis.t * mimW).z, mimTop.x, mimTop.y, mimTop.z, layer: layer));
        break;

      case ValveType.drainValve:
        // Спускной / дренажный кран: короткий патрубок вниз
        final drainEnd = center - basis.u * (w * 1.5);
        lines.add(WireframeSegment3D(center.x, center.y, center.z, drainEnd.x, drainEnd.y, drainEnd.z, layer: layer));
        break;

      case ValveType.waterMeter:
        // Водосчетчик: счетная коробка
        final boxW = w * 0.6;
        final boxTop = hwCenter + basis.u * (w * 0.5);
        lines.add(WireframeSegment3D(
          (hwCenter - basis.t * boxW).x, (hwCenter - basis.t * boxW).y, (hwCenter - basis.t * boxW).z,
          (hwCenter + basis.t * boxW).x, (hwCenter + basis.t * boxW).y, (hwCenter + basis.t * boxW).z,
          layer: layer,
        ));
        lines.add(WireframeSegment3D(
          (boxTop - basis.t * boxW).x, (boxTop - basis.t * boxW).y, (boxTop - basis.t * boxW).z,
          (boxTop + basis.t * boxW).x, (boxTop + basis.t * boxW).y, (boxTop + basis.t * boxW).z,
          layer: layer,
        ));
        lines.add(WireframeSegment3D((hwCenter - basis.t * boxW).x, (hwCenter - basis.t * boxW).y, (hwCenter - basis.t * boxW).z, (boxTop - basis.t * boxW).x, (boxTop - basis.t * boxW).y, (boxTop - basis.t * boxW).z, layer: layer));
        lines.add(WireframeSegment3D((hwCenter + basis.t * boxW).x, (hwCenter + basis.t * boxW).y, (hwCenter + basis.t * boxW).z, (boxTop + basis.t * boxW).x, (boxTop + basis.t * boxW).y, (boxTop + basis.t * boxW).z, layer: layer));
        break;

      case ValveType.pressureGauge:
      case ValveType.thermometer:
      case ValveType.airVent:
        // Прибор КИПиА: круг/циферблат на штоке
        final gaugeR = w * 0.9;
        const pts = 8;
        for (int i = 0; i < pts; i++) {
          final a1 = (i * 2 * math.pi) / pts;
          final a2 = ((i + 1) * 2 * math.pi) / pts;
          final pA = hwCenter + basis.t * (math.cos(a1) * gaugeR) + basis.u * (math.sin(a1) * gaugeR);
          final pB = hwCenter + basis.t * (math.cos(a2) * gaugeR) + basis.u * (math.sin(a2) * gaugeR);
          lines.add(WireframeSegment3D(pA.x, pA.y, pA.z, pB.x, pB.y, pB.z, layer: layer));
        }
        break;
    }

    // Если арматура фланцевая — засечки фланцев на торцах
    if (valve.isFlanged) {
      final flW = w * 1.25;
      lines.add(WireframeSegment3D(
        (cIn + basis.v * flW).x, (cIn + basis.v * flW).y, (cIn + basis.v * flW).z,
        (cIn - basis.v * flW).x, (cIn - basis.v * flW).y, (cIn - basis.v * flW).z,
        layer: layer,
      ));
      lines.add(WireframeSegment3D(
        (cOut + basis.v * flW).x, (cOut + basis.v * flW).y, (cOut + basis.v * flW).z,
        (cOut - basis.v * flW).x, (cOut - basis.v * flW).y, (cOut - basis.v * flW).z,
        layer: layer,
      ));

      if (valve.includeCounterFlanges) {
        final gap = math.max(6.0, w * 0.25);
        final neckLen = math.min(10.0, w * 0.35);

        // Входной ответный фланец и воротник приварки к трубе
        final cInC = cIn - basis.t * gap;
        lines.add(WireframeSegment3D(
          (cInC + basis.v * flW).x, (cInC + basis.v * flW).y, (cInC + basis.v * flW).z,
          (cInC - basis.v * flW).x, (cInC - basis.v * flW).y, (cInC - basis.v * flW).z,
          layer: layer,
        ));
        final pNeckIn = cInC - basis.t * neckLen;
        lines.add(WireframeSegment3D(
          (pNeckIn + basis.v * w).x, (pNeckIn + basis.v * w).y, (pNeckIn + basis.v * w).z,
          (pNeckIn - basis.v * w).x, (pNeckIn - basis.v * w).y, (pNeckIn - basis.v * w).z,
          layer: layer,
        ));
        lines.add(WireframeSegment3D(
          (cInC + basis.v * flW).x, (cInC + basis.v * flW).y, (cInC + basis.v * flW).z,
          (pNeckIn + basis.v * w).x, (pNeckIn + basis.v * w).y, (pNeckIn + basis.v * w).z,
          layer: layer,
        ));
        lines.add(WireframeSegment3D(
          (cInC - basis.v * flW).x, (cInC - basis.v * flW).y, (cInC - basis.v * flW).z,
          (pNeckIn - basis.v * w).x, (pNeckIn - basis.v * w).y, (pNeckIn - basis.v * w).z,
          layer: layer,
        ));

        // Выходной ответный фланец и воротник приварки к трубе
        final cOutC = cOut + basis.t * gap;
        lines.add(WireframeSegment3D(
          (cOutC + basis.v * flW).x, (cOutC + basis.v * flW).y, (cOutC + basis.v * flW).z,
          (cOutC - basis.v * flW).x, (cOutC - basis.v * flW).y, (cOutC - basis.v * flW).z,
          layer: layer,
        ));
        final pNeckOut = cOutC + basis.t * neckLen;
        lines.add(WireframeSegment3D(
          (pNeckOut + basis.v * w).x, (pNeckOut + basis.v * w).y, (pNeckOut + basis.v * w).z,
          (pNeckOut - basis.v * w).x, (pNeckOut - basis.v * w).y, (pNeckOut - basis.v * w).z,
          layer: layer,
        ));
        lines.add(WireframeSegment3D(
          (cOutC + basis.v * flW).x, (cOutC + basis.v * flW).y, (cOutC + basis.v * flW).z,
          (pNeckOut + basis.v * w).x, (pNeckOut + basis.v * w).y, (pNeckOut + basis.v * w).z,
          layer: layer,
        ));
        lines.add(WireframeSegment3D(
          (cOutC - basis.v * flW).x, (cOutC - basis.v * flW).y, (cOutC - basis.v * flW).z,
          (pNeckOut - basis.v * w).x, (pNeckOut - basis.v * w).y, (pNeckOut - basis.v * w).z,
          layer: layer,
        ));
      }
    }

    return lines;
  }

  /// Генерация 3D-векторного обозначения заглушки (купольная дуга на торце трубы)
  static List<WireframeSegment3D> generateCapWireframe(
    Fitting fitting,
    Node3D node,
    Node3D pipeNode, {
    double? pipeOuterDiameter,
    String layer = layerCaps,
  }) {
    final lines = <WireframeSegment3D>[];
    final angleRad = fitting.rotationAngleDeg * math.pi / 180.0;
    var basis = PipeBasis3D.fromEndpoints(pipeNode, node, rotationAngleRad: angleRad);
    if (fitting.isFlipped) {
      basis = PipeBasis3D(
        t: basis.t * -1.0,
        u: basis.u,
        v: basis.v * -1.0,
      );
    }

    final center = Vector3D.fromNode(node);
    final r = math.max(10.0, ((pipeOuterDiameter ?? fitting.dn.toDouble()) / 2.0));

    final std = fitting.standard ?? '';
    final isFlat = std.toLowerCase().contains('плоск') ||
        (fitting.name?.toLowerCase().contains('плоск') == true) ||
        (std.contains('ОСТ') && !std.contains('ГОСТ'));

    if (isFlat) {
      // Плоская приварная заглушка (ОСТ 34.10.758): торец трубы и плоская торцевая пластина
      final pB1 = center + basis.u * r;
      final pB2 = center - basis.u * r;
      lines.add(WireframeSegment3D(pB1.x, pB1.y, pB1.z, pB2.x, pB2.y, pB2.z, layer: layer));

      final pV1 = center + basis.v * (r * 0.4);
      final pV2 = center - basis.v * (r * 0.4);
      lines.add(WireframeSegment3D(pV1.x, pV1.y, pV1.z, pV2.x, pV2.y, pV2.z, layer: layer));

      final thick = math.max(6.0, r * 0.2);
      final cPlate = center + basis.t * thick;
      final pP1 = cPlate + basis.u * (r * 1.05);
      final pP2 = cPlate - basis.u * (r * 1.05);
      lines.add(WireframeSegment3D(pP1.x, pP1.y, pP1.z, pP2.x, pP2.y, pP2.z, layer: layer));
      lines.add(WireframeSegment3D(pB1.x, pB1.y, pB1.z, pP1.x, pP1.y, pP1.z, layer: layer));
      lines.add(WireframeSegment3D(pB2.x, pB2.y, pB2.z, pP2.x, pP2.y, pP2.z, layer: layer));
    } else {
      // Эллиптическое днище (ГОСТ 6533 / ГОСТ 17379) — один чистый эллипс купола
      final h = (fitting.buildingLengthMm != null && fitting.buildingLengthMm! > 0)
          ? fitting.buildingLengthMm!
          : math.max(12.0, r * 0.5);

      // Базовый поперечный отрезок торца трубы (сварной шов)
      final pB1 = center + basis.u * r;
      final pB2 = center - basis.u * r;
      lines.add(WireframeSegment3D(pB1.x, pB1.y, pB1.z, pB2.x, pB2.y, pB2.z, layer: layer));

      // Единственная полукруглая дуга купола в плоскости (u, t) (8 сегментов)
      const int numSegs = 8;
      Vector3D prevPt = pB1;
      for (int i = 1; i <= numSegs; i++) {
        final angle = (math.pi / 2.0) - (math.pi * i / numSegs);
        final pt = center + basis.u * (r * math.sin(angle)) + basis.t * (h * math.cos(angle));
        lines.add(WireframeSegment3D(prevPt.x, prevPt.y, prevPt.z, pt.x, pt.y, pt.z, layer: layer));
        prevPt = pt;
      }

      // Осевая центровочная риска на вершине купола
      final pApex = center + basis.t * h;
      final pAxisTip = center + basis.t * (h + 4.0);
      lines.add(WireframeSegment3D(pApex.x, pApex.y, pApex.z, pAxisTip.x, pAxisTip.y, pAxisTip.z, layer: layer));
    }

    return lines;
  }

  /// Генерация 3D-векторного обозначения фланца (поперечный штрих или пара штрихов)
  static List<WireframeSegment3D> generateFlangeWireframe(
    Fitting fitting,
    Node3D node,
    Node3D otherNode, {
    double? pipeOuterDiameter,
    String layer = layerFlanges,
  }) {
    final lines = <WireframeSegment3D>[];
    final angleRad = fitting.rotationAngleDeg * math.pi / 180.0;
    var basis = PipeBasis3D.fromEndpoints(otherNode, node, rotationAngleRad: angleRad);
    if (fitting.isFlipped) {
      basis = PipeBasis3D(
        t: basis.t * -1.0,
        u: basis.u,
        v: basis.v * -1.0,
      );
    }

    final center = Vector3D.fromNode(node);
    final r = math.max(12.0, ((pipeOuterDiameter ?? fitting.dn.toDouble()) / 2.0));
    final flW = r * 1.35;

    // Первый диск фланца
    final p1 = center + basis.u * flW;
    final p2 = center - basis.u * flW;
    lines.add(WireframeSegment3D(p1.x, p1.y, p1.z, p2.x, p2.y, p2.z, layer: layer));

    // Поперечный штрих в плоскости v для пространственной четкости
    final pV1 = center + basis.v * (flW * 0.25);
    final pV2 = center - basis.v * (flW * 0.25);
    lines.add(WireframeSegment3D(pV1.x, pV1.y, pV1.z, pV2.x, pV2.y, pV2.z, layer: layer));

    // Воротниковый переход к трубе (коническая юбка приварки встык по ГОСТ 33259 тип 11)
    final pNeck = center - basis.t * math.min(10.0, r * 0.35);
    final pN1 = pNeck + basis.u * r;
    final pN2 = pNeck - basis.u * r;
    lines.add(WireframeSegment3D(pN1.x, pN1.y, pN1.z, pN2.x, pN2.y, pN2.z, layer: layer));
    lines.add(WireframeSegment3D(pN1.x, pN1.y, pN1.z, p1.x, p1.y, p1.z, layer: layer));
    lines.add(WireframeSegment3D(pN2.x, pN2.y, pN2.z, p2.x, p2.y, p2.z, layer: layer));

    if (fitting.isFlangePair || fitting.flangeConnectionType == FlangeConnectionType.pipeToPipe) {
      // Фланцевая пара: второй фланец на расстоянии gap
      final gap = (fitting.buildingLengthMm != null && fitting.buildingLengthMm! > 0)
          ? fitting.buildingLengthMm! * 0.4
          : 14.0;
      final c2 = center + basis.t * gap;
      final p3 = c2 + basis.u * flW;
      final p4 = c2 - basis.u * flW;
      lines.add(WireframeSegment3D(p3.x, p3.y, p3.z, p4.x, p4.y, p4.z, layer: layer));

      final pV3 = c2 + basis.v * (flW * 0.25);
      final pV4 = c2 - basis.v * (flW * 0.25);
      lines.add(WireframeSegment3D(pV3.x, pV3.y, pV3.z, pV4.x, pV4.y, pV4.z, layer: layer));

      // Воротниковый переход второго фланца к ответной трубе (юбка приварки)
      final pNeck2 = c2 + basis.t * math.min(10.0, r * 0.35);
      final pN3 = pNeck2 + basis.u * r;
      final pN4 = pNeck2 - basis.u * r;
      lines.add(WireframeSegment3D(pN3.x, pN3.y, pN3.z, pN4.x, pN4.y, pN4.z, layer: layer));
      lines.add(WireframeSegment3D(pN3.x, pN3.y, pN3.z, p3.x, p3.y, p3.z, layer: layer));
      lines.add(WireframeSegment3D(pN4.x, pN4.y, pN4.z, p4.x, p4.y, p4.z, layer: layer));

      // Межфланцевая прокладка (засечки между дисками)
      lines.add(WireframeSegment3D((center + basis.u * (flW * 0.6)).x, (center + basis.u * (flW * 0.6)).y, (center + basis.u * (flW * 0.6)).z, (c2 + basis.u * (flW * 0.6)).x, (c2 + basis.u * (flW * 0.6)).y, (c2 + basis.u * (flW * 0.6)).z, layer: layer));
      lines.add(WireframeSegment3D((center - basis.u * (flW * 0.6)).x, (center - basis.u * (flW * 0.6)).y, (center - basis.u * (flW * 0.6)).z, (c2 - basis.u * (flW * 0.6)).x, (c2 - basis.u * (flW * 0.6)).y, (c2 - basis.u * (flW * 0.6)).z, layer: layer));
    } else if (fitting.flangeConnectionType == FlangeConnectionType.blindFlange) {
      // Глухой фланец: пластина заглушки с наружной стороны
      final cBlind = center + basis.t * 8.0;
      final pB1 = cBlind + basis.u * (flW * 1.05);
      final pB2 = cBlind - basis.u * (flW * 1.05);
      lines.add(WireframeSegment3D(pB1.x, pB1.y, pB1.z, pB2.x, pB2.y, pB2.z, layer: layer));
      lines.add(WireframeSegment3D(p1.x, p1.y, p1.z, pB1.x, pB1.y, pB1.z, layer: layer));
      lines.add(WireframeSegment3D(p2.x, p2.y, p2.z, pB2.x, pB2.y, pB2.z, layer: layer));
    } else if (fitting.flangeConnectionType == FlangeConnectionType.toEquipment) {
      // Фланец к оборудованию: штуцер/патрубок аппарата
      final cEq = center + basis.t * 12.0;
      final pE1 = cEq + basis.u * (flW * 1.15);
      final pE2 = cEq - basis.u * (flW * 1.15);
      lines.add(WireframeSegment3D(pE1.x, pE1.y, pE1.z, pE2.x, pE2.y, pE2.z, layer: layer));
      lines.add(WireframeSegment3D(p1.x, p1.y, p1.z, pE1.x, pE1.y, pE1.z, layer: layer));
      lines.add(WireframeSegment3D(p2.x, p2.y, p2.z, pE2.x, pE2.y, pE2.z, layer: layer));
    }

    return lines;
  }

  /// Генерация 3D каркасной геометрии штуцера технологического оборудования (Nozzle):
  /// - Осевой патрубок от точки на грани аппарата к торцу штуцера
  /// - 3D-диск фланца штуцера (ортогонален направлению патрубка)
  /// - Конический воротник приварки к аппарату (юбка по ГОСТ 33259 тип 11)
  /// - При [includeCounterFlange] == true: ответный фланец трубопровода с межфланцевой прокладкой
  static List<WireframeSegment3D> generateNozzleWireframe({
    required double startX,
    required double startY,
    required double startZ,
    required double dirX,
    required double dirY,
    required double dirZ,
    required int dn,
    double spudLengthMm = 120.0,
    bool includeCounterFlange = false,
    String layer = layerFlanges,
  }) {
    final lines = <WireframeSegment3D>[];
    final vStart = Vector3D(startX, startY, startZ);
    var vDir = Vector3D(dirX, dirY, dirZ);
    if (vDir.length < 1e-6) {
      vDir = const Vector3D(0, 0, 1);
    } else {
      vDir = vDir.normalized();
    }

    final vEnd = vStart + vDir * spudLengthMm;

    // 1. Осевой патрубок
    lines.add(WireframeSegment3D(
      vStart.x, vStart.y, vStart.z,
      vEnd.x, vEnd.y, vEnd.z,
      layer: layer,
    ));

    // Базис вдоль направления штуцера
    final basis = PipeBasis3D.fromEndpoints(
      Node3D(id: '', x: vStart.x, y: vStart.y, z: vStart.z),
      Node3D(id: '', x: vEnd.x, y: vEnd.y, z: vEnd.z),
    );

    final r = math.max(12.0, dn / 2.0);
    final flW = r * 1.35;

    // 2. Первый фланец (комплектный фланец штуцера на торце патрубка)
    // 8-угольный диск фланца
    const int segments = 8;
    final fl1Pts = <Vector3D>[];
    for (int i = 0; i < segments; i++) {
      final theta = 2.0 * math.pi * i / segments;
      final offset = basis.u * (flW * math.cos(theta)) + basis.v * (flW * math.sin(theta));
      fl1Pts.add(vEnd + offset);
    }
    for (int i = 0; i < segments; i++) {
      final next = (i + 1) % segments;
      lines.add(WireframeSegment3D(
        fl1Pts[i].x, fl1Pts[i].y, fl1Pts[i].z,
        fl1Pts[next].x, fl1Pts[next].y, fl1Pts[next].z,
        layer: layer,
      ));
    }

    // Две взаимно перпендикулярные образующие диска фланца (перекрестие по U и V)
    final pU1 = vEnd + basis.u * flW;
    final pU2 = vEnd - basis.u * flW;
    lines.add(WireframeSegment3D(pU1.x, pU1.y, pU1.z, pU2.x, pU2.y, pU2.z, layer: layer));

    final pV1 = vEnd + basis.v * flW;
    final pV2 = vEnd - basis.v * flW;
    lines.add(WireframeSegment3D(pV1.x, pV1.y, pV1.z, pV2.x, pV2.y, pV2.z, layer: layer));

    // 3. Воротниковый переход к патрубку (юбка по ГОСТ 33259 тип 11)
    final pNeck = vEnd - basis.t * math.min(12.0, r * 0.35);
    final pN1 = pNeck + basis.u * r;
    final pN2 = pNeck - basis.u * r;
    lines.add(WireframeSegment3D(pN1.x, pN1.y, pN1.z, pN2.x, pN2.y, pN2.z, layer: layer));
    lines.add(WireframeSegment3D(pN1.x, pN1.y, pN1.z, pU1.x, pU1.y, pU1.z, layer: layer));
    lines.add(WireframeSegment3D(pN2.x, pN2.y, pN2.z, pU2.x, pU2.y, pU2.z, layer: layer));

    // 4. Ответный фланец (при включении тумблера «Ответный фланец в МТО»)
    if (includeCounterFlange) {
      const gap = 14.0;
      final c2 = vEnd + basis.t * gap;

      // 8-угольный диск ответного фланца
      final fl2Pts = <Vector3D>[];
      for (int i = 0; i < segments; i++) {
        final theta = 2.0 * math.pi * i / segments;
        final offset = basis.u * (flW * math.cos(theta)) + basis.v * (flW * math.sin(theta));
        fl2Pts.add(c2 + offset);
      }
      for (int i = 0; i < segments; i++) {
        final next = (i + 1) % segments;
        lines.add(WireframeSegment3D(
          fl2Pts[i].x, fl2Pts[i].y, fl2Pts[i].z,
          fl2Pts[next].x, fl2Pts[next].y, fl2Pts[next].z,
          layer: layer,
        ));
      }

      final pU3 = c2 + basis.u * flW;
      final pU4 = c2 - basis.u * flW;
      lines.add(WireframeSegment3D(pU3.x, pU3.y, pU3.z, pU4.x, pU4.y, pU4.z, layer: layer));

      final pV3 = c2 + basis.v * flW;
      final pV4 = c2 - basis.v * flW;
      lines.add(WireframeSegment3D(pV3.x, pV3.y, pV3.z, pV4.x, pV4.y, pV4.z, layer: layer));

      // Воротник ответного фланца наружу к ответной трубе
      final pNeck2 = c2 + basis.t * math.min(12.0, r * 0.35);
      final pN3 = pNeck2 + basis.u * r;
      final pN4 = pNeck2 - basis.u * r;
      lines.add(WireframeSegment3D(pN3.x, pN3.y, pN3.z, pN4.x, pN4.y, pN4.z, layer: layer));
      lines.add(WireframeSegment3D(pN3.x, pN3.y, pN3.z, pU3.x, pU3.y, pU3.z, layer: layer));
      lines.add(WireframeSegment3D(pN4.x, pN4.y, pN4.z, pU4.x, pU4.y, pU4.z, layer: layer));

      // Межфланцевая прокладка (засечки между дисками)
      lines.add(WireframeSegment3D(
        (vEnd + basis.u * (flW * 0.6)).x, (vEnd + basis.u * (flW * 0.6)).y, (vEnd + basis.u * (flW * 0.6)).z,
        (c2 + basis.u * (flW * 0.6)).x, (c2 + basis.u * (flW * 0.6)).y, (c2 + basis.u * (flW * 0.6)).z,
        layer: layer,
      ));
      lines.add(WireframeSegment3D(
        (vEnd - basis.u * (flW * 0.6)).x, (vEnd - basis.u * (flW * 0.6)).y, (vEnd - basis.u * (flW * 0.6)).z,
        (c2 - basis.u * (flW * 0.6)).x, (c2 - basis.u * (flW * 0.6)).y, (c2 - basis.u * (flW * 0.6)).z,
        layer: layer,
      ));
    }

    return lines;
  }

  /// Генерация 3D-векторной дуги отвода между точками тангенсов в плоскости гиба
  static List<WireframeSegment3D> generateElbowWireframe(
    Fitting fitting,
    Node3D node,
    Node3D n1,
    Node3D n2, {
    double? pipeOuterDiameter,
    String layer = '0',
  }) {
    final lines = <WireframeSegment3D>[];
    final vNode = Vector3D.fromNode(node);
    final v1 = Vector3D.fromNode(n1);
    final v2 = Vector3D.fromNode(n2);

    final d1 = (v1 - vNode);
    final d2 = (v2 - vNode);
    final len1 = d1.length;
    final len2 = d2.length;
    if (len1 < 1e-4 || len2 < 1e-4) return lines;

    final u1 = d1.normalized();
    final u2 = d2.normalized();

    final dot = (u1.dot(u2)).clamp(-1.0, 1.0);
    final bendAngleRad = math.pi - math.acos(dot);
    if (bendAngleRad < 0.05) return lines;

    final radMm = fitting.effectiveRadiusMm;
    final t = (radMm * math.tan(bendAngleRad / 2.0)).clamp(0.0, math.min(len1, len2) * 0.45);

    final t1 = vNode + u1 * t;
    final t2 = vNode + u2 * t;

    // Дуга аппроксимируется 8 сегментами Безье
    const int segs = 8;
    Vector3D prevPt = t1;
    for (int i = 1; i <= segs; i++) {
      final s = i / segs;
      final pt = t1 * ((1 - s) * (1 - s)) + vNode * (2 * (1 - s) * s) + t2 * (s * s);
      lines.add(WireframeSegment3D(prevPt.x, prevPt.y, prevPt.z, pt.x, pt.y, pt.z, layer: layer));
      prevPt = pt;
    }

    return lines;
  }

  /// Генерация 3D-векторного обозначения тройника (засечки стыков на концах ответвлений)
  static List<WireframeSegment3D> generateTeeWireframe(
    Fitting fitting,
    Node3D node,
    List<Node3D> connectedNodes, {
    String layer = '0',
  }) {
    final lines = <WireframeSegment3D>[];
    final vNode = Vector3D.fromNode(node);
    final w = math.max(10.0, fitting.dn * 0.4);

    for (final other in connectedNodes) {
      final dir = (Vector3D.fromNode(other) - vNode).normalized();
      final ref = dir.z.abs() < 0.9 ? const Vector3D(0, 0, 1) : const Vector3D(0, 1, 0);
      final normal = dir.cross(ref).normalized();
      final tickPos = vNode + dir * (math.max(20.0, fitting.effectiveRadiusMm * 0.7));
      lines.add(WireframeSegment3D(
        (tickPos + normal * w).x, (tickPos + normal * w).y, (tickPos + normal * w).z,
        (tickPos - normal * w).x, (tickPos - normal * w).y, (tickPos - normal * w).z,
        layer: layer,
      ));
    }

    return lines;
  }

  /// Вычисляет подотрезки трубы в 3D (мм) с вырезанными интервалами под проходную арматуру
  static List<(Vector3D, Vector3D)> calcPipeDrawableIntervals3d(
    Node3D start,
    Node3D end,
    List<Valve> valves, {
    double trimStartMm = 0.0,
    double trimEndMm = 0.0,
  }) {
    final vStart = Vector3D.fromNode(start);
    final vEnd = Vector3D.fromNode(end);
    final axis = vEnd - vStart;
    final totalLen = axis.length;
    if (totalLen < 1e-4) {
      return [(vStart, vEnd)];
    }

    final dir = axis / totalLen;

    final dMin = trimStartMm.clamp(0.0, totalLen * 0.45);
    final dMax = (totalLen - trimEndMm).clamp(dMin, totalLen);
    if (dMax <= dMin + 1e-3) {
      return [];
    }

    final inlineValves = valves.where((v) => v.valveType.isInline).toList();
    if (inlineValves.isEmpty) {
      return [(vStart + dir * dMin, vStart + dir * dMax)];
    }

    // Собираем интервалы вырезания
    final cutIntervals = <(double, double)>[];
    for (final v in inlineValves) {
      final cDist = v.ratio * totalLen;
      final halfL = math.max(12.0, v.lengthMm / 2.0);
      final vIn = (cDist - halfL).clamp(dMin, dMax);
      final vOut = (cDist + halfL).clamp(dMin, dMax);
      if (vOut > vIn + 0.1) {
        cutIntervals.add((vIn, vOut));
      }
    }

    if (cutIntervals.isEmpty) {
      return [(vStart + dir * dMin, vStart + dir * dMax)];
    }

    cutIntervals.sort((a, b) => a.$1.compareTo(b.$1));

    // Слияние перекрывающихся интервалов
    final mergedCuts = <(double, double)>[];
    var currentMerged = cutIntervals.first;
    for (int i = 1; i < cutIntervals.length; i++) {
      final next = cutIntervals[i];
      if (next.$1 <= currentMerged.$2) {
        currentMerged = (currentMerged.$1, math.max(currentMerged.$2, next.$2));
      } else {
        mergedCuts.add(currentMerged);
        currentMerged = next;
      }
    }
    mergedCuts.add(currentMerged);

    // Формируем результирующие подотрезки
    final result = <(Vector3D, Vector3D)>[];
    var dCurr = dMin;

    for (final (cutStart, cutEnd) in mergedCuts) {
      if (cutStart > dCurr + 0.5) {
        result.add((vStart + dir * dCurr, vStart + dir * cutStart));
      }
      dCurr = math.max(dCurr, cutEnd);
    }

    if (dCurr < dMax - 0.5) {
      result.add((vStart + dir * dCurr, vStart + dir * dMax));
    }

    return result.isEmpty ? [(vStart + dir * dMin, vStart + dir * dMax)] : result;
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
      allLines.addAll(generateWeld3d(
        weld,
        s,
        e,
        pipeOuterDiameter: seg.outerDiameterMm,
        style: weld.getEffectiveStyle(network.defaultWeldStyle),
        tickSizeMm: weld.getEffectiveTickSize(network.defaultWeldTickSizeMm, seg.outerDiameterMm),
      ));
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
      } else if (fit.fittingType == FittingType.directBranch) {
        if (connectedSegs.length == 3) {
          final branchSeg = network.identifyBranchSegment(fit.nodeId, connectedSegs);
          final mainSegs = connectedSegs.where((s) => s.id != branchSeg?.id).toList();
          if (branchSeg != null && mainSegs.isNotEmpty) {
            final otherNodeId = branchSeg.startNodeId == fit.nodeId ? branchSeg.endNodeId : branchSeg.startNodeId;
            final otherNode = network.nodes[otherNodeId];
            if (otherNode != null) {
              allLines.addAll(generateDirectBranch3d(
                fit,
                node,
                otherNode,
                mainOuterDiameter: mainSegs[0].outerDiameterMm,
                branchOuterDiameter: branchSeg.outerDiameterMm,
              ));
            }
          }
        }
      }
    }

    return allLines;
  }
}
