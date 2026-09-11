import 'dart:math' as math;
import '../enums/fitting_type.dart';
import '../enums/inspection_method.dart';
import '../enums/valve_type.dart';
import '../enums/weld_type.dart';
import 'construction_axis.dart';
import 'fitting.dart';
import 'fitting_catalog.dart';
import 'node_3d.dart';
import 'pipe_dimension.dart';
import 'pipe_segment.dart';
import 'pipe_spool.dart';
import 'piping_system.dart';
import 'valve.dart';
import 'weld_joint.dart';

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
        catalog = catalog ?? FittingCatalog(),
        pipeCatalog = pipeCatalog ?? PipeAssortmentCatalog();

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
      catalog: catalog,
      pipeCatalog: pipeCatalog,
    );
  }

  /// Получение списка сегментов, подключенных к узлу
  List<PipeSegment> getConnectedSegments(String nodeId) {
    return segments.values
        .where((s) => s.startNodeId == nodeId || s.endNodeId == nodeId)
        .toList();
  }

  /// 1. Перемещение узла в 3D (стилусом или вводом координат)
  /// Все примыкающие трубы автоматически растягиваются/сжимаются, сохраняя соединение
  void moveNode(String nodeId, double newX, double newY, double newZ) {
    final node = nodes[nodeId];
    if (node == null) return;

    nodes[nodeId] = node.copyWith(x: newX, y: newY, z: newZ);
    _autoDetectFittingsForNode(nodeId);
    recalculateSpools();
  }

  /// Добавление нового сегмента трубы в сеть с автоматическим определением фитингов
  void addSegment(PipeSegment segment) {
    segments[segment.id] = segment;
    _autoDetectFittingsForNode(segment.startNodeId);
    _autoDetectFittingsForNode(segment.endNodeId);
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
      _autoDetectFittingsForNode(id);
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

    _autoDetectFittingsForNode(seg.startNodeId);
    _autoDetectFittingsForNode(seg.endNodeId);
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

    _autoDetectFittingsForNode(seg.startNodeId);
    _autoDetectFittingsForNode(seg.endNodeId);
    recalculateSpools();
  }

  /// Обновление параметров сегмента трубы (диаметр DN, наружный диаметр, толщина стенки, марка стали)
  void updateSegmentProperties(
    String segmentId, {
    int? dn,
    double? outerDiameterMm,
    double? wallThicknessMm,
    String? material,
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
    );
    _autoDetectFittingsForNode(seg.startNodeId);
    _autoDetectFittingsForNode(seg.endNodeId);
    recalculateSpools();
  }

  void _cascadeShift(String currentNodeId, double dx, double dy, double dz, Set<String> visited) {
    visited.add(currentNodeId);
    final node = nodes[currentNodeId];
    if (node != null) {
      nodes[currentNodeId] = node.copyWith(
        x: node.x + dx,
        y: node.y + dy,
        z: node.z + dz,
      );
    }

    for (final s in getConnectedSegments(currentNodeId)) {
      final nextNodeId = s.startNodeId == currentNodeId ? s.endNodeId : s.startNodeId;
      if (!visited.contains(nextNodeId)) {
        _cascadeShift(nextNodeId, dx, dy, dz, visited);
      }
    }
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
    final id = 'weld_${DateTime.now().millisecondsSinceEpoch}_$nextNumber';
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
    final id = 'valve_${DateTime.now().millisecondsSinceEpoch}';
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

    // Если арматура под приварку или фланцевая, автоматически добавляем сварные стыки по краям
    if (valveType != ValveType.pressureGauge &&
        valveType != ValveType.thermometer &&
        valveType != ValveType.airVent) {
      final segLength = seg != null && nodes[seg.startNodeId] != null && nodes[seg.endNodeId] != null
          ? nodes[seg.startNodeId]!.distanceTo(nodes[seg.endNodeId]!)
          : 1000.0;
      final halfValveRatio = (length / 2.0) / math.max(segLength, 1.0);

      addWeldJoint(
        segmentId: segmentId,
        ratio: (ratio - halfValveRatio).clamp(0.0, 1.0),
        weldType: WeldType.c17,
      );
      addWeldJoint(
        segmentId: segmentId,
        ratio: (ratio + halfValveRatio).clamp(0.0, 1.0),
        weldType: WeldType.c17,
      );
    }

    recalculateSpools();
    return valve;
  }

  /// Разделение сегмента трубы на два участка в точке ratio (0.0 < ratio < 1.0)
  /// Возвращает созданный промежуточный узел
  Node3D? splitSegmentAtRatio(String segmentId, double ratio) {
    final oldSeg = segments[segmentId];
    if (oldSeg == null) return null;
    final startNode = nodes[oldSeg.startNodeId];
    final endNode = nodes[oldSeg.endNodeId];
    if (startNode == null || endNode == null) return null;

    final midX = startNode.x + (endNode.x - startNode.x) * ratio;
    final midY = startNode.y + (endNode.y - startNode.y) * ratio;
    final midZ = startNode.z + (endNode.z - startNode.z) * ratio;

    final midNodeId = 'node_split_${DateTime.now().millisecondsSinceEpoch}';
    final midNode = Node3D(id: midNodeId, x: midX, y: midY, z: midZ);
    nodes[midNodeId] = midNode;

    segments.remove(segmentId);

    final seg1Id = '${segmentId}_a';
    final seg2Id = '${segmentId}_b';

    final seg1 = oldSeg.copyWith(
      id: seg1Id,
      endNodeId: midNodeId,
    );
    final seg2 = oldSeg.copyWith(
      id: seg2Id,
      startNodeId: midNodeId,
    );

    segments[seg1Id] = seg1;
    segments[seg2Id] = seg2;

    // Переносим существующие сварные швы на новые сегменты
    final affectedWelds = weldJoints.values.where((w) => w.segmentId == segmentId).toList();
    for (final w in affectedWelds) {
      weldJoints.remove(w.id);
      if (w.ratio <= ratio) {
        final newRatio = ratio > 0.0001 ? (w.ratio / ratio).clamp(0.0, 1.0) : 0.0;
        weldJoints[w.id] = w.copyWith(segmentId: seg1Id, ratio: newRatio);
      } else {
        final newRatio = (1.0 - ratio) > 0.0001 ? ((w.ratio - ratio) / (1.0 - ratio)).clamp(0.0, 1.0) : 0.0;
        weldJoints[w.id] = w.copyWith(segmentId: seg2Id, ratio: newRatio);
      }
    }

    // Переносим арматуру
    final affectedValves = valves.values.where((v) => v.segmentId == segmentId).toList();
    for (final v in affectedValves) {
      valves.remove(v.id);
      if (v.ratio <= ratio) {
        final newRatio = ratio > 0.0001 ? (v.ratio / ratio).clamp(0.05, 0.95) : 0.5;
        valves[v.id] = v.copyWith(segmentId: seg1Id, ratio: newRatio);
      } else {
        final newRatio = (1.0 - ratio) > 0.0001 ? ((v.ratio - ratio) / (1.0 - ratio)).clamp(0.05, 0.95) : 0.5;
        valves[v.id] = v.copyWith(segmentId: seg2Id, ratio: newRatio);
      }
    }

    return midNode;
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
    );
    fittings[midNode.id] = fitting;

    // Сварные стыки по обе стороны перехода
    addWeldJoint(segmentId: '${segmentId}_a', ratio: 1.0, weldType: WeldType.c17);
    addWeldJoint(segmentId: seg2Id, ratio: 0.0, weldType: WeldType.c17);

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

    // Расчет количества стыков:
    // toEquipment / blindFlange / singleFlange: 1 стык (на стороне трубы)
    // pipeToPipe: 2 стыка (на обоих отрезках)
    final numWelds = fit.effectiveWeldCount;
    if (numWelds >= 1) {
      addWeldJoint(segmentId: '${segmentId}_a', ratio: 1.0, weldType: fit.weldType);
    }
    if (numWelds >= 2) {
      addWeldJoint(segmentId: '${segmentId}_b', ratio: 0.0, weldType: fit.weldType);
    }

    recalculateSpools();
    return fit;
  }

  /// Обновление параметров фитинга в узле с пересчетом швов и катушек
  void updateFitting(String nodeId, Fitting updatedFit) {
    fittings[nodeId] = updatedFit;

    // Синхронизация стыков для фланцев
    if (updatedFit.fittingType == FittingType.flange) {
      final conn = getConnectedSegments(nodeId);
      if (conn.length == 2) {
        final s1 = conn[0];
        final s2 = conn[1];
        final r1 = s1.startNodeId == nodeId ? 0.0 : 1.0;
        final r2 = s2.startNodeId == nodeId ? 0.0 : 1.0;

        final targetCount = updatedFit.effectiveWeldCount;
        final existingWelds = weldJoints.values.where((w) {
          return (w.segmentId == s1.id && (w.ratio - r1).abs() < 0.05) ||
              (w.segmentId == s2.id && (w.ratio - r2).abs() < 0.05);
        }).toList();

        if (targetCount == 1) {
          if (existingWelds.length > 1) {
            // Удаляем лишний второй стык (сторона оборудования)
            weldJoints.remove(existingWelds[1].id);
          } else if (existingWelds.isEmpty) {
            addWeldJoint(segmentId: s1.id, ratio: r1, weldType: updatedFit.weldType);
          }
        } else if (targetCount >= 2) {
          if (existingWelds.length < 2) {
            final hasW1 = existingWelds.any((w) => w.segmentId == s1.id);
            final hasW2 = existingWelds.any((w) => w.segmentId == s2.id);
            if (!hasW1) addWeldJoint(segmentId: s1.id, ratio: r1, weldType: updatedFit.weldType);
            if (!hasW2) addWeldJoint(segmentId: s2.id, ratio: r2, weldType: updatedFit.weldType);
          }
        } else if (targetCount == 0) {
          for (final w in existingWelds) {
            weldJoints.remove(w.id);
          }
        }
      }
    }

    recalculateSpools();
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
    final branchSegId = 'seg_branch_${DateTime.now().millisecondsSinceEpoch}';
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

      // 1 угловой шов У18 на ответвлении
      addWeldJoint(segmentId: branchSegId, ratio: 0.0, weldType: WeldType.u18);
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

      // 3 стыковых шва С17
      addWeldJoint(segmentId: hostSegA.id, ratio: 1.0, weldType: WeldType.c17);
      addWeldJoint(segmentId: '${hostSegmentId}_b', ratio: 0.0, weldType: WeldType.c17);
      addWeldJoint(segmentId: branchSegId, ratio: 0.0, weldType: WeldType.c17);
    }

    recalculateSpools();
    return fit;
  }

  /// Автоматическое определение фитингов (отводов, тройников, крестовин) во всех узлах сети
  void autoDetectAllFittings() {
    for (final nodeId in nodes.keys.toList()) {
      _autoDetectFittingsForNode(nodeId);
    }
  }

  /// Автоматическое определение фитингов (отводов, тройников, крестовин) в узле
  void _autoDetectFittingsForNode(String nodeId) {
    // Если фитинг уже вручную настроен (прямая врезка, фланец), сохраняем его
    final existingFit = fittings[nodeId];
    if (existingFit != null &&
        (existingFit.fittingType == FittingType.directBranch ||
            existingFit.fittingType == FittingType.flange)) {
      return;
    }

    final connected = getConnectedSegments(nodeId);
    if (connected.length < 2) {
      if (existingFit != null && existingFit.fittingType != FittingType.flange) {
        fittings.remove(nodeId);
      }
      return;
    }

    if (connected.length == 2) {
      final s1 = connected[0];
      final s2 = connected[1];
      final nCenter = nodes[nodeId]!;
      final n1 = nodes[s1.startNodeId == nodeId ? s1.endNodeId : s1.startNodeId]!;
      final n2 = nodes[s2.startNodeId == nodeId ? s2.endNodeId : s2.startNodeId]!;

      // Векторы направлений от узла
      final v1x = n1.x - nCenter.x;
      final v1y = n1.y - nCenter.y;
      final v1z = n1.z - nCenter.z;
      final len1 = math.sqrt(v1x * v1x + v1y * v1y + v1z * v1z);

      final v2x = n2.x - nCenter.x;
      final v2y = n2.y - nCenter.y;
      final v2z = n2.z - nCenter.z;
      final len2 = math.sqrt(v2x * v2x + v2y * v2y + v2z * v2z);

      if (len1 > 0 && len2 > 0) {
        final cosAngle = ((v1x * v2x + v1y * v2y + v1z * v2z) / (len1 * len2)).clamp(-1.0, 1.0);
        final angleDeg = math.acos(cosAngle) * 180.0 / math.pi;
        final bendAngleDeg = 180.0 - angleDeg;

        if (bendAngleDeg >= 12.0 && bendAngleDeg <= 168.0) {
          // Это поворот трассы — создаем отвод или сохраняем пользовательский
          final targetType = (bendAngleDeg >= 25.0 && bendAngleDeg < 65.0)
              ? FittingType.elbow45
              : FittingType.elbow90;

          if (existingFit != null &&
              (existingFit.fittingType == targetType || existingFit.customRadiusMm != null)) {
            // Отвод уже существует и настроен — сохраняем его
            if (existingFit.dn != s1.dn) {
              fittings[nodeId] = existingFit.copyWith(dn: s1.dn);
            }
            return;
          }

          if (bendAngleDeg >= 65.0 && bendAngleDeg <= 115.0) {
            final def = catalog.getDefinition(catalog.defaultElbowId);
            final rad = def != null ? def.calculateDeduction(s1.dn) : (s1.dn * 1.5);
            fittings[nodeId] = Fitting(
              id: 'fit_$nodeId',
              nodeId: nodeId,
              fittingType: FittingType.elbow90,
              definitionId: def?.id,
              name: def?.name ?? 'Отвод 90° Ду${s1.dn}',
              standard: def?.standard ?? 'ГОСТ 17375-2001',
              material: s1.material,
              weldType: def?.weldType ?? WeldType.c17,
              dn: s1.dn,
              radiusMm: rad,
              customRadiusMm: def?.fixedLengthMm ?? (def?.radiusFactor != null ? def!.radiusFactor! * s1.dn : null),
            );
          } else if (bendAngleDeg >= 25.0 && bendAngleDeg < 65.0) {
            final def = catalog.getDefinition('elbow45_gost_17375');
            final rad = def != null ? def.calculateDeduction(s1.dn) : (s1.dn * 0.625);
            fittings[nodeId] = Fitting(
              id: 'fit_$nodeId',
              nodeId: nodeId,
              fittingType: FittingType.elbow45,
              definitionId: def?.id,
              name: def?.name ?? 'Отвод 45° Ду${s1.dn}',
              standard: def?.standard ?? 'ГОСТ 17375-2001',
              material: s1.material,
              weldType: def?.weldType ?? WeldType.c17,
              dn: s1.dn,
              radiusMm: rad,
              customRadiusMm: def?.fixedLengthMm ?? (def?.radiusFactor != null ? def!.radiusFactor! * s1.dn : null),
            );
          } else {
            // Другой угол поворота (косой/секторный)
            final def = catalog.getDefinition(catalog.defaultElbowId);
            final rad = def != null ? def.calculateDeduction(s1.dn) : (s1.dn * 1.5);
            fittings[nodeId] = Fitting(
              id: 'fit_$nodeId',
              nodeId: nodeId,
              fittingType: FittingType.elbow90,
              definitionId: def?.id,
              name: 'Отвод ${bendAngleDeg.round()}° Ду${s1.dn}',
              standard: def?.standard ?? 'ГОСТ 17375-2001',
              material: s1.material,
              weldType: def?.weldType ?? WeldType.c17,
              dn: s1.dn,
              radiusMm: rad,
              customRadiusMm: def?.fixedLengthMm ?? (def?.radiusFactor != null ? def!.radiusFactor! * s1.dn : null),
            );
          }
        } else if (s1.dn != s2.dn) {
          // Прямой переход диаметров
          fittings[nodeId] = Fitting(
            id: 'fit_$nodeId',
            nodeId: nodeId,
            fittingType: FittingType.reducerConcentric,
            name: 'Переход ${s1.dn}х${s2.dn}',
            standard: 'ГОСТ 17378-2001',
            material: s1.material,
            weldType: WeldType.c17,
            dn: s1.dn,
            dnSecondary: s2.dn,
            radiusMm: s1.dn * 1.5,
          );
        } else {
          // Прямая неразрывная труба без изменения диаметра
          if (existingFit != null && existingFit.fittingType != FittingType.flange) {
            fittings.remove(nodeId);
          }
        }
      }
    } else if (connected.length == 3) {
      if (existingFit != null &&
          (existingFit.fittingType == FittingType.tee ||
              existingFit.fittingType == FittingType.directBranch)) {
        return;
      }

      final def = catalog.getDefinition(catalog.defaultBranchId);
      final isDirect = def?.fittingType == FittingType.directBranch;

      // Определение проходного и ответвленного диаметров тройника
      final dns = connected.map((s) => s.dn).toList()..sort();
      final mainDn = dns[1];
      final branchDn = dns.first != dns.last ? (dns[0] == dns[1] ? dns[2] : dns[0]) : mainDn;
      final isReducing = branchDn != mainDn;

      if (isDirect) {
        fittings[nodeId] = Fitting(
          id: 'fit_$nodeId',
          nodeId: nodeId,
          fittingType: FittingType.directBranch,
          definitionId: def?.id,
          name: def?.name ?? 'Прямая врезка Ду$branchDn в Ду$mainDn',
          standard: def?.standard ?? 'ГОСТ 16037-80 У18',
          material: connected[0].material,
          weldType: WeldType.u18,
          dn: mainDn,
          dnSecondary: branchDn,
          radiusMm: 0.0,
          cutsMainPipe: false,
        );
      } else {
        fittings[nodeId] = Fitting(
          id: 'fit_$nodeId',
          nodeId: nodeId,
          fittingType: FittingType.tee,
          definitionId: def?.id,
          name: isReducing ? 'Тройник переходной $mainDnх$branchDn' : 'Тройник равнопроходный Ду$mainDn',
          standard: def?.standard ?? 'ГОСТ 17376-2001',
          material: connected[0].material,
          weldType: WeldType.c17,
          dn: mainDn,
          dnSecondary: branchDn,
          radiusMm: mainDn * 1.0,
          cutsMainPipe: true,
        );
      }
    } else if (connected.length >= 4) {
      final s = connected[0];
      fittings[nodeId] = Fitting(
        id: 'fit_$nodeId',
        nodeId: nodeId,
        fittingType: FittingType.cross,
        name: 'Крестовина Ду${s.dn}',
        standard: 'ГОСТ',
        material: s.material,
        dn: s.dn,
        radiusMm: s.dn * 1.0,
      );
    }
  }

  /// 6. Пересчет длин катушек (трубных заготовок) для всей сети
  /// Вычитает строительные длины отводов, задвижек, затворов и сварочные зазоры
  void recalculateSpools() {
    autoDetectAllFittings();
    spools.clear();
    int spoolCounter = 1;

    for (final seg in segments.values) {
      final start = nodes[seg.startNodeId];
      final end = nodes[seg.endNodeId];
      if (start == null || end == null) continue;

      final totalLen = start.distanceTo(end);

      // Сварные стыки на этом сегменте
      final segWelds = weldJoints.values
          .where((w) => w.segmentId == seg.id)
          .toList()
        ..sort((a, b) => a.ratio.compareTo(b.ratio));

      // Проходная арматура на этом сегменте
      final segValves = valves.values
          .where((v) => v.segmentId == seg.id && v.valveType.isInline)
          .toList()
        ..sort((a, b) => a.ratio.compareTo(b.ratio));

      // Вычеты фитингов на концах
      double startDeduction = 0.0;
      final startFit = fittings[seg.startNodeId];
      if (startFit != null) {
        if (startFit.fittingType == FittingType.directBranch) {
          // Для прямой врезки вычет из магистрали = 0!
          startDeduction = 0.0;
        } else if (startFit.buildingLengthMm != null && startFit.buildingLengthMm! > 0) {
          startDeduction = startFit.buildingLengthMm! / 2.0;
        } else {
          startDeduction = startFit.effectiveRadiusMm;
        }
      }

      double endDeduction = 0.0;
      final endFit = fittings[seg.endNodeId];
      if (endFit != null) {
        if (endFit.fittingType == FittingType.directBranch) {
          endDeduction = 0.0;
        } else if (endFit.buildingLengthMm != null && endFit.buildingLengthMm! > 0) {
          endDeduction = endFit.buildingLengthMm! / 2.0;
        } else {
          endDeduction = endFit.effectiveRadiusMm;
        }
      }

      if (segWelds.isEmpty && segValves.isEmpty) {
        // Одиночная катушка на весь участок
        final cutLen = math.max(0.0, totalLen - startDeduction - endDeduction);
        final spoolId = 'spool_${seg.id}_1';
        spools[spoolId] = PipeSpool(
          id: spoolId,
          segmentId: seg.id,
          number: 'К-$spoolCounter',
          cutLengthMm: cutLen,
          dn: seg.dn,
          wallThickness: seg.wallThicknessMm,
          material: seg.material,
        );
        spoolCounter++;
      } else {
        // Разбиение на подкатушки между швами и арматурой
        final points = <double>[0.0];
        for (final w in segWelds) {
          points.add(w.ratio);
        }
        for (final v in segValves) {
          final halfRatio = (v.lengthMm / 2.0) / math.max(totalLen, 1.0);
          points.add((v.ratio - halfRatio).clamp(0.0, 1.0));
          points.add((v.ratio + halfRatio).clamp(0.0, 1.0));
        }
        points.add(1.0);
        points.sort();

        // Удаляем дубликаты
        final uniquePoints = <double>[];
        for (final p in points) {
          if (uniquePoints.isEmpty || (p - uniquePoints.last).abs() > 0.001) {
            uniquePoints.add(p);
          }
        }

        for (int i = 0; i < uniquePoints.length - 1; i++) {
          final p1 = uniquePoints[i];
          final p2 = uniquePoints[i + 1];
          final rawSegmentLen = (p2 - p1) * totalLen;

          // Проверяем, не попадает ли интервал внутрь корпуса арматуры
          bool insideValve = false;
          for (final v in segValves) {
            final halfRatio = (v.lengthMm / 2.0) / math.max(totalLen, 1.0);
            if (p1 >= v.ratio - halfRatio - 0.001 && p2 <= v.ratio + halfRatio + 0.001) {
              insideValve = true;
              break;
            }
          }
          if (insideValve) continue;

          double deduction = 0.0;
          if (i == 0) deduction += startDeduction;
          if (i == uniquePoints.length - 2) deduction += endDeduction;

          final cutLen = math.max(0.0, rawSegmentLen - deduction);
          if (cutLen > 1.0) {
            final spoolId = 'spool_${seg.id}_${i + 1}';
            spools[spoolId] = PipeSpool(
              id: spoolId,
              segmentId: seg.id,
              number: 'К-$spoolCounter',
              cutLengthMm: cutLen,
              dn: seg.dn,
              wallThickness: seg.wallThicknessMm,
              material: seg.material,
            );
            spoolCounter++;
          }
        }
      }
    }
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
      catalog: catalog,
      pipeCatalog: pipeCatalog,
    );
    return net;
  }
}
