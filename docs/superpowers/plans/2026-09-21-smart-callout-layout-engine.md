# Smart Callout Layout & Collision Avoidance Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a high-performance 2D spatial layout and collision avoidance engine (`CalloutLayoutEngine`) that automatically organizes piping callouts into clean, readable, non-overlapping positions with vertical column stacking ("гребенки") and manual pinning support.

**Architecture:** 
- Mathematical 2D spatial map (`CalloutObstacleMap`) collects pipe segment corridors and callout bounding boxes.
- Multi-pass solver (`CalloutLayoutEngine`) evaluates dynamic radial-angular candidate positions via a weighted cost function, followed by a column stacking pass that aligns adjacent parallel callouts along uniform vertical ladders.
- User interface integrates one-click layout actions in `CalloutManagerPanel`, `DesktopCadLayout`, and `SheetToolbar`, respecting manual `isPinned` callouts.

**Tech Stack:** Dart, Flutter Canvas, Vector 2D math, AxonometryProjector, ViewportTransformService.

**Spec:** `docs/superpowers/specs/2026-09-21-smart-callout-layout-engine-design.md`

## Global Constraints

- 100% preservation of all existing callout types, text generation, templates, and ГОСТ drafting styles.
- Execution time under 50 ms for 100+ callouts (0 perceptible frame lag on mobile tablets).
- 0 warnings and 0 errors on `dart analyze lib test`.
- All 612 existing automated tests must continue to pass without regression.

---

### Task 1: Add `isPinned` Field and Serialization to `Callout` Model

**Files:**
- Modify: `lib/domain/models/callout.dart:1-120`
- Test: `test/callout_pinning_test.dart`

**Interfaces:**
- Produces:
  - `Callout.isPinned` (bool, default `false`)
  - `Callout.copyWith({bool? isPinned, ...})`
  - `Callout.toJson()` includes `'isPinned'`
  - `Callout.fromJson(Map<String, dynamic> json)` deserializes `'isPinned'` (fallback to `false` if missing)

- [ ] **Step 1: Write the failing test**

Create `test/callout_pinning_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/callout.dart';

void main() {
  group('Callout isPinned property', () {
    test('defaults to false', () {
      const callout = Callout(
        id: 'c1',
        targetId: 'seg1',
        targetType: CalloutTargetType.segment,
      );
      expect(callout.isPinned, isFalse);
    });

    test('copyWith updates isPinned', () {
      const callout = Callout(
        id: 'c1',
        targetId: 'seg1',
        targetType: CalloutTargetType.segment,
      );
      final pinned = callout.copyWith(isPinned: true);
      expect(pinned.isPinned, isTrue);
      final unpinned = pinned.copyWith(isPinned: false);
      expect(unpinned.isPinned, isFalse);
    });

    test('JSON serialization preserves isPinned', () {
      const callout = Callout(
        id: 'c1',
        targetId: 'seg1',
        targetType: CalloutTargetType.segment,
        isPinned: true,
      );
      final json = callout.toJson();
      expect(json['isPinned'], isTrue);

      final restored = Callout.fromJson(json);
      expect(restored.isPinned, isTrue);

      final legacy = Callout.fromJson({
        'id': 'c2',
        'targetId': 'seg2',
        'targetType': 'segment',
      });
      expect(legacy.isPinned, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/callout_pinning_test.dart`  
Expected: FAIL with "The named parameter 'isPinned' isn't defined"

- [ ] **Step 3: Implement `isPinned` in `Callout`**

Modify `lib/domain/models/callout.dart`:
Add `final bool isPinned;` to `Callout`, update constructor with `this.isPinned = false`, update `copyWith`, `toJson`, and `fromJson`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/callout_pinning_test.dart`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/domain/models/callout.dart test/callout_pinning_test.dart
git commit -m "feat: add isPinned flag and serialization to Callout model"
```

---

### Task 2: 2D Spatial Obstacle Model (`CalloutObstacleMap`)

**Files:**
- Create: `lib/domain/services/callout_layout_engine.dart`
- Test: `test/callout_layout_engine_test.dart`

**Interfaces:**
- Produces:
  - `class RectObstacle { final Rect rect; ... }`
  - `class SegmentObstacle { final Offset p1; final Offset p2; final double radius; ... }`
  - `class CalloutObstacleMap`
    - `void addRect(Rect rect)`
    - `void addPipe(Offset p1, Offset p2, double radiusPx)`
    - `bool testShelfCollision(Rect shelfRect)`
    - `int countLeaderLineIntersections(Offset start, Offset end)`
    - `double pointToSegmentDistance(Offset p, Offset s1, Offset s2)`

- [ ] **Step 1: Write the failing unit tests for geometry and obstacle map**

Create `test/callout_layout_engine_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/services/callout_layout_engine.dart';

void main() {
  group('CalloutObstacleMap', () {
    test('detects shelf overlap with existing callout rects', () {
      final map = CalloutObstacleMap();
      map.addRect(const Rect.fromLTWH(100, 100, 80, 20));

      // Overlapping rect
      expect(map.testShelfCollision(const Rect.fromLTWH(120, 110, 80, 20)), isTrue);
      // Disjoint rect
      expect(map.testShelfCollision(const Rect.fromLTWH(250, 100, 80, 20)), isFalse);
    });

    test('detects shelf collision with pipe corridor', () {
      final map = CalloutObstacleMap();
      map.addPipe(const Offset(0, 50), const Offset(200, 50), 10.0);

      // Shelf intersecting pipe
      expect(map.testShelfCollision(const Rect.fromLTWH(50, 45, 60, 20)), isTrue);
      // Shelf clearly outside pipe corridor
      expect(map.testShelfCollision(const Rect.fromLTWH(50, 80, 60, 20)), isFalse);
    });

    test('counts leader line intersections with pipes and other leader lines', () {
      final map = CalloutObstacleMap();
      // Pipe across Y=100
      map.addPipe(const Offset(0, 100), const Offset(200, 100), 5.0);

      // Leader crossing the pipe
      final count1 = map.countLeaderLineIntersections(const Offset(50, 50), const Offset(50, 150));
      expect(count1, equals(1));

      // Leader not crossing the pipe
      final count2 = map.countLeaderLineIntersections(const Offset(50, 110), const Offset(50, 150));
      expect(count2, equals(0));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/callout_layout_engine_test.dart`  
Expected: FAIL with "CalloutObstacleMap not found"

- [ ] **Step 3: Implement `CalloutObstacleMap` and 2D intersection primitives**

Create `lib/domain/services/callout_layout_engine.dart`:
Implement `RectObstacle`, `SegmentObstacle`, and `CalloutObstacleMap` with line-segment intersection algorithms (using 2D cross-products) and point-to-segment distance formulas.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/callout_layout_engine_test.dart`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/domain/services/callout_layout_engine.dart test/callout_layout_engine_test.dart
git commit -m "feat: implement 2D obstacle map and collision primitives for callouts"
```

---

### Task 3: Dynamic Radial-Angular Candidate Search & Cost Function

**Files:**
- Modify: `lib/domain/services/callout_layout_engine.dart`
- Test: `test/callout_layout_engine_test.dart`

**Interfaces:**
- Produces:
  - `class CalloutCandidate { final Offset shelfStart; final Offset shelfEnd; final Rect bounds; final double cost; ... }`
  - `CalloutCandidate? findBestCandidate(...)`
  - Evaluates cost weights:
    - `shelfTextOverlapPenalty = 10000.0`
    - `shelfPipeOverlapPenalty = 5000.0`
    - `leaderCrossPenalty = 800.0`
    - `distancePenaltyWeight = 1.5`
    - `columnAlignmentReward = 150.0`

- [ ] **Step 1: Write failing test for candidate generator and scoring**

Add to `test/callout_layout_engine_test.dart`:
```dart
    test('findBestCandidate avoids obstacles and chooses clear quadrant', () {
      final map = CalloutObstacleMap();
      // Block top-right quadrant with a pipe and obstacle
      map.addRect(const Rect.fromLTWH(110, 80, 100, 40));
      map.addPipe(const Offset(100, 100), const Offset(200, 50), 8.0);

      final anchor = const Offset(100, 100);
      const textWidth = 60.0;
      const textHeight = 12.0;

      final best = CalloutLayoutEngine.evaluateBestOffset(
        anchor: anchor,
        textWidth: textWidth,
        textHeight: textHeight,
        obstacleMap: map,
      );

      expect(best, isNotNull);
      // The chosen shelf rect must not collide with the obstacle
      final chosenBounds = Rect.fromLTWH(
        anchor.dx + best!.dx,
        anchor.dy + best.dy - textHeight - 4.0,
        textWidth + 10.0,
        textHeight + 8.0,
      );
      expect(map.testShelfCollision(chosenBounds), isFalse);
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/callout_layout_engine_test.dart`  
Expected: FAIL with "evaluateBestOffset not defined"

- [ ] **Step 3: Implement candidate generator and cost evaluation**

In `lib/domain/services/callout_layout_engine.dart`:
- Scan angles across 4 quadrants with adaptive steps ($15^\circ$ increments).
- Scan radii: 35 px, 50 px, 65 px, 85 px, 110 px, 140 px.
- Calculate cost for each candidate and select the candidate with minimal cost.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/callout_layout_engine_test.dart`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/domain/services/callout_layout_engine.dart test/callout_layout_engine_test.dart
git commit -m "feat: implement adaptive radial-angular candidate search and cost evaluation"
```

---

### Task 4: Multi-Pass Layout & Grebyonka Stacking Pass

**Files:**
- Modify: `lib/domain/services/callout_layout_engine.dart`
- Test: `test/callout_layout_engine_test.dart`

**Interfaces:**
- Produces:
  - `Map<String, Offset> CalloutLayoutEngine.calculateLayout({ ... })`
  - Sorts unpinned callouts by local anchor density (placing dense clusters first).
  - Grebyonka pass: identifies callouts whose shelves are within a horizontal threshold ($\pm 35$ px) and stacks them into a single column with uniform $Y$-spacing (18-24 px).

- [ ] **Step 1: Write failing test for full layout and column stacking (гребенка)**

Add to `test/callout_layout_engine_test.dart`:
```dart
    test('calculateLayout aligns parallel pipe callouts into a stacked column', () {
      final network = PipingNetwork();
      final n1 = network.addNode(x: 0, y: 0, z: 0);
      final n2 = network.addNode(x: 5000, y: 0, z: 0);
      final n3 = network.addNode(x: 0, y: 500, z: 0);
      final n4 = network.addNode(x: 5000, y: 500, z: 0);
      final seg1 = network.addSegment(startNodeId: n1.id, endNodeId: n2.id, outerDiameterMm: 108);
      final seg2 = network.addSegment(startNodeId: n3.id, endNodeId: n4.id, outerDiameterMm: 108);

      final c1 = Callout(id: 'c1', targetId: seg1.id, targetType: CalloutTargetType.segment);
      final c2 = Callout(id: 'c2', targetId: seg2.id, targetType: CalloutTargetType.segment);
      network.callouts[c1.id] = c1;
      network.callouts[c2.id] = c2;

      const projector = AxonometryProjector();
      final offsets = CalloutLayoutEngine.calculateLayout(
        network: network,
        projector: projector,
      );

      expect(offsets.containsKey('c1'), isTrue);
      expect(offsets.containsKey('c2'), isTrue);

      final off1 = offsets['c1']!;
      final off2 = offsets['c2']!;

      // They should not have identical offsets and their shelves must not collide
      expect((off1.dy - off2.dy).abs() >= 16.0 || (off1.dx - off2.dx).abs() >= 40.0, isTrue);
    });

    test('calculateLayout respects isPinned callouts and does not alter their offsets', () {
      final network = PipingNetwork();
      final n1 = network.addNode(x: 0, y: 0, z: 0);
      final n2 = network.addNode(x: 3000, y: 0, z: 0);
      final seg = network.addSegment(startNodeId: n1.id, endNodeId: n2.id, outerDiameterMm: 89);
      const customOffset = Offset(123.0, -88.0);
      final pinnedCallout = Callout(
        id: 'cp',
        targetId: seg.id,
        targetType: CalloutTargetType.segment,
        screenOffsetX: customOffset.dx,
        screenOffsetY: customOffset.dy,
        isPinned: true,
      );
      network.callouts[pinnedCallout.id] = pinnedCallout;

      final offsets = CalloutLayoutEngine.calculateLayout(
        network: network,
        projector: const AxonometryProjector(),
        onlyUnpinned: true,
      );

      expect(offsets['cp'], equals(customOffset));
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/callout_layout_engine_test.dart`  
Expected: FAIL with "calculateLayout not defined"

- [ ] **Step 3: Implement `calculateLayout` and column stacking pass**

In `lib/domain/services/callout_layout_engine.dart`:
- Collect obstacles: pipe corridors, equipment, pinned callout bounding boxes.
- Compute initial candidate offsets for unpinned callouts sorted by anchor density.
- Run grebyonka column clustering pass: detect vertical alignment clusters, align X-offset, and space Y-offsets evenly.
- Return `Map<String, Offset>`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/callout_layout_engine_test.dart`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/domain/services/callout_layout_engine.dart test/callout_layout_engine_test.dart
git commit -m "feat: implement multi-pass layout and column stacking in CalloutLayoutEngine"
```

---

### Task 5: Integrate `CalloutLayoutEngine` into `PipingInputController`

**Files:**
- Modify: `lib/ui/canvas/input_controller.dart`
- Test: `test/callout_layout_integration_test.dart`

**Interfaces:**
- Produces:
  - `int PipingInputController.autoLayoutCallouts({bool onlyUnpinned = true})`
  - `void PipingInputController.toggleCalloutPinning(String calloutId)`
  - `void PipingInputController.unpinAllCallouts()`
  - Setting `isPinned = true` automatically in `handlePointerUp` when a callout has been dragged.
  - History tracking (Undo / Redo works seamlessly).

- [ ] **Step 1: Write integration test for controller autoLayoutCallouts**

Create `test/callout_layout_integration_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/ui/canvas/input_controller.dart';

void main() {
  test('PipingInputController.autoLayoutCallouts updates callouts and records history', () {
    final network = PipingNetwork();
    final n1 = network.addNode(x: 0, y: 0, z: 0);
    final n2 = network.addNode(x: 4000, y: 0, z: 0);
    final seg = network.addSegment(startNodeId: n1.id, endNodeId: n2.id, outerDiameterMm: 108);
    final c1 = Callout(id: 'c1', targetId: seg.id, targetType: CalloutTargetType.segment);
    network.callouts[c1.id] = c1;

    final controller = PipingInputController(initialNetwork: network);
    expect(controller.canUndo, isFalse);

    final updated = controller.autoLayoutCallouts();
    expect(updated, greaterThanOrEqualTo(1));
    expect(controller.canUndo, isTrue);

    // Undo restores previous state
    controller.undo();
    expect(controller.network.callouts['c1']?.screenOffsetX, equals(c1.screenOffsetX));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/callout_layout_integration_test.dart`  
Expected: FAIL with "autoLayoutCallouts isn't defined"

- [ ] **Step 3: Implement controller methods in `PipingInputController`**

In `lib/ui/canvas/input_controller.dart`:
- Implement `autoLayoutCallouts({bool onlyUnpinned = true})`.
- In `handlePointerUp()`, when `isDraggingCallout` finishes, mark the dragged callout with `callout.copyWith(isPinned: true)`.
- Implement `toggleCalloutPinning(String calloutId)` and `unpinAllCallouts()`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/callout_layout_integration_test.dart`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/ui/canvas/input_controller.dart test/callout_layout_integration_test.dart
git commit -m "feat: integrate autoLayoutCallouts and pin tracking into PipingInputController"
```

---

### Task 6: UI Controls Integration in Panels and Toolbars

**Files:**
- Modify: `lib/ui/features/editor/widgets/callout_manager_panel.dart`
- Modify: `lib/ui/features/editor/widgets/desktop_cad_layout.dart`
- Modify: `lib/ui/features/editor/widgets/sheet_toolbar.dart`
- Test: `test/callout_ui_actions_test.dart`

**Interfaces:**
- Produces:
  - "Авто-расстановка" button in `CalloutManagerPanel` with options ("Расставить незакрепленные", "Пересчитать все").
  - "Авто-расстановка выносок" action in `DesktopCadLayout` toolbar and `SheetToolbar`.
  - Pin / Unpin indicator and action in callout item rows.

- [ ] **Step 1: Write widget test for callout layout UI button**

Create `test/callout_ui_actions_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/ui/canvas/input_controller.dart';
import 'package:akso/ui/features/editor/widgets/callout_manager_panel.dart';

void main() {
  testWidgets('CalloutManagerPanel shows auto-layout button and triggers layout', (tester) async {
    final network = PipingNetwork();
    final n1 = network.addNode(x: 0, y: 0, z: 0);
    final n2 = network.addNode(x: 3000, y: 0, z: 0);
    network.addSegment(startNodeId: n1.id, endNodeId: n2.id, outerDiameterMm: 89);
    final controller = PipingInputController(initialNetwork: network);
    controller.generateMissingCallouts();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CalloutManagerPanel(controller: controller),
        ),
      ),
    );

    final autoLayoutButton = find.byKey(const Key('auto_layout_callouts_button'));
    expect(autoLayoutButton, findsOneWidget);

    await tester.tap(autoLayoutButton);
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/callout_ui_actions_test.dart`  
Expected: FAIL with "auto_layout_callouts_button not found"

- [ ] **Step 3: Add UI buttons in `CalloutManagerPanel`, `DesktopCadLayout`, and `SheetToolbar`**

- In `CalloutManagerPanel`: add `FilledButton.icon` with key `'auto_layout_callouts_button'`, icon `Icons.auto_fix_high`, and label `'Авто-расстановка'`.
- Add pin icon toggle on each callout row.
- In `DesktopCadLayout` and `SheetToolbar`: add quick action icon button to trigger `controller.autoLayoutCallouts()`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/callout_ui_actions_test.dart`  
Expected: PASS

- [ ] **Step 5: Run full project verification**

Run:
1. `dart analyze lib test` (must be 0 issues)
2. `flutter test` (all 612+ tests must pass)
3. `graphify update .`

- [ ] **Step 6: Commit**

```bash
git add lib/ui/features/editor/widgets/callout_manager_panel.dart \
        lib/ui/features/editor/widgets/desktop_cad_layout.dart \
        lib/ui/features/editor/widgets/sheet_toolbar.dart \
        test/callout_ui_actions_test.dart
git commit -m "feat: add auto-layout UI buttons and pin indicators to panels and toolbars"
```
