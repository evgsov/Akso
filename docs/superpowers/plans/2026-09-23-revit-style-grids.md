# Revit-Style Editable Coordinate Grids Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement full Revit-style interactive coordinate grids in Akso, including bubble toggles, alignment chain locks, temporary inter-axis dimensions, elbow break shoulders, in-place renaming with GOST auto-increment, and 3D in-plane ("лежачие") marks.

**Architecture:** Extended immutable `ConstructionAxis` model, pure geometric `GridSystemEngine` service for alignment chains and temporary dimensions, 3D ellipse and affine matrix text projection in `PipingCanvas`/`GridPainter`, enriched grip hit-testing in `InputController`, and comprehensive inspector controls in `DesktopCadLayout`.

**Tech Stack:** Flutter / Dart, `AxonometryProjector`, `PipingNetwork`, `Matrix4` 2D affine canvas transforms.

**Spec:** `docs/superpowers/specs/2026-09-23-revit-style-grids-design.md`

## Global Constraints
- Backward compatibility for `ConstructionAxis` serialization is strictly maintained.
- ГОСТ Р 21.101-2020 Clause 5.3.3 alphabetic rules: letters Ё, З, Й, О, Х, Ц, Ч, Щ, Ъ, Ы, Ь are never generated.
- Line styles follow ГОСТ 2.303 dash-dot-dot centerline standard.
- All unit tests must pass with 0 warnings in `flutter analyze`.

---

### Task 1: Domain Model Extension & Serialization (`ConstructionAxis`)

**Files:**
- Modify: `lib/domain/models/construction_axis.dart`
- Test: `test/construction_axis_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class ConstructionAxis {
    final String id;
    final String label;
    final Node3D startPoint;
    final Node3D endPoint;
    final bool isBuildingGrid;
    final bool showStartBubble;
    final bool showEndBubble;
    final double elevationZ;
    final Offset? startElbowOffset;
    final Offset? endElbowOffset;
    final bool isPinned;
    final bool is3dPlaneOriented;
    final bool isStartLocked;
    final bool isEndLocked;
    ...
  }
  ```

- [ ] **Step 1: Write the failing unit tests for new `ConstructionAxis` properties and serialization**

```dart
// test/construction_axis_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/construction_axis.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'dart:ui';

void main() {
  group('ConstructionAxis Revit properties', () {
    test('default values match expected Revit configuration', () {
      final axis = ConstructionAxis(
        id: 'ax1',
        label: '1',
        startPoint: const Node3D(id: 'n1', x: 0, y: 0, z: 0),
        endPoint: const Node3D(id: 'n2', x: 6000, y: 0, z: 0),
      );
      expect(axis.showStartBubble, isTrue);
      expect(axis.showEndBubble, isFalse);
      expect(axis.elevationZ, 0.0);
      expect(axis.isPinned, isFalse);
      expect(axis.is3dPlaneOriented, isTrue);
      expect(axis.isStartLocked, isTrue);
      expect(axis.isEndLocked, isTrue);
      expect(axis.startElbowOffset, isNull);
    });

    test('serialization round-trip with all fields', () {
      final axis = ConstructionAxis(
        id: 'ax2',
        label: 'А',
        startPoint: const Node3D(id: 'n1', x: 0, y: 0, z: 1000),
        endPoint: const Node3D(id: 'n2', x: 0, y: 6000, z: 1000),
        showStartBubble: true,
        showEndBubble: true,
        elevationZ: 1000.0,
        startElbowOffset: const Offset(15.0, -20.0),
        isPinned: true,
        is3dPlaneOriented: true,
        isStartLocked: false,
        isEndLocked: true,
      );
      final json = axis.toJson();
      final restored = ConstructionAxis.fromJson(json);
      expect(restored.id, 'ax2');
      expect(restored.showStartBubble, isTrue);
      expect(restored.showEndBubble, isTrue);
      expect(restored.elevationZ, 1000.0);
      expect(restored.startElbowOffset?.dx, 15.0);
      expect(restored.startElbowOffset?.dy, -20.0);
      expect(restored.isPinned, isTrue);
      expect(restored.isStartLocked, isFalse);
    });

    test('backward compatibility for legacy json', () {
      final legacyJson = {
        'id': 'legacy1',
        'label': 'Б',
        'startPoint': {'id': 'n1', 'x': 0.0, 'y': 0.0, 'z': 0.0},
        'endPoint': {'id': 'n2', 'x': 5000.0, 'y': 0.0, 'z': 0.0},
        'isBuildingGrid': true,
      };
      final restored = ConstructionAxis.fromJson(legacyJson);
      expect(restored.showStartBubble, isTrue);
      expect(restored.showEndBubble, isFalse);
      expect(restored.elevationZ, 0.0);
      expect(restored.isPinned, isFalse);
      expect(restored.is3dPlaneOriented, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/construction_axis_test.dart`
Expected: FAIL with compilation errors (missing fields)

- [ ] **Step 3: Update `ConstructionAxis` implementation**

Implement the new fields, updated `copyWith`, `toJson`, and `fromJson` in `lib/domain/models/construction_axis.dart`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/construction_axis_test.dart`
Expected: PASS

- [ ] **Step 5: Commit changes**

```bash
git add lib/domain/models/construction_axis.dart test/construction_axis_test.dart
git commit -m "feat(grid): extend ConstructionAxis model with Revit properties and serialization"
```

---

### Task 2: Domain Service `GridSystemEngine`

**Files:**
- Create: `lib/domain/services/grid_system_engine.dart`
- Test: `test/grid_system_engine_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class GridSystemEngine {
    static String generateNextLabel(String currentLabel);
    static List<AlignmentChain> findAlignmentChains(Map<String, ConstructionAxis> axes, {double toleranceMm = 50.0});
    static Map<String, ConstructionAxis> stretchChainedEndpoints(
      String draggedAxisId,
      bool isStart,
      Node3D newPoint,
      Map<String, ConstructionAxis> axes,
    );
    static List<TemporaryGridDimension> calculateTemporaryDimensions(
      String selectedAxisId,
      Map<String, ConstructionAxis> axes,
    );
    static ConstructionAxis moveAxisByDistance(
      ConstructionAxis axisToMove,
      ConstructionAxis referenceAxis,
      double targetDistanceMm,
    );
    static ConstructionAxis createOffsetAxis(
      ConstructionAxis sourceAxis,
      double offsetDistanceMm, {
      bool positiveSide = true,
    });
  }
  ```

- [ ] **Step 1: Write failing unit tests for `GridSystemEngine`**

Cover GOST label generation (digits, Cyrillic skipping Ё, З, Й, О, Х, Ц, Ч, Щ, Ъ, Ы, Ь, Latin), alignment chains detection, parallel distances, and axis displacement.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/grid_system_engine_test.dart`
Expected: FAIL (file not found)

- [ ] **Step 3: Implement `GridSystemEngine`**

Write `lib/domain/services/grid_system_engine.dart` with mathematical vector projections, normal calculations, and GOST 21.101 label sequences.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/grid_system_engine_test.dart`
Expected: PASS

- [ ] **Step 5: Commit changes**

```bash
git add lib/domain/services/grid_system_engine.dart test/grid_system_engine_test.dart
git commit -m "feat(grid): implement GridSystemEngine for GOST labels, alignment chains, and spacing"
```

---

### Task 3: 3D In-Plane Marks & ГОСТ Line Renderer in `PipingCanvas` & `GridPainter`

**Files:**
- Modify: `lib/ui/canvas/piping_canvas.dart`
- Modify: `lib/ui/canvas/painters/grid_painter.dart` (or dedicated `axis_painter.dart`)
- Test: `test/grid_3d_rendering_test.dart`

**Interfaces:**
- Consumes: `ConstructionAxis`, `AxonometryProjector`, `GridSystemEngine`
- Produces:
  ```dart
  void drawConstructionAxes(Canvas canvas);
  void drawGridBubble3d(Canvas canvas, AxonometryProjector projector, ConstructionAxis axis, Node3D point, bool isStart, ...);
  ```

- [ ] **Step 1: Write widget/painter test for 3D in-plane axis bubble rendering and ГОСТ line**

Test that when `is3dPlaneOriented == true`, `PipingCanvas` renders an ellipse and applies text transformation, and respects `showStartBubble` / `showEndBubble`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/grid_3d_rendering_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement ГОСТ 2.303 centerline, 3D in-plane marks, elbow shoulders, and grip handles**

Update `PipingCanvas` / `GridPainter` to:
- Render long-dash dot-dot lines.
- Render 3D in-plane marks using sampled circle points projected via `projector.project(Node3D(...))`.
- Apply affine matrix `Matrix4` so label text lies flat in $XY$ plane.
- Draw elbow break dogleg when `startElbowOffset` / `endElbowOffset` is non-null.
- Draw alignment lock padlock icons and bubble toggle checkboxes when selected.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/grid_3d_rendering_test.dart`
Expected: PASS

- [ ] **Step 5: Commit changes**

```bash
git add lib/ui/canvas/piping_canvas.dart test/grid_3d_rendering_test.dart
git commit -m "feat(grid): render ГОСТ centerline, 3D in-plane marks, and Revit grips"
```

---

### Task 4: Interactive Canvas Grips & Hit-Testing in `InputController`

**Files:**
- Modify: `lib/ui/canvas/input_controller.dart`
- Test: `test/grid_interactive_grips_test.dart`

**Interfaces:**
- Produces:
  ```dart
  enum AxisGripHitType {
    startHandle,
    endHandle,
    startBubbleToggle,
    endBubbleToggle,
    startLockToggle,
    endLockToggle,
    startElbow,
    endElbow,
    temporaryDimension,
  }
  ```

- [ ] **Step 1: Write failing controller test for interactive grips and chain dragging**

Verify:
- Toggling start/end bubble checkboxes updates axis.
- Dragging locked endpoint stretches entire aligned chain.
- Dragging unlocked endpoint stretches only this axis.
- Dragging elbow handle sets `startElbowOffset` / `endElbowOffset`.
- Clicking temporary dimension moves axis by distance.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/grid_interactive_grips_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement grip hit-testing and drag handlers in `InputController`**

Add hit-testing in `_findAxisGripAtScreenPos`, drag update in `handlePointerMove`, and mouse up in `handlePointerUp`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/grid_interactive_grips_test.dart`
Expected: PASS

- [ ] **Step 5: Commit changes**

```bash
git add lib/ui/canvas/input_controller.dart test/grid_interactive_grips_test.dart
git commit -m "feat(grid): implement interactive grips, alignment chain dragging, and elbow breaks"
```

---

### Task 5: Inspector Panel UI in `DesktopCadLayout`

**Files:**
- Modify: `lib/ui/features/editor/widgets/desktop_cad_layout.dart`
- Test: `test/grid_inspector_widget_test.dart`

**Interfaces:**
- Rich properties editor for selected `ConstructionAxis`:
  - Label text field with auto-increment button.
  - Start/End bubble checkboxes.
  - Elevation Z number field.
  - 3D in-plane vs 2D billboard radio/toggle.
  - Pin toggle.
  - "Создать смещение" (Offset) button with distance input.
  - "Сбросить изломы" (Reset Elbows) button.

- [ ] **Step 1: Write widget test for `DesktopCadLayout` axis properties inspector**

Test that inspector renders all controls and modifying them updates the network axis.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/grid_inspector_widget_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement inspector UI in `desktop_cad_layout.dart`**

Replace the read-only axis section in `DesktopCadLayout` with interactive form fields and action buttons.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/grid_inspector_widget_test.dart`
Expected: PASS

- [ ] **Step 5: Commit changes**

```bash
git add lib/ui/features/editor/widgets/desktop_cad_layout.dart test/grid_inspector_widget_test.dart
git commit -m "feat(ui): add comprehensive Revit-style inspector controls for coordinate axes"
```

---

### Task 6: Full Integration Verification & Documentation

**Files:**
- Modify: `PROJECT_MEMORY.md`

- [ ] **Step 1: Run full test suite**

Run: `flutter test`
Expected: All 679+ tests pass (100%).

- [ ] **Step 2: Run static analyzer**

Run: `flutter analyze`
Expected: 0 issues found.

- [ ] **Step 3: Update knowledge graph & PROJECT_MEMORY.md**

Run: `graphify update .`
Document new milestone in `PROJECT_MEMORY.md`.

- [ ] **Step 4: Commit changes**

```bash
git add PROJECT_MEMORY.md graphify-out/
git commit -m "docs: record Revit-style coordinate grids milestone and update knowledge graph"
```
