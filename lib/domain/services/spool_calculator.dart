import 'dart:math' as math;
import '../models/piping_network.dart';
import '../models/pipe_spool.dart';
import '../models/pipe_segment.dart';
import '../enums/fitting_type.dart';
import '../enums/valve_type.dart';

class SpoolCalculator {
  static void recalculateSpools(PipingNetwork network) {
    network.autoDetectAllFittings();
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
        final startDeduction = _getFittingDeduction(network, seg.startNodeId, isDirectBranch: _isDirectBranchRun(network, seg.startNodeId, seg.id));
        final endDeduction = _getFittingDeduction(network, seg.endNodeId, isDirectBranch: _isDirectBranchRun(network, seg.endNodeId, seg.id));

        final segWelds = network.weldJoints.values
            .where((w) => w.segmentId == seg.id)
            .toList()
          ..sort((a, b) => a.ratio.compareTo(b.ratio));

        final segValves = network.valves.values
            .where((v) => v.segmentId == seg.id && v.valveType.isInline)
            .toList()
          ..sort((a, b) => a.ratio.compareTo(b.ratio));

        if (segWelds.isEmpty && segValves.isEmpty) {
          final cutLen = math.max(0.0, totalLen - startDeduction - endDeduction);
          if (cutLen > 1.0) {
            final spoolId = 'spool_${seg.id}_1';
            network.spools[spoolId] = PipeSpool(
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
        } else {
          spoolCounter = _generateSubSpoolsForSingle(
            network: network,
            seg: seg,
            totalLen: totalLen,
            startDeduction: startDeduction,
            endDeduction: endDeduction,
            segWelds: segWelds,
            segValves: segValves,
            spoolCounter: spoolCounter,
          );
        }
      } else {
        // Составная сквозная цепочка (несколько сегментов магистрали через прямые врезки)
        spoolCounter = _generateSpoolsForThroughChain(
          network: network,
          chain: chain,
          spoolCounter: spoolCounter,
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

  static double _getFittingDeduction(PipingNetwork network, String nodeId, {bool isDirectBranch = false}) {
    if (isDirectBranch) return 0.0;
    final fit = network.fittings[nodeId];
    if (fit == null) return 0.0;
    if (fit.fittingType == FittingType.directBranch) return 0.0;
    if (fit.buildingLengthMm != null && fit.buildingLengthMm! > 0) {
      return fit.buildingLengthMm! / 2.0;
    }
    if (fit.fittingType == FittingType.reducerConcentric || fit.fittingType == FittingType.reducerEccentric) {
      return fit.effectiveBuildingLengthMm / 2.0;
    }
    if (fit.fittingType == FittingType.elbow90 || fit.fittingType == FittingType.elbow45) {
      return network.getElbowTangentMm(nodeId);
    }
    return fit.effectiveRadiusMm;
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

    for (int i = 0; i < uniquePoints.length - 1; i++) {
      final p1 = uniquePoints[i];
      final p2 = uniquePoints[i + 1];
      final rawSegmentLen = (p2 - p1) * totalLen;

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
        network.spools[spoolId] = PipeSpool(
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
    return spoolCounter;
  }

  static int _generateSpoolsForThroughChain({
    required PipingNetwork network,
    required List<PipeSegment> chain,
    required int spoolCounter,
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
      final nStart = network.nodes[seg.startNodeId]!;
      final nEnd = network.nodes[seg.endNodeId]!;
      segLengths.add(nStart.distanceTo(nEnd));
      curExpectedStart = isRev ? seg.startNodeId : seg.endNodeId;
    }

    final totalChainLen = segLengths.fold(0.0, (sum, l) => sum + l);
    if (totalChainLen <= 0.1) return spoolCounter;

    final outerEndNodeId = curExpectedStart;
    final startDeduction = _getFittingDeduction(network, outerStartNodeId);
    final endDeduction = _getFittingDeduction(network, outerEndNodeId);

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

      double deduction = 0.0;
      if (i == 0) deduction += startDeduction;
      if (i == uniqueDistances.length - 2) deduction += endDeduction;

      final rawLen = d2 - d1;
      final cutLen = math.max(0.0, rawLen - deduction);

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

        final spoolId = 'spool_${repSeg.id}_${i + 1}';
        network.spools[spoolId] = PipeSpool(
          id: spoolId,
          segmentId: repSeg.id,
          number: 'К-$spoolCounter',
          cutLengthMm: cutLen,
          dn: repSeg.dn,
          wallThickness: repSeg.wallThicknessMm,
          material: repSeg.material,
        );
        spoolCounter++;
      }
    }

    return spoolCounter;
  }
}
