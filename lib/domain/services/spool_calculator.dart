import 'dart:math' as math;
import '../models/piping_network.dart';
import '../models/pipe_spool.dart';
import '../models/pipe_segment.dart';
import '../models/node_3d.dart';
import '../enums/fitting_type.dart';
import '../enums/valve_type.dart';

class SpoolCalculator {
  static void recalculateSpools(PipingNetwork network) {
    network.autoDetectAllFittings();
    final previousSpoolData = <String, (String?, String?)>{};
    for (final sp in network.spools.values) {
      previousSpoolData[sp.id] = (sp.name, sp.serialNumber);
    }
    network.spools.clear();
    int spoolCounter = 1;

    // 1. Находим сквозные соединения через прямые врезки (FittingType.directBranch),
    // где магистральная труба не режется (cutsMainPipe == false).
    final throughAdj = <String, Set<String>>{};
    for (final fit in network.fittings.values) {
      if (fit.fittingType != FittingType.directBranch) continue;
      final conn = network.getConnectedSegments(fit.nodeId);
      if (conn.length != 3) continue;

      final branchSeg = network.identifyBranchSegment(fit.nodeId, conn);
      final mainSegs = conn.where((s) => s.id != branchSeg?.id).toList();
      if (mainSegs.length != 2) continue;

      final sA = mainSegs[0];
      final sB = mainSegs[1];

      // Магистраль должна быть одного диаметра, толщины стенки и материала
      if (sA.dn != sB.dn ||
          sA.material != sB.material ||
          (sA.wallThicknessMm - sB.wallThicknessMm).abs() > 0.01) {
        continue;
      }

      // Проверяем отсутствие стыковых сварных швов в узле врезки между sA и sB
      final hasButtWeld = network.weldJoints.values.any((w) {
        final rA = sA.startNodeId == fit.nodeId ? 0.0 : 1.0;
        final rB = sB.startNodeId == fit.nodeId ? 0.0 : 1.0;
        return (w.segmentId == sA.id && (w.ratio - rA).abs() < 0.05) ||
            (w.segmentId == sB.id && (w.ratio - rB).abs() < 0.05);
      });
      if (hasButtWeld) continue;

      throughAdj.putIfAbsent(sA.id, () => <String>{}).add(sB.id);
      throughAdj.putIfAbsent(sB.id, () => <String>{}).add(sA.id);
    }

    // 2. Группируем сегменты в непересекающиеся сквозные цепочки (ThroughRuns)
    final visited = <String>{};
    final chains = <List<PipeSegment>>[];

    for (final seg in network.segments.values) {
      if (visited.contains(seg.id)) continue;

      if (!throughAdj.containsKey(seg.id)) {
        // Одиночный сегмент без сквозных врезок
        visited.add(seg.id);
        chains.add([seg]);
        continue;
      }

      // Находим все сегменты в этой связанной компоненте
      final componentSegIds = <String>{};
      final queue = <String>[seg.id];
      componentSegIds.add(seg.id);
      visited.add(seg.id);

      while (queue.isNotEmpty) {
        final cur = queue.removeLast();
        for (final nxt in (throughAdj[cur] ?? const <String>{})) {
          if (!componentSegIds.contains(nxt)) {
            componentSegIds.add(nxt);
            visited.add(nxt);
            queue.add(nxt);
          }
        }
      }

      // Находим концы цепочки (сегменты с степенью связности 1 в подграфе сквозных врезок)
      String? startSegId;
      for (final id in componentSegIds) {
        final deg = throughAdj[id]?.where((n) => componentSegIds.contains(n)).length ?? 0;
        if (deg <= 1) {
          startSegId = id;
          break;
        }
      }
      startSegId ??= componentSegIds.first;

      // Выстраиваем сегменты цепочки в упорядоченный список
      final orderedChain = <PipeSegment>[];
      String? curId = startSegId;
      String? prevId;
      while (curId != null) {
        orderedChain.add(network.segments[curId]!);
        final neighbors = throughAdj[curId]?.where((n) => componentSegIds.contains(n)).toList() ?? [];
        String? nextId;
        for (final n in neighbors) {
          if (n != prevId) {
            nextId = n;
            break;
          }
        }
        prevId = curId;
        curId = nextId;
      }

      chains.add(orderedChain);
    }

    // 3. Вычисляем катушки для каждой цепочки
    for (final chain in chains) {
      if (chain.length == 1) {
        final seg = chain.first;
        final start = network.nodes[seg.startNodeId];
        final end = network.nodes[seg.endNodeId];
        if (start == null || end == null) continue;
        final totalLen = start.distanceTo(end);
        final startDeduction = getFittingDeduction(
          network,
          seg.startNodeId,
          segmentId: seg.id,
          isDirectBranch: _isDirectBranchRun(network, seg.startNodeId, seg.id),
        );
        final endDeduction = getFittingDeduction(
          network,
          seg.endNodeId,
          segmentId: seg.id,
          isDirectBranch: _isDirectBranchRun(network, seg.endNodeId, seg.id),
        );
        final startVisualDeduction = _getVisualFittingDeduction(
          network,
          seg.startNodeId,
          segmentId: seg.id,
          isDirectBranch: _isDirectBranchRun(network, seg.startNodeId, seg.id),
        );
        final endVisualDeduction = _getVisualFittingDeduction(
          network,
          seg.endNodeId,
          segmentId: seg.id,
          isDirectBranch: _isDirectBranchRun(network, seg.endNodeId, seg.id),
        );

        final segWelds = network.weldJoints.values
            .where((w) => w.segmentId == seg.id)
            .toList()
          ..sort((a, b) => a.ratio.compareTo(b.ratio));

        final segValves = network.valves.values
            .where((v) => v.segmentId == seg.id && v.valveType.isInline)
            .toList()
          ..sort((a, b) => a.ratio.compareTo(b.ratio));

        if (network.isButtJoint(seg.id)) {
          // Стык элементов встык: между элементами физической трубы (катушки) нет!
          continue;
        }

        if (segWelds.isEmpty && segValves.isEmpty) {
          final cutLen = math.max(0.0, totalLen - startDeduction - endDeduction);
          if (cutLen > 1.0) {
            final spoolId = 'spool_${seg.id}_1';
            final uX = totalLen > 0 ? (end.x - start.x) / totalLen : 0.0;
            final uY = totalLen > 0 ? (end.y - start.y) / totalLen : 0.0;
            final uZ = totalLen > 0 ? (end.z - start.z) / totalLen : 0.0;
            final ptStart = Node3D(
              id: '',
              x: start.x + uX * startVisualDeduction,
              y: start.y + uY * startVisualDeduction,
              z: start.z + uZ * startVisualDeduction,
            );
            final ptEnd = Node3D(
              id: '',
              x: start.x + uX * (totalLen - endVisualDeduction),
              y: start.y + uY * (totalLen - endVisualDeduction),
              z: start.z + uZ * (totalLen - endVisualDeduction),
            );
            final prev = previousSpoolData[spoolId];
            network.spools[spoolId] = PipeSpool(
              id: spoolId,
              segmentId: seg.id,
              number: 'К-$spoolCounter',
              cutLengthMm: cutLen,
              dn: seg.dn,
              wallThickness: seg.wallThicknessMm,
              material: seg.material,
              startPoint: ptStart,
              endPoint: ptEnd,
              name: prev?.$1,
              serialNumber: prev?.$2,
            );
            spoolCounter++;
          }
        } else {
          spoolCounter = _generateSubSpoolsForSingle(
            network: network,
            seg: seg,
            totalLen: totalLen,
            startDeduction: startDeduction,
            endDeduction: endDeduction,
            startVisualDeduction: startVisualDeduction,
            endVisualDeduction: endVisualDeduction,
            segWelds: segWelds,
            segValves: segValves,
            spoolCounter: spoolCounter,
            previousSpoolData: previousSpoolData,
          );
        }
      } else {
        // Составная сквозная цепочка (несколько сегментов магистрали через прямые врезки)
        spoolCounter = _generateSpoolsForThroughChain(
          network: network,
          chain: chain,
          spoolCounter: spoolCounter,
          previousSpoolData: previousSpoolData,
        );
      }
    }
  }

  static bool _isDirectBranchRun(PipingNetwork network, String nodeId, String segId) {
    final fit = network.fittings[nodeId];
    if (fit == null || fit.fittingType != FittingType.directBranch) return false;
    final conn = network.getConnectedSegments(nodeId);
    if (conn.length != 3) return false;
    final branch = network.identifyBranchSegment(nodeId, conn);
    return branch?.id != segId;
  }

  static double getFittingDeduction(
    PipingNetwork network,
    String nodeId, {
    bool isDirectBranch = false,
    String? segmentId,
  }) {
    if (isDirectBranch) return 0.0;
    final fit = network.fittings[nodeId];
    if (fit == null) return 0.0;

    if (fit.fittingType == FittingType.directBranch) {
      if (segmentId != null) {
        final conn = network.getConnectedSegments(nodeId);
        final branch = network.identifyBranchSegment(nodeId, conn);
        if (branch?.id == segmentId) {
          // Сегмент ответвления: заготовительный вычет равен наружному радиусу магистрали D_нар / 2
          final runSeg = conn.firstWhere(
            (s) => s.id != segmentId,
            orElse: () => network.segments[segmentId]!,
          );
          final dim = network.pipeCatalog.getDimension(runSeg.dn);
          final outerMm = dim?.outerDiameterMm ?? (runSeg.dn.toDouble());
          return outerMm / 2.0;
        }
      }
      return 0.0; // Магистральная труба не режется и не укорачивается
    }

    if (fit.fittingType == FittingType.tee) {
      if (segmentId != null) {
        final conn = network.getConnectedSegments(nodeId);
        final branch = network.identifyBranchSegment(nodeId, conn);
        if (branch?.id == segmentId) {
          return fit.effectiveBranchLengthMm;
        } else {
          return (fit.buildingLengthMm != null && fit.buildingLengthMm! > 0)
              ? fit.buildingLengthMm! / 2.0
              : fit.dn * 1.0;
        }
      }
      return (fit.buildingLengthMm != null && fit.buildingLengthMm! > 0)
          ? fit.buildingLengthMm! / 2.0
          : fit.dn * 1.0;
    }

    if (fit.fittingType == FittingType.flange) {
      if (fit.buildingLengthMm != null && fit.buildingLengthMm! > 0) {
        return fit.buildingLengthMm!;
      }
      return fit.effectiveBuildingLengthMm;
    }
    if (fit.buildingLengthMm != null && fit.buildingLengthMm! > 0) {
      return fit.buildingLengthMm! / 2.0;
    }
    if (fit.fittingType == FittingType.cap) {
      return 0.0; // Заглушка (днище) приваривается к торцу трубы в узле, вычет из длины трубы = 0
    }
    if (fit.fittingType == FittingType.reducerConcentric || fit.fittingType == FittingType.reducerEccentric) {
      return fit.effectiveBuildingLengthMm / 2.0;
    }
    if (fit.fittingType == FittingType.elbow90 || fit.fittingType == FittingType.elbow45) {
      return network.getElbowTangentMm(nodeId);
    }
    return fit.effectiveRadiusMm;
  }

  /// Получение вычета для визуального отображения геометрии катушки на чертеже
  static double _getVisualFittingDeduction(
    PipingNetwork network,
    String nodeId, {
    bool isDirectBranch = false,
    String? segmentId,
  }) {
    if (isDirectBranch) return 0.0;
    final fit = network.fittings[nodeId];
    if (fit == null) return 0.0;

    // Прямая врезка: на чертеже труба ответвления визуально чертится строго до оси магистрали (узла) без пустоты
    if (fit.fittingType == FittingType.directBranch) {
      return 0.0;
    }

    return getFittingDeduction(network, nodeId, isDirectBranch: isDirectBranch, segmentId: segmentId);
  }

  static int _generateSubSpoolsForSingle({
    required PipingNetwork network,
    required PipeSegment seg,
    required double totalLen,
    required double startDeduction,
    required double endDeduction,
    required List<dynamic> segWelds,
    required List<dynamic> segValves,
    required int spoolCounter,
    required Map<String, (String?, String?)> previousSpoolData,
    double? startVisualDeduction,
    double? endVisualDeduction,
  }) {
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

    final uniquePoints = <double>[];
    for (final p in points) {
      if (uniquePoints.isEmpty || (p - uniquePoints.last).abs() > 0.001) {
        uniquePoints.add(p);
      }
    }

    final start = network.nodes[seg.startNodeId];
    final end = network.nodes[seg.endNodeId];
    if (start == null || end == null) {
      return spoolCounter;
    }
    final uX = totalLen > 0 ? (end.x - start.x) / totalLen : 0.0;
    final uY = totalLen > 0 ? (end.y - start.y) / totalLen : 0.0;
    final uZ = totalLen > 0 ? (end.z - start.z) / totalLen : 0.0;

    final sVisD = startVisualDeduction ?? startDeduction;
    final eVisD = endVisualDeduction ?? endDeduction;

    for (int i = 0; i < uniquePoints.length - 1; i++) {
      final p1 = uniquePoints[i];
      final p2 = uniquePoints[i + 1];

      bool insideValve = false;
      for (final v in segValves) {
        final halfRatio = (v.lengthMm / 2.0) / math.max(totalLen, 1.0);
        if (p1 >= v.ratio - halfRatio - 0.001 && p2 <= v.ratio + halfRatio + 0.001) {
          insideValve = true;
          break;
        }
      }
      if (insideValve) continue;

      double dStart = p1 * totalLen;
      double dEnd = p2 * totalLen;
      double dStartVisual = p1 * totalLen;
      double dEndVisual = p2 * totalLen;
      if (i == 0) {
        dStart += startDeduction;
        dStartVisual += sVisD;
      }
      if (i == uniquePoints.length - 2) {
        dEnd -= endDeduction;
        dEndVisual -= eVisD;
      }

      final cutLen = math.max(0.0, dEnd - dStart);
      if (cutLen > 1.0) {
        final spoolId = 'spool_${seg.id}_${i + 1}';
        final ptStart = Node3D(
          id: '',
          x: start.x + uX * dStartVisual,
          y: start.y + uY * dStartVisual,
          z: start.z + uZ * dStartVisual,
        );
        final ptEnd = Node3D(
          id: '',
          x: start.x + uX * dEndVisual,
          y: start.y + uY * dEndVisual,
          z: start.z + uZ * dEndVisual,
        );
        final prev = previousSpoolData[spoolId];
        network.spools[spoolId] = PipeSpool(
          id: spoolId,
          segmentId: seg.id,
          number: 'К-$spoolCounter',
          cutLengthMm: cutLen,
          dn: seg.dn,
          wallThickness: seg.wallThicknessMm,
          material: seg.material,
          startPoint: ptStart,
          endPoint: ptEnd,
          name: prev?.$1,
          serialNumber: prev?.$2,
        );
        spoolCounter++;
      }
    }
    return spoolCounter;
  }

  static int _generateSpoolsForThroughChain({
    required PipingNetwork network,
    required List<PipeSegment> chain,
    required int spoolCounter,
    required Map<String, (String?, String?)> previousSpoolData,
  }) {
    // Определяем ориентацию первого сегмента (какой узел внешний, какой соединяется со вторым)
    final s1 = chain[0];
    final s2 = chain[1];
    final shared1 = (s1.startNodeId == s2.startNodeId || s1.startNodeId == s2.endNodeId)
        ? s1.startNodeId
        : s1.endNodeId;
    final outerStartNodeId = (s1.startNodeId == shared1) ? s1.endNodeId : s1.startNodeId;

    // Вычисляем общую длину и смещения вдоль цепочки
    final segLengths = <double>[];
    final segReversed = <bool>[];
    String curExpectedStart = outerStartNodeId;

    for (final seg in chain) {
      final isRev = (seg.startNodeId != curExpectedStart);
      segReversed.add(isRev);
      final nStart = network.nodes[seg.startNodeId];
      final nEnd = network.nodes[seg.endNodeId];
      if (nStart == null || nEnd == null) {
        return spoolCounter;
      }
      segLengths.add(nStart.distanceTo(nEnd));
      curExpectedStart = isRev ? seg.startNodeId : seg.endNodeId;
    }

    final totalChainLen = segLengths.fold(0.0, (sum, l) => sum + l);
    if (totalChainLen <= 0.1) return spoolCounter;

    final outerEndNodeId = curExpectedStart;
    final startDeduction = getFittingDeduction(network, outerStartNodeId, segmentId: chain.first.id);
    final endDeduction = getFittingDeduction(network, outerEndNodeId, segmentId: chain.last.id);

    // Собираем все точки реза (сварные швы и арматуру) вдоль всей цепочки
    final cutDistances = <double>[0.0];
    final valveIntervals = <(double, double)>[];

    double accumDist = 0.0;
    for (int sIdx = 0; sIdx < chain.length; sIdx++) {
      final seg = chain[sIdx];
      final len = segLengths[sIdx];
      final isRev = segReversed[sIdx];

      final segWelds = network.weldJoints.values.where((w) => w.segmentId == seg.id);
      for (final w in segWelds) {
        final r = isRev ? (1.0 - w.ratio) : w.ratio;
        final d = accumDist + r * len;
        // Игнорируем швы, находящиеся прямо на внутренних стыках сквозной врезки
        if (d > 0.1 && d < totalChainLen - 0.1) {
          cutDistances.add(d);
        }
      }

      final segValves = network.valves.values.where((v) => v.segmentId == seg.id && v.valveType.isInline);
      for (final v in segValves) {
        final r = isRev ? (1.0 - v.ratio) : v.ratio;
        final cDist = accumDist + r * len;
        final half = v.lengthMm / 2.0;
        final d1 = math.max(0.0, cDist - half);
        final d2 = math.min(totalChainLen, cDist + half);
        valveIntervals.add((d1, d2));
        cutDistances.add(d1);
        cutDistances.add(d2);
      }

      accumDist += len;
    }

    cutDistances.add(totalChainLen);
    cutDistances.sort();

    final uniqueDistances = <double>[];
    for (final d in cutDistances) {
      if (uniqueDistances.isEmpty || (d - uniqueDistances.last).abs() > 0.001) {
        uniqueDistances.add(d);
      }
    }

    // Формируем катушки
    final firstSeg = chain.first;
    for (int i = 0; i < uniqueDistances.length - 1; i++) {
      final d1 = uniqueDistances[i];
      final d2 = uniqueDistances[i + 1];
      final midD = (d1 + d2) / 2.0;

      // Проверяем, не внутри арматуры ли интервал
      bool insideValve = false;
      for (final interval in valveIntervals) {
        if (d1 >= interval.$1 - 0.001 && d2 <= interval.$2 + 0.001) {
          insideValve = true;
          break;
        }
      }
      if (insideValve) continue;

      double dStart = d1;
      double dEnd = d2;
      if (i == 0) dStart += startDeduction;
      if (i == uniqueDistances.length - 2) dEnd -= endDeduction;

      final cutLen = math.max(0.0, dEnd - dStart);

      if (cutLen > 1.0) {
        // Находим сегмент, которому принадлежит середина катушки
        double acc = 0.0;
        PipeSegment repSeg = firstSeg;
        for (int sIdx = 0; sIdx < chain.length; sIdx++) {
          acc += segLengths[sIdx];
          if (midD <= acc + 0.001) {
            repSeg = chain[sIdx];
            break;
          }
        }

        final ptStart = _pointAlongChain(network, chain, segLengths, segReversed, dStart);
        final ptEnd = _pointAlongChain(network, chain, segLengths, segReversed, dEnd);

        final spoolId = 'spool_${repSeg.id}_${i + 1}';
        final prev = previousSpoolData[spoolId];
        network.spools[spoolId] = PipeSpool(
          id: spoolId,
          segmentId: repSeg.id,
          number: 'К-$spoolCounter',
          cutLengthMm: cutLen,
          dn: repSeg.dn,
          wallThickness: repSeg.wallThicknessMm,
          material: repSeg.material,
          startPoint: ptStart,
          endPoint: ptEnd,
          name: prev?.$1,
          serialNumber: prev?.$2,
        );
        spoolCounter++;
      }
    }

    return spoolCounter;
  }

  static Node3D _pointAlongChain(
    PipingNetwork network,
    List<PipeSegment> chain,
    List<double> segLengths,
    List<bool> segReversed,
    double targetDist,
  ) {
    double acc = 0.0;
    for (int i = 0; i < chain.length; i++) {
      final seg = chain[i];
      final len = segLengths[i];
      final isRev = segReversed[i];
      if (targetDist <= acc + len || i == chain.length - 1) {
        final localD = (targetDist - acc).clamp(0.0, len);
        final startNode = network.nodes[isRev ? seg.endNodeId : seg.startNodeId];
        final endNode = network.nodes[isRev ? seg.startNodeId : seg.endNodeId];
        if (startNode == null || endNode == null) {
          return startNode ?? endNode ?? Node3D(id: '', x: 0, y: 0, z: 0);
        }
        final uX = len > 0 ? (endNode.x - startNode.x) / len : 0.0;
        final uY = len > 0 ? (endNode.y - startNode.y) / len : 0.0;
        final uZ = len > 0 ? (endNode.z - startNode.z) / len : 0.0;
        return Node3D(
          id: '',
          x: startNode.x + uX * localD,
          y: startNode.y + uY * localD,
          z: startNode.z + uZ * localD,
        );
      }
      acc += len;
    }
    final lastSeg = chain.last;
    final isRev = segReversed.last;
    final lastNode = network.nodes[isRev ? lastSeg.startNodeId : lastSeg.endNodeId];
    return lastNode ?? Node3D(id: '', x: 0, y: 0, z: 0);
  }
}
