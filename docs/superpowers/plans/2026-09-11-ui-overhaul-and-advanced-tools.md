# UI Overhaul, Dual Layout Styles & Advanced CAD Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform Akso into a professional, scalable CAD/BIM solution with dual layout modes (Desktop CAD and Tablet Touch), Undo/Redo history, operation cancellation, magnetic snapping, polar angle tracking, construction grid axes, Revit-style piping systems management, and universal fitting prototype cloning.

**Architecture:** 
- `PipingHistoryManager`: JSON-based circular state snapshot manager providing 50-step undo/redo.
- `SnapEngine`: screen-space and world-space magnetic snapping to nodes, pipe segment axes, grid axes, and angular ray projections ($30^\circ, 45^\circ, 90^\circ$, custom, free).
- `ConstructionAxis`: building grid lines with circular bubbles per ГОСТ 21.101 and DXF export (`АКСО_ОСИ`).
- `PipingSystem`: Revit-style parameterized systems with default steel grades, allowed DN ranges, and custom system management.
- `EditorLayoutScaffold`: adaptive shell hosting `DesktopCadLayout` (left tool palette, options bar, status bar) and `TabletTouchLayout` (clean canvas, floating tool island, touch-sized buttons, bottom parameters sheet).

**Tech Stack:** Flutter 3.x / Dart, CustomPaint canvas, Vector math, AutoCAD DXF ASCII R2000.

**Spec:** `docs/superpowers/specs/2026-09-11-ui-overhaul-and-advanced-tools-design.md`

## Global Constraints
- Full adherence to ГОСТ 21.602, ГОСТ 21.101, ГОСТ 2.303, ГОСТ 16037-80, ГОСТ 33259-2015.
- Zero analysis errors or warnings (`flutter analyze`).
- 100% passing automated test suite (`flutter test`).
- Responsive layout with touch targets $\ge 48\times48$ pt in tablet mode and compact density in desktop mode.

---

### Task 1: Network History & State Management (Undo / Redo + Action Cancellation)

**Files:**
- Create: `lib/domain/models/network_history_manager.dart`
- Modify: `lib/ui/canvas/input_controller.dart`
- Test: `test/network_history_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class NetworkHistoryManager {
    void recordState(PipingNetwork network);
    bool undo(PipingNetwork network);
    bool redo(PipingNetwork network);
    bool get canUndo;
    bool get canRedo;
    void clear();
  }
  ```
- Consumes: `PipingNetwork.toJson()`, `PipingNetwork.loadFromJson()`, `PipingNetwork.recalculateSpools()`.

- [ ] **Step 1: Write the failing unit tests for NetworkHistoryManager and cancel operation**

```dart
// test/network_history_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/network_history_manager.dart';

void main() {
  group('NetworkHistoryManager Tests', () {
    late PipingNetwork network;
    late NetworkHistoryManager history;

    setUp(() {
      network = PipingNetwork();
      history = NetworkHistoryManager(maxSnapshots: 20);
    });

    test('Фиксация состояния, Undo и Redo восстанавливают структуру сети', () {
      expect(history.canUndo, isFalse);
      expect(history.canRedo, isFalse);

      // Сохраняем исходное пустое состояние
      history.recordState(network);

      // Добавляем узел и трубу
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.segments['seg1'] = const PipeSegment(id: 'seg1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_b1', dn: 50);
      history.recordState(network);

      expect(history.canUndo, isTrue);
      expect(history.canRedo, isFalse);

      // Добавляем еще один узел
      network.nodes['n3'] = const Node3D(id: 'n3', x: 1000, y: 1000, z: 0);
      network.segments['seg2'] = const PipeSegment(id: 'seg2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys_b1', dn: 50);
      history.recordState(network);

      expect(network.segments.length, equals(2));

      // Откат на 1 шаг назад
      final undo1 = history.undo(network);
      expect(undo1, isTrue);
      expect(network.segments.length, equals(1));
      expect(history.canRedo, isTrue);

      // Откат еще на 1 шаг назад (к пустому состоянию)
      final undo2 = history.undo(network);
      expect(undo2, isTrue);
      expect(network.segments.isEmpty, isTrue);

      // Повтор вперед (Redo)
      final redo1 = history.redo(network);
      expect(redo1, isTrue);
      expect(network.segments.length, equals(1));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**
Run: `flutter test test/network_history_test.dart`
Expected: Compilation failure due to missing `NetworkHistoryManager`.

- [ ] **Step 3: Implement `NetworkHistoryManager` and wire into `PipingInputController`**
Create `lib/domain/models/network_history_manager.dart`:
```dart
import 'dart:convert';
import 'piping_network.dart';

class NetworkHistoryManager {
  final int maxSnapshots;
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];

  NetworkHistoryManager({this.maxSnapshots = 50});

  bool get canUndo => _undoStack.length > 1;
  bool get canRedo => _redoStack.isNotEmpty;

  void recordState(PipingNetwork network) {
    final snapshot = jsonEncode(network.toJson());
    if (_undoStack.isNotEmpty && _undoStack.last == snapshot) {
      return;
    }
    _undoStack.add(snapshot);
    if (_undoStack.length > maxSnapshots) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  bool undo(PipingNetwork network) {
    if (!canUndo) return false;
    final currentState = _undoStack.removeLast();
    _redoStack.add(currentState);
    final previousState = _undoStack.last;
    final Map<String, dynamic> json = jsonDecode(previousState);
    network.loadFromJson(json);
    network.recalculateSpools();
    return true;
  }

  bool redo(PipingNetwork network) {
    if (!canRedo) return false;
    final stateToRestore = _redoStack.removeLast();
    _undoStack.add(stateToRestore);
    final Map<String, dynamic> json = jsonDecode(stateToRestore);
    network.loadFromJson(json);
    network.recalculateSpools();
    return true;
  }

  void clear() {
    _undoStack.clear();
    _redoStack.clear();
  }
}
```
Add `undo()`, `redo()`, `cancelCurrentOperation()`, `recordState()` to `PipingInputController`.

- [ ] **Step 4: Run test to verify it passes**
Run: `flutter test test/network_history_test.dart`
Expected: PASS.

---

### Task 2: Snapping Engine & Polar Angle Tracking

**Files:**
- Create: `lib/core/math/snap_engine.dart`
- Modify: `lib/ui/canvas/input_controller.dart`
- Modify: `lib/ui/canvas/piping_canvas.dart`
- Test: `test/snap_engine_test.dart`

**Interfaces:**
- Produces:
  ```dart
  enum SnapType { none, node, segmentAxis, gridAxis, polarAngle }
  enum AngleSnapMode { ortho90, isometric45, iso30, custom, free }
  class SnapResult {
    final SnapType type;
    final Offset screenPoint;
    final Node3D worldPoint;
    final String label;
    final double? snapAngleDegrees;
  }
  ```

- [ ] **Step 1: Write failing tests for SnapEngine and Polar Angle calculations**
Test polar angle snapping with $90^\circ, 45^\circ, 30^\circ$, and node snapping.

- [ ] **Step 2: Run test to verify it fails**
Run: `flutter test test/snap_engine_test.dart`

- [ ] **Step 3: Implement `SnapEngine` with angle tracking and magnetic capture**
Implement polar snapping math ($\Delta X, \Delta Y \to \theta$, snap to nearest step with $\pm 5^\circ$ tolerance), distance to nodes/segments, and visual markers in `PipingCanvasPainter`.

- [ ] **Step 4: Run tests to verify they pass**
Run: `flutter test test/snap_engine_test.dart`
Expected: PASS.

---

### Task 3: Construction Lines & Building Grid Axes (`ConstructionAxis`)

**Files:**
- Create: `lib/domain/models/construction_axis.dart`
- Modify: `lib/domain/models/piping_network.dart`
- Modify: `lib/data/dxf/dxf_writer.dart`
- Modify: `lib/ui/canvas/piping_canvas.dart`
- Modify: `lib/ui/canvas/input_controller.dart`
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
  }
  ```

- [ ] **Step 1: Write failing unit tests for ConstructionAxis serialization and DXF output**
Verify axis creation, serialization in `PipingNetwork`, and layer `АКСО_ОСИ` generation in `DxfWriter`.

- [ ] **Step 2: Run test to verify it fails**
Run: `flutter test test/construction_axis_test.dart`

- [ ] **Step 3: Implement `ConstructionAxis`, rendering in canvas, and DXF exporter layer**
Implement dash-dot line drawing, circle labels on ends (ГОСТ 21.101), add to `DxfWriter` with ACI 8 color and DASHDOT linetype.

- [ ] **Step 4: Run test to verify it passes**
Run: `flutter test test/construction_axis_test.dart`
Expected: PASS.

---

### Task 4: Revit-Style Piping Systems Model & Manager Dialog

**Files:**
- Modify: `lib/domain/models/piping_system.dart`
- Modify: `lib/domain/models/piping_network.dart`
- Create: `lib/ui/features/editor/widgets/piping_systems_dialog.dart`
- Test: `test/piping_systems_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class PipingSystem {
    final String defaultMaterial;
    final List<int> availableDns;
    final bool isCustom;
    // ...
  }
  ```

- [ ] **Step 1: Write failing tests for custom PipingSystem creation and serialization**
- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Implement extended `PipingSystem` and `PipingSystemsDialog`**
Add system creation, editing, color picker, steel grade, allowed diameters, and routing preferences.
- [ ] **Step 4: Run test to verify it passes**
Run: `flutter test test/piping_systems_test.dart`
Expected: PASS.

---

### Task 5: Custom Fitting Constructor Improvements («Создать на основе...»)

**Files:**
- Modify: `lib/ui/features/editor/widgets/fitting_catalog_dialog.dart`
- Test: `test/fitting_catalog_test.dart`

- [ ] **Step 1: Write failing test verifying base prototype selection and cloning**
- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Update `FittingCatalogDialog` with base definition dropdown selector and clone button**
- [ ] **Step 4: Run test to verify it passes**

---

### Task 6: Viewport Navigation & Mouse/Touch Gesture Engine

**Files:**
- Modify: `lib/ui/canvas/input_controller.dart`
- Modify: `lib/ui/features/editor/editor_screen.dart`
- Test: `test/viewport_navigation_test.dart`

- [ ] **Step 1: Write failing test for MMB pan, RMB orbit, wheel zoom, and Escape/cancel actions**
- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Implement pointer routing and keyboard listener**
Listen for:
- MMB drag / Space + Drag $\to$ Pan
- RMB drag $\to$ 3D Orbit (in 3D) or Cancel / Context menu (in 2D)
- Scroll wheel $\to$ Zoom to cursor
- Key `Esc` $\to$ `cancelCurrentOperation()`
- Key `Ctrl+Z` $\to$ `undo()`, `Ctrl+Y` $\to$ `redo()`
- [ ] **Step 4: Run test to verify it passes**

---

### Task 7: Two UI Layout Styles: Desktop CAD Layout & Tablet Touch Layout

**Files:**
- Create: `lib/ui/features/editor/widgets/desktop_cad_layout.dart`
- Create: `lib/ui/features/editor/widgets/tablet_touch_layout.dart`
- Modify: `lib/ui/features/editor/editor_screen.dart`
- Modify: `lib/ui/features/editor/widgets/top_bar.dart`
- Modify: `lib/ui/features/editor/widgets/tools_panel.dart`
- Test: `test/widget_test.dart`

- [ ] **Step 1: Write failing widget test verifying switching between Desktop CAD and Tablet Touch modes**
- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Implement `DesktopCadLayout` and `TabletTouchLayout`**
- `DesktopCadLayout`: Slim header with Undo/Redo, left docked vertical CAD tool palette, horizontal top options bar, bottom status bar with coordinates & snap info, right floating property inspector.
- `TabletTouchLayout`: Clean full-screen canvas, floating tool island with $\ge 48\times48$ pt buttons, floating action buttons (Undo, Redo, Cancel, Properties), bottom collapsible sheet.
- Add mode switch button in header («🖥️ Десктоп / 📱 Планшет»).
- [ ] **Step 4: Run test to verify it passes**
Run: `flutter test test/widget_test.dart`
Expected: PASS.

---

### Task 8: Full Verification & Static Analysis

- [ ] **Step 1: Run complete automated test suite**
Run: `flutter test`
Expected: All 30+ tests pass.

- [ ] **Step 2: Run static code analysis**
Run: `flutter analyze`
Expected: No issues found!

- [ ] **Step 3: Update knowledge graph and project memory**
Run: `graphify update .`
Update `PROJECT_MEMORY.md` and `walkthrough.md`.
