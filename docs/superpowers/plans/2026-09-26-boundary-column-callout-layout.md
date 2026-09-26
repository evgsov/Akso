# Boundary Column Callout Layout & Multi-Tier Stacking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement non-crossing boundary column auto-layout for drawing sheet callouts with adaptive pitch, optional node-level multi-shelf stacking, and elevation callout isolation.

**Architecture:** Replace greedy radial ray search in `calculateSheetLayout` with a planar boundary labeling sweep-line algorithm that groups anchors into left/right corridors, sorts by Y to guarantee 0 leader crossings, computes dynamic pitch from `textHeight`, respects stamp and table keepouts, and provides an optional multi-shelf grouping toggle for coincident node elements.

**Tech Stack:** Dart, Flutter, Axonometric projection, Computational Geometry (Boundary Labeling).

**Spec:** `docs/superpowers/specs/2026-09-26-boundary-column-callout-layout-design.md`

## Global Constraints
- `flutter analyze` must produce 0 issues.
- Never run `flutter test` or `dart test` directly on Windows (hooks hang indefinitely); use static analysis and unit test files checked via analysis.
- All sheet offsets must be stored in `callout.sheetOffsets[sheet.id]` normalized as `stored = offsetMm / 0.35`.
- Do not mutate 3D model `screenOffsetX / screenOffsetY` during sheet auto-layout.
- All UI text must be in Russian.

---

### Task 1: Domain Model Updates for Multi-Level Toggle & Settings

**Files:**
- Modify: `lib/domain/models/drawing_sheet.dart`
- Test: `test/drawing_sheet_multilevel_test.dart`

**Interfaces:**
- Consumes: `DrawingSheet` class in `lib/domain/models/drawing_sheet.dart`.
- Produces: `DrawingSheet.groupMultiLevelCallouts: bool` (default `true`), updated `copyWith`, `toJson`, and `fromJson`.

- [ ] **Step 1: Write unit test for DrawingSheet.groupMultiLevelCallouts**

Create `test/drawing_sheet_multilevel_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/drawing_sheet.dart';
import 'package:akso/domain/models/sheet_viewport.dart';

void main() {
  test('DrawingSheet defaults groupMultiLevelCallouts to true', () {
    final sheet = DrawingSheet(
      id: 'sheet_1',
      name: 'Монтажная схема',
      format: SheetFormat.a3Landscape,
      viewport: SheetViewport.standardA3(),
    );
    expect(sheet.groupMultiLevelCallouts, isTrue);
  });

  test('DrawingSheet serialization preserves groupMultiLevelCallouts', () {
    final sheet = DrawingSheet(
      id: 'sheet_1',
      name: 'Монтажная схема',
      format: SheetFormat.a3Landscape,
      viewport: SheetViewport.standardA3(),
      groupMultiLevelCallouts: false,
    );
    final json = sheet.toJson();
    expect(json['groupMultiLevelCallouts'], isFalse);

    final restored = DrawingSheet.fromJson(json);
    expect(restored.groupMultiLevelCallouts, isFalse);
  });
}
```

- [ ] **Step 2: Implement field in DrawingSheet**

Modify `lib/domain/models/drawing_sheet.dart`:
Add `final bool groupMultiLevelCallouts;` with default `true` in constructor, `copyWith`, `toJson`, and `fromJson`.

- [ ] **Step 3: Verify with static analysis**

Run: `flutter analyze`
Expected: 0 issues.

- [ ] **Step 4: Commit**

```bash
git add lib/domain/models/drawing_sheet.dart test/drawing_sheet_multilevel_test.dart
git commit -m "feat(sheet): add groupMultiLevelCallouts toggle to DrawingSheet"
```

---

### Task 2: Core Algorithm — Planar Sweep-Line Boundary Column Engine

**Files:**
- Modify: `lib/domain/services/callout_layout_engine.dart`
- Create: `test/callout_boundary_column_layout_test.dart`

**Interfaces:**
- Consumes: `PipingNetwork`, `DrawingSheet`, `AxonometryProjector`, `ViewportTransformService`.
- Produces: `CalloutLayoutEngine.calculateSheetLayout(...)` rewritten with non-crossing boundary column sweep-line algorithm and dynamic adaptive pitch.

- [ ] **Step 1: Write test for non-crossing boundary layout**

Create `test/callout_boundary_column_layout_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/drawing_sheet.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/sheet_viewport.dart';
import 'package:akso/domain/models/valve.dart';
import 'package:akso/domain/services/callout_layout_engine.dart';
import 'package:akso/core/math/axonometry_projector.dart';

void main() {
  test('calculateSheetLayout generates 0 crossing leader lines in boundary column mode', () {
    final nodes = <String, Node3D>{};
    final segments = <String, PipeSegment>{};
    final valves = <String, Valve>{};
    final callouts = <String, Callout>{};

    // Создаем цепочку из 20 узлов и элементов
    for (int i = 0; i < 20; i++) {
      final n1 = Node3D(id: 'n_$i', x: i * 100.0, y: (i % 3) * 80.0, z: (i % 2) * 50.0);
      nodes[n1.id] = n1;
      if (i > 0) {
        final seg = PipeSegment(
          id: 'seg_$i',
          startNodeId: 'n_${i - 1}',
          endNodeId: 'n_$i',
          outerDiameterMm: 57.0,
          wallThicknessMm: 3.5,
        );
        segments[seg.id] = seg;
      }
      final v = Valve(
        id: 'val_$i',
        nodeId: n1.id,
        valveType: ValveType.ball,
      );
      valves[v.id] = v;
      final c = Callout(
        id: 'call_$i',
        targetType: CalloutTargetType.valve,
        targetId: v.id,
        customText: 'А-$i',
      );
      callouts[c.id] = c;
    }

    final net = PipingNetwork(
      nodes: nodes,
      segments: segments,
      valves: valves,
      callouts: callouts,
    );

    final sheet = DrawingSheet(
      id: 'sheet_test',
      name: 'Схема',
      format: SheetFormat.a3Landscape,
      viewport: SheetViewport.standardA3(),
    );

    final projector = AxonometryProjector.iso();
    final layout = CalloutLayoutEngine.calculateSheetLayout(
      sheet: sheet,
      network: net,
      projector: projector,
    );

    expect(layout.length, equals(callouts.length));

    // Проверяем, что ни одна полочка не заходит на штамп 185x55 мм
    final stampRect = Rect.fromLTWH(
      sheet.format.widthMm - sheet.format.frameRightMm - 185.0,
      sheet.format.heightMm - sheet.format.frameBottomMm - 55.0,
      185.0,
      55.0,
    );

    for (final entry in layout.entries) {
      final c = callouts[entry.key]!;
      final anchor = CalloutLayoutEngine.computeAnchorNode(c, net)!;
      final pMm = projector.projectRaw(anchor.x, anchor.y, anchor.z);
      // Смещение в мм
      final offMm = entry.value * 0.35;
      final shelfStart = pMm + offMm;
      expect(stampRect.contains(shelfStart), isFalse, reason: 'Callout ${entry.key} overlaps stamp');
    }
  });
}
```

- [ ] **Step 2: Implement Boundary Column Engine in `callout_layout_engine.dart`**

Modify `lib/domain/services/callout_layout_engine.dart`:
1. Add `_SheetAnchorItem` class:
   - `Callout callout`
   - `Offset anchorMm`
   - `double textWidthMm`
   - `double textHeightMm`
   - `bool isLeft`
2. Add `_calculateAdaptivePitch(double textHeight, double availableHeight, int count)`:
   - $\Delta Y_{ideal} = \text{textHeight} \times 2.2$.
   - $\Delta Y_{min} = \text{textHeight} + 1.2$.
   - If $count \times \Delta Y_{ideal} \le availableHeight$, return $\Delta Y_{ideal}$.
   - Else return $\max(\Delta Y_{min}, availableHeight / count)$.
3. Implement `_calculateBoundaryColumnLayout(...)`:
   - Compute bounding box of active segments $[X_{min}, Y_{min}, X_{max}, Y_{max}]$.
   - $X_{mid} = (X_{min} + X_{max}) / 2$.
   - Partition anchors into Left ($X \le X_{mid}$) and Right ($X > X_{mid}$).
   - Set left column guideline: $X_{col\_L} = \max(\text{frameLeft} + 22.0, X_{min} - 28.0)$.
   - Set right column guideline: $X_{col\_R} = \min(\text{frameRight} - 28.0, X_{max} + 18.0)$.
   - Calculate right column bottom limit avoiding stamp (Форма 3: 185×55 мм) and sheet tables:
     $Y_{bottom\_R} = \min(H_{sheet} - 60.0, \min(Y_{tables}) - 5.0)$.
   - For Elevation callouts: offset locally above the anchor ($dy = -(\text{textHeight} \times 2.5 + 4.0)$, $dx = 0$).
   - For all other callouts:
     - Sort anchors by $Y$ ascending ($y_1 \le y_2 \le \dots \le y_n$).
     - Calculate adaptive pitch $\Delta Y$.
     - Assign slots $Y_k = Y_{start} + k \times \Delta Y$.
     - For left column: shelf goes leftward; offset = $Offset(X_{col\_L} - x_a, Y_k - y_a)$.
     - For right column: shelf goes rightward; offset = $Offset(X_{col\_R} - x_a, Y_k - y_a)$.
     - Normalize to stored units: $Offset(dx / 0.35, dy / 0.35)$.
4. In `calculateSheetLayout(...)`, route execution to `_calculateBoundaryColumnLayout(...)`.

- [ ] **Step 3: Run static analysis**

Run: `flutter analyze`
Expected: 0 issues.

- [ ] **Step 4: Commit**

```bash
git add lib/domain/services/callout_layout_engine.dart test/callout_boundary_column_layout_test.dart
git commit -m "feat(layout): implement planar boundary column sweep-line layout with adaptive pitch"
```

---

### Task 3: Multi-Level Node Stacking (Этажерки) & Coincident Anchor Grouping

**Files:**
- Modify: `lib/domain/services/callout_layout_engine.dart`
- Modify: `test/callout_boundary_column_layout_test.dart`

**Interfaces:**
- Consumes: `groupMultiLevelCallouts` from `DrawingSheet` (or parameter).
- Produces: Coincident node clustering (distance $< 4.0\text{ мм}$), sorting by element priority (Valve $\to$ Flange $\to$ Weld $\to$ Other), and stacked multi-shelf slot assignment.

- [ ] **Step 1: Write test for coincident anchor grouping and multi-shelf toggle**

Add test cases in `test/callout_boundary_column_layout_test.dart`:
```dart
test('groupMultiLevelCallouts groups coincident valve and weld callouts', () {
  // Тестируем, что элементы одного узла получают последовательные слоты этажерки
});

test('groupMultiLevelCallouts = false produces independent slots per element', () {
  // Тестируем, что при отключении каждый элемент распределяется построчно
});
```

- [ ] **Step 2: Implement node clustering and multi-shelf stacking**

In `lib/domain/services/callout_layout_engine.dart`:
1. Add cluster detection:
   - Group items where `(a.anchorMm - b.anchorMm).distance < 4.0`.
2. Priority sorter:
   - Valve $\to$ Flange $\to$ WeldJoint $\to$ Fitting $\to$ Support $\to$ Elevation.
3. If `sheet.groupMultiLevelCallouts` is `true`:
   - Treat the cluster as a single compound item during column height allocation.
   - Allocate consecutive vertical slots for each shelf in the cluster.
   - All shelves in the cluster share the unified projection origin.
4. If `sheet.groupMultiLevelCallouts` is `false`:
   - Each item is treated as an independent slot in the sorted sweep-line order.

- [ ] **Step 3: Run static analysis**

Run: `flutter analyze`
Expected: 0 issues.

- [ ] **Step 4: Commit**

```bash
git add lib/domain/services/callout_layout_engine.dart test/callout_boundary_column_layout_test.dart
git commit -m "feat(layout): add coincident node clustering and multi-level shelf grouping"
```

---

### Task 4: UI Integration in SheetToolbar & Filter Dialog

**Files:**
- Modify: `lib/ui/canvas/input_controller.dart`
- Modify: `lib/ui/canvas/sheet_toolbar.dart`

**Interfaces:**
- Consumes: `runSheetCalloutAutoLayout` and `setSheetGroupMultiLevel` in `PipingInputController`.
- Produces:
  - Menu items in `SheetToolbar`: «Авторасстановка (с этажерками)», «Авторасстановка (построчно)», «Сбросить выноски к 3D-модели».
  - SwitchListTile in Sheet Callout Filter Dialog for toggling multi-level grouping.

- [ ] **Step 1: Update PipingInputController**

In `lib/ui/canvas/input_controller.dart`:
Add methods / parameters:
```dart
void setSheetGroupMultiLevel(bool enabled) {
  final sheet = activeSheet;
  if (sheet == null) return;
  updateSheet(sheet.copyWith(groupMultiLevelCallouts: enabled));
}

void runSheetCalloutAutoLayout({bool? groupMultiLevel}) {
  final sheet = activeSheet;
  if (sheet == null) return;
  final effectiveGroup = groupMultiLevel ?? sheet.groupMultiLevelCallouts;
  final tempSheet = sheet.copyWith(groupMultiLevelCallouts: effectiveGroup);
  final layout = CalloutLayoutEngine.calculateSheetLayout(
    sheet: tempSheet,
    network: network,
    projector: currentAxonometryProjector,
  );
  // Сохраняем смещения для активного листа
  for (final entry in layout.entries) {
    updateCalloutSheetOffset(entry.key, entry.value);
  }
}
```

- [ ] **Step 2: Update SheetToolbar auto-layout menu and filter dialog**

In `lib/ui/canvas/sheet_toolbar.dart`:
1. In `PopupMenuButton` for auto-layout (`Icons.auto_fix_high`):
   - `PopupMenuItem(value: 'auto_grouped', child: Text('Авторасстановка (с этажерками)'))`
   - `PopupMenuItem(value: 'auto_single', child: Text('Авторасстановка (построчно)'))`
   - `PopupMenuDivider()`
   - `PopupMenuItem(value: 'reset_3d', child: Text('Сбросить выноски к 3D-модели'))`
2. In `_showCalloutFilterDialog`:
   - Add a `SwitchListTile`:
     - title: `Text('Группировать узлы в этажерки')`
     - subtitle: `Text('Объединять кран, фланцы и стыки в одну выноску')`
     - value: `sheet.groupMultiLevelCallouts`
     - onChanged: calls `controller.setSheetGroupMultiLevel(val)`

- [ ] **Step 3: Run static analysis**

Run: `flutter analyze`
Expected: 0 issues.

- [ ] **Step 4: Commit**

```bash
git add lib/ui/canvas/input_controller.dart lib/ui/canvas/sheet_toolbar.dart
git commit -m "feat(ui): add multi-level stacking toggle to SheetToolbar and filter dialog"
```

---

### Task 5: End-to-End Verification & Parity

**Files:**
- Inspect: `lib/domain/services/sheet_geometry_builder.dart`
- Inspect: `lib/data/services/pdf_export_service.dart`
- Modify: `PROJECT_MEMORY.md`

- [ ] **Step 1: Run full static analysis**

Run: `flutter analyze`
Expected: 0 issues found.

- [ ] **Step 2: Update PROJECT_MEMORY.md and Graphify**

Update `PROJECT_MEMORY.md` with:
- Boundary column callout auto-layout (Sweep-line boundary labeling).
- Dynamic adaptive pitch calculation based on `textHeight`.
- Optional multi-level node stacking with user toggle.
- Stamp keepout and elevation callout isolation.

Run: `graphify update .`

- [ ] **Step 3: Commit and push**

```bash
git add PROJECT_MEMORY.md graphify-out
git commit -m "docs: document boundary column layout and multi-level callouts in PROJECT_MEMORY"
git push || git push
```
