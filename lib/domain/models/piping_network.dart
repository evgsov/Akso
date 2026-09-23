import 'dart:math' as math;
import 'package:uuid/uuid.dart';
import '../../core/math/vector_3d.dart';
import '../enums/fitting_type.dart';
import '../enums/inspection_method.dart';
import '../enums/valve_type.dart';
import '../enums/weld_joint_style.dart';
import '../enums/weld_type.dart';
import '../services/fitting_detector.dart';
import '../services/spool_calculator.dart';
import '../services/topology_service.dart';
import 'callout.dart';
import 'construction_axis.dart';
import 'equipment.dart';
import 'fitting.dart';
import 'fitting_catalog.dart';
import 'linear_dimension.dart';
import 'node_3d.dart';
import 'pipe_dimension.dart';
import 'pipe_segment.dart';
import 'pipe_spool.dart';
import 'pipe_support.dart';
import 'piping_system.dart';
import 'valve.dart';
import 'weld_joint.dart';

const _uuid = Uuid();

/// Топологический граф трубопроводной сети (параметрическая связность как в Revit)
class PipingNetwork {
  final Map<String, Node3D> nodes;
  final Map<String, PipeSegment> segments;
  final Map<String, Valve> valves;
  final Map<String, WeldJoint> weldJoints;
  final Map<String, Fitting> fittings;
  final Map<String, PipeSpool> spools;
  final Map<String, PipingSystem> systems;
  final Map<String, ConstructionAxis> axes;
  final Map<String, Equipment> equipments;
  final Map<String, PipeSupport> supports;
  final Map<String, Callout> callouts;
  final Map<String, LinearDimension> dimensions;
  final FittingCatalog catalog;
  final PipeAssortmentCatalog pipeCatalog;

  /// Стиль визуального отображения сварных стыков по умолчанию для всего проекта
  WeldJointStyle defaultWeldStyle;

  /// Размер засечки сварного стыка по умолчанию для всей сети (в мм). null = по диаметру трубы.
  double? defaultWeldTickSizeMm;

  PipingNetwork({
    Map<String, Node3D>? nodes,
    Map<String, PipeSegment>? segments,
    Map<String, Valve>? valves,
    Map<String, WeldJoint>? weldJoints,
    Map<String, Fitting>? fittings,
    Map<String, PipeSpool>? spools,
    Map<String, PipingSystem>? systems,
    Map<String, ConstructionAxis>? axes,
    Map<String, Equipment>? equipments,
    Map<String, PipeSupport>? supports,
    Map<String, Callout>? callouts,
    Map<String, LinearDimension>? dimensions,
    FittingCatalog? catalog,
    PipeAssortmentCatalog? pipeCatalog,
    this.defaultWeldStyle = WeldJointStyle.tick,
    this.defaultWeldTickSizeMm,
  })  : nodes = nodes ?? {},
        segments = segments ?? {},
        valves = valves ?? {},
        weldJoints = weldJoints ?? {},
        fittings = fittings ?? {},
        spools = spools ?? {},
        systems = systems ?? {for (var s in PipingSystem.defaults) s.id: s},
        axes = axes ?? {},
        equipments = equipments ?? {},
        supports = supports ?? {},
        callouts = callouts ?? {},
        dimensions = dimensions ?? {},
        catalog = catalog ?? FittingCatalog(),
        pipeCatalog = pipeCatalog ?? PipeAssortmentCatalog();

  /// Добавление нового узла в 3D координатах сети
  Node3D addNode({required double x, required double y, required double z}) {
    final id = 'node_${_uuid.v4()}';
    final node = Node3D(id: id, x: x, y: y, z: z);
    nodes[id] = node;
    return node;
  }

  /// Создание копии сети с возможностью подмены полей
  PipingNetwork copyWith({
    Map<String, Node3D>? nodes,
    Map<String, PipeSegment>? segments,
    Map<String, Valve>? valves,
    Map<String, WeldJoint>? weldJoints,
    Map<String, Fitting>? fittings,
    Map<String, PipeSpool>? spools,
    Map<String, PipingSystem>? systems,
    Map<String, ConstructionAxis>? axes,
    Map<String, Equipment>? equipments,
    Map<String, PipeSupport>? supports,
    Map<String, Callout>? callouts,
    Map<String, LinearDimension>? dimensions,
    FittingCatalog? catalog,
    PipeAssortmentCatalog? pipeCatalog,
    WeldJointStyle? defaultWeldStyle,
    double? defaultWeldTickSizeMm,
    bool clearDefaultWeldTickSizeMm = false,
  }) {
    return PipingNetwork(
      nodes: nodes ?? Map.from(this.nodes),
      segments: segments ?? Map.from(this.segments),
      valves: valves ?? Map.from(this.valves),
      weldJoints: weldJoints ?? Map.from(this.weldJoints),
      fittings: fittings ?? Map.from(this.fittings),
      spools: spools ?? Map.from(this.spools),
      systems: systems ?? Map.from(this.systems),
      axes: axes ?? Map.from(this.axes),
      equipments: equipments ?? Map.from(this.equipments),
      supports: supports ?? Map.from(this.supports),
      callouts: callouts ?? Map.from(this.callouts),
      dimensions: dimensions ?? Map.from(this.dimensions),
      catalog: catalog ?? this.catalog,
      pipeCatalog: pipeCatalog ?? this.pipeCatalog,
      defaultWeldStyle: defaultWeldStyle ?? this.defaultWeldStyle,
      defaultWeldTickSizeMm: clearDefaultWeldTickSizeMm ? null : (defaultWeldTickSizeMm ?? this.defaultWeldTickSizeMm),
    );
  }

  /// Создание полной копии сети для иммутабельности и Undo/Redo
  PipingNetwork clone() {
    return PipingNetwork(
      nodes: Map.from(nodes),
      segments: Map.from(segments),
      valves: Map.from(valves),
      weldJoints: Map.from(weldJoints),
      fittings: Map.from(fittings),
      spools: Map.from(spools),
      systems: Map.from(systems),
      axes: Map.from(axes),
      equipments: Map.from(equipments),
      supports: Map.from(supports),
      callouts: Map.from(callouts),
      dimensions: Map.from(dimensions),
      catalog: catalog,
      pipeCatalog: pipeCatalog,
      defaultWeldStyle: defaultWeldStyle,
      defaultWeldTickSizeMm: defaultWeldTickSizeMm,
    );
  }

  /// Получение списка сегментов, подключенных к узлу
  List<PipeSegment> getConnectedSegments(String nodeId) {
    return TopologyService.getConnectedSegments(this, nodeId);
  }

  /// 1. Перемещение узла в 3D (стилусом или вводом координат)
  /// Все примыкающие трубы автоматически растягиваются/сжимаются, сохраняя соединение.
  /// Если узел является штуцером оборудования, перемещается все оборудование целиком.
  void moveNode(String nodeId, double newX, double newY, double newZ) {
    final node = nodes[nodeId];
    if (node == null) return;

    if (node.equipmentId != null) {
      final dx = newX - node.x;
      final dy = newY - node.y;
      final dz = newZ - node.z;
      moveEquipment(node.equipmentId!, dx, dy, dz);
      return;
    }

    nodes[nodeId] = node.copyWith(x: newX, y: newY, z: newZ);
    FittingDetector.autoDetectFittingsForNode(this, nodeId);
    for (final entry in dimensions.entries) {
      if (entry.value.startNodeId == nodeId) {
        dimensions[entry.key] = entry.value.copyWith(
          startPoint: Node3D(id: nodeId, x: newX, y: newY, z: newZ),
        );
      } else if (entry.value.endNodeId == nodeId) {
        dimensions[entry.key] = entry.value.copyWith(
          endPoint: Node3D(id: nodeId, x: newX, y: newY, z: newZ),
        );
      }
    }
    recalculateSpools();
  }

  /// Добавление оборудования и автоматическая регистрация штуцеров как 3D-узлов сети
  void addEquipment(Equipment eq) {
    equipments[eq.id] = eq;
    for (final nozzle in eq.nozzles) {
      final node = Node3D(
        id: nozzle.id,
        x: eq.x + nozzle.localX,
        y: eq.y + nozzle.localY,
        z: eq.z + nozzle.localZ,
        equipmentId: eq.id,
        nozzleId: nozzle.id,
      );
      nodes[node.id] = node;
    }
  }

  /// Перемещение оборудования со всеми его штуцерами и подключенными трубами
  void moveEquipment(String eqId, double dx, double dy, double dz) {
    final eq = equipments[eqId];
    if (eq == null) return;

    equipments[eqId] = eq.copyWith(
      x: eq.x + dx,
      y: eq.y + dy,
      z: eq.z + dz,
    );

    final movedNodeIds = <String>[];
    for (final entry in nodes.entries) {
      final node = entry.value;
      if (node.equipmentId == eqId) {
        nodes[entry.key] = node.copyWith(
          x: node.x + dx,
          y: node.y + dy,
          z: node.z + dz,
        );
        movedNodeIds.add(node.id);
      }
    }

    for (final nId in movedNodeIds) {
      FittingDetector.autoDetectFittingsForNode(this, nId);
    }
    recalculateSpools();
  }

  /// Создание динамического штуцера на оборудовании в заданной трехмерной точке грани
  Node3D attachNozzleAtWorldPoint(
    String eqId,
    Node3D worldPoint, {
    int dn = 50,
    EquipmentFace? face,
    String? name,
    bool includeInMto = false,
    double? dirX,
    double? dirY,
    double? dirZ,
  }) {
    final eq = equipments[eqId];
    if (eq == null) {
      final fallback = Node3D(id: 'noz_${_uuid.v4()}', x: worldPoint.x, y: worldPoint.y, z: worldPoint.z);
      nodes[fallback.id] = fallback;
      return fallback;
    }

    final rad = eq.rotationAngleDeg * math.pi / 180.0;
    final cosA = math.cos(rad);
    final sinA = math.sin(rad);

    // Вектор от центра оборудования к мировой точке
    final dx = worldPoint.x - eq.x;
    final dy = worldPoint.y - eq.y;
    final dz = worldPoint.z - eq.z;

    // Преобразуем в локальную систему координат аппарата (до поворота)
    final lx = dx * cosA + dy * sinA;
    final ly = -dx * sinA + dy * cosA;
    final lz = dz;

    // Определяем грань, если не указана явно
    EquipmentFace determinedFace = face ?? EquipmentFace.top;
    double localDirX = 0.0;
    double localDirY = 0.0;
    double localDirZ = 1.0;

    if (face == null) {
      if (eq.type == EquipmentType.box) {
        final distTop = (lz - eq.height).abs();
        final distBottom = lz.abs();
        final distRight = (lx - eq.width / 2.0).abs();
        final distLeft = (lx + eq.width / 2.0).abs();
        final distFront = (ly - eq.length / 2.0).abs();
        final distBack = (ly + eq.length / 2.0).abs();

        final minDist = [distTop, distBottom, distRight, distLeft, distFront, distBack].reduce(math.min);
        if (minDist == distTop) {
          determinedFace = EquipmentFace.top;
          localDirZ = 1.0;
        } else if (minDist == distBottom) {
          determinedFace = EquipmentFace.bottom;
          localDirZ = -1.0;
        } else if (minDist == distRight) {
          determinedFace = EquipmentFace.right;
          localDirX = 1.0;
          localDirZ = 0.0;
        } else if (minDist == distLeft) {
          determinedFace = EquipmentFace.left;
          localDirX = -1.0;
          localDirZ = 0.0;
        } else if (minDist == distFront) {
          determinedFace = EquipmentFace.front;
          localDirY = 1.0;
          localDirZ = 0.0;
        } else {
          determinedFace = EquipmentFace.back;
          localDirY = -1.0;
          localDirZ = 0.0;
        }
      } else if (eq.type == EquipmentType.cylinderVertical) {
        final distTop = (lz - eq.height).abs();
        final distBottom = lz.abs();
        final r = eq.width / 2.0;
        final radDist = math.sqrt(lx * lx + ly * ly);
        final distSide = (radDist - r).abs();
        final minDist = [distTop, distBottom, distSide].reduce(math.min);
        if (minDist == distTop) {
          determinedFace = EquipmentFace.top;
          localDirZ = 1.0;
        } else if (minDist == distBottom) {
          determinedFace = EquipmentFace.bottom;
          localDirZ = -1.0;
        } else {
          determinedFace = EquipmentFace.cylindrical;
          if (radDist > 0.001) {
            localDirX = lx / radDist;
            localDirY = ly / radDist;
            localDirZ = 0.0;
          }
        }
      } else {
        // cylinderHorizontal
        final distFront = (ly - eq.length / 2.0).abs();
        final distBack = (ly + eq.length / 2.0).abs();
        if (distFront < 50.0) {
          determinedFace = EquipmentFace.front;
          localDirY = 1.0;
          localDirZ = 0.0;
        } else if (distBack < 50.0) {
          determinedFace = EquipmentFace.back;
          localDirY = -1.0;
          localDirZ = 0.0;
        } else {
          determinedFace = EquipmentFace.cylindrical;
          final r = eq.height / 2.0;
          final dzCenter = lz - r;
          final radDist = math.sqrt(lx * lx + dzCenter * dzCenter);
          if (radDist > 0.001) {
            localDirX = lx / radDist;
            localDirZ = dzCenter / radDist;
          }
        }
      }
    }

    // Мировое направление нормали
    final double worldDirX;
    final double worldDirY;
    final double worldDirZ;

    if (dirX != null || dirY != null || dirZ != null) {
      final dx_ = dirX ?? 0.0;
      final dy_ = dirY ?? 0.0;
      final dz_ = dirZ ?? 0.0;
      final len = math.sqrt(dx_ * dx_ + dy_ * dy_ + dz_ * dz_);
      if (len > 1e-4) {
        worldDirX = dx_ / len;
        worldDirY = dy_ / len;
        worldDirZ = dz_ / len;
      } else {
        worldDirX = localDirX * cosA - localDirY * sinA;
        worldDirY = localDirX * sinA + localDirY * cosA;
        worldDirZ = localDirZ;
      }
    } else {
      worldDirX = localDirX * cosA - localDirY * sinA;
      worldDirY = localDirX * sinA + localDirY * cosA;
      worldDirZ = localDirZ;
    }

    final nozId = 'noz_${_uuid.v4()}';
    final nozName = name ?? 'Ш-${eq.nozzles.length + 1}';
    final nozzle = Nozzle(
      id: nozId,
      equipmentId: eq.id,
      name: nozName,
      localX: lx,
      localY: ly,
      localZ: lz,
      dirX: worldDirX,
      dirY: worldDirY,
      dirZ: worldDirZ,
      dn: dn,
      face: determinedFace,
      includeInMto: includeInMto,
    );

    equipments[eq.id] = eq.copyWith(nozzles: [...eq.nozzles, nozzle]);

    final node = Node3D(
      id: nozId,
      x: worldPoint.x,
      y: worldPoint.y,
      z: worldPoint.z,
      equipmentId: eq.id,
      nozzleId: nozId,
    );
    nodes[node.id] = node;
    return node;
  }

  /// Возвращает эффективное направление патрубка штуцера в мировых координатах:
  /// - Если к штуцеру подключен сегмент трубы, вектор направлен строго вдоль трубы наружу от аппарата,
  ///   благодаря чему привалочная плоскость фланца всегда строго перпендикулярна подключенной трубе.
  /// - Если труба еще не подключена, используется базовое направление нормали грани (dirX, dirY, dirZ).
  Vector3D getNozzleEffectiveDirection(Nozzle noz) {
    final connectedSegs = getConnectedSegments(noz.id);
    if (connectedSegs.isNotEmpty) {
      final seg = connectedSegs.first;
      final otherNodeId = seg.startNodeId == noz.id ? seg.endNodeId : seg.startNodeId;
      final otherNode = nodes[otherNodeId];
      final node = nodes[noz.id];
      if (otherNode != null && node != null) {
        final dx = otherNode.x - node.x;
        final dy = otherNode.y - node.y;
        final dz = otherNode.z - node.z;
        final len = math.sqrt(dx * dx + dy * dy + dz * dz);
        if (len > 1e-4) {
          return Vector3D(dx / len, dy / len, dz / len);
        }
      }
    }
    return Vector3D(noz.dirX, noz.dirY, noz.dirZ);
  }

  /// Вычисляет эффективную длину патрубка штуцера (мм) с учетом длины подключенной трубы,
  /// чтобы фланец штуцера не выходил за пределы коротких участков трубопровода.
  double getNozzleEffectiveSpudLength(Nozzle noz, {double defaultSpudMm = 120.0}) {
    final connectedSegs = getConnectedSegments(noz.id);
    if (connectedSegs.isNotEmpty) {
      final seg = connectedSegs.first;
      final otherNodeId = seg.startNodeId == noz.id ? seg.endNodeId : seg.startNodeId;
      final otherNode = nodes[otherNodeId];
      final node = nodes[noz.id];
      if (otherNode != null && node != null) {
        final pipeLen = node.distanceTo(otherNode);
        if (pipeLen > 10.0) {
          return math.min(defaultSpudMm, pipeLen * 0.45);
        }
      }
    }
    return defaultSpudMm;
  }

  /// Обновляет сохраненное направление штуцера по подключенной трубе (если узел принадлежит оборудованию)
  void _updateNozzleDirectionForNode(String nodeId) {
    final node = nodes[nodeId];
    if (node == null || node.equipmentId == null || node.nozzleId == null) return;
    final eq = equipments[node.equipmentId!];
    if (eq == null) return;

    final nozIndex = eq.nozzles.indexWhere((n) => n.id == node.nozzleId);
    if (nozIndex == -1) return;

    final noz = eq.nozzles[nozIndex];
    final effDir = getNozzleEffectiveDirection(noz);
    if ((effDir.x - noz.dirX).abs() > 1e-3 ||
        (effDir.y - noz.dirY).abs() > 1e-3 ||
        (effDir.z - noz.dirZ).abs() > 1e-3) {
      final updatedNozzles = List<Nozzle>.from(eq.nozzles);
      updatedNozzles[nozIndex] = noz.copyWith(
        dirX: effDir.x,
        dirY: effDir.y,
        dirZ: effDir.z,
      );
      equipments[eq.id] = eq.copyWith(nozzles: updatedNozzles);
    }
  }

  /// Поворот оборудования вокруг вертикальной оси Z (через центр аппарата)
  void rotateEquipment(String eqId, double angleDeltaDeg) {
    final eq = equipments[eqId];
    if (eq == null) return;

    final newAngle = (eq.rotationAngleDeg + angleDeltaDeg) % 360.0;
    final newRad = newAngle * math.pi / 180.0;
    final cosNew = math.cos(newRad);
    final sinNew = math.sin(newRad);

    final movedNodeIds = <String>[];
    for (final noz in eq.nozzles) {
      final node = nodes[noz.id];
      if (node != null) {
        final newWx = eq.x + noz.localX * cosNew - noz.localY * sinNew;
        final newWy = eq.y + noz.localX * sinNew + noz.localY * cosNew;
        final newWz = eq.z + noz.localZ;
        nodes[noz.id] = node.copyWith(x: newWx, y: newWy, z: newWz);
        movedNodeIds.add(noz.id);
      }
    }

    equipments[eqId] = eq.copyWith(rotationAngleDeg: newAngle);

    for (final nId in movedNodeIds) {
      FittingDetector.autoDetectFittingsForNode(this, nId);
    }
    recalculateSpools();
  }

  /// Обновление параметров оборудования с пересчетом положений штуцеров на гранях
  void updateEquipment(Equipment updatedEq) {
    final oldEq = equipments[updatedEq.id];
    if (oldEq == null) return;

    final rad = updatedEq.rotationAngleDeg * math.pi / 180.0;
    final cosA = math.cos(rad);
    final sinA = math.sin(rad);

    final updatedNozzles = <Nozzle>[];
    for (final noz in updatedEq.nozzles) {
      double lx = noz.localX;
      double ly = noz.localY;
      double lz = noz.localZ;

      // Если штуцер привязан к грани, корректируем его координату при изменении габаритов
      if (noz.face != null) {
        switch (noz.face!) {
          case EquipmentFace.top:
            lz = updatedEq.height;
            break;
          case EquipmentFace.bottom:
            lz = 0.0;
            break;
          case EquipmentFace.right:
            lx = updatedEq.width / 2.0;
            break;
          case EquipmentFace.left:
            lx = -updatedEq.width / 2.0;
            break;
          case EquipmentFace.front:
            ly = updatedEq.length / 2.0;
            break;
          case EquipmentFace.back:
            ly = -updatedEq.length / 2.0;
            break;
          case EquipmentFace.cylindrical:
            if (updatedEq.type == EquipmentType.cylinderVertical) {
              final rOld = math.sqrt(noz.localX * noz.localX + noz.localY * noz.localY);
              final rNew = updatedEq.width / 2.0;
              if (rOld > 0.001) {
                lx = noz.localX * (rNew / rOld);
                ly = noz.localY * (rNew / rOld);
              }
            }
            break;
        }
      }

      final updatedNoz = noz.copyWith(localX: lx, localY: ly, localZ: lz);
      updatedNozzles.add(updatedNoz);

      final node = nodes[noz.id];
      if (node != null) {
        final wx = updatedEq.x + lx * cosA - ly * sinA;
        final wy = updatedEq.y + lx * sinA + ly * cosA;
        final wz = updatedEq.z + lz;
        nodes[noz.id] = node.copyWith(x: wx, y: wy, z: wz);
      }
    }

    equipments[updatedEq.id] = updatedEq.copyWith(nozzles: updatedNozzles);
    recalculateSpools();
  }

  /// Автоматическое удаление неиспользуемых штуцеров оборудования (к которым не подключены трубы)
  void cleanupUnusedEquipmentNozzles() {
    bool changed = false;
    for (final eq in equipments.values.toList()) {
      final activeNozzles = <Nozzle>[];
      for (final noz in eq.nozzles) {
        final node = nodes[noz.id];
        if (node != null) {
          final connected = getConnectedSegments(noz.id);
          if (connected.isEmpty) {
            nodes.remove(noz.id);
            changed = true;
          } else {
            activeNozzles.add(noz);
          }
        }
      }
      if (activeNozzles.length != eq.nozzles.length) {
        equipments[eq.id] = eq.copyWith(nozzles: activeNozzles);
        changed = true;
      }
    }
    if (changed) {
      recalculateSpools();
    }
  }

  void removeEquipment(String eqId) {
    final eq = equipments.remove(eqId);
    if (eq == null) return;
    final nozzleNodeIds = nodes.values
        .where((n) => n.equipmentId == eqId)
        .map((n) => n.id)
        .toList();
    for (final nId in nozzleNodeIds) {
      final segsToRemove = segments.values
          .where((s) => s.startNodeId == nId || s.endNodeId == nId)
          .map((s) => s.id)
          .toList();
      for (final sId in segsToRemove) {
        segments.remove(sId);
        valves.removeWhere((_, v) => v.segmentId == sId);
        weldJoints.removeWhere((_, w) => w.segmentId == sId);
        supports.removeWhere((_, s) => s.segmentId == sId);
        callouts.removeWhere((_, c) => c.targetId == sId);
      }
      fittings.remove(nId);
      nodes.remove(nId);
      callouts.removeWhere((_, c) => c.targetId == nId);
    }
    recalculateSpools();
  }

  /// Удаление конкретного штуцера оборудования
  void removeEquipmentNozzle(String eqId, String nozzleId) {
    final eq = equipments[eqId];
    if (eq == null) return;

    equipments[eqId] = eq.copyWith(
      nozzles: eq.nozzles.where((n) => n.id != nozzleId).toList(),
    );

    final segsToRemove = segments.values
        .where((s) => s.startNodeId == nozzleId || s.endNodeId == nozzleId)
        .map((s) => s.id)
        .toList();
    for (final sId in segsToRemove) {
      segments.remove(sId);
      valves.removeWhere((_, v) => v.segmentId == sId);
      weldJoints.removeWhere((_, w) => w.segmentId == sId);
      supports.removeWhere((_, s) => s.segmentId == sId);
      callouts.removeWhere((_, c) => c.targetId == sId);
    }
    fittings.remove(nozzleId);
    nodes.remove(nozzleId);
    callouts.removeWhere((_, c) => c.targetId == nozzleId);
    recalculateSpools();
  }

  /// Настройка включения ответного фланца штуцера в ведомость МТО
  void setNozzleIncludeInMto(String eqId, String nozzleId, bool includeInMto) {
    final eq = equipments[eqId];
    if (eq == null) return;

    final updatedNozzles = eq.nozzles.map((n) {
      if (n.id == nozzleId) {
        return n.copyWith(includeInMto: includeInMto);
      }
      return n;
    }).toList();

    equipments[eqId] = eq.copyWith(nozzles: updatedNozzles);
  }

  /// Добавление нового сегмента трубы в сеть с автоматическим определением фитингов
  void addSegment(PipeSegment segment) {
    segments[segment.id] = segment;
    _updateNozzleDirectionForNode(segment.startNodeId);
    _updateNozzleDirectionForNode(segment.endNodeId);
    FittingDetector.autoDetectFittingsForNode(this, segment.startNodeId);
    FittingDetector.autoDetectFittingsForNode(this, segment.endNodeId);
    recalculateSpools();
  }

  /// 2. Сдвиг стояка целиком (всех узлов вертикальной оси)
  /// Подходящие горизонтальные трубы автоматически сдвигаются и растягиваются
  void moveRiser(List<String> riserNodeIds, double deltaX, double deltaY) {
    for (final id in riserNodeIds) {
      final node = nodes[id];
      if (node != null) {
        nodes[id] = node.copyWith(
          x: node.x + deltaX,
          y: node.y + deltaY,
        );
      }
    }

    // Пересчитываем фитинги и катушки для всех сдвинутых узлов
    for (final id in riserNodeIds) {
      FittingDetector.autoDetectFittingsForNode(this, id);
    }
    recalculateSpools();
  }

  /// 3. Параллельный сдвиг трубы (смещение линии в сторону)
  /// Сдвигает оба конечных узла, смежные перпендикулярные трубы автоматически адаптируются
  void shiftSegment(String segmentId, double deltaX, double deltaY, double deltaZ) {
    final seg = segments[segmentId];
    if (seg == null) return;

    final start = nodes[seg.startNodeId];
    final end = nodes[seg.endNodeId];
    if (start == null || end == null) return;

    nodes[seg.startNodeId] = start.copyWith(
      x: start.x + deltaX,
      y: start.y + deltaY,
      z: start.z + deltaZ,
    );
    nodes[seg.endNodeId] = end.copyWith(
      x: end.x + deltaX,
      y: end.y + deltaY,
      z: end.z + deltaZ,
    );

    FittingDetector.autoDetectFittingsForNode(this, seg.startNodeId);
    FittingDetector.autoDetectFittingsForNode(this, seg.endNodeId);
    recalculateSpools();
  }

  /// Изменение системы для сегмента трубы
  void changeSegmentSystem(String segmentId, String newSystemId) {
    final seg = segments[segmentId];
    if (seg == null) return;
    segments[segmentId] = seg.copyWith(systemId: newSystemId);
    recalculateSpools();
  }

  /// Массовое изменение системы для группы сегментов
  void changeSegmentsSystem(Iterable<String> segmentIds, String newSystemId) {
    bool changed = false;
    for (final id in segmentIds) {
      final seg = segments[id];
      if (seg != null && seg.systemId != newSystemId) {
        segments[id] = seg.copyWith(systemId: newSystemId);
        changed = true;
      }
    }
    if (changed) {
      recalculateSpools();
    }
  }

  /// Массовое изменение номинального диаметра DN для группы сегментов
  void changeSegmentsDn(Iterable<String> segmentIds, int newDn) {
    if (newDn <= 0) return;
    final dim = pipeCatalog.getDimension(newDn);
    final resolvedOuterD = dim?.outerDiameterMm;
    final resolvedWallS = dim?.defaultWallThicknessMm;

    final affectedNodeIds = <String>{};
    bool changed = false;

    for (final id in segmentIds) {
      final seg = segments[id];
      if (seg != null && seg.dn != newDn) {
        segments[id] = seg.copyWith(
          dn: newDn,
          outerDiameterMm: resolvedOuterD ?? seg.outerDiameterMm,
          wallThicknessMm: resolvedWallS ?? seg.wallThicknessMm,
        );
        affectedNodeIds.add(seg.startNodeId);
        affectedNodeIds.add(seg.endNodeId);
        changed = true;
      }
    }

    if (changed) {
      for (final nId in affectedNodeIds) {
        FittingDetector.autoDetectFittingsForNode(this, nId);
      }
      recalculateSpools();
    }
  }

  /// Массовое изменение марки стали для группы сегментов
  void changeSegmentsMaterial(Iterable<String> segmentIds, String newMaterial) {
    if (newMaterial.trim().isEmpty) return;
    bool changed = false;

    for (final id in segmentIds) {
      final seg = segments[id];
      if (seg != null && seg.material != newMaterial) {
        segments[id] = seg.copyWith(material: newMaterial);
        changed = true;
      }
    }

    if (changed) {
      final segSet = segmentIds.toSet();
      for (final entry in weldJoints.entries) {
        if (segSet.contains(entry.value.segmentId)) {
          weldJoints[entry.key] = entry.value.copyWith(steelGrade: newMaterial);
        }
      }
      recalculateSpools();
    }
  }

  /// Массовое изменение уклона (i) для группы сегментов
  void changeSegmentsSlope(Iterable<String> segmentIds, double newSlope) {
    bool changed = false;
    for (final id in segmentIds) {
      final seg = segments[id];
      if (seg != null && (seg.slope - newSlope).abs() > 0.0001) {
        segments[id] = seg.copyWith(slope: newSlope);
        changed = true;
      }
    }
    if (changed) {
      recalculateSpools();
    }
  }

  /// Изменение высотной отметки (Z в метрах) для сегмента трубы
  void changeSegmentElevation(String segmentId, double newZMeters) {
    final seg = segments[segmentId];
    if (seg == null) return;
    final start = nodes[seg.startNodeId];
    if (start == null) return;
    final newZMm = newZMeters * 1000.0;
    final deltaZ = newZMm - start.z;
    if (deltaZ.abs() < 0.1) return;
    shiftSegment(segmentId, 0.0, 0.0, deltaZ);
  }

  /// Массовый сдвиг высотной отметки (дельта Z в метрах) для группы сегментов
  void shiftSegmentsElevation(Iterable<String> segmentIds, double deltaZMeters) {
    final deltaZMm = deltaZMeters * 1000.0;
    if (deltaZMm.abs() < 0.1) return;

    final affectedNodeIds = <String>{};
    for (final sId in segmentIds) {
      final seg = segments[sId];
      if (seg != null) {
        affectedNodeIds.add(seg.startNodeId);
        affectedNodeIds.add(seg.endNodeId);
      }
    }

    for (final nId in affectedNodeIds) {
      final n = nodes[nId];
      if (n != null) {
        nodes[nId] = n.copyWith(z: n.z + deltaZMm);
      }
    }

    for (final nId in affectedNodeIds) {
      FittingDetector.autoDetectFittingsForNode(this, nId);
    }
    generateElementWeldJoints();
    recalculateSpools();
  }

  /// Изменение высотной отметки (Z в метрах) для конкретного узла
  void setNodeElevation(String nodeId, double newZMeters) {
    final n = nodes[nodeId];
    if (n == null) return;
    final newZMm = newZMeters * 1000.0;
    if ((n.z - newZMm).abs() < 0.1) return;

    nodes[nodeId] = n.copyWith(z: newZMm);
    FittingDetector.autoDetectFittingsForNode(this, nodeId);
    final conn = getConnectedSegments(nodeId);
    for (final seg in conn) {
      FittingDetector.autoDetectFittingsForNode(this, seg.startNodeId);
      FittingDetector.autoDetectFittingsForNode(this, seg.endNodeId);
    }
    generateElementWeldJoints();
    recalculateSpools();
  }

  /// Изменение высотной отметки (Z в метрах) для оборудования
  void changeEquipmentElevation(String eqId, double newZMeters) {
    final eq = equipments[eqId];
    if (eq == null) return;
    final newZMm = newZMeters * 1000.0;
    final deltaZ = newZMm - eq.z;
    if (deltaZ.abs() < 0.1) return;
    moveEquipment(eqId, 0.0, 0.0, deltaZ);
  }

  /// 4. Параметрическое изменение длины сегмента
  /// Конечному узлу задается смещение вдоль вектора трубы, и вся последующая ветка сети сдвигается
  void changeSegmentLength(String segmentId, double newLengthMm) {
    final seg = segments[segmentId];
    if (seg == null) return;

    final start = nodes[seg.startNodeId];
    final end = nodes[seg.endNodeId];
    if (start == null || end == null) return;

    final curLen = start.distanceTo(end);
    if (curLen < 0.001) return;

    final ratio = newLengthMm / curLen;
    final deltaX = (end.x - start.x) * (ratio - 1.0);
    final deltaY = (end.y - start.y) * (ratio - 1.0);
    final deltaZ = (end.z - start.z) * (ratio - 1.0);

    // Сдвигаем узел end и всю последующую сеть за ним
    _cascadeShift(seg.endNodeId, deltaX, deltaY, deltaZ, {seg.startNodeId});

    FittingDetector.autoDetectFittingsForNode(this, seg.startNodeId);
    FittingDetector.autoDetectFittingsForNode(this, seg.endNodeId);
    recalculateSpools();
  }

  /// Установка пользовательских метаданных катушки (маркировка и заводской номер)
  void setSpoolMetadata(String spoolId, {String? name, String? serialNumber}) {
    final spool = spools[spoolId];
    if (spool == null) return;
    spools[spoolId] = spool.copyWith(
      name: name,
      serialNumber: serialNumber,
    );
  }

  /// Параметрическое изменение длины катушки трубы
  /// Удлиняет или укорачивает катушку, каскадно сдвигая downstream элементы
  void changeSpoolLength(String spoolId, double newLengthMm) {
    if (newLengthMm <= 0.0) return;
    final spool = spools[spoolId];
    if (spool == null) return;

    final seg = segments[spool.segmentId];
    if (seg == null) return;

    final start = nodes[seg.startNodeId];
    final end = nodes[seg.endNodeId];
    if (start == null || end == null) return;

    final curSegLen = start.distanceTo(end);
    if (curSegLen < 0.001) return;

    final curCutLen = spool.cutLengthMm;
    final deltaL = newLengthMm - curCutLen;
    if (deltaL.abs() < 0.001) return;

    final newSegLen = curSegLen + deltaL;
    if (newSegLen < 1.0) return;

    // Вектор направления оси сегмента от start к end
    final dirX = (end.x - start.x) / curSegLen;
    final dirY = (end.y - start.y) / curSegLen;
    final dirZ = (end.z - start.z) / curSegLen;

    final deltaX = dirX * deltaL;
    final deltaY = dirY * deltaL;
    final deltaZ = dirZ * deltaL;

    // Определяем позицию центра текущей катушки вдоль оси сегмента
    final spoolStart = spool.startPoint ?? start;
    final spoolEnd = spool.endPoint ?? end;
    final spoolMidDist = ((spoolStart.distanceTo(start)) + (spoolEnd.distanceTo(start))) / 2.0;

    // Сдвигаем арматуру на сегменте, расположенную ПОСЛЕ этой катушки
    for (final vEntry in valves.entries) {
      final v = vEntry.value;
      if (v.segmentId == seg.id) {
        final curDist = v.ratio * curSegLen;
        if (curDist > spoolMidDist) {
          final newDist = (curDist + deltaL).clamp(0.0, newSegLen);
          valves[vEntry.key] = v.copyWith(ratio: newDist / newSegLen);
        } else {
          valves[vEntry.key] = v.copyWith(ratio: curDist / newSegLen);
        }
      }
    }

    // Сдвигаем сварные стыки на сегменте, расположенные ПОСЛЕ этой катушки
    for (final wEntry in weldJoints.entries) {
      final w = wEntry.value;
      if (w.segmentId == seg.id) {
        final curDist = w.ratio * curSegLen;
        if (curDist > spoolMidDist) {
          final newDist = (curDist + deltaL).clamp(0.0, newSegLen);
          weldJoints[wEntry.key] = w.copyWith(ratio: newDist / newSegLen);
        } else {
          weldJoints[wEntry.key] = w.copyWith(ratio: curDist / newSegLen);
        }
      }
    }

    // Сдвигаем узел end и всю последующую сеть за ним
    _cascadeShift(seg.endNodeId, deltaX, deltaY, deltaZ, {seg.startNodeId});

    FittingDetector.autoDetectFittingsForNode(this, seg.startNodeId);
    FittingDetector.autoDetectFittingsForNode(this, seg.endNodeId);
    recalculateSpools();
  }

  /// Точная строительная длина тангенса отвода T = R * tan(alpha / 2) в мм
  double getElbowTangentMm(String nodeId) {
    final fit = fittings[nodeId];
    if (fit == null) return 0.0;
    if (fit.fittingType != FittingType.elbow90 && fit.fittingType != FittingType.elbow45) {
      return 0.0;
    }
    final conn = getConnectedSegments(nodeId);
    if (conn.length != 2) return fit.effectiveRadiusMm;
    final nCenter = nodes[nodeId];
    if (nCenter == null) return fit.effectiveRadiusMm;

    final s1 = conn[0];
    final s2 = conn[1];
    final n1 = nodes[s1.startNodeId == nodeId ? s1.endNodeId : s1.startNodeId];
    final n2 = nodes[s2.startNodeId == nodeId ? s2.endNodeId : s2.startNodeId];
    if (n1 == null || n2 == null) return fit.effectiveRadiusMm;

    final v1x = n1.x - nCenter.x;
    final v1y = n1.y - nCenter.y;
    final v1z = n1.z - nCenter.z;
    final len1 = math.sqrt(v1x * v1x + v1y * v1y + v1z * v1z);

    final v2x = n2.x - nCenter.x;
    final v2y = n2.y - nCenter.y;
    final v2z = n2.z - nCenter.z;
    final len2 = math.sqrt(v2x * v2x + v2y * v2y + v2z * v2z);

    if (len1 < 1e-4 || len2 < 1e-4) return fit.effectiveRadiusMm;

    final dot = ((v1x * v2x + v1y * v2y + v1z * v2z) / (len1 * len2)).clamp(-1.0, 1.0);
    final bendAngleRad = math.pi - math.acos(dot);
    if (bendAngleRad <= 0.01) return 0.0;

    return fit.effectiveRadiusMm * math.tan(bendAngleRad / 2.0);
  }

  /// Проверяет, установлен ли в данном узле отвод
  bool isElbowNode(String nodeId) {
    final fit = fittings[nodeId];
    return fit != null && (fit.fittingType == FittingType.elbow90 || fit.fittingType == FittingType.elbow45);
  }

  /// Проверяет, установлен ли в данном узле фитинг или подключение к элементу
  bool hasFittingOrElementAtNode(String nodeId, [String? segmentId]) {
    final fit = fittings[nodeId];
    if (fit != null) {
      if (fit.fittingType == FittingType.directBranch) {
        if (segmentId != null) {
          final conn = getConnectedSegments(nodeId);
          final branch = identifyBranchSegment(nodeId, conn);
          return branch?.id == segmentId;
        }
        return false;
      }
      return true;
    }
    final node = nodes[nodeId];
    if (node?.equipmentId != null) return true;
    for (final eq in equipments.values) {
      if (eq.nozzles.any((n) => n.id == nodeId)) return true;
    }
    return false;
  }

  /// Возвращает понятное наименование элемента/фитинга в данном узле
  String getFittingLabelForNode(String nodeId, [String? segmentId]) {
    final fit = fittings[nodeId];
    if (fit != null) {
      switch (fit.fittingType) {
        case FittingType.elbow90:
          return 'Отвод 90°';
        case FittingType.elbow45:
          return 'Отвод 45°';
        case FittingType.tee:
          if (segmentId != null) {
            final conn = getConnectedSegments(nodeId);
            final branch = identifyBranchSegment(nodeId, conn);
            if (branch?.id == segmentId) {
              return 'Тройник (штуцер)';
            }
          }
          return 'Тройник';
        case FittingType.cross:
          return 'Крестовина';
        case FittingType.reducerConcentric:
          return 'Переход конц.';
        case FittingType.reducerEccentric:
          return 'Переход эксц.';
        case FittingType.flange:
          return 'Фланец';
        case FittingType.cap:
          return 'Заглушка';
        case FittingType.directBranch:
          return 'Прямая врезка';
      }
    }
    final node = nodes[nodeId];
    if (node != null && node.equipmentId != null) {
      final eq = equipments[node.equipmentId];
      return eq != null ? 'Штуцер (${eq.name})' : 'Штуцер оборуд.';
    }
    for (final eq in equipments.values) {
      final noz = eq.nozzles.where((n) => n.id == nodeId).firstOrNull;
      if (noz != null) {
        return 'Штуцер ${noz.name}';
      }
    }
    return 'Элемент';
  }

  /// Проверяет, соединяет ли сегмент два элемента (фитинги, врезки, оборудование или фитинг + арматура),
  /// которые могут быть сварены встык
  bool isConnectingFittingsSegment(String segmentId) {
    final seg = segments[segmentId];
    if (seg == null) return false;
    final hasStart = hasFittingOrElementAtNode(seg.startNodeId, segmentId);
    final hasEnd = hasFittingOrElementAtNode(seg.endNodeId, segmentId);
    if (hasStart && hasEnd) return true;
    final hasInlineValve = valves.values.any((v) => v.segmentId == segmentId && v.valveType.isInline);
    if (hasInlineValve && (hasStart || hasEnd)) {
      return true;
    }
    return false;
  }

  /// Проверяет, соединяет ли сегмент два смежных отвода
  bool isElbowToElbowSegment(String segmentId) {
    final seg = segments[segmentId];
    if (seg == null) return false;
    final fit1 = fittings[seg.startNodeId];
    final fit2 = fittings[seg.endNodeId];
    if (fit1 == null || fit2 == null) return false;

    const elbowTypes = {FittingType.elbow90, FittingType.elbow45};
    return elbowTypes.contains(fit1.fittingType) && elbowTypes.contains(fit2.fittingType);
  }

  /// Возвращает теоретическое расстояние между узлами для сварки элементов встык: D1 + D2 + L_арматуры
  double? getButtJointTargetLength(String segmentId) {
    if (!isConnectingFittingsSegment(segmentId)) return null;
    final seg = segments[segmentId];
    if (seg == null) return null;
    final d1 = getFittingDeduction(seg.startNodeId, segmentId);
    final d2 = getFittingDeduction(seg.endNodeId, segmentId);

    double valvesLen = 0.0;
    for (final v in valves.values) {
      if (v.segmentId == segmentId && v.valveType.isInline) {
        valvesLen += v.effectiveTotalLengthMm;
      }
    }
    return d1 + d2 + valvesLen;
  }

  /// Возвращает теоретическое расстояние между узлами для сварки двух отводов встык: T1 + T2
  double? getElbowToElbowTargetLength(String segmentId) {
    return getButtJointTargetLength(segmentId);
  }

  /// Человекочитаемое название сопряжения элементов встык (например, "Переход эксцентрический – Обратный клапан")
  String getButtJointLabel(String segmentId) {
    final seg = segments[segmentId];
    if (seg == null) return 'Элементы встык';
    final hasStart = hasFittingOrElementAtNode(seg.startNodeId, segmentId);
    final hasEnd = hasFittingOrElementAtNode(seg.endNodeId, segmentId);
    final l1 = hasStart ? getFittingLabelForNode(seg.startNodeId, segmentId) : null;
    final l2 = hasEnd ? getFittingLabelForNode(seg.endNodeId, segmentId) : null;
    final v = valves.values.where((v) => v.segmentId == segmentId && v.valveType.isInline).firstOrNull;
    final vLabel = v != null ? (v.name.trim().isNotEmpty ? v.name : v.valveType.displayName) : null;

    if (l1 != null && l2 != null) {
      if (vLabel != null) {
        return '$l1 – $vLabel – $l2';
      }
      return '$l1 – $l2';
    }
    if (l1 != null && vLabel != null) {
      return '$l1 – $vLabel';
    }
    if (l2 != null && vLabel != null) {
      return '$vLabel – $l2';
    }
    return 'Элементы встык';
  }

  /// Проверяет, соединены ли два элемента сегмента напрямую встык (L ≈ TargetLen, L_pipe = 0)
  bool isButtJoint(String segmentId) {
    final targetLen = getButtJointTargetLength(segmentId);
    if (targetLen == null) return false;
    final seg = segments[segmentId];
    if (seg == null) return false;
    final n1 = nodes[seg.startNodeId];
    final n2 = nodes[seg.endNodeId];
    if (n1 == null || n2 == null) return false;
    final dist = n1.distanceTo(n2);
    return (dist - targetLen).abs() <= 2.0 || dist <= targetLen + 0.5;
  }

  /// Мгновенное стягивание двух элементов встык: устанавливает длину сегмента в TargetLen
  bool collapseSegmentToButtJoint(String segmentId) {
    final targetLen = getButtJointTargetLength(segmentId);
    if (targetLen == null) return false;
    changeSegmentLength(segmentId, targetLen);

    // Если на сегменте есть арматура, перецентрируем ее точно в сопряжение
    final segValves = valves.values.where((v) => v.segmentId == segmentId && v.valveType.isInline).toList();
    if (segValves.isNotEmpty && targetLen > 0.1) {
      final seg = segments[segmentId]!;
      final d1 = getFittingDeduction(seg.startNodeId, segmentId);
      for (final v in segValves) {
        final optimalRatio = (d1 + v.effectiveHalfLengthMm) / targetLen;
        valves[v.id] = v.copyWith(ratio: optimalRatio.clamp(0.01, 0.99));
      }
      generateElementWeldJoints();
      recalculateSpools();
    }
    return true;
  }

  /// Мгновенное стягивание двух отводов встык: устанавливает длину сегмента в T1 + T2
  bool collapseElbowToElbow(String segmentId) {
    return collapseSegmentToButtJoint(segmentId);
  }

  /// Обновление параметров сегмента трубы (диаметр DN, наружный диаметр, толщина стенки, марка стали, маркировка, заводской номер/партия, уклон)
  void updateSegmentProperties(
    String segmentId, {
    int? dn,
    double? outerDiameterMm,
    double? wallThicknessMm,
    String? material,
    double? slope,
    String? name,
    String? serialNumber,
    bool clearName = false,
    bool clearSerialNumber = false,
  }) {
    final seg = segments[segmentId];
    if (seg == null) return;

    final targetDn = dn ?? seg.dn;
    double? resolvedOuterD = outerDiameterMm;
    double? resolvedWallS = wallThicknessMm;

    // Если диаметр изменился и параметры стенки не заданы явно, берем их из каталога
    if (dn != null && dn != seg.dn) {
      final dim = pipeCatalog.getDimension(dn);
      if (dim != null) {
        resolvedOuterD ??= dim.outerDiameterMm;
        resolvedWallS ??= dim.defaultWallThicknessMm;
      }
    }

    segments[segmentId] = seg.copyWith(
      dn: targetDn,
      outerDiameterMm: resolvedOuterD,
      wallThicknessMm: resolvedWallS,
      material: material ?? seg.material,
      slope: slope ?? seg.slope,
      name: clearName ? null : (name ?? seg.name),
      serialNumber: clearSerialNumber ? null : (serialNumber ?? seg.serialNumber),
    );
    FittingDetector.autoDetectFittingsForNode(this, seg.startNodeId);
    FittingDetector.autoDetectFittingsForNode(this, seg.endNodeId);
    recalculateSpools();
  }

  void _cascadeShift(String currentNodeId, double dx, double dy, double dz, Set<String> visited) {
    TopologyService.cascadeShift(this, currentNodeId, dx, dy, dz, visited);
  }

  /// 5. Скольжение арматуры вдоль трубы
  void slideValve(String valveId, double newRatio) {
    final v = valves[valveId];
    if (v == null) return;
    final clampedRatio = newRatio.clamp(0.0, 1.0);
    final updated = v.copyWith(ratio: clampedRatio);
    valves[valveId] = updated;
    syncValveWelds(updated);
    recalculateSpools();
  }

  /// Врезка сварного стыка на сегменте трубы
  WeldJoint addWeldJoint({
    required String segmentId,
    required double ratio,
    String stamp = 'ИВ-01',
    WeldType weldType = WeldType.c17,
    InspectionMethod inspectionMethod = InspectionMethod.vik,
    String? steelGrade,
    String? electrodeGrade,
    String? sourceElementId,
    bool isManual = false,
  }) {
    final nextNumber = weldJoints.length + 1;
    final id = 'weld_${_uuid.v4()}_$nextNumber';
    final seg = segments[segmentId];
    final defaultGrade = seg?.material ?? 'Сталь 20';

    final weld = WeldJoint(
      id: id,
      segmentId: segmentId,
      ratio: ratio.clamp(0.0, 1.0),
      number: nextNumber,
      stamp: stamp,
      weldType: weldType,
      inspectionMethod: inspectionMethod,
      date: DateTime.now().toIso8601String().substring(0, 10),
      steelGrade: steelGrade ?? defaultGrade,
      electrodeGrade: electrodeGrade ?? 'УОНИ 13/55',
      sourceElementId: sourceElementId,
      isManual: isManual,
    );
    weldJoints[id] = weld;
    recalculateSpools();
    return weld;
  }

  /// Обновление параметров конкретного сварного стыка
  WeldJoint? updateWeldJoint(String id, WeldJoint Function(WeldJoint) updater) {
    final w = weldJoints[id];
    if (w != null) {
      final updated = updater(w);
      weldJoints[id] = updated;
      return updated;
    }
    return null;
  }

  /// Массовое обновление параметров сварных стыков по списку ID
  void bulkUpdateWeldJoints(
    Iterable<String> ids, {
    String? stamp,
    WeldType? weldType,
    InspectionMethod? inspectionMethod,
    String? date,
    String? steelGrade,
    String? electrodeGrade,
    String? notes,
    WeldJointStyle? style,
    bool clearStyle = false,
    double? tickSizeMm,
    bool clearTickSize = false,
  }) {
    for (final id in ids) {
      final w = weldJoints[id];
      if (w != null) {
        weldJoints[id] = w.copyWith(
          stamp: stamp,
          weldType: weldType,
          inspectionMethod: inspectionMethod,
          date: date,
          steelGrade: steelGrade,
          electrodeGrade: electrodeGrade,
          notes: notes,
          style: style,
          clearStyle: clearStyle,
          tickSizeMm: tickSizeMm,
          clearTickSize: clearTickSize,
        );
      }
    }
  }

  /// Врезка арматуры (задвижки, затвора, крана) в участок трубы
  Valve addValve({
    required String segmentId,
    required double ratio,
    required ValveType valveType,
    String? name,
    int? dn,
    double? customLengthMm,
    bool? isFlanged,
    int? flangePressurePn,
    bool? includeCounterFlanges,
    String? counterFlangeType,
    double? counterFlangeLengthMm,
    String? counterFlangeMaterial,
    bool isTerminal = false,
  }) {
    final seg = segments[segmentId];
    final valveDn = dn ?? seg?.dn ?? 25;
    final valveName = name ?? '${valveType.displayName} Ду$valveDn';
    final length = customLengthMm ?? valveType.defaultLengthMm(valveDn);
    final id = 'valve_${_uuid.v4()}';
    final flanged = isFlanged ?? catalog.defaultValveIsFlanged;

    final effectiveRatio = isTerminal ? ratio.clamp(0.0, 1.0) : ratio.clamp(0.02, 0.98);

    final valve = Valve(
      id: id,
      segmentId: segmentId,
      ratio: effectiveRatio,
      valveType: valveType,
      name: valveName,
      dn: valveDn,
      lengthMm: length,
      isFlanged: flanged,
      flangePressurePn: flangePressurePn ?? 16,
      includeCounterFlanges: includeCounterFlanges ?? true,
      counterFlangeType: counterFlangeType ?? 'ГОСТ 33259-2015 тип 11',
      counterFlangeLengthMm: counterFlangeLengthMm,
      counterFlangeMaterial: counterFlangeMaterial ?? 'Сталь 20',
    );
    valves[id] = valve;

    recalculateSpools();
    return valve;
  }

  /// Удаление арматуры с автоматической очисткой ее сварных стыков и пересчетом катушек
  bool removeValve(String valveId) {
    final v = valves.remove(valveId);
    if (v == null) return false;
    weldJoints.removeWhere((_, w) => w.sourceElementId != null && w.sourceElementId!.startsWith(valveId));
    callouts.removeWhere((_, c) => c.targetId == valveId);
    validateAndCleanWeldJoints();
    recalculateSpools();
    return true;
  }

  /// Монтаж арматуры на открытый торец трубы (концевой узел со степенью <= 1)
  Valve? attachEndValveToNode(
    String nodeId, {
    required ValveType valveType,
    String? name,
    int? dn,
    double? customLengthMm,
    bool? isFlanged,
    int? flangePressurePn,
    bool? includeCounterFlanges,
    String? counterFlangeType,
    double? counterFlangeLengthMm,
    String? counterFlangeMaterial,
  }) {
    final connected = getConnectedSegments(nodeId);
    if (connected.length != 1) return null;
    final seg = connected[0];
    final startNode = nodes[seg.startNodeId];
    final endNode = nodes[seg.endNodeId];
    if (startNode == null || endNode == null) return null;

    final segLength = seg.calculateLength(startNode, endNode);
    if (segLength <= 0.1) return null;

    final valveDn = dn ?? seg.dn;
    final length = customLengthMm ?? valveType.defaultLengthMm(valveDn);
    final halfRatio = (length / 2.0) / segLength;

    // Если узел начальный (startNodeId == nodeId), арматура смещается от 0 внутрь на halfRatio.
    // Если узел конечный (endNodeId == nodeId), арматура смещается от 1 внутрь на (1.0 - halfRatio).
    final isAtStart = seg.startNodeId == nodeId;
    final ratio = isAtStart
        ? (halfRatio <= 0.5 ? halfRatio : 0.0)
        : (halfRatio <= 0.5 ? (1.0 - halfRatio) : 1.0);

    return addValve(
      segmentId: seg.id,
      ratio: ratio,
      valveType: valveType,
      name: name,
      dn: valveDn,
      customLengthMm: length,
      isFlanged: isFlanged,
      flangePressurePn: flangePressurePn,
      includeCounterFlanges: includeCounterFlanges,
      counterFlangeType: counterFlangeType,
      counterFlangeLengthMm: counterFlangeLengthMm,
      counterFlangeMaterial: counterFlangeMaterial,
      isTerminal: true,
    );
  }

  /// Установка опоры или подвески на участок трубы
  PipeSupport addSupport({
    required String segmentId,
    required double distanceRatio,
    PipeSupportType type = PipeSupportType.sliding,
    String? name,
  }) {
    final supportId = 'support_${_uuid.v4()}';
    final supportName = name ?? '${type.shortCode}-${supports.length + 1}';
    final support = PipeSupport(
      id: supportId,
      segmentId: segmentId,
      distanceRatio: distanceRatio.clamp(0.0, 1.0),
      type: type,
      name: supportName,
    );
    supports[supportId] = support;
    return support;
  }

  /// Удаление опоры
  void removeSupport(String id) {
    supports.remove(id);
  }

  /// Разделение сегмента трубы на два участка в точке ratio (0.0 < ratio < 1.0)
  /// Возвращает созданный промежуточный узел
  Node3D? splitSegmentAtRatio(String segmentId, double ratio) {
    return TopologyService.splitSegmentAtRatio(this, segmentId, ratio, idGenerator: () => _uuid.v4());
  }

  /// Удаление узла со сращиванием примыкающих труб (Dissolve Node / Merge Pipes)
  bool dissolveNode(String nodeId) {
    return TopologyService.dissolveNode(this, nodeId);
  }

  /// Врезка перехода (концентрического или эксцентрического) в сегмент трубы
  Fitting? insertReducer({
    required String segmentId,
    required double ratio,
    required int newDn,
    bool isEccentric = false,
  }) {
    final oldSeg = segments[segmentId];
    if (oldSeg == null) return null;

    final midNode = splitSegmentAtRatio(segmentId, ratio);
    if (midNode == null) return null;

    // seg2_b получает новый диаметр
    final seg2Id = '${segmentId}_b';
    final seg2 = segments[seg2Id]!;
    segments[seg2Id] = seg2.copyWith(dn: newDn);

    final fittingType = isEccentric ? FittingType.reducerEccentric : FittingType.reducerConcentric;
    final fitId = 'fit_${midNode.id}';
    final fitting = Fitting(
      id: fitId,
      nodeId: midNode.id,
      fittingType: fittingType,
      name: isEccentric ? 'Переход эксц. ${oldSeg.dn}х$newDn' : 'Переход конц. ${oldSeg.dn}х$newDn',
      standard: 'ГОСТ 17378-2001',
      material: oldSeg.material,
      dn: oldSeg.dn,
      dnSecondary: newDn,
      radiusMm: oldSeg.dn * 1.5,
      buildingLengthMm: math.max(80.0, oldSeg.dn * 1.5),
      rotationAngleDeg: 0.0,
    );
    fittings[midNode.id] = fitting;

    recalculateSpools();
    return fitting;
  }

  /// Врезка фланца (к оборудованию, межтрубного, заглушки) в сегмент трубы
  Fitting? insertFlange({
    required String segmentId,
    required double ratio,
    bool? isPair,
    FlangeConnectionType? flangeConnectionType,
    int? dn,
    int pressurePn = 16,
    String? material,
    int? customWeldCount,
  }) {
    final oldSeg = segments[segmentId];
    if (oldSeg == null) return null;

    final midNode = splitSegmentAtRatio(segmentId, ratio);
    if (midNode == null) return null;

    final flangeDn = dn ?? oldSeg.dn;
    final flangeMat = material ?? oldSeg.material;

    // Режим подключения: приоритет за явно переданным flangeConnectionType, затем по флагу isPair, затем дефолт каталога
    final connType = flangeConnectionType ??
        (isPair != null
            ? (isPair ? FlangeConnectionType.pipeToPipe : FlangeConnectionType.toEquipment)
            : catalog.defaultFlangeConnectionType);

    final pair = connType == FlangeConnectionType.pipeToPipe;
    final def = catalog.getDefinition(catalog.defaultFlangeId);
    final rad = def != null
        ? def.calculateDeduction(flangeDn)
        : (pair ? (flangeDn <= 50 ? 35.0 : 45.0) : (flangeDn <= 50 ? 18.0 : 22.0));

    String fitName;
    if (pair) {
      fitName = 'Фланцевая пара Ду$flangeDn Ру$pressurePn';
    } else if (connType == FlangeConnectionType.blindFlange) {
      fitName = 'Заглушка фланцевая Ду$flangeDn Ру$pressurePn';
    } else {
      fitName = 'Фланец Ду$flangeDn Ру$pressurePn (${connType.displayName})';
    }

    final fitId = 'flange_${midNode.id}';
    final fit = Fitting(
      id: fitId,
      nodeId: midNode.id,
      fittingType: FittingType.flange,
      definitionId: def?.id,
      dn: flangeDn,
      radiusMm: rad,
      name: fitName,
      standard: def?.standard ?? 'ГОСТ 33259-2015',
      material: flangeMat,
      weldType: def?.weldType ?? WeldType.c17,
      pressurePn: pressurePn,
      isFlangePair: pair,
      flangeConnectionType: connType,
      customWeldCount: customWeldCount,
    );
    fittings[midNode.id] = fit;

    recalculateSpools();
    return fit;
  }

  /// Установка днища (заглушки) на концевой узел трубы
  Fitting? attachCapToNode(String nodeId) {
    final node = nodes[nodeId];
    if (node == null) return null;
    final conn = getConnectedSegments(nodeId);
    if (conn.isEmpty) return null;

    final s = conn[0];
    final def = catalog.getDefinition(catalog.defaultCapId);
    final rad = def != null ? def.calculateDeduction(s.dn) : FittingType.cap.defaultDeductionMm(s.dn);

    final fitId = 'cap_$nodeId';
    final fit = Fitting(
      id: fitId,
      nodeId: nodeId,
      fittingType: FittingType.cap,
      dn: s.dn,
      radiusMm: rad,
      name: 'Днище (заглушка) Ду${s.dn}',
      standard: def?.standard ?? 'ГОСТ 6533-78',
      material: s.material,
      weldType: def?.weldType ?? WeldType.c17,
      definitionId: def?.id,
    );
    fittings[nodeId] = fit;

    recalculateSpools();
    return fit;
  }

  /// Установка концевого фланца на открытый конец трубы (к оборудованию, глухой фланец или воротниковый)
  Fitting? attachEndFlangeToNode(
    String nodeId, {
    FlangeConnectionType flangeConnectionType = FlangeConnectionType.toEquipment,
    int pressurePn = 16,
    String? material,
  }) {
    final node = nodes[nodeId];
    if (node == null) return null;
    final conn = getConnectedSegments(nodeId);
    if (conn.isEmpty) return null;

    final s = conn[0];
    final def = catalog.getDefinition(catalog.defaultFlangeId);
    final flangeDn = s.dn;
    final flangeMat = material ?? s.material;
    final rad = def != null ? def.calculateDeduction(flangeDn) : (flangeDn <= 50 ? 18.0 : 22.0);

    String fitName;
    if (flangeConnectionType == FlangeConnectionType.blindFlange) {
      fitName = 'Заглушка фланцевая Ду$flangeDn Ру$pressurePn';
    } else {
      fitName = 'Фланец концевой Ду$flangeDn Ру$pressurePn (${flangeConnectionType.displayName})';
    }

    final fitId = 'flange_$nodeId';
    final fit = Fitting(
      id: fitId,
      nodeId: nodeId,
      fittingType: FittingType.flange,
      definitionId: def?.id,
      dn: flangeDn,
      radiusMm: rad,
      name: fitName,
      standard: def?.standard ?? 'ГОСТ 33259-2015',
      material: flangeMat,
      weldType: def?.weldType ?? WeldType.c17,
      pressurePn: pressurePn,
      isFlangePair: false,
      flangeConnectionType: flangeConnectionType,
      customWeldCount: flangeConnectionType == FlangeConnectionType.blindFlange ? 0 : 1,
    );
    fittings[nodeId] = fit;

    recalculateSpools();
    return fit;
  }

  /// Удаление фитинга в узле со сбросом монтажных стыков и пересчетом катушек
  void removeFitting(String nodeId) {
    if (!fittings.containsKey(nodeId)) return;
    fittings.remove(nodeId);

    // Удаляем концевые стыки на подключенных сегментах у этого узла
    final conn = getConnectedSegments(nodeId);
    for (final seg in conn) {
      final isStart = seg.startNodeId == nodeId;
      final toRemove = weldJoints.values
          .where((w) =>
              w.segmentId == seg.id &&
              ((isStart && w.ratio < 0.35) || (!isStart && w.ratio > 0.65)))
          .map((w) => w.id)
          .toList();
      for (final wid in toRemove) {
        weldJoints.remove(wid);
      }
    }

    validateAndCleanWeldJoints();
    recalculateSpools();
  }

  /// Обновление параметров фитинга в узле с пересчетом катушек
  void updateFitting(String nodeId, Fitting updatedFit) {
    fittings[nodeId] = updatedFit;
    recalculateSpools();
  }

  /// Поворот фитинга вокруг оси трубы (на заданный угол в градусах)
  Fitting? updateFittingRotation(String nodeId, double angleDeg) {
    final fit = fittings[nodeId];
    if (fit != null) {
      final updated = fit.copyWith(rotationAngleDeg: angleDeg);
      fittings[nodeId] = updated;
      return updated;
    }
    return null;
  }

  /// Обновление точной строительной длины фитинга (мм) с пересчетом катушек
  Fitting? updateFittingLength(String nodeId, double lengthMm) {
    final fit = fittings[nodeId];
    if (fit != null) {
      final updated = fit.copyWith(
        buildingLengthMm: lengthMm,
        radiusMm: lengthMm / 2.0,
      );
      fittings[nodeId] = updated;
      recalculateSpools();
      return updated;
    }
    return null;
  }

  /// Обновление параметров арматуры с пересчетом катушек
  void updateValve(String valveId, Valve updatedValve) {
    valves[valveId] = updatedValve;
    syncValveWelds(updatedValve);
    recalculateSpools();
  }

  /// Обновление точной строительной длины арматуры (мм) с пересчетом катушек
  Valve? updateValveLength(String valveId, double lengthMm) {
    final v = valves[valveId];
    if (v != null) {
      final updated = v.copyWith(lengthMm: lengthMm);
      valves[valveId] = updated;
      syncValveWelds(updated);
      recalculateSpools();
      return updated;
    }
    return null;
  }

  /// Обновление параметров опоры
  void updateSupport(String supportId, PipeSupport updatedSupport) {
    supports[supportId] = updatedSupport;
  }

  /// Перенос арматуры на другой сегмент трубы со сменой DN и пересчетом катушек
  bool transferValveToSegment(String valveId, String newSegmentId, double newRatio) {
    final v = valves[valveId];
    final targetSeg = segments[newSegmentId];
    if (v == null || targetSeg == null) return false;

    valves[valveId] = v.copyWith(
      segmentId: newSegmentId,
      ratio: newRatio.clamp(0.0, 1.0),
      dn: targetSeg.dn,
    );
    syncValveWelds(valves[valveId]!);
    recalculateSpools();
    return true;
  }

  /// Перенос опоры на другой сегмент трубы
  bool transferSupportToSegment(String supportId, String newSegmentId, double newRatio) {
    final s = supports[supportId];
    final targetSeg = segments[newSegmentId];
    if (s == null || targetSeg == null) return false;

    supports[supportId] = s.copyWith(
      segmentId: newSegmentId,
      distanceRatio: newRatio.clamp(0.0, 1.0),
    );
    return true;
  }

  /// Вычисление строительного вычета/плеча (в мм) от узла до границы сопряжения трубы с элементом
  double getFittingDeduction(String nodeId, String segmentId) {
    return SpoolCalculator.getFittingDeduction(this, nodeId, segmentId: segmentId);
  }

  /// Проверка и создание сварного шва на сегменте в позиции ratio, если такой шов еще не существует.
  /// Если шов уже существует в этой точке (допуск 0.02) или привязан к sourceElementId, обновляет параметры и возвращает null.
  /// Также аккуратно мигрирует устаревшие швы из крайних позиций 0.0/1.0 в точные физические координаты.
  WeldJoint? ensureWeldExists(
    String segmentId,
    double ratio,
    WeldType weldType, {
    String? sourceElementId,
    bool isManual = false,
  }) {
    // 1. Поиск по sourceElementId
    if (sourceElementId != null) {
      final existingBySource = weldJoints.values.where(
        (w) => w.sourceElementId == sourceElementId,
      ).firstOrNull;
      if (existingBySource != null) {
        if (existingBySource.segmentId != segmentId ||
            (existingBySource.ratio - ratio).abs() > 0.001 ||
            existingBySource.weldType != weldType) {
          weldJoints[existingBySource.id] = existingBySource.copyWith(
            segmentId: segmentId,
            ratio: ratio,
            weldType: weldType,
          );
        }
        return null;
      }
    }

    // 2. Поиск по совпадению координат на сегменте
    final exactMatch = weldJoints.values.where(
      (w) => w.segmentId == segmentId && (w.ratio - ratio).abs() < 0.02,
    ).firstOrNull;
    if (exactMatch != null) {
      if ((exactMatch.ratio - ratio).abs() > 0.001 ||
          (sourceElementId != null && exactMatch.sourceElementId != sourceElementId)) {
        weldJoints[exactMatch.id] = exactMatch.copyWith(
          ratio: ratio,
          sourceElementId: sourceElementId ?? exactMatch.sourceElementId,
        );
      }
      return null;
    }

    // 3. Если это шов фитинга у торца трубы, проверяем, нет ли устаревшего шва в крайнем положении 0.0 или 1.0 (или устаревшего coaxial)
    if (ratio < 0.5) {
      final legacyStartWeld = weldJoints.values.where(
        (w) =>
            w.segmentId == segmentId &&
            !w.isManual &&
            (w.ratio < 0.05 ||
                (w.sourceElementId != null &&
                    w.sourceElementId!.startsWith('coaxial_'))),
      ).firstOrNull;
      if (legacyStartWeld != null) {
        weldJoints[legacyStartWeld.id] = legacyStartWeld.copyWith(
          ratio: ratio,
          sourceElementId: sourceElementId ?? legacyStartWeld.sourceElementId,
          weldType: weldType,
        );
        return null;
      }
    } else {
      final legacyEndWeld = weldJoints.values.where(
        (w) =>
            w.segmentId == segmentId &&
            !w.isManual &&
            (w.ratio > 0.95 ||
                (w.sourceElementId != null &&
                    w.sourceElementId!.startsWith('coaxial_'))),
      ).firstOrNull;
      if (legacyEndWeld != null) {
        weldJoints[legacyEndWeld.id] = legacyEndWeld.copyWith(
          ratio: ratio,
          sourceElementId: sourceElementId ?? legacyEndWeld.sourceElementId,
          weldType: weldType,
        );
        return null;
      }
    }

    return addWeldJoint(
      segmentId: segmentId,
      ratio: ratio,
      weldType: weldType,
      sourceElementId: sourceElementId,
      isManual: isManual,
    );
  }

  /// Синхронизация монтажных сварных стыков конкретной арматуры с ее положением и сегментом.
  /// Перемещает существующие стыки арматуры при ее сдвиге/переносе, не создавая дубликатов и лишних катушек.
  int syncValveWelds(Valve v, {bool createIfMissing = false}) {
    final seg = segments[v.segmentId];
    if (seg == null) {
      weldJoints.removeWhere((_, w) => w.sourceElementId != null && w.sourceElementId!.startsWith(v.id));
      return 0;
    }

    // Если арматура фланцевая и ответные фланцы отключены, стыки приварки не формируются
    if (v.isFlanged && !v.includeCounterFlanges) {
      weldJoints.removeWhere((_, w) => w.sourceElementId != null && w.sourceElementId!.startsWith(v.id));
      return 0;
    }

    final startKey = '${v.id}_start';
    final endKey = '${v.id}_end';

    final hasStart = weldJoints.values.any((w) => w.sourceElementId == startKey);
    final hasEnd = weldJoints.values.any((w) => w.sourceElementId == endKey);

    if (!createIfMissing && !hasStart && !hasEnd) {
      return 0;
    }

    final startNode = nodes[seg.startNodeId];
    final endNode = nodes[seg.endNodeId];
    if (startNode == null || endNode == null) return 0;
    final totalLen = seg.calculateLength(startNode, endNode);
    if (totalLen <= 0.1) return 0;

    final halfRatio = (v.effectiveHalfLengthMm) / totalLen;
    final r1 = (v.ratio - halfRatio).clamp(0.0, 1.0);
    final r2 = (v.ratio + halfRatio).clamp(0.0, 1.0);

    final connStart = getConnectedSegments(seg.startNodeId);
    final connEnd = getConnectedSegments(seg.endNodeId);

    // Концевой монтаж на открытый торец (степень узла <= 1):
    // со стороны открытого конца шов не создается, только со стороны трубы
    final isTerminalAtStart = connStart.length <= 1 && (v.ratio - halfRatio) <= 0.05;
    final isTerminalAtEnd = connEnd.length <= 1 && (v.ratio + halfRatio) >= 0.95;

    final weldType = v.isFlanged ? v.counterFlangeWeldType : WeldType.c17;

    int added = 0;
    if (!isTerminalAtStart && r1 > 0.001) {
      if (ensureWeldExists(v.segmentId, r1, weldType, sourceElementId: startKey) != null) {
        added++;
      }
    } else {
      weldJoints.removeWhere((_, w) => w.sourceElementId == startKey);
    }

    if (!isTerminalAtEnd && r2 < 0.999) {
      if (ensureWeldExists(v.segmentId, r2, weldType, sourceElementId: endKey) != null) {
        added++;
      }
    } else {
      weldJoints.removeWhere((_, w) => w.sourceElementId == endKey);
    }

    return added;
  }

  /// Определение сегмента ответвления среди 3 подключенных к узлу сегментов.
  /// Ответвлением считается сегмент, не лежащий на одной прямой с двумя остальными (магистралью).
  PipeSegment? identifyBranchSegment(String nodeId, [List<PipeSegment>? connectedSegments]) {
    return TopologyService.identifyBranchSegment(this, nodeId, connectedSegments);
  }

  /// Генерация технологических сварных стыков по ГОСТ 16037 для всех элементов сети
  /// (арматура, переходы, отводы, тройники, врезки, фланцы, заглушки, соосные стыки труб).
  /// Стыки позиционируются строго на физических границах сопряжения трубы и элементов,
  /// а не скапливаются в центре узла.
  /// Метод идемпотентен: существующие стыки не дублируются.
  int generateElementWeldJoints() {
    int added = 0;

    // 1. Арматура (Valves): синхронизируем стыки по краям строительной длины
    for (final v in valves.values) {
      added += syncValveWelds(v, createIfMissing: true);
    }

    // 2. Фасонные элементы (Fittings)
    for (final entry in fittings.entries) {
      final nodeId = entry.key;
      final fit = entry.value;
      final connected = getConnectedSegments(nodeId);

      switch (fit.fittingType) {
        case FittingType.elbow90:
        case FittingType.elbow45:
          for (final seg in connected) {
            final startNode = nodes[seg.startNodeId];
            final endNode = nodes[seg.endNodeId];
            if (startNode == null || endNode == null) continue;
            final totalLen = seg.calculateLength(startNode, endNode);
            if (totalLen <= 0.1) continue;

            if (isButtJoint(seg.id)) {
              // Единый монтажный шов на границе сопряжения элементов встык
              final d1 = getFittingDeduction(seg.startNodeId, seg.id);
              final d2 = getFittingDeduction(seg.endNodeId, seg.id);
              final totalD = (d1 + d2) > 0 ? (d1 + d2) : 1.0;
              final r = (d1 / totalD).clamp(0.0, 1.0);
              if (ensureWeldExists(seg.id, r, fit.weldType, sourceElementId: 'butt_${seg.id}') != null) added++;
              continue;
            } else {
              final t = getElbowTangentMm(nodeId);
              final safeT = t.clamp(0.0, totalLen * 0.45);
              final deltaR = safeT / totalLen;
              final r = seg.startNodeId == nodeId ? deltaR : (1.0 - deltaR);
              if (ensureWeldExists(seg.id, r, fit.weldType, sourceElementId: 'fit_${nodeId}_${seg.id}') != null) added++;
            }
          }
          break;

        case FittingType.reducerConcentric:
        case FittingType.reducerEccentric:
          for (final seg in connected) {
            final startNode = nodes[seg.startNodeId];
            final endNode = nodes[seg.endNodeId];
            if (startNode == null || endNode == null) continue;
            final totalLen = seg.calculateLength(startNode, endNode);
            if (totalLen <= 0.1) continue;

            if (isButtJoint(seg.id)) {
              final d1 = getFittingDeduction(seg.startNodeId, seg.id);
              final d2 = getFittingDeduction(seg.endNodeId, seg.id);
              final totalD = (d1 + d2) > 0 ? (d1 + d2) : 1.0;
              final r = (d1 / totalD).clamp(0.0, 1.0);
              if (ensureWeldExists(seg.id, r, fit.weldType, sourceElementId: 'butt_${seg.id}') != null) added++;
              continue;
            }

            final armMm = fit.effectiveBuildingLengthMm / 2.0;
            final safeArm = armMm.clamp(0.0, totalLen * 0.45);
            final deltaR = safeArm / totalLen;
            final r = seg.startNodeId == nodeId ? deltaR : (1.0 - deltaR);
            if (ensureWeldExists(seg.id, r, fit.weldType, sourceElementId: 'fit_${nodeId}_${seg.id}') != null) added++;
          }
          break;

        case FittingType.tee:
          final branchSeg = identifyBranchSegment(nodeId, connected);
          for (final seg in connected) {
            final startNode = nodes[seg.startNodeId];
            final endNode = nodes[seg.endNodeId];
            if (startNode == null || endNode == null) continue;
            final totalLen = seg.calculateLength(startNode, endNode);
            if (totalLen <= 0.1) continue;

            if (isButtJoint(seg.id)) {
              final d1 = getFittingDeduction(seg.startNodeId, seg.id);
              final d2 = getFittingDeduction(seg.endNodeId, seg.id);
              final totalD = (d1 + d2) > 0 ? (d1 + d2) : 1.0;
              final r = (d1 / totalD).clamp(0.0, 1.0);
              if (ensureWeldExists(seg.id, r, fit.weldType, sourceElementId: 'butt_${seg.id}') != null) added++;
              continue;
            }

            final isBranch = seg.id == branchSeg?.id;
            final armMm = isBranch
                ? fit.effectiveBranchLengthMm
                : ((fit.buildingLengthMm != null && fit.buildingLengthMm! > 0)
                    ? fit.buildingLengthMm! / 2.0
                    : fit.dn * 1.0);
            final safeArm = armMm.clamp(0.0, totalLen * 0.45);
            final deltaR = safeArm / totalLen;
            final r = seg.startNodeId == nodeId ? deltaR : (1.0 - deltaR);
            if (ensureWeldExists(seg.id, r, fit.weldType, sourceElementId: 'fit_${nodeId}_${seg.id}') != null) added++;
          }
          break;

        case FittingType.directBranch:
          final branchSeg = identifyBranchSegment(nodeId, connected);
          if (branchSeg != null) {
            final startNode = nodes[branchSeg.startNodeId];
            final endNode = nodes[branchSeg.endNodeId];
            if (startNode != null && endNode != null) {
              final totalLen = branchSeg.calculateLength(startNode, endNode);
              if (totalLen > 0.1) {
                if (isButtJoint(branchSeg.id)) {
                  final d1 = getFittingDeduction(branchSeg.startNodeId, branchSeg.id);
                  final d2 = getFittingDeduction(branchSeg.endNodeId, branchSeg.id);
                  final totalD = (d1 + d2) > 0 ? (d1 + d2) : 1.0;
                  final r = (d1 / totalD).clamp(0.0, 1.0);
                  if (ensureWeldExists(branchSeg.id, r, WeldType.u18, sourceElementId: 'butt_${branchSeg.id}') != null) added++;
                  break;
                }
                // Находим сквозную магистраль для расчета наружного радиуса
                final mainSeg = connected.firstWhere(
                  (s) => s.id != branchSeg.id,
                  orElse: () => branchSeg,
                );
                final dim = pipeCatalog.getDimension(mainSeg.dn);
                final rMain = (dim?.outerDiameterMm ?? mainSeg.dn.toDouble()) * 0.5;
                final safeArm = rMain.clamp(0.0, totalLen * 0.45);
                final deltaR = safeArm / totalLen;
                final r = branchSeg.startNodeId == nodeId ? deltaR : (1.0 - deltaR);
                if (ensureWeldExists(branchSeg.id, r, WeldType.u18, sourceElementId: 'fit_${nodeId}_${branchSeg.id}') != null) added++;
              }
            }
          }
          break;

        case FittingType.cross:
          for (final seg in connected) {
            final startNode = nodes[seg.startNodeId];
            final endNode = nodes[seg.endNodeId];
            if (startNode == null || endNode == null) continue;
            final totalLen = seg.calculateLength(startNode, endNode);
            if (totalLen <= 0.1) continue;

            if (isButtJoint(seg.id)) {
              final d1 = getFittingDeduction(seg.startNodeId, seg.id);
              final d2 = getFittingDeduction(seg.endNodeId, seg.id);
              final totalD = (d1 + d2) > 0 ? (d1 + d2) : 1.0;
              final r = (d1 / totalD).clamp(0.0, 1.0);
              if (ensureWeldExists(seg.id, r, fit.weldType, sourceElementId: 'butt_${seg.id}') != null) added++;
              continue;
            }

            final armMm = (fit.buildingLengthMm != null && fit.buildingLengthMm! > 0)
                ? fit.buildingLengthMm! / 2.0
                : fit.dn * 1.0;
            final safeArm = armMm.clamp(0.0, totalLen * 0.45);
            final deltaR = safeArm / totalLen;
            final r = seg.startNodeId == nodeId ? deltaR : (1.0 - deltaR);
            if (ensureWeldExists(seg.id, r, fit.weldType, sourceElementId: 'fit_${nodeId}_${seg.id}') != null) added++;
          }
          break;

        case FittingType.flange:
          if (fit.flangeConnectionType == FlangeConnectionType.blindFlange &&
              (fit.customWeldCount ?? 0) == 0) {
            break;
          }
          for (final seg in connected) {
            final startNode = nodes[seg.startNodeId];
            final endNode = nodes[seg.endNodeId];
            if (startNode == null || endNode == null) continue;
            final totalLen = seg.calculateLength(startNode, endNode);
            if (totalLen <= 0.1) continue;

            if (isButtJoint(seg.id)) {
              final d1 = getFittingDeduction(seg.startNodeId, seg.id);
              final d2 = getFittingDeduction(seg.endNodeId, seg.id);
              final totalD = (d1 + d2) > 0 ? (d1 + d2) : 1.0;
              final r = (d1 / totalD).clamp(0.0, 1.0);
              if (ensureWeldExists(seg.id, r, fit.weldType, sourceElementId: 'butt_${seg.id}') != null) added++;
              continue;
            }

            final armMm = (fit.buildingLengthMm != null && fit.buildingLengthMm! > 0)
                ? fit.buildingLengthMm!
                : fit.effectiveBuildingLengthMm;
            final safeArm = armMm.clamp(0.0, totalLen * 0.45);
            final deltaR = safeArm / totalLen;
            final r = seg.startNodeId == nodeId ? deltaR : (1.0 - deltaR);
            if (ensureWeldExists(seg.id, r, fit.weldType, sourceElementId: 'fit_${nodeId}_${seg.id}') != null) added++;
          }
          break;

        case FittingType.cap:
          for (final seg in connected) {
            if (isButtJoint(seg.id)) {
              final d1 = getFittingDeduction(seg.startNodeId, seg.id);
              final d2 = getFittingDeduction(seg.endNodeId, seg.id);
              final totalD = (d1 + d2) > 0 ? (d1 + d2) : 1.0;
              final r = (d1 / totalD).clamp(0.0, 1.0);
              if (ensureWeldExists(seg.id, r, fit.weldType, sourceElementId: 'butt_${seg.id}') != null) added++;
              continue;
            }
            final r = seg.startNodeId == nodeId ? 0.0 : 1.0;
            if (ensureWeldExists(seg.id, r, fit.weldType, sourceElementId: 'fit_${nodeId}_${seg.id}') != null) added++;
          }
          break;
      }
    }

    // 3. Соосные стыки двух прямых труб (без фитинга)
    for (final node in nodes.values) {
      if (fittings.containsKey(node.id)) continue;
      final conn = getConnectedSegments(node.id);
      if (conn.length == 2) {
        final s1 = conn[0];
        final s2 = conn[1];
        if (s1.dn == s2.dn) {
          final n1 = nodes[s1.startNodeId == node.id ? s1.endNodeId : s1.startNodeId];
          final n2 = nodes[s2.startNodeId == node.id ? s2.endNodeId : s2.startNodeId];
          if (n1 == null || n2 == null) continue;

          final v1x = n1.x - node.x;
          final v1y = n1.y - node.y;
          final v1z = n1.z - node.z;
          final l1 = math.sqrt(v1x * v1x + v1y * v1y + v1z * v1z);

          final v2x = n2.x - node.x;
          final v2y = n2.y - node.y;
          final v2z = n2.z - node.z;
          final l2 = math.sqrt(v2x * v2x + v2y * v2y + v2z * v2z);

          // Игнорируем вырожденные микросегменты
          if (l1 < 10.0 || l2 < 10.0) continue;

          // Проверка истинной соосности: трубы должны продолжать друг друга (угол ~180°, cosAngle <= -0.95)
          final cosAngle = (v1x * v2x + v1y * v2y + v1z * v2z) / (l1 * l2);
          if (cosAngle > -0.95) continue;

          final r1 = s1.startNodeId == node.id ? 0.0 : 1.0;
          final r2 = s2.startNodeId == node.id ? 0.0 : 1.0;
          final hasWeld = weldJoints.values.any((w) =>
              (w.segmentId == s1.id && (w.ratio - r1).abs() < 0.05) ||
              (w.segmentId == s2.id && (w.ratio - r2).abs() < 0.05));
          if (!hasWeld) {
            addWeldJoint(segmentId: s1.id, ratio: r1, weldType: WeldType.c17, sourceElementId: 'coaxial_${node.id}');
            added++;
          }
        }
      }
    }

    // 4. Очистка невалидных швов и перенумерация
    validateAndCleanWeldJoints();

    if (added > 0) {
      recalculateSpools();
    }
    return added;
  }

  /// Проверка топологической связности и очистка невалидных сварных стыков.
  /// Удаляет:
  /// - Швы на несуществующих сегментах;
  /// - Швы удаленных или перемещенных элементов (арматуры, фитингов);
  /// - Невалидные швы внутри тела арматуры;
  /// - Швы на открытых свободных концах труб (степень узла <= 1 без фланца или заглушки);
  /// - Швы на сквозных магистралях прямых врезок;
  /// - Дублирующие швы в одном узле и на сегментах;
  /// - Перенумеровывает оставшиеся швы непрерывно (1, 2, 3...).
  int validateAndCleanWeldJoints() {
    final toRemove = <String>{};

    for (final w in weldJoints.values) {
      final seg = segments[w.segmentId];
      if (seg == null) {
        toRemove.add(w.id);
        continue;
      }

      final startNode = nodes[seg.startNodeId];
      final endNode = nodes[seg.endNodeId];
      if (startNode == null || endNode == null) {
        toRemove.add(w.id);
        continue;
      }

      // 0. Очистка стыков, чьи элементы-источники больше не существуют или не должны иметь швов
      if (w.sourceElementId != null) {
        if (w.sourceElementId!.startsWith('valve_')) {
          String vId = w.sourceElementId!;
          if (vId.endsWith('_start')) {
            vId = vId.substring(0, vId.length - 6);
          } else if (vId.endsWith('_end')) {
            vId = vId.substring(0, vId.length - 4);
          }
          final v = valves[vId];
          if (v == null || (v.isFlanged && !v.includeCounterFlanges) || v.segmentId != w.segmentId) {
            toRemove.add(w.id);
            continue;
          }
        } else if (w.sourceElementId!.startsWith('fit_')) {
          final hasFitting = fittings.keys.any((nId) => w.sourceElementId!.startsWith('fit_${nId}_'));
          if (!hasFitting) {
            toRemove.add(w.id);
            continue;
          }
        } else if (w.sourceElementId!.startsWith('butt_')) {
          final segId = w.sourceElementId!.substring(5);
          if (!isButtJoint(segId)) {
            toRemove.add(w.id);
            continue;
          }
        } else if (w.sourceElementId!.startsWith('coaxial_')) {
          final nodeId = w.sourceElementId!.substring(8);
          final node = nodes[nodeId];
          if (node == null || fittings.containsKey(nodeId) || getConnectedSegments(nodeId).length != 2) {
            toRemove.add(w.id);
            continue;
          }
          final conn = getConnectedSegments(nodeId);
          final s1 = conn[0];
          final s2 = conn[1];
          final n1 = nodes[s1.startNodeId == nodeId ? s1.endNodeId : s1.startNodeId];
          final n2 = nodes[s2.startNodeId == nodeId ? s2.endNodeId : s2.startNodeId];
          if (n1 != null && n2 != null) {
            final v1x = n1.x - node.x;
            final v1y = n1.y - node.y;
            final v1z = n1.z - node.z;
            final l1 = math.sqrt(v1x * v1x + v1y * v1y + v1z * v1z);
            final v2x = n2.x - node.x;
            final v2y = n2.y - node.y;
            final v2z = n2.z - node.z;
            final l2 = math.sqrt(v2x * v2x + v2y * v2y + v2z * v2z);
            if (l1 < 10.0 || l2 < 10.0 || ((v1x * v2x + v1y * v2y + v1z * v2z) / (l1 * l2)) > -0.95) {
              toRemove.add(w.id);
              continue;
            }
          }
        }
      }

      // 0.1 Очистка неручных стыков, оказавшихся внутри тела арматуры
      if (!w.isManual) {
        final totalLen = seg.calculateLength(startNode, endNode);
        if (totalLen > 0.1) {
          for (final v in valves.values) {
            if (w.segmentId == v.segmentId) {
              final half = v.effectiveHalfLengthMm / totalLen;
              if (w.ratio > v.ratio - half + 0.005 && w.ratio < v.ratio + half - 0.005) {
                toRemove.add(w.id);
                break;
              }
            }
          }
        }
        if (toRemove.contains(w.id)) continue;
      }

      // 0.2 Очистка неручных стыков, оказавшихся внутри строительного вычета фитинга
      if (!w.isManual) {
        final totalLen = seg.calculateLength(startNode, endNode);
        if (totalLen > 0.1) {
          final startFitDeduction = getFittingDeduction(seg.startNodeId, seg.id);
          final endFitDeduction = getFittingDeduction(seg.endNodeId, seg.id);
          final distFromStart = w.ratio * totalLen;
          final distFromEnd = (1.0 - w.ratio) * totalLen;

          if (startFitDeduction > 1.0 && distFromStart < startFitDeduction - 2.0) {
            if (w.sourceElementId != 'butt_${seg.id}' && w.sourceElementId != 'fit_${seg.startNodeId}_${seg.id}') {
              toRemove.add(w.id);
              continue;
            }
          }
          if (endFitDeduction > 1.0 && distFromEnd < endFitDeduction - 2.0) {
            if (w.sourceElementId != 'butt_${seg.id}' && w.sourceElementId != 'fit_${seg.endNodeId}_${seg.id}') {
              toRemove.add(w.id);
              continue;
            }
          }
        }
        if (toRemove.contains(w.id)) continue;
      }

      // 0.3 Очистка лишних неручных швов при наличии штатного шва фитинга на том же конце
      if (!w.isManual && (w.sourceElementId == null || !w.sourceElementId!.startsWith('valve_'))) {
        final totalLen = seg.calculateLength(startNode, endNode);
        if (totalLen > 0.1) {
          final hasStartFittingWeld = weldJoints.values.any((wOther) =>
              wOther.segmentId == seg.id &&
              wOther.id != w.id &&
              (wOther.sourceElementId == 'fit_${seg.startNodeId}_${seg.id}' ||
               wOther.sourceElementId == 'butt_${seg.id}'));
          if (hasStartFittingWeld &&
              w.sourceElementId != 'fit_${seg.startNodeId}_${seg.id}' &&
              w.sourceElementId != 'butt_${seg.id}') {
            final startD = getFittingDeduction(seg.startNodeId, seg.id);
            final distFromStart = w.ratio * totalLen;
            if (distFromStart <= startD + 10.0 || w.ratio < 0.05) {
              toRemove.add(w.id);
              continue;
            }
          }

          final hasEndFittingWeld = weldJoints.values.any((wOther) =>
              wOther.segmentId == seg.id &&
              wOther.id != w.id &&
              (wOther.sourceElementId == 'fit_${seg.endNodeId}_${seg.id}' ||
               wOther.sourceElementId == 'butt_${seg.id}'));
          if (hasEndFittingWeld &&
              w.sourceElementId != 'fit_${seg.endNodeId}_${seg.id}' &&
              w.sourceElementId != 'butt_${seg.id}') {
            final endD = getFittingDeduction(seg.endNodeId, seg.id);
            final distFromEnd = (1.0 - w.ratio) * totalLen;
            if (distFromEnd <= endD + 10.0 || w.ratio > 0.95) {
              toRemove.add(w.id);
              continue;
            }
          }
        }
        if (toRemove.contains(w.id)) continue;
      }

      final isNearStart = w.ratio < 0.25;
      final isNearEnd = w.ratio > 0.75;

      if (isNearStart || isNearEnd) {
        final targetNodeId = isNearStart ? seg.startNodeId : seg.endNodeId;
        final conn = getConnectedSegments(targetNodeId);

        // 1. Свободный открытый торец трубы (степень <= 1)
        if (conn.length <= 1) {
          final hasTerminalValve = valves.values.any((v) =>
              v.segmentId == seg.id &&
              (!v.isFlanged || v.includeCounterFlanges) &&
              (isNearStart ? v.ratio <= 0.4 : v.ratio >= 0.6));

          if (hasTerminalValve) {
            // Удаляем только шов на самом краю среза трубы (висящий в воздухе),
            // а внутренний шов приварки арматуры к трубе сохраняем
            if (w.ratio <= 0.05 || w.ratio >= 0.95) {
              toRemove.add(w.id);
              continue;
            }
          } else {
            final fit = fittings[targetNodeId];
            if (fit == null ||
                (fit.fittingType != FittingType.cap &&
                 fit.fittingType != FittingType.flange)) {
              toRemove.add(w.id);
              continue;
            }
            if (fit.fittingType == FittingType.flange &&
                fit.flangeConnectionType == FlangeConnectionType.blindFlange &&
                (fit.customWeldCount ?? 0) == 0) {
              toRemove.add(w.id);
              continue;
            }
          }
        }

        // 2. Прямая врезка: на магистральных сегментах шва врезки быть не должно
        final fit = fittings[targetNodeId];
        if (fit != null && fit.fittingType == FittingType.directBranch) {
          final branchSeg = identifyBranchSegment(targetNodeId, conn);
          if (branchSeg != null && seg.id != branchSeg.id) {
            toRemove.add(w.id);
            continue;
          }
        }
      }
    }

    // 3. Поиск дублирующих стыков в одном узле сопряжения двух прямых труб
    for (final node in nodes.values) {
      if (fittings.containsKey(node.id)) continue;
      final conn = getConnectedSegments(node.id);
      if (conn.length == 2) {
        final s1 = conn[0];
        final s2 = conn[1];
        final r1 = s1.startNodeId == node.id ? 0.0 : 1.0;
        final r2 = s2.startNodeId == node.id ? 0.0 : 1.0;
        final w1 = weldJoints.values.where((w) => w.segmentId == s1.id && (w.ratio - r1).abs() < 0.15).firstOrNull;
        final w2 = weldJoints.values.where((w) => w.segmentId == s2.id && (w.ratio - r2).abs() < 0.15).firstOrNull;
        if (w1 != null && w2 != null && !toRemove.contains(w1.id) && !toRemove.contains(w2.id)) {
          toRemove.add(w2.id);
        }
      }
    }

    // 4. Поиск дублирующих стыков на одном сегменте (ближе 15-20 мм)
    for (final seg in segments.values) {
      final startNode = nodes[seg.startNodeId];
      final endNode = nodes[seg.endNodeId];
      final totalLen = (startNode != null && endNode != null)
          ? seg.calculateLength(startNode, endNode)
          : 1000.0;

      final segWelds = weldJoints.values
          .where((w) => w.segmentId == seg.id && !toRemove.contains(w.id))
          .toList();
      for (int i = 0; i < segWelds.length; i++) {
        for (int j = i + 1; j < segWelds.length; j++) {
          final w1 = segWelds[i];
          final w2 = segWelds[j];
          final distMm = (w1.ratio - w2.ratio).abs() * totalLen;
          if ((w1.ratio - w2.ratio).abs() < 0.015 || distMm < 20.0) {
            // Приоритет сохранению шва с sourceElementId или ручного
            if (w1.sourceElementId != null && w2.sourceElementId == null) {
              toRemove.add(w2.id);
            } else if (w1.sourceElementId == null && w2.sourceElementId != null) {
              toRemove.add(w1.id);
            } else if (w1.isManual && !w2.isManual) {
              toRemove.add(w2.id);
            } else if (!w1.isManual && w2.isManual) {
              toRemove.add(w1.id);
            } else {
              toRemove.add(w2.id);
            }
          }
        }
      }
    }

    for (final wid in toRemove) {
      weldJoints.remove(wid);
    }

    // Перенумерация оставшихся швов: 1, 2, 3...
    final sortedWelds = weldJoints.values.toList()
      ..sort((a, b) => a.number.compareTo(b.number));
    for (int i = 0; i < sortedWelds.length; i++) {
      final expectedNum = i + 1;
      final w = sortedWelds[i];
      if (w.number != expectedNum) {
        weldJoints[w.id] = w.copyWith(number: expectedNum);
      }
    }

    if (toRemove.isNotEmpty) {
      cleanOrphanedCallouts();
    }

    return toRemove.length;
  }

  /// Синхронизация физических сварных швов для всех фасонных элементов сети
  /// (вызывает generateElementWeldJoints)
  void syncFittingWeldJoints() {
    generateElementWeldJoints();
  }

  /// Подключение ответвления к существующей трубе (Revit-like T-branching)
  /// Создает тройник (Tee) или прямую врезку (DirectBranch)
  Fitting? connectBranchToSegment({
    required String hostSegmentId,
    required double ratio,
    required String branchEndNodeId,
    int? branchDn,
    bool useDirectBranch = false,
  }) {
    final hostSeg = segments[hostSegmentId];
    if (hostSeg == null) return null;

    final midNode = splitSegmentAtRatio(hostSegmentId, ratio);
    if (midNode == null) return null;

    final hostSegA = segments['${hostSegmentId}_a']!;
    final bDn = branchDn ?? hostSegA.dn;

    // Создаем сегмент ответвления от midNode к branchEndNodeId
    final branchSegId = 'seg_${_uuid.v4()}';
    final branchSeg = PipeSegment(
      id: branchSegId,
      startNodeId: midNode.id,
      endNodeId: branchEndNodeId,
      systemId: hostSegA.systemId,
      dn: bDn,
      material: hostSegA.material,
    );
    segments[branchSegId] = branchSeg;

    final Fitting fit;
    if (useDirectBranch) {
      // Прямая врезка труба в трубу (шов У18)
      fit = Fitting(
        id: 'branch_${midNode.id}',
        nodeId: midNode.id,
        fittingType: FittingType.directBranch,
        dn: hostSegA.dn,
        dnSecondary: bDn,
        radiusMm: 0.0,
        name: 'Прямая врезка Ду$bDn в Ду${hostSegA.dn}',
        standard: 'ГОСТ 16037-80 У18',
        material: hostSegA.material,
        weldType: WeldType.u18,
        cutsMainPipe: false, // Магистраль не укорачивается!
      );
      fittings[midNode.id] = fit;
    } else {
      // Стандартный фасонный тройник (ГОСТ 17376)
      final isReducing = bDn != hostSegA.dn;
      fit = Fitting(
        id: 'tee_${midNode.id}',
        nodeId: midNode.id,
        fittingType: FittingType.tee,
        dn: hostSegA.dn,
        dnSecondary: bDn,
        radiusMm: hostSegA.dn * 1.0,
        name: isReducing ? 'Тройник переходной ${hostSegA.dn}х$bDn' : 'Тройник равнопроходный Ду${hostSegA.dn}',
        standard: 'ГОСТ 17376-2001',
        material: hostSegA.material,
        weldType: WeldType.c17,
        cutsMainPipe: true,
      );
      fittings[midNode.id] = fit;
    }

    recalculateSpools();
    return fit;
  }

  /// Автоматическое определение фитингов (отводов, тройников, крестовин) во всех узлах сети
  void autoDetectAllFittings() {
    FittingDetector.autoDetectAllFittings(this);
  }

  /// 6. Пересчет длин катушек (трубных заготовок) для всей сети
  /// Вычитает строительные длины отводов, задвижек, затворов и сварочные зазоры
  void recalculateSpools() {
    cleanOrphanedCallouts();
    SpoolCalculator.recalculateSpools(this);
  }

  Map<String, dynamic> toJson() => {
        'nodes': nodes.map((k, v) => MapEntry(k, v.toJson())),
        'segments': segments.map((k, v) => MapEntry(k, v.toJson())),
        'valves': valves.map((k, v) => MapEntry(k, v.toJson())),
        'weldJoints': weldJoints.map((k, v) => MapEntry(k, v.toJson())),
        'fittings': fittings.map((k, v) => MapEntry(k, v.toJson())),
        'spools': spools.map((k, v) => MapEntry(k, v.toJson())),
        'systems': systems.map((k, v) => MapEntry(k, v.toJson())),
        'axes': axes.map((k, v) => MapEntry(k, v.toJson())),
        'equipments': equipments.map((k, v) => MapEntry(k, v.toJson())),
        'supports': supports.map((k, v) => MapEntry(k, v.toJson())),
        'callouts': callouts.map((k, v) => MapEntry(k, v.toJson())),
        'dimensions': dimensions.map((k, v) => MapEntry(k, v.toJson())),
        'catalog': catalog.toJson(),
        'pipeCatalog': pipeCatalog.toJson(),
        'defaultWeldStyle': defaultWeldStyle.name,
        if (defaultWeldTickSizeMm != null) 'defaultWeldTickSizeMm': defaultWeldTickSizeMm,
      };

  /// Восстановление состояния сети из JSON
  void loadFromJson(Map<String, dynamic> json) {
    nodes.clear();
    segments.clear();
    valves.clear();
    weldJoints.clear();
    fittings.clear();
    spools.clear();
    systems.clear();
    axes.clear();
    equipments.clear();
    supports.clear();
    callouts.clear();
    dimensions.clear();

    if (json.containsKey('nodes')) {
      final m = json['nodes'] as Map<String, dynamic>;
      m.forEach((k, v) => nodes[k] = Node3D.fromJson(v as Map<String, dynamic>));
    }
    if (json.containsKey('segments')) {
      final m = json['segments'] as Map<String, dynamic>;
      m.forEach((k, v) => segments[k] = PipeSegment.fromJson(v as Map<String, dynamic>));
    }
    if (json.containsKey('valves')) {
      final m = json['valves'] as Map<String, dynamic>;
      m.forEach((k, v) => valves[k] = Valve.fromJson(v as Map<String, dynamic>));
    }
    if (json.containsKey('weldJoints')) {
      final m = json['weldJoints'] as Map<String, dynamic>;
      m.forEach((k, v) => weldJoints[k] = WeldJoint.fromJson(v as Map<String, dynamic>));
    }
    if (json.containsKey('fittings')) {
      final m = json['fittings'] as Map<String, dynamic>;
      m.forEach((k, v) => fittings[k] = Fitting.fromJson(v as Map<String, dynamic>));
    }
    if (json.containsKey('spools')) {
      final m = json['spools'] as Map<String, dynamic>;
      m.forEach((k, v) => spools[k] = PipeSpool.fromJson(v as Map<String, dynamic>));
    }
    if (json.containsKey('systems')) {
      final m = json['systems'] as Map<String, dynamic>;
      m.forEach((k, v) => systems[k] = PipingSystem.fromJson(v as Map<String, dynamic>));
    }
    if (json.containsKey('axes')) {
      final m = json['axes'] as Map<String, dynamic>;
      m.forEach((k, v) => axes[k] = ConstructionAxis.fromJson(v as Map<String, dynamic>));
    }
    if (json.containsKey('equipments')) {
      final m = json['equipments'] as Map<String, dynamic>;
      m.forEach((k, v) => equipments[k] = Equipment.fromJson(v as Map<String, dynamic>));
    }
    if (json.containsKey('supports')) {
      final m = json['supports'] as Map<String, dynamic>;
      m.forEach((k, v) => supports[k] = PipeSupport.fromJson(v as Map<String, dynamic>));
    }
    if (json.containsKey('callouts')) {
      final m = json['callouts'] as Map<String, dynamic>;
      m.forEach((k, v) => callouts[k] = Callout.fromJson(v as Map<String, dynamic>));
    }
    if (json.containsKey('dimensions')) {
      final m = json['dimensions'] as Map<String, dynamic>;
      m.forEach((k, v) => dimensions[k] = LinearDimension.fromJson(v as Map<String, dynamic>));
    }
    if (json.containsKey('catalog')) {
      catalog.loadFromJson(json['catalog'] as Map<String, dynamic>);
    }
    if (json.containsKey('pipeCatalog')) {
      final pc = PipeAssortmentCatalog.fromJson(json['pipeCatalog'] as Map<String, dynamic>);
      for (final dim in pc.dimensions.values) {
        pipeCatalog.addCustomDimension(dim);
      }
    }
    if (json.containsKey('defaultWeldStyle')) {
      defaultWeldStyle = WeldJointStyle.fromString(json['defaultWeldStyle'] as String?);
    }
    if (json.containsKey('defaultWeldTickSizeMm')) {
      defaultWeldTickSizeMm = (json['defaultWeldTickSizeMm'] as num?)?.toDouble();
    }
  }

  factory PipingNetwork.fromJson(Map<String, dynamic> json) {
    final catalog = FittingCatalog();
    if (json.containsKey('catalog')) {
      catalog.loadFromJson(json['catalog'] as Map<String, dynamic>);
    }

    final pipeCatalog = json.containsKey('pipeCatalog')
        ? PipeAssortmentCatalog.fromJson(json['pipeCatalog'] as Map<String, dynamic>)
        : PipeAssortmentCatalog();

    final net = PipingNetwork(
      nodes: (json['nodes'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, Node3D.fromJson(v as Map<String, dynamic>)),
          ) ??
          {},
      segments: (json['segments'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, PipeSegment.fromJson(v as Map<String, dynamic>)),
          ) ??
          {},
      valves: (json['valves'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, Valve.fromJson(v as Map<String, dynamic>)),
          ) ??
          {},
      weldJoints: (json['weldJoints'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, WeldJoint.fromJson(v as Map<String, dynamic>)),
          ) ??
          {},
      fittings: (json['fittings'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, Fitting.fromJson(v as Map<String, dynamic>)),
          ) ??
          {},
      spools: (json['spools'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, PipeSpool.fromJson(v as Map<String, dynamic>)),
          ) ??
          {},
      systems: (json['systems'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, PipingSystem.fromJson(v as Map<String, dynamic>)),
          ) ??
          {},
      axes: (json['axes'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, ConstructionAxis.fromJson(v as Map<String, dynamic>)),
          ) ??
          {},
      equipments: (json['equipments'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, Equipment.fromJson(v as Map<String, dynamic>)),
          ) ??
          {},
      supports: (json['supports'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, PipeSupport.fromJson(v as Map<String, dynamic>)),
          ) ??
          {},
      callouts: (json['callouts'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, Callout.fromJson(v as Map<String, dynamic>)),
          ) ??
          {},
      dimensions: (json['dimensions'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, LinearDimension.fromJson(v as Map<String, dynamic>)),
          ) ??
          {},
      catalog: catalog,
      pipeCatalog: pipeCatalog,
      defaultWeldStyle: json['defaultWeldStyle'] != null
          ? WeldJointStyle.fromString(json['defaultWeldStyle'] as String?)
          : WeldJointStyle.tick,
      defaultWeldTickSizeMm: (json['defaultWeldTickSizeMm'] as num?)?.toDouble(),
    );
    return net;
  }

  void addDimension(LinearDimension dim) {
    dimensions[dim.id] = dim;
  }

  void removeDimension(String id) {
    dimensions.remove(id);
  }

  /// Подстановка плейсхолдеров шаблона для целевого объекта выноски
  String formatCalloutTemplate(
    CalloutTargetType targetType,
    String targetId,
    String template, {
    String? dateFormat,
    Map<String, String>? templates,
  }) {
    var text = template;
    switch (targetType) {
      case CalloutTargetType.segment:
        PipeSegment? seg = segments[targetId];
        PipeSpool? spool = spools[targetId];
        if (spool != null) {
          seg = segments[spool.segmentId] ?? seg;
        } else if (seg != null) {
          final segSpools = spools.values.where((s) => s.segmentId == targetId).toList();
          if (segSpools.length == 1) {
            spool = segSpools.first;
          }
        }
        if (seg == null && spool == null) return 'Труба (удалена)';

        final dn = spool?.dn ?? seg?.dn ?? 0;
        final od = seg != null ? seg.outerDiameterMm : (dn.toDouble());
        final wall = spool?.wallThickness ?? seg?.wallThicknessMm ?? 0.0;
        final mat = (spool != null && spool.material.isNotEmpty)
            ? spool.material
            : (seg?.material ?? 'Ст20');
        final sysCode = (seg != null && systems[seg.systemId] != null) ? (systems[seg.systemId]?.code ?? seg.systemId) : '';

        final dStr = od.truncateToDouble() == od ? od.toStringAsFixed(0) : od.toStringAsFixed(1);
        final sStr = wall.truncateToDouble() == wall ? wall.toStringAsFixed(0) : wall.toStringAsFixed(1);

        final nameStr = (spool?.name != null && spool!.name!.isNotEmpty)
            ? spool.name!
            : (seg?.name ?? '');

        final segName = seg?.name;
        // Человекочитаемая марка катушки / трубы (напр. "К-1", "К-2", либо пользовательское имя "Уч-1")
        final spoolMark = (spool?.name != null && spool!.name!.isNotEmpty)
            ? spool.name!
            : (spool?.number != null && spool!.number.isNotEmpty)
                ? spool.number
                : (segName != null && segName.isNotEmpty)
                    ? segName
                    : 'К-1';

        final serialStr = (spool?.serialNumber != null && spool!.serialNumber!.isNotEmpty)
            ? spool.serialNumber!
            : (seg?.serialNumber ?? '');

        text = text
            .replaceAll('{DN}', '$dn')
            .replaceAll('{WALL}', sStr)
            .replaceAll('{S}', sStr)
            .replaceAll('{D_OUT}', dStr)
            .replaceAll('{OD}', dStr)
            .replaceAll('{OUTER_DIAMETER}', dStr)
            .replaceAll('{MATERIAL}', mat)
            .replaceAll('{STANDARD}', 'ГОСТ 10704-91')
            .replaceAll('{SYSTEM}', sysCode)
            .replaceAll('{NAME}', nameStr)
            .replaceAll('{TAG}', nameStr.isNotEmpty ? nameStr : spoolMark)
            .replaceAll('{SERIAL}', serialStr)
            .replaceAll('{SERIAL_NUMBER}', serialStr)
            .replaceAll('{BATCH}', serialStr)
            .replaceAll('{SPOOL}', spoolMark)
            .replaceAll('{NUM}', spoolMark)
            .replaceAll('{ID}', spoolMark)
            .replaceAll('{TECH_ID}', spool?.id ?? seg?.id ?? targetId);

        final int len;
        if (spool != null) {
          len = spool.cutLengthMm.round();
        } else if (seg != null) {
          final start = nodes[seg.startNodeId];
          final end = nodes[seg.endNodeId];
          len = (start != null && end != null) ? start.distanceTo(end).round() : 0;
        } else {
          len = 0;
        }

        text = text
            .replaceAll('{LENGTH}', '$len')
            .replaceAll('{L}', '$len')
            .replaceAll('{L_CUT}', '$len')
            .replaceAll('{CUT_LENGTH}', '$len');
        break;

      case CalloutTargetType.valve:
        final v = valves[targetId];
        if (v == null) return 'Арматура (удалена)';

        final seg = segments[v.segmentId];
        final sysCode = (seg != null && systems[seg.systemId] != null) ? systems[seg.systemId]!.code : '';
        final material = seg?.material ?? 'Ст20';
        final start = seg != null ? nodes[seg.startNodeId] : null;
        final end = seg != null ? nodes[seg.endNodeId] : null;
        final zVal = (start != null && end != null) ? (start.z + (end.z - start.z) * v.ratio) : 0.0;
        final zMeters = zVal / 1000.0;
        final sign = zMeters >= 0 ? '+' : '-';
        final zStr = '$sign${zMeters.abs().toStringAsFixed(3)}';

        text = text
            .replaceAll('{NAME}', v.name)
            .replaceAll('{TAG}', v.name)
            .replaceAll('{SERIAL}', v.serialNumber ?? '')
            .replaceAll('{SERIAL_NUMBER}', v.serialNumber ?? '')
            .replaceAll('{BATCH}', v.serialNumber ?? '')
            .replaceAll('{DN}', '${v.dn}')
            .replaceAll('{TYPE}', v.valveType.displayName)
            .replaceAll('{LENGTH}', '${v.lengthMm.round()}')
            .replaceAll('{L}', '${v.lengthMm.round()}')
            .replaceAll('{MATERIAL}', material)
            .replaceAll('{SYSTEM}', sysCode)
            .replaceAll('{PN}', 'Ру16')
            .replaceAll('+{Z_M}', zStr)
            .replaceAll('{Z_M}', zStr)
            .replaceAll('+{Z}', zStr)
            .replaceAll('{Z}', zStr)
            .replaceAll('{ELEVATION}', zStr)
            .replaceAll('{ID}', v.name.isNotEmpty ? v.name : v.id)
            .replaceAll('{TECH_ID}', v.id);
        break;

      case CalloutTargetType.fitting:
        final fit = fittings[targetId] ??
            fittings.values.where((f) => f.id == targetId).firstOrNull;
        if (fit == null) return 'Деталь (удалена)';

        final conn = getConnectedSegments(fit.nodeId);
        final firstSeg = conn.isNotEmpty ? conn.first : null;
        final sysCode = (firstSeg != null && systems[firstSeg.systemId] != null) ? systems[firstSeg.systemId]!.code : '';
        final material = fit.material.isNotEmpty ? fit.material : (firstSeg?.material ?? 'Ст20');
        final standard = (fit.standard != null && fit.standard!.isNotEmpty) ? fit.standard! : 'ГОСТ 17375';

        final fitName = fit.name ?? fit.fittingType.displayName;
        text = text
            .replaceAll('{NAME}', fitName)
            .replaceAll('{TAG}', fitName)
            .replaceAll('{SERIAL}', fit.serialNumber ?? '')
            .replaceAll('{SERIAL_NUMBER}', fit.serialNumber ?? '')
            .replaceAll('{BATCH}', fit.serialNumber ?? '')
            .replaceAll('{TYPE}', fit.fittingType.displayName)
            .replaceAll('{STANDARD}', standard)
            .replaceAll('{MATERIAL}', material)
            .replaceAll('{SYSTEM}', sysCode)
            .replaceAll('{DN}', '${fit.dn}')
            .replaceAll('{DN2}', fit.dnSecondary != null ? '${fit.dnSecondary}' : '${fit.dn}')
            .replaceAll('{ID}', fitName)
            .replaceAll('{TECH_ID}', fit.id);
        break;

      case CalloutTargetType.weld:
        final w = weldJoints[targetId];
        if (w == null) return 'Стык (удален)';

        final numStr = w.number > 0 ? '${w.number}' : '1';
        final seg = segments[w.segmentId];
        final dStr = seg != null
            ? (seg.outerDiameterMm.truncateToDouble() == seg.outerDiameterMm
                ? seg.outerDiameterMm.toStringAsFixed(0)
                : seg.outerDiameterMm.toStringAsFixed(1))
            : '';
        final sStr = seg != null
            ? (seg.wallThicknessMm.truncateToDouble() == seg.wallThicknessMm
                ? seg.wallThicknessMm.toStringAsFixed(0)
                : seg.wallThicknessMm.toStringAsFixed(1))
            : '';
        final dnStr = seg != null ? '${seg.dn}' : '';

        text = text
            .replaceAll('{ID}', numStr)
            .replaceAll('{NUM}', numStr)
            .replaceAll('{NUMBER}', numStr)
            .replaceAll('{STAMP}', w.stamp)
            .replaceAll('{TYPE}', w.weldType.shortName);

        // Форматирование даты сварного шва с учетом настройки и инлайн-модификатора {DATE:FORMAT}
        final effectiveFormat = dateFormat ?? templates?['date_format'] ?? 'DD.MM.YYYY';
        final formattedDate = formatWeldDate(w.date, effectiveFormat);
        final dateRegex = RegExp(r'\{DATE(?::([A-Za-z0-9_./-]+))?\}');
        text = text.replaceAllMapped(dateRegex, (match) {
          final inlineFormat = match.group(1);
          if (inlineFormat != null && inlineFormat.isNotEmpty) {
            return formatWeldDate(w.date, inlineFormat);
          }
          return formattedDate;
        });

        final start = seg != null ? nodes[seg.startNodeId] : null;
        final end = seg != null ? nodes[seg.endNodeId] : null;
        final zVal = (start != null && end != null) ? (start.z + (end.z - start.z) * w.ratio) : 0.0;
        final zMeters = zVal / 1000.0;
        final sign = zMeters >= 0 ? '+' : '-';
        final zStr = '$sign${zMeters.abs().toStringAsFixed(3)}';

        text = text
            .replaceAll('{STEEL}', w.steelGrade)
            .replaceAll('{MATERIAL}', w.steelGrade)
            .replaceAll('{ELECTRODE}', w.electrodeGrade)
            .replaceAll('{METHOD}', w.inspectionMethod.shortName)
            .replaceAll('{DN}', dnStr)
            .replaceAll('{WALL}', sStr)
            .replaceAll('{S}', sStr)
            .replaceAll('{D_OUT}', dStr)
            .replaceAll('{OD}', dStr)
            .replaceAll('{DIAMETER}', dStr)
            .replaceAll('+{Z_M}', zStr)
            .replaceAll('{Z_M}', zStr)
            .replaceAll('+{Z}', zStr)
            .replaceAll('{Z}', zStr)
            .replaceAll('{ELEVATION}', zStr)
            .replaceAll('{WELD_ID}', w.id)
            .replaceAll('{TECH_ID}', w.id);
        break;

      case CalloutTargetType.equipment:
        final eq = equipments[targetId];
        if (eq == null) return 'Оборудование (удалено)';

        // Короткий тег аппарата (напр. "Е-1", "Н-1", "Т-2")
        final tagStr = eq.name.trim().contains(RegExp(r'\s+'))
            ? eq.name.trim().split(RegExp(r'\s+')).last
            : eq.name;
        final dimsStr = '${eq.width.round()}x${eq.length.round()}x${eq.height.round()}';

        text = text
            .replaceAll('{NAME}', eq.name)
            .replaceAll('{TAG}', tagStr)
            .replaceAll('{SERIAL}', eq.serialNumber ?? '')
            .replaceAll('{SERIAL_NUMBER}', eq.serialNumber ?? '')
            .replaceAll('{BATCH}', eq.serialNumber ?? '')
            .replaceAll('{TYPE}', eq.type.displayName)
            .replaceAll('{DIMENSIONS}', dimsStr)
            .replaceAll('{ID}', tagStr)
            .replaceAll('{TECH_ID}', eq.id);
        break;

      case CalloutTargetType.nozzle:
        Nozzle? noz;
        Equipment? parentEq;
        for (final eq in equipments.values) {
          for (final n in eq.nozzles) {
            if (n.id == targetId) {
              noz = n;
              parentEq = eq;
              break;
            }
          }
          if (noz != null) break;
        }

        if (noz == null) return 'Штуцер (удален)';

        final eqTag = parentEq != null
            ? (parentEq.name.trim().contains(RegExp(r'\s+'))
                ? parentEq.name.trim().split(RegExp(r'\s+')).last
                : parentEq.name)
            : '';

        text = text
            .replaceAll('{NAME}', noz.name)
            .replaceAll('{TAG}', noz.name)
            .replaceAll('{DN}', '${noz.dn}')
            .replaceAll('{EQUIPMENT}', parentEq?.name ?? '')
            .replaceAll('{EQUIPMENT_TAG}', eqTag)
            .replaceAll('{FACE}', noz.face?.name ?? '')
            .replaceAll('{ID}', noz.name)
            .replaceAll('{TECH_ID}', noz.id);
        break;

      case CalloutTargetType.support:
        final sup = supports[targetId];
        if (sup == null) return 'Опора (удалена)';

        final supName = sup.name.isNotEmpty ? sup.name : sup.type.shortCode;
        text = text
            .replaceAll('{NAME}', supName)
            .replaceAll('{TAG}', supName)
            .replaceAll('{TYPE}', sup.type.displayName)
            .replaceAll('{CODE}', sup.type.shortCode)
            .replaceAll('{ID}', supName)
            .replaceAll('{TECH_ID}', sup.id);
        break;

      case CalloutTargetType.node:
        final node = nodes[targetId];
        if (node == null) return 'Узел (удален)';

        final cleanNum = node.id.replaceFirst(RegExp(r'^(node_|n_)'), '');
        final zM = node.elevationString;
        final zMm = node.z.round();

        final connectedSegs = getConnectedSegments(node.id);
        final primarySeg = connectedSegs.isNotEmpty ? connectedSegs.first : null;
        final pipeDn = primarySeg?.dn ?? 0;
        final pipeOd = primarySeg != null ? primarySeg.outerDiameterMm : (pipeDn.toDouble());
        final radiusMeters = (pipeOd / 2.0) / 1000.0;
        final zMeters = node.z / 1000.0;
        final zTopM = zMeters + radiusMeters;
        final zBotM = zMeters - radiusMeters;

        String formatM(double m) {
          if (m.abs() < 0.0001) return '0.000';
          final sign = m > 0 ? '+' : '';
          return '$sign${m.toStringAsFixed(3)}';
        }

        final zTopStr = formatM(zTopM);
        final zBotStr = formatM(zBotM);
        final sysCode = (primarySeg != null && systems[primarySeg.systemId] != null)
            ? systems[primarySeg.systemId]!.code
            : '';

        text = text
            .replaceAll('+{Z_M}', zM)
            .replaceAll('{Z_M}', zM)
            .replaceAll('{Z_MM}', '$zMm')
            .replaceAll('{Z}', '$zMm')
            .replaceAll('{TOP}', 'В.Т. $zTopStr')
            .replaceAll('{Z_TOP}', zTopStr)
            .replaceAll('{BOP}', 'Н.Т. $zBotStr')
            .replaceAll('{BOT}', 'Н.Т. $zBotStr')
            .replaceAll('{Z_BOT}', zBotStr)
            .replaceAll('{Z_AXIS}', 'ОСЬ $zM')
            .replaceAll('{DN}', pipeDn > 0 ? '$pipeDn' : '')
            .replaceAll('{SYSTEM}', sysCode)
            .replaceAll('{NAME}', node.customElevation != null ? node.customElevation! : 'Узел $cleanNum')
            .replaceAll('{ID}', cleanNum)
            .replaceAll('{NUM}', cleanNum)
            .replaceAll('{X}', '${node.x.round()}')
            .replaceAll('{Y}', '${node.y.round()}');
        break;
    }
    return text;
  }

  /// Генерация верхнего текста для выноски по шаблону или возврат customText
  String generateCalloutText(
    Callout callout,
    Map<String, String> templates, {
    bool ignoreCustomText = false,
  }) {
    if (!ignoreCustomText && callout.customText != null && callout.customText!.trim().isNotEmpty) {
      final lines = callout.customText!.split('\n');
      final firstLine = lines.first;
      if (firstLine.contains('{') && firstLine.contains('}')) {
        return formatCalloutTemplate(
          callout.targetType,
          callout.targetId,
          firstLine,
          dateFormat: templates['date_format'],
          templates: templates,
        );
      }
      return firstLine;
    }

    if (callout.elevationStyle != null) {
      final template = templates['node'] ?? '+{Z_M}';
      final topTemplate = template.split('\n').first;
      return formatCalloutTemplate(
        callout.targetType,
        callout.targetId,
        topTemplate,
        dateFormat: templates['date_format'],
        templates: templates,
      );
    }

    final template = templates[callout.targetType.name] ?? callout.targetType.defaultTemplate;
    final topTemplate = template.split('\n').first;
    return formatCalloutTemplate(
      callout.targetType,
      callout.targetId,
      topTemplate,
      dateFormat: templates['date_format'],
      templates: templates,
    );
  }

  /// Генерация нижнего текста для двухполочной выноски (под полочкой)
  String? generateCalloutBottomText(
    Callout callout,
    Map<String, String> templates, {
    bool ignoreCustomText = false,
  }) {
    if (!ignoreCustomText && callout.customBottomText != null && callout.customBottomText!.trim().isNotEmpty) {
      if (callout.customBottomText!.contains('{') && callout.customBottomText!.contains('}')) {
        return formatCalloutTemplate(
          callout.targetType,
          callout.targetId,
          callout.customBottomText!,
          dateFormat: templates['date_format'],
          templates: templates,
        );
      }
      return callout.customBottomText!;
    }
    if (!ignoreCustomText && callout.customText != null && callout.customText!.contains('\n')) {
      final lines = callout.customText!.split('\n');
      if (lines.length > 1 && lines[1].trim().isNotEmpty) {
        final bottomPart = lines.sublist(1).join('\n');
        if (bottomPart.contains('{') && bottomPart.contains('}')) {
          return formatCalloutTemplate(
            callout.targetType,
            callout.targetId,
            bottomPart,
            dateFormat: templates['date_format'],
            templates: templates,
          );
        }
        return bottomPart;
      }
    }

    if (callout.elevationStyle != null) {
      return null;
    }

    final bottomKey = '${callout.targetType.name}_bottom';
    final bottomTemplate = templates[bottomKey] ?? callout.targetType.defaultBottomTemplate;
    if (bottomTemplate != null && bottomTemplate.trim().isNotEmpty) {
      final formatted = formatCalloutTemplate(
        callout.targetType,
        callout.targetId,
        bottomTemplate,
        dateFormat: templates['date_format'],
        templates: templates,
      );
      if (formatted.trim().isNotEmpty) return formatted.trim();
    }

    final template = templates[callout.targetType.name];
    if (template != null && template.contains('\n')) {
      final lines = template.split('\n');
      if (lines.length > 1 && lines[1].trim().isNotEmpty) {
        return formatCalloutTemplate(
          callout.targetType,
          callout.targetId,
          lines.sublist(1).join('\n'),
          dateFormat: templates['date_format'],
          templates: templates,
        );
      }
    }

    return null;
  }

  /// Определение связанного сегмента для объекта выноски (если применимо)
  String? getTargetSegmentId(CalloutTargetType type, String targetId) {
    switch (type) {
      case CalloutTargetType.segment:
        return targetId;
      case CalloutTargetType.valve:
        return valves[targetId]?.segmentId;
      case CalloutTargetType.weld:
        return weldJoints[targetId]?.segmentId;
      case CalloutTargetType.fitting:
        final fit = fittings[targetId] ??
            fittings.values.where((f) => f.id == targetId).firstOrNull;
        if (fit != null) {
          final conn = getConnectedSegments(fit.nodeId);
          return conn.isNotEmpty ? conn.first.id : null;
        }
        return null;
      case CalloutTargetType.support:
        return supports[targetId]?.segmentId;
      case CalloutTargetType.nozzle:
      case CalloutTargetType.node:
      case CalloutTargetType.equipment:
        return null;
    }
  }

  /// Автогенерация недостающих выносок для сегментов, арматуры и сварных стыков
  /// с предотвращением наложения (Collision Avoidance) смещений текста.
  /// При передаче [targetTypes] генерируются выноски только для указанных типов.
  int generateMissingCallouts({
    Set<CalloutTargetType>? targetTypes,
    double offsetX = 50.0,
    double offsetY = -50.0,
    double textHeight = 12.0,
    double margin = 8.0,
  }) {
    int addedCount = 0;
    final existingTargetIds = callouts.values.map((c) => c.targetId).toSet();
    final step = textHeight + margin;

    double resolveNonCollidingOffsetY(String? segmentId, double initialOffsetY) {
      double curY = initialOffsetY;
      while (callouts.values.any((c) {
        if (segmentId != null && getTargetSegmentId(c.targetType, c.targetId) != segmentId) {
          return false;
        }
        return (c.screenOffsetY - curY).abs() < step;
      })) {
        curY += step;
      }
      return curY;
    }

    if (targetTypes == null || targetTypes.contains(CalloutTargetType.segment)) {
      for (final seg in segments.values) {
        if (!existingTargetIds.contains(seg.id)) {
          final id = 'callout_${_uuid.v4()}';
          final resolvedY = resolveNonCollidingOffsetY(seg.id, offsetY);
          callouts[id] = Callout(
            id: id,
            targetId: seg.id,
            targetType: CalloutTargetType.segment,
            screenOffsetX: offsetX,
            screenOffsetY: resolvedY,
            textHeight: textHeight,
          );
          existingTargetIds.add(seg.id);
          addedCount++;
        }
      }
    }

    if (targetTypes == null || targetTypes.contains(CalloutTargetType.valve)) {
      for (final valve in valves.values) {
        if (!existingTargetIds.contains(valve.id)) {
          final id = 'callout_${_uuid.v4()}';
          final resolvedY = resolveNonCollidingOffsetY(valve.segmentId, offsetY);
          callouts[id] = Callout(
            id: id,
            targetId: valve.id,
            targetType: CalloutTargetType.valve,
            screenOffsetX: offsetX,
            screenOffsetY: resolvedY,
            textHeight: textHeight,
          );
          existingTargetIds.add(valve.id);
          addedCount++;
        }
      }
    }

    if (targetTypes == null || targetTypes.contains(CalloutTargetType.weld)) {
      for (final weld in weldJoints.values) {
        if (!existingTargetIds.contains(weld.id)) {
          final id = 'callout_${_uuid.v4()}';
          final resolvedY = resolveNonCollidingOffsetY(weld.segmentId, offsetY);
          callouts[id] = Callout(
            id: id,
            targetId: weld.id,
            targetType: CalloutTargetType.weld,
            screenOffsetX: offsetX,
            screenOffsetY: resolvedY,
            textHeight: textHeight,
          );
          existingTargetIds.add(weld.id);
          addedCount++;
        }
      }
    }

    if (targetTypes == null || targetTypes.contains(CalloutTargetType.fitting)) {
      for (final fit in fittings.values) {
        if (!existingTargetIds.contains(fit.id) && !existingTargetIds.contains(fit.nodeId)) {
          final id = 'callout_${_uuid.v4()}';
          final resolvedY = resolveNonCollidingOffsetY(null, offsetY);
          callouts[id] = Callout(
            id: id,
            targetId: fit.id,
            targetType: CalloutTargetType.fitting,
            screenOffsetX: offsetX,
            screenOffsetY: resolvedY,
            textHeight: textHeight,
          );
          existingTargetIds.add(fit.id);
          addedCount++;
        }
      }
    }

    if (targetTypes == null || targetTypes.contains(CalloutTargetType.equipment)) {
      for (final eq in equipments.values) {
        if (!existingTargetIds.contains(eq.id)) {
          final id = 'callout_${_uuid.v4()}';
          final resolvedY = resolveNonCollidingOffsetY(null, offsetY);
          callouts[id] = Callout(
            id: id,
            targetId: eq.id,
            targetType: CalloutTargetType.equipment,
            screenOffsetX: offsetX,
            screenOffsetY: resolvedY,
            textHeight: textHeight,
          );
          existingTargetIds.add(eq.id);
          addedCount++;
        }
      }
    }

    if (targetTypes == null || targetTypes.contains(CalloutTargetType.nozzle)) {
      for (final eq in equipments.values) {
        for (final noz in eq.nozzles) {
          if (!existingTargetIds.contains(noz.id)) {
            final id = 'callout_${_uuid.v4()}';
            final resolvedY = resolveNonCollidingOffsetY(null, offsetY);
            callouts[id] = Callout(
              id: id,
              targetId: noz.id,
              targetType: CalloutTargetType.nozzle,
              screenOffsetX: offsetX,
              screenOffsetY: resolvedY,
              textHeight: textHeight,
            );
            existingTargetIds.add(noz.id);
            addedCount++;
          }
        }
      }
    }

    if (targetTypes == null || targetTypes.contains(CalloutTargetType.support)) {
      for (final sup in supports.values) {
        if (!existingTargetIds.contains(sup.id)) {
          final id = 'callout_${_uuid.v4()}';
          final resolvedY = resolveNonCollidingOffsetY(sup.segmentId, offsetY);
          callouts[id] = Callout(
            id: id,
            targetId: sup.id,
            targetType: CalloutTargetType.support,
            screenOffsetX: offsetX,
            screenOffsetY: resolvedY,
            textHeight: textHeight,
          );
          existingTargetIds.add(sup.id);
          addedCount++;
        }
      }
    }

    if (targetTypes?.contains(CalloutTargetType.node) == true) {
      for (final node in nodes.values) {
        final connected = getConnectedSegments(node.id);
        final hasVertical = connected.any((s) {
          final sNode = nodes[s.startNodeId];
          final eNode = nodes[s.endNodeId];
          return sNode != null && eNode != null && s.isVertical(sNode, eNode);
        });
        if (connected.length == 1 || hasVertical || node.customElevation != null) {
          if (!existingTargetIds.contains(node.id)) {
            final id = 'callout_${_uuid.v4()}';
            final resolvedY = resolveNonCollidingOffsetY(null, offsetY);
            callouts[id] = Callout(
              id: id,
              targetId: node.id,
              targetType: CalloutTargetType.node,
              screenOffsetX: offsetX,
              screenOffsetY: resolvedY,
              textHeight: textHeight,
              arrowOnNode: true,
            );
            existingTargetIds.add(node.id);
            addedCount++;
          }
        }
      }
    }

    return addedCount;
  }

  /// Добавление выноски в сеть
  void addCallout(Callout callout) {
    callouts[callout.id] = callout;
  }

  /// Удаление выноски из сети
  void removeCallout(String id) {
    callouts.remove(id);
  }

  /// Очистка осиротевших выносок (ссылающихся на несуществующие трубы, арматуру, стыки, фитинги, оборудование, опоры)
  int cleanOrphanedCallouts() {
    final toRemove = <String>[];
    for (final entry in callouts.entries) {
      final c = entry.value;
      bool exists = true;
      switch (c.targetType) {
        case CalloutTargetType.segment:
          exists = segments.containsKey(c.targetId);
          break;
        case CalloutTargetType.valve:
          exists = valves.containsKey(c.targetId);
          break;
        case CalloutTargetType.weld:
          exists = weldJoints.containsKey(c.targetId);
          break;
        case CalloutTargetType.fitting:
          exists = fittings.containsKey(c.targetId) ||
              fittings.values.any((f) => f.id == c.targetId || f.nodeId == c.targetId);
          break;
        case CalloutTargetType.equipment:
          exists = equipments.containsKey(c.targetId);
          break;
        case CalloutTargetType.nozzle:
          exists = equipments.values.any((eq) => eq.nozzles.any((n) => n.id == c.targetId));
          break;
        case CalloutTargetType.support:
          exists = supports.containsKey(c.targetId);
          break;
        case CalloutTargetType.node:
          exists = nodes.containsKey(c.targetId);
          break;
      }
      if (!exists) {
        toRemove.add(entry.key);
      }
    }
    for (final id in toRemove) {
      callouts.remove(id);
    }
    return toRemove.length;
  }
}

/// Форматирование даты выполнения сварного шва в заданный формат
/// Поддерживаемые форматы: 'DD.MM.YYYY', 'DD.MM.YY', 'YYYY-MM-DD', 'DD/MM/YYYY'
String formatWeldDate(String rawDate, [String format = 'DD.MM.YYYY']) {
  final trimmed = rawDate.trim();
  if (trimmed.isEmpty) return '';

  int year = 0;
  int month = 0;
  int day = 0;

  // 1. Попытка разобрать ISO (YYYY-MM-DD или YYYY.MM.DD или YYYY/MM/DD)
  final isoMatch = RegExp(r'^(\d{4})[-./](\d{1,2})[-./](\d{1,2})').firstMatch(trimmed);
  if (isoMatch != null) {
    year = int.tryParse(isoMatch.group(1)!) ?? 0;
    month = int.tryParse(isoMatch.group(2)!) ?? 0;
    day = int.tryParse(isoMatch.group(3)!) ?? 0;
  } else {
    // 2. Попытка разобрать ДД.ММ.ГГГГ или ДД/ММ/ГГГГ или ДД-ММ-ГГГГ
    final dmyMatch = RegExp(r'^(\d{1,2})[-./](\d{1,2})[-./](\d{2,4})').firstMatch(trimmed);
    if (dmyMatch != null) {
      day = int.tryParse(dmyMatch.group(1)!) ?? 0;
      month = int.tryParse(dmyMatch.group(2)!) ?? 0;
      var y = int.tryParse(dmyMatch.group(3)!) ?? 0;
      if (y < 100) {
        y += 2000;
      }
      year = y;
    } else {
      // Не удалось распарсить структуру даты — возвращаем как есть
      return trimmed;
    }
  }

  if (year == 0 || month == 0 || day == 0) return trimmed;

  final dd = day.toString().padLeft(2, '0');
  final mm = month.toString().padLeft(2, '0');
  final yyyy = year.toString().padLeft(4, '0');
  final yy = (year % 100).toString().padLeft(2, '0');

  switch (format.toUpperCase()) {
    case 'DD.MM.YY':
      return '$dd.$mm.$yy';
    case 'YYYY-MM-DD':
      return '$yyyy-$mm-$dd';
    case 'DD/MM/YYYY':
      return '$dd/$mm/$yyyy';
    case 'DD.MM.YYYY':
    default:
      return '$dd.$mm.$yyyy';
  }
}
