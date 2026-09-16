import 'dart:math' as math;
import 'package:uuid/uuid.dart';
import '../enums/fitting_type.dart';
import '../enums/inspection_method.dart';
import '../enums/valve_type.dart';
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

  /// Удаление оборудования с каскадной очисткой штуцеров и примыкающих элементов
  void updateEquipment(Equipment updatedEq) {
    if (!equipments.containsKey(updatedEq.id)) return;
    equipments[updatedEq.id] = updatedEq;
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

  /// Добавление нового сегмента трубы в сеть с автоматическим определением фитингов
  void addSegment(PipeSegment segment) {
    segments[segment.id] = segment;
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

  /// Возвращает теоретическое расстояние между узлами для сварки двух отводов встык: T1 + T2
  double? getElbowToElbowTargetLength(String segmentId) {
    if (!isElbowToElbowSegment(segmentId)) return null;
    final seg = segments[segmentId]!;
    final t1 = getElbowTangentMm(seg.startNodeId);
    final t2 = getElbowTangentMm(seg.endNodeId);
    return t1 + t2;
  }

  /// Проверяет, соединены ли два отвода сегмента напрямую встык (L ≈ T1 + T2, L_pipe = 0)
  bool isButtJoint(String segmentId) {
    final targetLen = getElbowToElbowTargetLength(segmentId);
    if (targetLen == null) return false;
    final seg = segments[segmentId]!;
    final n1 = nodes[seg.startNodeId];
    final n2 = nodes[seg.endNodeId];
    if (n1 == null || n2 == null) return false;
    final dist = n1.distanceTo(n2);
    return (dist - targetLen).abs() <= 2.0 || dist <= targetLen + 0.5;
  }

  /// Мгновенное стягивание двух отводов встык: устанавливает длину сегмента в T1 + T2
  bool collapseElbowToElbow(String segmentId) {
    final targetLen = getElbowToElbowTargetLength(segmentId);
    if (targetLen == null) return false;
    changeSegmentLength(segmentId, targetLen);
    return true;
  }

  /// Обновление параметров сегмента трубы (диаметр DN, наружный диаметр, толщина стенки, марка стали, маркировка, заводской номер/партия)
  void updateSegmentProperties(
    String segmentId, {
    int? dn,
    double? outerDiameterMm,
    double? wallThicknessMm,
    String? material,
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
    final clampedRatio = newRatio.clamp(0.05, 0.95);
    valves[valveId] = v.copyWith(ratio: clampedRatio);
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
  }) {
    final seg = segments[segmentId];
    final valveDn = dn ?? seg?.dn ?? 25;
    final valveName = name ?? '${valveType.displayName} Ду$valveDn';
    final length = customLengthMm ?? valveType.defaultLengthMm(valveDn);
    final id = 'valve_${_uuid.v4()}';
    final flanged = isFlanged ?? catalog.defaultValveIsFlanged;

    final valve = Valve(
      id: id,
      segmentId: segmentId,
      ratio: ratio.clamp(0.05, 0.95),
      valveType: valveType,
      name: valveName,
      dn: valveDn,
      lengthMm: length,
      isFlanged: flanged,
    );
    valves[id] = valve;

    recalculateSpools();
    return valve;
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

    // Удаляем концевые стыки на подключенных сегментах
    final conn = getConnectedSegments(nodeId);
    for (final seg in conn) {
      final r = seg.startNodeId == nodeId ? 0.0 : 1.0;
      final toRemove = weldJoints.values
          .where((w) => w.segmentId == seg.id && (w.ratio - r).abs() < 0.05)
          .map((w) => w.id)
          .toList();
      for (final wid in toRemove) {
        weldJoints.remove(wid);
      }
    }

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
    recalculateSpools();
  }

  /// Обновление точной строительной длины арматуры (мм) с пересчетом катушек
  Valve? updateValveLength(String valveId, double lengthMm) {
    final v = valves[valveId];
    if (v != null) {
      final updated = v.copyWith(lengthMm: lengthMm);
      valves[valveId] = updated;
      recalculateSpools();
      return updated;
    }
    return null;
  }

  /// Обновление параметров опоры
  void updateSupport(String supportId, PipeSupport updatedSupport) {
    supports[supportId] = updatedSupport;
  }

  /// Проверка и создание сварного шва на сегменте в позиции ratio, если такой шов еще не существует
  WeldJoint? ensureWeldExists(String segmentId, double ratio, WeldType weldType) {
    final exists = weldJoints.values.any(
      (w) => w.segmentId == segmentId && (w.ratio - ratio).abs() < 0.05,
    );
    if (!exists) {
      return addWeldJoint(segmentId: segmentId, ratio: ratio, weldType: weldType);
    }
    return null;
  }

  /// Определение сегмента ответвления среди 3 подключенных к узлу сегментов.
  /// Ответвлением считается сегмент, не лежащий на одной прямой с двумя остальными (магистралью).
  PipeSegment? identifyBranchSegment(String nodeId, [List<PipeSegment>? connectedSegments]) {
    return TopologyService.identifyBranchSegment(this, nodeId, connectedSegments);
  }

  /// Генерация технологических сварных стыков по ГОСТ 16037 для всех элементов сети
  /// (арматура, переходы, отводы, тройники, врезки, фланцы, заглушки).
  /// Метод идемпотентен: существующие стыки не дублируются.
  int generateElementWeldJoints() {
    int added = 0;

    // 1. Арматура (Valves): 2 стыка С17 по краям строительной длины
    for (final v in valves.values) {
      final seg = segments[v.segmentId];
      if (seg == null) continue;
      final startNode = nodes[seg.startNodeId];
      final endNode = nodes[seg.endNodeId];
      if (startNode == null || endNode == null) continue;
      final totalLen = seg.calculateLength(startNode, endNode);
      final halfRatio = (v.lengthMm / 2.0) / (totalLen > 0 ? totalLen : 1.0);
      final r1 = (v.ratio - halfRatio).clamp(0.0, 1.0);
      final r2 = (v.ratio + halfRatio).clamp(0.0, 1.0);
      if (ensureWeldExists(v.segmentId, r1, WeldType.c17) != null) added++;
      if (ensureWeldExists(v.segmentId, r2, WeldType.c17) != null) added++;
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
            if (isButtJoint(seg.id)) {
              // Для стыка встык создаем ровно один общий шов на границе сопряжения отводов
              final t1 = getElbowTangentMm(seg.startNodeId);
              final t2 = getElbowTangentMm(seg.endNodeId);
              final totalT = (t1 + t2) > 0 ? (t1 + t2) : 1.0;
              final r = (t1 / totalT).clamp(0.0, 1.0);
              if (ensureWeldExists(seg.id, r, fit.weldType) != null) added++;
            } else {
              final r = seg.startNodeId == nodeId ? 0.0 : 1.0;
              if (ensureWeldExists(seg.id, r, fit.weldType) != null) added++;
            }
          }
          break;

        case FittingType.reducerConcentric:
        case FittingType.reducerEccentric:
          for (final seg in connected) {
            final r = seg.startNodeId == nodeId ? 0.0 : 1.0;
            if (ensureWeldExists(seg.id, r, fit.weldType) != null) added++;
          }
          break;

        case FittingType.tee:
          for (final seg in connected) {
            final r = seg.startNodeId == nodeId ? 0.0 : 1.0;
            if (ensureWeldExists(seg.id, r, fit.weldType) != null) added++;
          }
          break;

        case FittingType.directBranch:
          final branchSeg = identifyBranchSegment(nodeId, connected);
          if (branchSeg != null) {
            final r = branchSeg.startNodeId == nodeId ? 0.0 : 1.0;
            if (ensureWeldExists(branchSeg.id, r, WeldType.u18) != null) added++;
          }
          break;

        case FittingType.cross:
          for (final seg in connected) {
            final r = seg.startNodeId == nodeId ? 0.0 : 1.0;
            if (ensureWeldExists(seg.id, r, fit.weldType) != null) added++;
          }
          break;

        case FittingType.flange:
          for (final seg in connected) {
            final r = seg.startNodeId == nodeId ? 0.0 : 1.0;
            if (ensureWeldExists(seg.id, r, fit.weldType) != null) added++;
          }
          break;

        case FittingType.cap:
          for (final seg in connected) {
            final r = seg.startNodeId == nodeId ? 0.0 : 1.0;
            if (ensureWeldExists(seg.id, r, fit.weldType) != null) added++;
          }
          break;
      }
    }

    if (added > 0) {
      recalculateSpools();
    }
    return added;
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
  String formatCalloutTemplate(CalloutTargetType targetType, String targetId, String template) {
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
        final serialStr = (spool?.serialNumber != null && spool!.serialNumber!.isNotEmpty)
            ? spool.serialNumber!
            : (seg?.serialNumber ?? '');
        final idStr = spool?.id ?? seg?.id ?? targetId;

        text = text
            .replaceAll('{DN}', '$dn')
            .replaceAll('{WALL}', sStr)
            .replaceAll('{S}', sStr)
            .replaceAll('{D_OUT}', dStr)
            .replaceAll('{OD}', dStr)
            .replaceAll('{OUTER_DIAMETER}', dStr)
            .replaceAll('{MATERIAL}', mat)
            .replaceAll('{SYSTEM}', sysCode)
            .replaceAll('{NAME}', nameStr)
            .replaceAll('{TAG}', nameStr)
            .replaceAll('{SERIAL}', serialStr)
            .replaceAll('{SERIAL_NUMBER}', serialStr)
            .replaceAll('{BATCH}', serialStr)
            .replaceAll('{SPOOL}', spool?.name ?? spool?.id ?? '')
            .replaceAll('{ID}', idStr);

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
            .replaceAll('{ID}', v.id);
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

        text = text
            .replaceAll('{NAME}', fit.name ?? fit.fittingType.displayName)
            .replaceAll('{TAG}', fit.name ?? fit.fittingType.displayName)
            .replaceAll('{SERIAL}', fit.serialNumber ?? '')
            .replaceAll('{SERIAL_NUMBER}', fit.serialNumber ?? '')
            .replaceAll('{BATCH}', fit.serialNumber ?? '')
            .replaceAll('{TYPE}', fit.fittingType.displayName)
            .replaceAll('{STANDARD}', standard)
            .replaceAll('{MATERIAL}', material)
            .replaceAll('{SYSTEM}', sysCode)
            .replaceAll('{DN}', '${fit.dn}')
            .replaceAll('{DN2}', fit.dnSecondary != null ? '${fit.dnSecondary}' : '${fit.dn}')
            .replaceAll('{ID}', fit.id);
        break;

      case CalloutTargetType.weld:
        final w = weldJoints[targetId];
        if (w == null) return 'Стык (удален)';

        final numStr = w.number > 0 ? '${w.number}' : w.id;
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
            .replaceAll('{NUM}', '${w.number}')
            .replaceAll('{NUMBER}', '${w.number}')
            .replaceAll('{STAMP}', w.stamp)
            .replaceAll('{TYPE}', w.weldType.shortName)
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
            .replaceAll('{WELD_ID}', w.id);
        break;

      case CalloutTargetType.equipment:
        final eq = equipments[targetId];
        if (eq == null) return 'Оборудование (удалено)';

        text = text
            .replaceAll('{NAME}', eq.name)
            .replaceAll('{TAG}', eq.name)
            .replaceAll('{SERIAL}', eq.serialNumber ?? '')
            .replaceAll('{SERIAL_NUMBER}', eq.serialNumber ?? '')
            .replaceAll('{BATCH}', eq.serialNumber ?? '')
            .replaceAll('{TYPE}', eq.type.displayName)
            .replaceAll('{ID}', eq.id);
        break;

      case CalloutTargetType.support:
        final sup = supports[targetId];
        if (sup == null) return 'Опора (удалена)';

        text = text
            .replaceAll('{NAME}', sup.name)
            .replaceAll('{TYPE}', sup.type.displayName)
            .replaceAll('{CODE}', sup.type.shortCode)
            .replaceAll('{ID}', sup.id);
        break;

      case CalloutTargetType.node:
        final node = nodes[targetId];
        if (node == null) return 'Узел (удален)';

        text = text
            .replaceAll('{ID}', node.id)
            .replaceAll('{X}', '${node.x.round()}')
            .replaceAll('{Y}', '${node.y.round()}')
            .replaceAll('{Z}', '${node.z.round()}');
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
      return lines.first;
    }

    final template = templates[callout.targetType.name] ?? callout.targetType.defaultTemplate;
    final topTemplate = template.split('\n').first;
    return formatCalloutTemplate(callout.targetType, callout.targetId, topTemplate);
  }

  /// Генерация нижнего текста для двухполочной выноски (под полочкой)
  String? generateCalloutBottomText(
    Callout callout,
    Map<String, String> templates, {
    bool ignoreCustomText = false,
  }) {
    if (!ignoreCustomText && callout.customBottomText != null && callout.customBottomText!.trim().isNotEmpty) {
      return callout.customBottomText!;
    }
    if (!ignoreCustomText && callout.customText != null && callout.customText!.contains('\n')) {
      final lines = callout.customText!.split('\n');
      if (lines.length > 1 && lines[1].trim().isNotEmpty) {
        return lines.sublist(1).join('\n');
      }
    }

    final bottomKey = '${callout.targetType.name}_bottom';
    final bottomTemplate = templates[bottomKey] ?? callout.targetType.defaultBottomTemplate;
    if (bottomTemplate != null && bottomTemplate.trim().isNotEmpty) {
      final formatted = formatCalloutTemplate(callout.targetType, callout.targetId, bottomTemplate);
      if (formatted.trim().isNotEmpty) return formatted.trim();
    }

    final template = templates[callout.targetType.name];
    if (template != null && template.contains('\n')) {
      final lines = template.split('\n');
      if (lines.length > 1 && lines[1].trim().isNotEmpty) {
        return formatCalloutTemplate(callout.targetType, callout.targetId, lines.sublist(1).join('\n'));
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
      bool collision;
      int iterations = 0;
      do {
        collision = false;
        for (final existing in callouts.values.toList()) {
          final existingSegId = getTargetSegmentId(existing.targetType, existing.targetId);
          final sameContext = segmentId != null && existingSegId == segmentId;
          if (sameContext || (existingSegId == null && segmentId == null)) {
            if ((existing.screenOffsetX - offsetX).abs() < 40.0 &&
                (existing.screenOffsetY - curY).abs() < step) {
              curY += step;
              collision = true;
              break;
            }
          }
        }
        iterations++;
      } while (collision && iterations < 50);
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
