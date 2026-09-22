import 'dart:math' as math;
import 'package:uuid/uuid.dart';

import '../models/node_3d.dart';
import '../models/pipe_segment.dart';
import '../models/piping_network.dart';

/// Сервис топологических операций и анализа связности сети трубопроводов
class TopologyService {
  static const _uuid = Uuid();

  /// Получение списка сегментов, подключенных к заданному узлу
  static List<PipeSegment> getConnectedSegments(PipingNetwork network, String nodeId) {
    return network.segments.values
        .where((s) => s.startNodeId == nodeId || s.endNodeId == nodeId)
        .toList();
  }

  /// Определение сегмента ответвления среди 3 подключенных к узлу сегментов.
  /// Ответвлением считается сегмент, не лежащий на одной прямой с двумя остальными (магистралью).
  static PipeSegment? identifyBranchSegment(
    PipingNetwork network,
    String nodeId, [
    List<PipeSegment>? connectedSegments,
  ]) {
    final conn = connectedSegments ?? getConnectedSegments(network, nodeId);
    if (conn.length != 3) return null;

    final nCenter = network.nodes[nodeId];
    if (nCenter == null) return null;

    final dirsX = <double>[];
    final dirsY = <double>[];
    final dirsZ = <double>[];

    for (final seg in conn) {
      final otherId = seg.startNodeId == nodeId ? seg.endNodeId : seg.startNodeId;
      final other = network.nodes[otherId];
      if (other == null) {
        dirsX.add(0.0);
        dirsY.add(0.0);
        dirsZ.add(0.0);
        continue;
      }
      final dx = other.x - nCenter.x;
      final dy = other.y - nCenter.y;
      final dz = other.z - nCenter.z;
      final len = math.sqrt(dx * dx + dy * dy + dz * dz);
      if (len > 0.0001) {
        dirsX.add(dx / len);
        dirsY.add(dy / len);
        dirsZ.add(dz / len);
      } else {
        dirsX.add(0.0);
        dirsY.add(0.0);
        dirsZ.add(0.0);
      }
    }

    double minDot = 1.0;
    int best1 = 0;
    int best2 = 1;

    for (int i = 0; i < 3; i++) {
      for (int j = i + 1; j < 3; j++) {
        final dot = dirsX[i] * dirsX[j] + dirsY[i] * dirsY[j] + dirsZ[i] * dirsZ[j];
        if (dot < minDot) {
          minDot = dot;
          best1 = i;
          best2 = j;
        }
      }
    }

    for (int i = 0; i < 3; i++) {
      if (i != best1 && i != best2) {
        return conn[i];
      }
    }
    return conn.last;
  }

  /// Разделение сегмента трубы на два участка в точке ratio (0.0 < ratio < 1.0)
  /// Создает промежуточный узел и переносит привязанные стыки, арматуру, опоры и выноски.
  static Node3D? splitSegmentAtRatio(
    PipingNetwork network,
    String segmentId,
    double ratio, {
    String Function()? idGenerator,
  }) {
    final oldSeg = network.segments[segmentId];
    if (oldSeg == null) return null;
    final startNode = network.nodes[oldSeg.startNodeId];
    final endNode = network.nodes[oldSeg.endNodeId];
    if (startNode == null || endNode == null) return null;

    final midX = startNode.x + (endNode.x - startNode.x) * ratio;
    final midY = startNode.y + (endNode.y - startNode.y) * ratio;
    final midZ = startNode.z + (endNode.z - startNode.z) * ratio;

    final gen = idGenerator ?? () => _uuid.v4();
    final midNodeId = 'node_${gen()}';
    final midNode = Node3D(id: midNodeId, x: midX, y: midY, z: midZ);
    network.nodes[midNodeId] = midNode;

    network.segments.remove(segmentId);

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

    network.segments[seg1Id] = seg1;
    network.segments[seg2Id] = seg2;

    // Переносим существующие сварные швы на новые сегменты
    final affectedWelds = network.weldJoints.values.where((w) => w.segmentId == segmentId).toList();
    for (final w in affectedWelds) {
      network.weldJoints.remove(w.id);
      if (w.ratio <= ratio) {
        final newRatio = ratio > 0.0001 ? (w.ratio / ratio).clamp(0.0, 1.0) : 0.0;
        network.weldJoints[w.id] = w.copyWith(segmentId: seg1Id, ratio: newRatio);
      } else {
        final newRatio = (1.0 - ratio) > 0.0001 ? ((w.ratio - ratio) / (1.0 - ratio)).clamp(0.0, 1.0) : 0.0;
        network.weldJoints[w.id] = w.copyWith(segmentId: seg2Id, ratio: newRatio);
      }
    }

    // Переносим арматуру
    final affectedValves = network.valves.values.where((v) => v.segmentId == segmentId).toList();
    for (final v in affectedValves) {
      network.valves.remove(v.id);
      if (v.ratio <= ratio) {
        final newRatio = ratio > 0.0001 ? (v.ratio / ratio).clamp(0.05, 0.95) : 0.5;
        network.valves[v.id] = v.copyWith(segmentId: seg1Id, ratio: newRatio);
      } else {
        final newRatio = (1.0 - ratio) > 0.0001 ? ((v.ratio - ratio) / (1.0 - ratio)).clamp(0.05, 0.95) : 0.5;
        network.valves[v.id] = v.copyWith(segmentId: seg2Id, ratio: newRatio);
      }
    }

    // Переносим опоры и подвески
    final affectedSupports = network.supports.values.where((s) => s.segmentId == segmentId).toList();
    for (final s in affectedSupports) {
      network.supports.remove(s.id);
      if (s.distanceRatio <= ratio) {
        final newRatio = ratio > 0.0001 ? (s.distanceRatio / ratio).clamp(0.0, 1.0) : 0.0;
        network.supports[s.id] = s.copyWith(segmentId: seg1Id, distanceRatio: newRatio);
      } else {
        final newRatio = (1.0 - ratio) > 0.0001 ? ((s.distanceRatio - ratio) / (1.0 - ratio)).clamp(0.0, 1.0) : 0.0;
        network.supports[s.id] = s.copyWith(segmentId: seg2Id, distanceRatio: newRatio);
      }
    }

    // Обновляем целевой сегмент для выносок
    final affectedCallouts = network.callouts.values.where((c) => c.targetId == segmentId).toList();
    for (final c in affectedCallouts) {
      network.callouts[c.id] = c.copyWith(targetId: seg1Id);
    }

    return midNode;
  }

  /// Каскадный сдвиг подключенных участков сети
  static void cascadeShift(
    PipingNetwork network,
    String currentNodeId,
    double dx,
    double dy,
    double dz,
    Set<String> visited,
  ) {
    visited.add(currentNodeId);
    final node = network.nodes[currentNodeId];
    if (node != null) {
      network.nodes[currentNodeId] = node.copyWith(
        x: node.x + dx,
        y: node.y + dy,
        z: node.z + dz,
      );
    }

    for (final s in getConnectedSegments(network, currentNodeId)) {
      final nextNodeId = s.startNodeId == currentNodeId ? s.endNodeId : s.startNodeId;
      if (!visited.contains(nextNodeId)) {
        cascadeShift(network, nextNodeId, dx, dy, dz, visited);
      }
    }
  }

  /// Поиск всех связанных узлов в компоненте связности
  static Set<String> findConnectedComponent(PipingNetwork network, String startNodeId) {
    final visited = <String>{};
    final queue = <String>[startNodeId];

    while (queue.isNotEmpty) {
      final cur = queue.removeLast();
      if (!visited.add(cur)) continue;

      for (final s in getConnectedSegments(network, cur)) {
        final next = s.startNodeId == cur ? s.endNodeId : s.startNodeId;
        if (!visited.contains(next)) {
          queue.add(next);
        }
      }
    }

    return visited;
  }

  /// Проверка, лежат ли два сегмента на одной прямой (коллинеарны)
  static bool areSegmentsCollinear(PipingNetwork network, PipeSegment s1, PipeSegment s2) {
    final n1A = network.nodes[s1.startNodeId];
    final n1B = network.nodes[s1.endNodeId];
    final n2A = network.nodes[s2.startNodeId];
    final n2B = network.nodes[s2.endNodeId];

    if (n1A == null || n1B == null || n2A == null || n2B == null) return false;

    final d1X = n1B.x - n1A.x;
    final d1Y = n1B.y - n1A.y;
    final d1Z = n1B.z - n1A.z;
    final len1 = math.sqrt(d1X * d1X + d1Y * d1Y + d1Z * d1Z);

    final d2X = n2B.x - n2A.x;
    final d2Y = n2B.y - n2A.y;
    final d2Z = n2B.z - n2A.z;
    final len2 = math.sqrt(d2X * d2X + d2Y * d2Y + d2Z * d2Z);

    if (len1 < 1e-4 || len2 < 1e-4) return false;

    final dot = (d1X * d2X + d1Y * d2Y + d1Z * d2Z) / (len1 * len2);
    return (dot.abs() - 1.0).abs() < 0.01;
  }

  /// Удаление узла со сращиванием примыкающих труб (Dissolve Node / Merge Pipes)
  /// - При 2 примыкающих сегментах: объединяет их в один сегмент, переносит арматуру, стыки, опоры и выноски.
  /// - При 3 примыкающих сегментах (тройник): удаляет ответвление и сращивает две трубы магистрали.
  /// - При 1 примыкающем сегменте: удаляет узел и этот сегмент.
  /// - При 0 сегментах: просто удаляет узел.
  static bool dissolveNode(PipingNetwork network, String nodeId) {
    final node = network.nodes[nodeId];
    if (node == null) return false;

    final connected = getConnectedSegments(network, nodeId);

    if (connected.isEmpty) {
      network.fittings.remove(nodeId);
      network.nodes.remove(nodeId);
      network.callouts.removeWhere((_, c) => c.targetId == nodeId);
      network.dimensions.removeWhere((_, d) => d.startNodeId == nodeId || d.endNodeId == nodeId);
      return true;
    }

    if (connected.length == 1) {
      final seg = connected.first;
      network.segments.remove(seg.id);
      network.valves.removeWhere((_, v) => v.segmentId == seg.id);
      network.weldJoints.removeWhere((_, w) => w.segmentId == seg.id);
      network.supports.removeWhere((_, s) => s.segmentId == seg.id);
      network.callouts.removeWhere((_, c) => c.targetId == seg.id);
      network.dimensions.removeWhere((_, d) => d.startNodeId == nodeId || d.endNodeId == nodeId);
      network.fittings.remove(nodeId);
      network.nodes.remove(nodeId);
      network.callouts.removeWhere((_, c) => c.targetId == nodeId);
      network.autoDetectAllFittings();
      network.recalculateSpools();
      return true;
    }

    if (connected.length == 3) {
      final branchSeg = identifyBranchSegment(network, nodeId, connected);
      if (branchSeg != null) {
        network.segments.remove(branchSeg.id);
        network.valves.removeWhere((_, v) => v.segmentId == branchSeg.id);
        network.weldJoints.removeWhere((_, w) => w.segmentId == branchSeg.id);
        network.supports.removeWhere((_, s) => s.segmentId == branchSeg.id);
        network.callouts.removeWhere((_, c) => c.targetId == branchSeg.id);
        connected.removeWhere((s) => s.id == branchSeg.id);
      }
    }

    if (connected.length == 2) {
      final seg1 = connected[0];
      final seg2 = connected[1];

      final other1Id = seg1.startNodeId == nodeId ? seg1.endNodeId : seg1.startNodeId;
      final other2Id = seg2.startNodeId == nodeId ? seg2.endNodeId : seg2.startNodeId;

      final nodeA = network.nodes[other1Id];
      final nodeB = node;
      final nodeC = network.nodes[other2Id];

      if (nodeA == null || nodeC == null) {
        return false;
      }

      final len1 = nodeA.distanceTo(nodeB);
      final len2 = nodeB.distanceTo(nodeC);
      final totalPathLen = len1 + len2;

      final mergedSegId = seg1.id;
      final mergedSeg = seg1.copyWith(
        id: mergedSegId,
        startNodeId: other1Id,
        endNodeId: other2Id,
      );

      network.segments.remove(seg1.id);
      network.segments.remove(seg2.id);

      // Удаляем стыковые швы, которые находились непосредственно в распускаемом узле
      network.weldJoints.removeWhere((_, w) {
        final isSeg1Junction = w.segmentId == seg1.id &&
            ((seg1.startNodeId == nodeId && w.ratio <= 0.05) ||
             (seg1.endNodeId == nodeId && w.ratio >= 0.95));
        final isSeg2Junction = w.segmentId == seg2.id &&
            ((seg2.startNodeId == nodeId && w.ratio <= 0.05) ||
             (seg2.endNodeId == nodeId && w.ratio >= 0.95));
        return isSeg1Junction || isSeg2Junction;
      });

      // Переносим остальные сварные стыки
      final remainingWelds = network.weldJoints.values
          .where((w) => w.segmentId == seg1.id || w.segmentId == seg2.id)
          .toList();
      for (final w in remainingWelds) {
        network.weldJoints.remove(w.id);
        double distFromA = 0.0;
        if (w.segmentId == seg1.id) {
          final r = seg1.startNodeId == other1Id ? w.ratio : (1.0 - w.ratio);
          distFromA = r * len1;
        } else {
          final r = seg2.startNodeId == nodeId ? w.ratio : (1.0 - w.ratio);
          distFromA = len1 + r * len2;
        }
        final newRatio = totalPathLen > 0.0001 ? (distFromA / totalPathLen).clamp(0.0, 1.0) : 0.5;
        network.weldJoints[w.id] = w.copyWith(segmentId: mergedSegId, ratio: newRatio);
      }

      // Переносим арматуру
      final valves = network.valves.values
          .where((v) => v.segmentId == seg1.id || v.segmentId == seg2.id)
          .toList();
      for (final v in valves) {
        network.valves.remove(v.id);
        double distFromA = 0.0;
        if (v.segmentId == seg1.id) {
          final r = seg1.startNodeId == other1Id ? v.ratio : (1.0 - v.ratio);
          distFromA = r * len1;
        } else {
          final r = seg2.startNodeId == nodeId ? v.ratio : (1.0 - v.ratio);
          distFromA = len1 + r * len2;
        }
        final newRatio = totalPathLen > 0.0001 ? (distFromA / totalPathLen).clamp(0.05, 0.95) : 0.5;
        network.valves[v.id] = v.copyWith(segmentId: mergedSegId, ratio: newRatio);
      }

      // Переносим опоры и подвески
      final supports = network.supports.values
          .where((s) => s.segmentId == seg1.id || s.segmentId == seg2.id)
          .toList();
      for (final s in supports) {
        network.supports.remove(s.id);
        double distFromA = 0.0;
        if (s.segmentId == seg1.id) {
          final r = seg1.startNodeId == other1Id ? s.distanceRatio : (1.0 - s.distanceRatio);
          distFromA = r * len1;
        } else {
          final r = seg2.startNodeId == nodeId ? s.distanceRatio : (1.0 - s.distanceRatio);
          distFromA = len1 + r * len2;
        }
        final newRatio = totalPathLen > 0.0001 ? (distFromA / totalPathLen).clamp(0.0, 1.0) : 0.5;
        network.supports[s.id] = s.copyWith(segmentId: mergedSegId, distanceRatio: newRatio);
      }

      // Переносим выноски
      final callouts = network.callouts.values
          .where((c) => c.targetId == seg1.id || c.targetId == seg2.id)
          .toList();
      for (final c in callouts) {
        network.callouts[c.id] = c.copyWith(targetId: mergedSegId);
      }

      network.segments[mergedSegId] = mergedSeg;

      network.nodes.remove(nodeId);
      network.fittings.remove(nodeId);
      network.callouts.removeWhere((_, c) => c.targetId == nodeId);
      network.dimensions.removeWhere((_, d) => d.startNodeId == nodeId || d.endNodeId == nodeId);

      network.autoDetectAllFittings();
      network.generateElementWeldJoints();
      network.validateAndCleanWeldJoints();
      network.recalculateSpools();
      return true;
    }

    // При >3 примыкающих сегментах удаляем узел и все связанные сегменты
    for (final seg in connected) {
      network.segments.remove(seg.id);
      network.valves.removeWhere((_, v) => v.segmentId == seg.id);
      network.weldJoints.removeWhere((_, w) => w.segmentId == seg.id);
      network.supports.removeWhere((_, s) => s.segmentId == seg.id);
      network.callouts.removeWhere((_, c) => c.targetId == seg.id);
    }
    network.fittings.remove(nodeId);
    network.nodes.remove(nodeId);
    network.callouts.removeWhere((_, c) => c.targetId == nodeId);
    network.dimensions.removeWhere((_, d) => d.startNodeId == nodeId || d.endNodeId == nodeId);
    network.autoDetectAllFittings();
    network.generateElementWeldJoints();
    network.validateAndCleanWeldJoints();
    network.recalculateSpools();
    return true;
  }
}

