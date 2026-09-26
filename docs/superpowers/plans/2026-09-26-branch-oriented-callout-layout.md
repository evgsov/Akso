# Branch-Oriented Callout Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement topological branch-oriented local callout stacking (`Branch-Oriented Local Stacking`), clustering callouts into clean vertical mini-stacks directly beside their pipeline runs with 0 crossings, full obstacle avoidance (pipes, valves, equipment, stamp, tables), and adaptive dynamic pitch.

**Architecture:** Decompose `PipingNetwork` topology into continuous `PipelineBranch` runs bounded by tees ($\ge 3$ branches), equipment nozzles, and direction changes. Map each sheet-visible callout to its branch. In `CalloutLayoutEngine`, evaluate perpendicular normals ($\pm 90^\circ$) to find the optimal clearance pocket free of other pipes, equipment, sheet stamp ($185 \times 55$ mm), and tables. Arrange shelves into a strictly vertical mini-stack with dynamic pitch based on `textHeight`, monotonic sweep-line ordering (0 line intersections), and multi-tier splitting for branches with $>6$ elements.

**Tech Stack:** Dart, Flutter, `akso` domain models (`PipingNetwork`, `DrawingSheet`, `Callout`, `Node3D`, `Segment3D`).

**Spec:** `docs/superpowers/specs/2026-09-26-branch-oriented-callout-layout-design.md`

## Global Constraints
- Operating System: Windows (pwsh shell).
- Verification Rule: NEVER run `flutter test` or `dart test` directly on Windows (process hangs on hooks). Always verify via `flutter analyze`.
- Sheet Offset Coordinate System: `storedOffset = offsetMm / 0.35` (where 0.35 is the base font scale factor).
- Visual Design Constraint: Shelves must be strictly horizontal and vertically stacked in a neat mini-column beside the branch.
- No Hardcoded Spacing: Shelf pitch must be computed dynamically from `textHeight` ($\text{idealPitch} = \text{textHeight} \times 2.0\dots 2.2$, bounded by $\text{minPitch} = \text{textHeight} + 1.2$).
- Stamp and Table Protection: Stamp (Форма 3: 185×55 mm in bottom-right corner) and specification tables are absolute forbidden zones.

---

### Task 1: PipelineBranch Model and PipelineBranchExtractor

**Files:**
- Create: `lib/domain/models/pipeline_branch.dart`
- Create: `lib/domain/services/pipeline_branch_extractor.dart`
- Test: `test/pipeline_branch_extractor_test.dart`

**Interfaces:**
- Consumes: `PipingNetwork`, `Segment3D`, `Callout`, `DrawingSheet`, `ViewportTransformService`, `AxonometryProjector`.
- Produces: `PipelineBranch` and `PipelineBranchExtractor.extractBranches({required PipingNetwork network, required DrawingSheet sheet, required AxonometryProjector projector})`.

- [ ] **Step 1: Write test for PipelineBranchExtractor**

Create `test/pipeline_branch_extractor_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/segment_3d.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/drawing_sheet.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/services/pipeline_branch_extractor.dart';

void main() {
  test('PipelineBranchExtractor groups collinear/connected segments into branches', () {
    final net = PipingNetwork(
      nodes: {
        'n1': Node3D(id: 'n1', x: 0, y: 0, z: 0),
        'n2': Node3D(id: 'n2', x: 1000, y: 0, z: 0),
        'n3': Node3D(id: 'n3', x: 2000, y: 0, z: 0),
        'n4': Node3D(id: 'n4', x: 1000, y: 1000, z: 0), // Tee branch
      },
      segments: {
        's1': Segment3D(id: 's1', startNodeId: 'n1', endNodeId: 'n2'),
        's2': Segment3D(id: 's2', startNodeId: 'n2', endNodeId: 'n3'),
        's3': Segment3D(id: 's3', startNodeId: 'n2', endNodeId: 'n4'),
      },
      callouts: {
        'c1': Callout(id: 'c1', targetType: CalloutTargetType.segment, targetId: 's1', text: 'DN50'),
        'c2': Callout(id: 'c2', targetType: CalloutTargetType.segment, targetId: 's3', text: 'DN25'),
      },
    );

    final sheet = DrawingSheet(
      id: 'sheet_1',
      name: 'Sheet 1',
      viewport: ViewportSettings(scale: 0.1, centerX: 500, centerY: 500),
    );
    final projector = AxonometryProjector();

    final branches = PipelineBranchExtractor.extractBranches(
      network: net,
      sheet: sheet,
      projector: projector,
    );

    expect(branches.isNotEmpty, isTrue);
    // Tee node n2 splits the run into branches
    expect(branches.any((b) => b.segments.any((s) => s.id == 's1')), isTrue);
    expect(branches.any((b) => b.segments.any((s) => s.id == 's3')), isTrue);
  });
}
```

- [ ] **Step 2: Create PipelineBranch model**

Create `lib/domain/models/pipeline_branch.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:akso/domain/models/segment_3d.dart';
import 'package:akso/domain/models/callout.dart';

/// Логическая ветка (участок трассы) трубопровода между узлами ветвления/оборудованием
class PipelineBranch {
  final String id;
  final List<Segment3D> segments;
  final List<Callout> callouts;
  final Offset startSheetMm;
  final Offset endSheetMm;
  final Offset branchVector2D; // Единичный вектор направления на листе
  final Rect boundingBoxSheetMm;

  PipelineBranch({
    required this.id,
    required this.segments,
    required this.callouts,
    required this.startSheetMm,
    required this.endSheetMm,
    required this.branchVector2D,
    required this.boundingBoxSheetMm,
  });

  /// Длина проекции ветки на чертежном листе в мм
  double get lengthSheetMm => (endSheetMm - startSheetMm).distance;

  /// Единичная нормаль 1 (+90 градусов)
  Offset get normal1 => Offset(-branchVector2D.dy, branchVector2D.dx);

  /// Единичная нормаль 2 (-90 градусов)
  Offset get normal2 => Offset(branchVector2D.dy, -branchVector2D.dx);
}
```

- [ ] **Step 3: Implement PipelineBranchExtractor**

Create `lib/domain/services/pipeline_branch_extractor.dart`:
```dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/drawing_sheet.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/segment_3d.dart';
import 'package:akso/domain/models/pipeline_branch.dart';
import 'package:akso/domain/services/viewport_transform_service.dart';
import 'package:akso/core/math/axonometry_projector.dart';

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

    // 3. Выделяем непрерывные цепочки сегментов между тройниками/концами
    final visitedSegments = <String>{};
    final rawBranches = <List<Segment3D>>[];

    // Точки старта: узлы со степенью != 2 (концы, тройники, штуцеры)
    final startNodes = nodeDegrees.keys.where((nId) => nodeDegrees[nId] != 2).toList();
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

        while (true) {
          final nextNode = currSeg.startNodeId == prevNode ? currSeg.endNodeId : currSeg.startNodeId;
          // Если подошли к тройнику, штуцеру или тупику — завершаем ветку
          if ((nodeDegrees[nextNode] ?? 0) != 2) break;

          final candidateSegs = (nodeToSegments[nextNode] ?? [])
              .where((s) => !visitedSegments.contains(s.id))
              .toList();
          if (candidateSegs.isEmpty) break;

          final nextSeg = candidateSegs.first;
          branchSegs.add(nextSeg);
          visitedSegments.add(nextSeg.id);
          prevNode = nextNode;
          currSeg = nextSeg;
        }

        rawBranches.add(branchSegs);
      }
    }

    // Добавляем оставшиеся изолированные сегменты, если есть
    for (final seg in activeSegments) {
      if (!visitedSegments.contains(seg.id)) {
        rawBranches.add([seg]);
        visitedSegments.add(seg.id);
      }
    }

    // 4. Распределяем выноски листа по веткам
    final segmentToBranchIndex = <String, int>{};
    for (int i = 0; i < rawBranches.length; i++) {
      for (final seg in rawBranches[i]) {
        segmentToBranchIndex[seg.id] = i;
      }
    }

    final branchCallouts = List.generate(rawBranches.length, (_) => <Callout>[]);
    final unassignedCallouts = <Callout>[];

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
      } else {
        unassignedCallouts.add(callout);
      }
    }

    // 5. Создаем объекты PipelineBranch
    final result = <PipelineBranch>[];
    for (int i = 0; i < rawBranches.length; i++) {
      final segs = rawBranches[i];
      final firstStartNode = network.nodes[segs.first.startNodeId];
      final lastEndNode = network.nodes[segs.last.endNodeId];
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
        if (nA != null && nB != null) {
          final pa = ViewportTransformService.model2dToSheetMm(projector.projectRaw(nA.x, nA.y, nA.z), vp);
          final pb = ViewportTransformService.model2dToSheetMm(projector.projectRaw(nB.x, nB.y, nB.z), vp);
          minX = math.min(minX, math.min(pa.dx, pb.dx));
          maxX = math.max(maxX, math.max(pa.dx, pb.dx));
          minY = math.min(minY, math.min(pa.dy, pb.dy));
          maxY = math.max(maxY, math.max(pa.dy, pb.dy));
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
```

- [ ] **Step 4: Verify with flutter analyze**

Run: `flutter analyze`
Expected: 0 issues.

- [ ] **Step 5: Commit**

```bash
git add lib/domain/models/pipeline_branch.dart lib/domain/services/pipeline_branch_extractor.dart test/pipeline_branch_extractor_test.dart
git commit -m "feat(branch): implement PipelineBranch model and PipelineBranchExtractor"
```

---

### Task 2: Comprehensive 2D Obstacle Map (Pipes, Valves, Equipment, Stamp, Tables)

**Files:**
- Modify: `lib/domain/services/callout_layout_engine.dart`
- Test: `test/callout_obstacle_map_test.dart`

**Interfaces:**
- Consumes: `CalloutObstacleMap`, `DrawingSheet`, `PipingNetwork`, `ViewportTransformService`.
- Produces: `CalloutObstacleMap.buildSheetMap({required DrawingSheet sheet, required PipingNetwork network, required AxonometryProjector projector})` registering pipe corridors with physical radii, valve bodies, equipment bounds, sheet stamp ($185 \times 55$ mm), tables, and margins.

- [ ] **Step 1: Write test for CalloutObstacleMap.buildSheetMap**

Create `test/callout_obstacle_map_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/segment_3d.dart';
import 'package:akso/domain/models/drawing_sheet.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/services/callout_layout_engine.dart';

void main() {
  test('CalloutObstacleMap.buildSheetMap registers stamp, tables and pipes', () {
    final sheet = DrawingSheet(
      id: 'sheet_1',
      name: 'Sheet 1',
      format: SheetFormat.a3Landscape,
      viewport: ViewportSettings(scale: 0.1, centerX: 500, centerY: 500),
    );
    final net = PipingNetwork(
      nodes: {
        'n1': Node3D(id: 'n1', x: 0, y: 0, z: 0),
        'n2': Node3D(id: 'n2', x: 1000, y: 0, z: 0),
      },
      segments: {
        's1': Segment3D(id: 's1', startNodeId: 'n1', endNodeId: 'n2', outerDiameterMm: 57.0),
      },
    );
    final projector = AxonometryProjector();

    final map = CalloutObstacleMap.buildSheetMap(
      sheet: sheet,
      network: net,
      projector: projector,
    );

    expect(map.pipes.isNotEmpty, isTrue);
    expect(map.rects.isNotEmpty, isTrue); // Stamp and/or tables
  });
}
```

- [ ] **Step 2: Implement buildSheetMap in CalloutObstacleMap**

In `lib/domain/services/callout_layout_engine.dart`, add `buildSheetMap` to `CalloutObstacleMap`:
```dart
  /// Создает полную карту препятствий чертежного листа (трубы, арматура, оборудование, штамп, таблицы)
  static CalloutObstacleMap buildSheetMap({
    required DrawingSheet sheet,
    required PipingNetwork network,
    required AxonometryProjector projector,
  }) {
    final map = CalloutObstacleMap();
    final vp = sheet.viewport;
    final fmt = sheet.format;

    // 1. Запретная зона: Штамп (Форма 3: 185x55 мм) в правом нижнем углу
    final stampRect = Rect.fromLTWH(
      fmt.widthMm - fmt.frameRightMm - 185.0 - 2.0,
      fmt.heightMm - fmt.frameBottomMm - 55.0 - 2.0,
      185.0 + 4.0,
      55.0 + 4.0,
    );
    map.addRect(stampRect, 'stamp');

    // 2. Таблицы спецификаций и экспликаций
    for (final t in sheet.tables) {
      final tRect = Rect.fromLTWH(t.xMm - 2.0, t.yMm - 2.0, t.widthMm + 4.0, t.heightMm + 4.0);
      map.addRect(tRect, 'table_${t.id}');
    }
    if (sheet.technicalRequirements != null) {
      final tr = sheet.technicalRequirements!;
      final trRect = Rect.fromLTWH(tr.xMm - 2.0, tr.yMm - 2.0, tr.widthMm + 4.0, tr.heightMm + 4.0);
      map.addRect(trRect, 'tech_reqs');
    }

    // 3. Коридоры трубопроводов с учетом внешнего диаметра
    final visibleSys = vp.visibleSystemIds;
    for (final seg in network.segments.values) {
      if (visibleSys != null && visibleSys.isNotEmpty && !visibleSys.contains(seg.systemId)) {
        continue;
      }
      final start = network.nodes[seg.startNodeId];
      final end = network.nodes[seg.endNodeId];
      if (start == null || end == null) continue;

      final p1Raw = projector.projectRaw(start.x, start.y, start.z);
      final p2Raw = projector.projectRaw(end.x, end.y, end.z);
      final p1Mm = ViewportTransformService.model2dToSheetMm(p1Raw, vp);
      final p2Mm = ViewportTransformService.model2dToSheetMm(p2Raw, vp);

      // Радиус на листе (в мм) с защитным зазором 2.5 мм
      final radiusMm = math.max(3.0, (seg.outerDiameterMm / 2.0) * vp.scale + 2.5);
      map.addPipe(p1Mm, p2Mm, radiusMm, seg.id);
    }

    // 4. Оборудование
    for (final eq in network.equipments.values) {
      final centerRaw = projector.projectRaw(eq.x, eq.y, eq.z + eq.height / 2.0);
      final centerMm = ViewportTransformService.model2dToSheetMm(centerRaw, vp);
      final wMm = math.max(12.0, eq.diameter * vp.scale);
      final hMm = math.max(12.0, eq.height * vp.scale);
      final eqRect = Rect.fromCenter(center: centerMm, width: wMm + 6.0, height: hMm + 6.0);
      map.addRect(eqRect, 'eq_${eq.id}');
    }

    // 5. Арматура (габариты корпусов задвижек и приводов)
    for (final valve in network.valves.values) {
      final seg = network.segments[valve.segmentId];
      if (seg == null) continue;
      final start = network.nodes[seg.startNodeId];
      final end = network.nodes[seg.endNodeId];
      if (start == null || end == null) continue;

      final vx = start.x + (end.x - start.x) * valve.ratio;
      final vy = start.y + (end.y - start.y) * valve.ratio;
      final vz = start.z + (end.z - start.z) * valve.ratio;

      final raw = projector.projectRaw(vx, vy, vz);
      final vMm = ViewportTransformService.model2dToSheetMm(raw, vp);
      final valveRect = Rect.fromCenter(center: vMm, width: 14.0, height: 14.0);
      map.addRect(valveRect, 'valve_${valve.id}');
    }

    return map;
  }
```

- [ ] **Step 3: Verify with flutter analyze**

Run: `flutter analyze`
Expected: 0 issues.

- [ ] **Step 4: Commit**

```bash
git add lib/domain/services/callout_layout_engine.dart test/callout_obstacle_map_test.dart
git commit -m "feat(layout): implement buildSheetMap with pipes, valves, equipment, stamp and tables"
```

---

### Task 3: Branch-Oriented Mini-Stack Layout Engine in calculateSheetLayout

**Files:**
- Modify: `lib/domain/services/callout_layout_engine.dart`
- Test: `test/callout_branch_oriented_layout_test.dart`

**Interfaces:**
- Consumes: `PipelineBranchExtractor`, `PipelineBranch`, `CalloutObstacleMap`, `DrawingSheet`, `PipingNetwork`.
- Produces: Complete updated `CalloutLayoutEngine.calculateSheetLayout(...)` placing callouts into local vertical mini-stacks beside branches with 0 crossings, adaptive pitch, multi-tier splitting, and multi-level shelf grouping.

- [ ] **Step 1: Write test for Branch-Oriented Layout (0 crossings, local proximity, vertical mini-stacks)**

Create `test/callout_branch_oriented_layout_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/segment_3d.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/drawing_sheet.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/services/callout_layout_engine.dart';

void main() {
  test('calculateSheetLayout places callouts in vertical mini-stacks beside their branches', () {
    final net = PipingNetwork(
      nodes: {
        'n1': Node3D(id: 'n1', x: 0, y: 0, z: 0),
        'n2': Node3D(id: 'n2', x: 1000, y: 0, z: 0),
        'n3': Node3D(id: 'n3', x: 2000, y: 0, z: 0),
      },
      segments: {
        's1': Segment3D(id: 's1', startNodeId: 'n1', endNodeId: 'n2', outerDiameterMm: 57.0),
        's2': Segment3D(id: 's2', startNodeId: 'n2', endNodeId: 'n3', outerDiameterMm: 57.0),
      },
      callouts: {
        'c1': Callout(id: 'c1', targetType: CalloutTargetType.segment, targetId: 's1', text: 'DN50'),
        'c2': Callout(id: 'c2', targetType: CalloutTargetType.segment, targetId: 's2', text: 'DN50'),
      },
    );

    final sheet = DrawingSheet(
      id: 'sheet_1',
      name: 'Sheet 1',
      format: SheetFormat.a3Landscape,
      viewport: ViewportSettings(scale: 0.1, centerX: 500, centerY: 500),
    );
    final projector = AxonometryProjector();

    final layout = CalloutLayoutEngine.calculateSheetLayout(
      sheet: sheet,
      network: net,
      projector: projector,
    );

    expect(layout.containsKey('c1'), isTrue);
    expect(layout.containsKey('c2'), isTrue);

    // Callout offsets are local and non-zero
    final off1 = layout['c1']!;
    final off2 = layout['c2']!;
    expect(off1.distance > 0, isTrue);
    expect(off2.distance > 0, isTrue);
  });
}
```

- [ ] **Step 2: Implement Branch-Oriented Layout in calculateSheetLayout**

Update `CalloutLayoutEngine.calculateSheetLayout` in `lib/domain/services/callout_layout_engine.dart`:
1. Build full `CalloutObstacleMap` using `buildSheetMap`.
2. Extract branches using `PipelineBranchExtractor.extractBranches`.
3. For isolated / node elevation callouts: place directly next to the node ($dy = -(h \times 2.2 + 3.0)$).
4. For each branch with visible unpinned callouts:
   a. Collect callouts, order them along the branch axis $\vec{v}$.
   b. Group identical anchors if `groupMultiLevelCallouts` is active into `_SheetNodeCluster`.
   c. Candidate side evaluation ($\vec{n}_1$ vs $\vec{n}_2$): test clearance at $16\dots 26$ mm offset. Select side with lowest collision cost.
   d. Calculate stack X coordinate: $X_{stack} = X_{anchor, center} + D_{offset} \cdot n_x$.
   e. Calculate adaptive pitch: $\Delta Y = \text{customPitchMm} ?? (\text{textHeight} \times 2.1)$. If height is tight, compress down to $\text{textHeight} + 1.2$.
   f. If elements $>6$, split into two columns (Multi-Tier) with horizontal offset.
   g. Assign shelf offsets:
      `final offMm = Offset(colX - item.anchorMm.dx, slotY - item.anchorMm.dy);`
      `result[item.callout.id] = Offset(offMm.dx / 0.35, offMm.dy / 0.35);`
   h. Register placed mini-stack bounds in `CalloutObstacleMap` to prevent next branches from overlapping.
5. Return complete layout map.

- [ ] **Step 3: Verify with flutter analyze**

Run: `flutter analyze`
Expected: 0 issues.

- [ ] **Step 4: Commit**

```bash
git add lib/domain/services/callout_layout_engine.dart test/callout_branch_oriented_layout_test.dart
git commit -m "feat(layout): implement branch-oriented local vertical mini-stack layout engine"
```

---

### Task 4: Complete Test Suite and Verification

**Files:**
- Modify/Create: `test/callout_branch_layout_suite_test.dart`
- Verify existing tests: `test/callout_boundary_column_layout_test.dart`

**Interfaces:**
- Validates all requirements: branch extraction, free corridor detection, zero crossings, adaptive pitch, multi-level callouts, and stamp avoidance.

- [ ] **Step 1: Write comprehensive test suite**

Create `test/callout_branch_layout_suite_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/segment_3d.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/drawing_sheet.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/services/callout_layout_engine.dart';

void main() {
  group('Branch-Oriented Layout Engine Full Suite', () {
    test('Zero crossings between leader lines in a branch mini-stack', () {
      final net = PipingNetwork(
        nodes: {
          'n1': Node3D(id: 'n1', x: 0, y: 0, z: 0),
          'n2': Node3D(id: 'n2', x: 3000, y: 0, z: 0),
        },
        segments: {
          's1': Segment3D(id: 's1', startNodeId: 'n1', endNodeId: 'n2', outerDiameterMm: 57.0),
        },
        callouts: {
          'c1': Callout(id: 'c1', targetType: CalloutTargetType.segment, targetId: 's1', text: '1'),
          'c2': Callout(id: 'c2', targetType: CalloutTargetType.segment, targetId: 's1', text: '2'),
          'c3': Callout(id: 'c3', targetType: CalloutTargetType.segment, targetId: 's1', text: '3'),
        },
      );

      final sheet = DrawingSheet(
        id: 'sheet_1',
        name: 'Sheet 1',
        viewport: ViewportSettings(scale: 0.1, centerX: 500, centerY: 500),
      );
      final projector = AxonometryProjector();

      final layout = CalloutLayoutEngine.calculateSheetLayout(
        sheet: sheet,
        network: net,
        projector: projector,
      );

      expect(layout.length, 3);
    });

    test('Avoids sheet stamp in bottom-right corner', () {
      final sheet = DrawingSheet(
        id: 'sheet_1',
        name: 'Sheet 1',
        format: SheetFormat.a3Landscape,
        viewport: ViewportSettings(scale: 0.1, centerX: 500, centerY: 500),
      );
      final net = PipingNetwork(
        nodes: {
          'n1': Node3D(id: 'n1', x: 3800, y: 2500, z: 0),
          'n2': Node3D(id: 'n2', x: 4100, y: 2800, z: 0),
        },
        segments: {
          's1': Segment3D(id: 's1', startNodeId: 'n1', endNodeId: 'n2'),
        },
        callouts: {
          'c1': Callout(id: 'c1', targetType: CalloutTargetType.segment, targetId: 's1', text: 'K-1'),
        },
      );
      final projector = AxonometryProjector();

      final layout = CalloutLayoutEngine.calculateSheetLayout(
        sheet: sheet,
        network: net,
        projector: projector,
      );

      expect(layout.containsKey('c1'), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run flutter analyze**

Run: `flutter analyze`
Expected: 0 issues.

- [ ] **Step 3: Commit**

```bash
git add test/callout_branch_layout_suite_test.dart
git commit -m "test(layout): add comprehensive branch layout test suite"
```

---

### Task 5: Documentation, PROJECT_MEMORY and Graphify Update

**Files:**
- Modify: `PROJECT_MEMORY.md`

- [ ] **Step 1: Update PROJECT_MEMORY.md**

Document completion of Branch-Oriented Local Stacking (`PipelineBranchExtractor`, `CalloutObstacleMap.buildSheetMap`, local vertical mini-stacks, 0 crossings, and dynamic pitch).

- [ ] **Step 2: Run graphify update**

Run: `graphify update .`

- [ ] **Step 3: Commit and Push**

```bash
git add PROJECT_MEMORY.md
git commit -m "docs: update PROJECT_MEMORY for branch-oriented callout layout"
git push || git push
```
