import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/drawing_sheet.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/segment_3d.dart';
import 'package:akso/domain/models/pipeline_branch.dart';
import 'package:akso/domain/services/viewport_transform_service.dart';
import 'package:akso/core/math/axonometry_projector.dart';

class _BranchData {
  final List<Segment3D> segments;
  final String startNodeId;
  final String endNodeId;

  _BranchData({
    required this.segments,
    required this.startNodeId,
    required this.endNodeId,
  });
}

class PipelineBranchExtractor {
  /// Декомпозирует видимые трубопроводы сети на логические ветки трассы
  static List<PipelineBranch> extractBranches({
    required PipingNetwork network,
    required DrawingSheet sheet,
    required AxonometryProjector projector,
  }) {
    final vp = sheet.viewport;
    final visibleSys = vp.visibleSystemIds;

    // 1. Фильтруем активные сегменты по видовому экрану
    final activeSegments = network.segments.values.where((seg) {
      if (visibleSys != null && visibleSys.isNotEmpty && !visibleSys.contains(seg.systemId)) {
        return false;
      }
      return network.nodes.containsKey(seg.startNodeId) && network.nodes.containsKey(seg.endNodeId);
    }).toList();

    if (activeSegments.isEmpty) return [];

    // 2. Строим карту связности узлов
    final nodeDegrees = <String, int>{};
    final nodeToSegments = <String, List<Segment3D>>{};
    for (final seg in activeSegments) {
      nodeDegrees[seg.startNodeId] = (nodeDegrees[seg.startNodeId] ?? 0) + 1;
      nodeDegrees[seg.endNodeId] = (nodeDegrees[seg.endNodeId] ?? 0) + 1;
      nodeToSegments.putIfAbsent(seg.startNodeId, () => []).add(seg);
      nodeToSegments.putIfAbsent(seg.endNodeId, () => []).add(seg);
    }

    bool isEquipmentNode(String nId) {
      final node = network.nodes[nId];
      if (node != null && (node.equipmentId != null || node.nozzleId != null)) {
        return true;
      }
      return network.equipments.values.any((eq) => eq.nozzles.any((noz) => noz.id == nId));
    }

    bool isBoundaryNode(String nId) {
      return (nodeDegrees[nId] ?? 0) != 2 || isEquipmentNode(nId);
    }

    // 3. Выделяем непрерывные цепочки сегментов между тройниками/концами/оборудованием
    final visitedSegments = <String>{};
    final rawBranches = <_BranchData>[];

    // Точки старта: граничные узлы (концы, тройники, штуцеры оборудования)
    final startNodes = nodeDegrees.keys.where(isBoundaryNode).toList();
    if (startNodes.isEmpty && activeSegments.isNotEmpty) {
      // Замкнутый контур/кольцо
      startNodes.add(activeSegments.first.startNodeId);
    }

    for (final startNodeId in startNodes) {
      final incidentSegs = nodeToSegments[startNodeId] ?? [];
      for (final firstSeg in incidentSegs) {
        if (visitedSegments.contains(firstSeg.id)) continue;

        final branchSegs = <Segment3D>[firstSeg];
        visitedSegments.add(firstSeg.id);

        String prevNode = startNodeId;
        Segment3D currSeg = firstSeg;
        String nextNode = currSeg.startNodeId == prevNode ? currSeg.endNodeId : currSeg.startNodeId;

        while (!isBoundaryNode(nextNode)) {
          final candidateSegs = (nodeToSegments[nextNode] ?? [])
              .where((s) => !visitedSegments.contains(s.id))
              .toList();
          if (candidateSegs.isEmpty) break;

          final nextSeg = candidateSegs.first;
          branchSegs.add(nextSeg);
          visitedSegments.add(nextSeg.id);
          prevNode = nextNode;
          currSeg = nextSeg;
          nextNode = currSeg.startNodeId == prevNode ? currSeg.endNodeId : currSeg.startNodeId;
        }

        rawBranches.add(_BranchData(
          segments: branchSegs,
          startNodeId: startNodeId,
          endNodeId: nextNode,
        ));
      }
    }

    // Добавляем оставшиеся изолированные сегменты, если есть
    for (final seg in activeSegments) {
      if (!visitedSegments.contains(seg.id)) {
        rawBranches.add(_BranchData(
          segments: [seg],
          startNodeId: seg.startNodeId,
          endNodeId: seg.endNodeId,
        ));
        visitedSegments.add(seg.id);
      }
    }

    // 4. Распределяем выноски листа по веткам
    final segmentToBranchIndex = <String, int>{};
    for (int i = 0; i < rawBranches.length; i++) {
      for (final seg in rawBranches[i].segments) {
        segmentToBranchIndex[seg.id] = i;
      }
    }

    final branchCallouts = List.generate(rawBranches.length, (_) => <Callout>[]);

    for (final callout in network.callouts.values) {
      if (!sheet.isCalloutVisible(callout)) continue;

      // Высотные отметки не привязываются к веткам (остаются у узла)
      if (callout.targetType == CalloutTargetType.node || callout.elevationStyle != null) {
        continue;
      }

      final segId = network.getTargetSegmentId(callout.targetType, callout.targetId);
      if (segId != null && segmentToBranchIndex.containsKey(segId)) {
        final bIdx = segmentToBranchIndex[segId]!;
        branchCallouts[bIdx].add(callout);
      }
    }

    // 5. Создаем объекты PipelineBranch
    final result = <PipelineBranch>[];
    for (int i = 0; i < rawBranches.length; i++) {
      final raw = rawBranches[i];
      final segs = raw.segments;
      final firstStartNode = network.nodes[raw.startNodeId] ?? network.nodes[segs.first.startNodeId];
      final lastEndNode = network.nodes[raw.endNodeId] ?? network.nodes[segs.last.endNodeId];
      if (firstStartNode == null || lastEndNode == null) continue;

      final p1Raw = projector.projectRaw(firstStartNode.x, firstStartNode.y, firstStartNode.z);
      final p2Raw = projector.projectRaw(lastEndNode.x, lastEndNode.y, lastEndNode.z);
      final p1Mm = ViewportTransformService.model2dToSheetMm(p1Raw, vp);
      final p2Mm = ViewportTransformService.model2dToSheetMm(p2Raw, vp);

      final diff = p2Mm - p1Mm;
      final dist = diff.distance;
      final v2D = dist > 1e-6 ? Offset(diff.dx / dist, diff.dy / dist) : const Offset(1.0, 0.0);

      double minX = math.min(p1Mm.dx, p2Mm.dx);
      double maxX = math.max(p1Mm.dx, p2Mm.dx);
      double minY = math.min(p1Mm.dy, p2Mm.dy);
      double maxY = math.max(p1Mm.dy, p2Mm.dy);

      for (final s in segs) {
        final nA = network.nodes[s.startNodeId];
        final nB = network.nodes[s.endNodeId];
        if (nA != null) {
          final pa = ViewportTransformService.model2dToSheetMm(projector.projectRaw(nA.x, nA.y, nA.z), vp);
          minX = math.min(minX, pa.dx);
          maxX = math.max(maxX, pa.dx);
          minY = math.min(minY, pa.dy);
          maxY = math.max(maxY, pa.dy);
        }
        if (nB != null) {
          final pb = ViewportTransformService.model2dToSheetMm(projector.projectRaw(nB.x, nB.y, nB.z), vp);
          minX = math.min(minX, pb.dx);
          maxX = math.max(maxX, pb.dx);
          minY = math.min(minY, pb.dy);
          maxY = math.max(maxY, pb.dy);
        }
      }

      result.add(PipelineBranch(
        id: 'branch_$i',
        segments: segs,
        callouts: branchCallouts[i],
        startSheetMm: p1Mm,
        endSheetMm: p2Mm,
        branchVector2D: v2D,
        boundingBoxSheetMm: Rect.fromLTRB(minX, minY, maxX, maxY),
      ));
    }

    return result;
  }
}
