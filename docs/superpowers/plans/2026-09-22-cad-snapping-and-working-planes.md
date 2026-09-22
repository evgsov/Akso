# CAD Snapping Engine, 3D Object Snap Tracking (OTRACK), and Working Planes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement AutoCAD-style Hover-to-Acquire 3D OTRACK (horizontal & vertical $\pm Z$ rays), Working Plane Z-Lock isolation with toggleable axonometric grid and level dimming, and granular Osnap Settings popover controls in the status bar to eliminate cursor stickiness and elevation jumps.

**Architecture:** A clean immutable `DraftingSettings` model configures `SnapEngine` with strict Z-plane filtering and disables nearest-pipe snapping by default; `TracingController` manages hover dwelling ($\ge 350\text{ ms}$) to acquire up to 2 tracking points; `SnapEngine` casts single-point 3D rays (orthogonal, axial, and vertical riser with dynamic $\Delta Z$ badges) and computes dual-point ray intersections; `PipingCanvas` renders CAD `+` crosses, dashed rays, elevation tooltips, subtle grid planes, and dims non-active levels; `DesktopCadLayout` provides split-button Osnap toggles and Z-lock controls in the status bar.

**Tech Stack:** Flutter / Dart, CustomPainter, 2.5D Axonometry Vector Math.

**Spec:** docs/superpowers/specs/2026-09-22-cad-snapping-and-working-planes-design.md

## Global Constraints
- Flutter 3.41 / Dart SDK constraints.
- DO NOT run `flutter test` or `dart test` as native-assets hooks for `objective_c-9.5.0` hang on Windows. Use `flutter analyze` for verification.
- Always use `flutter analyze` after each task to ensure 0 errors and 0 warnings.
- Keep `PROJECT_MEMORY.md` and `graphify update .` updated after finishing all tasks.

---

### Task 1: Core Models — `DraftingSettings` and `AcquiredTrackingPoint`

**Files:**
- Create: `lib/core/math/drafting_settings.dart`
- Create: `lib/domain/models/acquired_tracking_point.dart`
- Test: `test/drafting_settings_model_test.dart`

**Interfaces:**
- Consumes: `Node3D` from `lib/domain/models/node_3d.dart`
- Produces:
  - `class DraftingSettings`: immutable with boolean flags (`snapNodes`, `snapIntersections`, `snapMidpoints`, `snapPerpendicular`, `snapNearest`, `enableOtrack`, `isZLocked`, `showZPlaneGrid`, `nodeSnapRadius`, `nearestSnapRadius`) and `copyWith`.
  - `class AcquiredTrackingPoint`: holds `Node3D worldPoint`, `Offset screenPoint`, `String? nodeId`, `String? segmentId`, and `DateTime acquiredAt`.

- [ ] **Step 1: Write unit test for `DraftingSettings` and `AcquiredTrackingPoint`**

```dart
// test/drafting_settings_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/drafting_settings.dart';
import 'package:akso/domain/models/acquired_tracking_point.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:flutter/material.dart';

void main() {
  group('DraftingSettings', () {
    test('default constructor has correct CAD drafting defaults', () {
      const settings = DraftingSettings();
      expect(settings.snapNodes, isTrue);
      expect(settings.snapIntersections, isTrue);
      expect(settings.snapMidpoints, isTrue);
      expect(settings.snapPerpendicular, isTrue);
      expect(settings.snapNearest, isFalse, reason: 'Nearest must be false by default to prevent stickiness');
      expect(settings.enableOtrack, isTrue);
      expect(settings.isZLocked, isTrue);
      expect(settings.showZPlaneGrid, isFalse);
      expect(settings.nodeSnapRadius, equals(20.0));
      expect(settings.nearestSnapRadius, equals(8.0));
    });

    test('copyWith works properly', () {
      const settings = DraftingSettings();
      final updated = settings.copyWith(snapNearest: true, isZLocked: false);
      expect(updated.snapNearest, isTrue);
      expect(updated.isZLocked, isFalse);
      expect(updated.snapNodes, isTrue);
    });
  });

  group('AcquiredTrackingPoint', () {
    test('instantiates with correct fields', () {
      final now = DateTime.now();
      final pt = AcquiredTrackingPoint(
        worldPoint: const Node3D(id: 'n1', x: 100, y: 200, z: 0),
        screenPoint: const Offset(50, 60),
        nodeId: 'n1',
        acquiredAt: now,
      );
      expect(pt.nodeId, equals('n1'));
      expect(pt.worldPoint.x, equals(100));
      expect(pt.screenPoint.dx, equals(50));
    });
  });
}
```

- [ ] **Step 2: Implement `DraftingSettings` in `lib/core/math/drafting_settings.dart`**

```dart
class DraftingSettings {
  final bool snapNodes;
  final bool snapIntersections;
  final bool snapMidpoints;
  final bool snapPerpendicular;
  final bool snapNearest;
  final bool enableOtrack;
  final bool isZLocked;
  final bool showZPlaneGrid;
  final double nodeSnapRadius;
  final double nearestSnapRadius;

  const DraftingSettings({
    this.snapNodes = true,
    this.snapIntersections = true,
    this.snapMidpoints = true,
    this.snapPerpendicular = true,
    this.snapNearest = false,
    this.enableOtrack = true,
    this.isZLocked = true,
    this.showZPlaneGrid = false,
    this.nodeSnapRadius = 20.0,
    this.nearestSnapRadius = 8.0,
  });

  DraftingSettings copyWith({
    bool? snapNodes,
    bool? snapIntersections,
    bool? snapMidpoints,
    bool? snapPerpendicular,
    bool? snapNearest,
    bool? enableOtrack,
    bool? isZLocked,
    bool? showZPlaneGrid,
    double? nodeSnapRadius,
    double? nearestSnapRadius,
  }) {
    return DraftingSettings(
      snapNodes: snapNodes ?? this.snapNodes,
      snapIntersections: snapIntersections ?? this.snapIntersections,
      snapMidpoints: snapMidpoints ?? this.snapMidpoints,
      snapPerpendicular: snapPerpendicular ?? this.snapPerpendicular,
      snapNearest: snapNearest ?? this.snapNearest,
      enableOtrack: enableOtrack ?? this.enableOtrack,
      isZLocked: isZLocked ?? this.isZLocked,
      showZPlaneGrid: showZPlaneGrid ?? this.showZPlaneGrid,
      nodeSnapRadius: nodeSnapRadius ?? this.nodeSnapRadius,
      nearestSnapRadius: nearestSnapRadius ?? this.nearestSnapRadius,
    );
  }
}
```

- [ ] **Step 3: Implement `AcquiredTrackingPoint` in `lib/domain/models/acquired_tracking_point.dart`**

```dart
import 'package:flutter/material.dart';
import 'node_3d.dart';

class AcquiredTrackingPoint {
  final Node3D worldPoint;
  final Offset screenPoint;
  final String? nodeId;
  final String? segmentId;
  final DateTime acquiredAt;

  const AcquiredTrackingPoint({
    required this.worldPoint,
    required this.screenPoint,
    this.nodeId,
    this.segmentId,
    required this.acquiredAt,
  });
}
```

- [ ] **Step 4: Verify with `flutter analyze`**

Run: `flutter analyze`  
Expected: 0 issues found.

- [ ] **Step 5: Commit**

```bash
git add lib/core/math/drafting_settings.dart lib/domain/models/acquired_tracking_point.dart test/drafting_settings_model_test.dart
git commit -m "feat(cad): add DraftingSettings and AcquiredTrackingPoint models"
```

---

### Task 2: Point Acquisition Logic in `TracingController` and `InputController`

**Files:**
- Modify: `lib/ui/canvas/controllers/tracing_controller.dart`
- Modify: `lib/ui/canvas/input_controller.dart`

**Interfaces:**
- Consumes: `DraftingSettings`, `AcquiredTrackingPoint`
- Produces:
  - `TracingController.draftingSettings`
  - `TracingController.acquiredPoints` (List up to 2)
  - `TracingController.processHoverDwell(Offset screenPos, Node3D? candidateNode, VoidCallback onAcquired)`
  - `TracingController.clearAcquiredPoints()`
  - `TracingController.updateDraftingSettings(DraftingSettings newSettings)`
  - `InputController.draftingSettings`, `InputController.setDraftingSettings()`

- [ ] **Step 1: Add acquisition timer & management to `TracingController`**
  - Add `DraftingSettings draftingSettings = const DraftingSettings();`
  - Add `final List<AcquiredTrackingPoint> acquiredPoints = [];`
  - Add `Timer? _hoverDwellTimer;`
  - Add `String? _pendingDwellNodeId;`
  - Implement `processHoverDwell(...)`:
    - If `candidateNode == null`, cancel `_hoverDwellTimer` and set `_pendingDwellNodeId = null`.
    - If `candidateNode != null`:
      - If `_pendingDwellNodeId != candidateNode.id`: cancel previous timer, record `_pendingDwellNodeId = candidateNode.id`, and start a 350 ms timer.
      - Upon timer expiration: toggle node in `acquiredPoints`. If already in list -> remove it; if not -> add to list (FIFO, keep max 2). Invoke callback.
  - Implement `clearAcquiredPoints()`: cancel timer and `acquiredPoints.clear()`.
  - Implement `updateDraftingSettings(DraftingSettings settings)`.

- [ ] **Step 2: Connect hover acquisition in `InputController.dart`**
  - Expose `DraftingSettings get draftingSettings => tracingController.draftingSettings;`
  - In `handlePointerHover(Offset screenPos)`:
    - If `isSnapEnabled && draftingSettings.enableOtrack`:
      - Detect if cursor is hovering over any node within 16 px.
      - Call `tracingController.processHoverDwell(screenPos, candidateNode, notifyListeners);`
    - When user left-clicks or places a point (`commitNode`, `handleTap`): call `tracingController.clearAcquiredPoints();`
    - In `cancelTrace()` / `resetToolState()`: call `tracingController.clearAcquiredPoints();`
  - Add `void toggleZLock()` and `void toggleZGrid()`.
  - Pass `draftingSettings` and `acquiredPoints` into `snapEngine.findSnap(...)`.

- [ ] **Step 3: Verify with `flutter analyze`**

Run: `flutter analyze`  
Expected: 0 issues found.

- [ ] **Step 4: Commit**

```bash
git add lib/ui/canvas/controllers/tracing_controller.dart lib/ui/canvas/input_controller.dart
git commit -m "feat(cad): integrate hover-to-acquire point tracker into tracing controller"
```

---

### Task 3: Enhanced `SnapEngine` with Z-Lock, Granular Filters, and 3D OTRACK

**Files:**
- Modify: `lib/core/math/snap_engine.dart`

**Interfaces:**
- Consumes: `DraftingSettings`, `List<AcquiredTrackingPoint>`
- Produces:
  - `SnapResult.findSnap(...)` accepting `DraftingSettings settings` and `List<AcquiredTrackingPoint> acquiredPoints = const []`.
  - Strict planar isolation when `settings.isZLocked == true`: skips discrete points and segments with $|Z - currentElevationZ| > 15$ mm.
  - Granular toggles for `snapNodes`, `snapIntersections`, `snapMidpoints`, `snapPerpendicular`, and `snapNearest`.
  - Single-point 3D OTRACK:
    - Emits $X, Y$ orthogonal rays and pipe axial continuation.
    - Emits **vertical riser ray ($\pm Z$)**: allows snapping along the vertical line with label `⬆ Стояк по створу [ΔZ: +X мм | ∇+Y.YYY]`.
    - Allows planar projection of vertical riser ray onto $Z = currentElevationZ$.
  - Dual-point OTRACK: computes 3D/planar ray intersection when 2 points are acquired.

- [ ] **Step 1: Update `findSnap()` signature and parameter plumbing in `snap_engine.dart`**
  - Add `DraftingSettings settings = const DraftingSettings()` and `List<AcquiredTrackingPoint> acquiredPoints = const []` to `findSnap()`.

- [ ] **Step 2: Add Z-Lock planar checks to discrete nodes, axes, midpoints, and perpendiculars**
  - In section 1.1 (Nodes): if `!settings.snapNodes`, skip nodes loop. If `settings.isZLocked`, only evaluate `node` if `(node.z - currentElevationZ).abs() <= 15.0`.
  - In section 1.2 (Axis endpoints): skip if `!settings.snapNodes`.
  - In section 1.3 & 1.4 (Intersections): skip if `!settings.snapIntersections`.
  - In section 2 (Midpoints): skip if `!settings.snapMidpoints`.
  - In section 2 (Perpendiculars): skip if `!settings.snapPerpendicular`.
  - In section 3 (Nearest / `segmentAxis`): skip if `!settings.snapNearest`! If enabled, use `settings.nearestSnapRadius` (8.0 px) instead of 18.0 px.

- [ ] **Step 3: Refactor `_findObjectTrackingSnap` to use acquired points and 3D rays**
  - If `!settings.enableOtrack || acquiredPoints.isEmpty`, return `null`.
  - Single acquired point:
    - Cast rays: $[1, 0, 0]$, $[0, 1, 0]$, connected pipe directions, and vertical riser vector $[0, 0, \pm 1]$.
    - Calculate distance from cursor to 3D rays projected on screen.
    - If cursor matches vertical riser ray:
      - Calculate $\Delta Z = rawWorld.z - pt.worldPoint.z$ (or elevation delta).
      - Build rich label: `⬆ Стояк по створу [ΔZ: +${deltaZ.round()} мм | ∇${elevM}]`.
  - Dual acquired points:
    - If 2 points exist, calculate the 2D intersection of their projection rays.
    - If cursor within 14 px of intersection, return `SnapType.intersection` with label `⤧ Пересечение створов`.

- [ ] **Step 4: Verify with `flutter analyze`**

Run: `flutter analyze`  
Expected: 0 issues found.

- [ ] **Step 5: Commit**

```bash
git add lib/core/math/snap_engine.dart
git commit -m "feat(cad): enhance SnapEngine with Z-Lock, granular Osnap filters, and 3D OTRACK"
```

---

### Task 4: Canvas Visualization (`piping_canvas.dart` & `pipe_painter.dart`)

**Files:**
- Modify: `lib/ui/canvas/piping_canvas.dart`
- Modify: `lib/ui/canvas/painters/pipe_painter.dart`

**Interfaces:**
- Consumes: `acquiredPoints`, `draftingSettings`, `isZLocked`, `showZPlaneGrid`, `currentElevationZ`
- Produces:
  - CAD `+` crosses at acquired tracking points.
  - Renders dashed tracking rays (horizontal, pipe axial, and vertical $\pm Z$).
  - Renders floating badge for vertical tracking: `⬆ Стояк: ΔZ +1200 мм [∇+3.200]`.
  - Renders subtle axonometric grid plane at $Z = currentElevationZ$ when `showZPlaneGrid == true`.
  - Applies 45% opacity / level dimming to pipes on other elevations when `isZLocked == true`.

- [ ] **Step 1: Render acquired points & tracking rays in `piping_canvas.dart`**
  - In `PipingCanvasPainter.paint()`:
    - For each point in `controller.tracingController.acquiredPoints`:
      - Draw CAD tracking cross `+` (size 12 px, color `Colors.amber.shade700`, stroke 1.8 px).
    - In `_drawSnapIndicator(Canvas canvas)`:
      - If snapping to vertical riser ray: draw vertical dashed line and floating badge with $\Delta Z$ and absolute elevation.
  - Draw subtle Z-plane grid:
    - When `controller.draftingSettings.showZPlaneGrid`:
      - Draw axonometric grid lines centered around the drawing extents at $Z = controller.currentElevationZ$ with 12% opacity.

- [ ] **Step 2: Level dimming in `pipe_painter.dart`**
  - Pass `isZLocked: controller.draftingSettings.isZLocked` and `activeElevationZ: controller.currentElevationZ` into `PipePainter.paint(...)`.
  - For segments and fittings whose $|Z - activeElevationZ| > 15$ mm when `isZLocked == true`:
    - Apply `withValues(alpha: 0.45)` to stroke/fill colors, visually dimming non-active levels and giving focus to the working elevation.

- [ ] **Step 3: Verify with `flutter analyze`**

Run: `flutter analyze`  
Expected: 0 issues found.

- [ ] **Step 4: Commit**

```bash
git add lib/ui/canvas/piping_canvas.dart lib/ui/canvas/painters/pipe_painter.dart
git commit -m "feat(cad): render CAD tracking glyphs, vertical riser rays, Z-grid, and level dimming"
```

---

### Task 5: Status Bar Controls & Popover Menu in `DesktopCadLayout`

**Files:**
- Modify: `lib/ui/features/editor/widgets/desktop_cad_layout.dart`

**Interfaces:**
- Consumes: `controller.draftingSettings`, `controller.setDraftingSettings()`
- Produces:
  - Split button `SNAP (F3) ▼`:
    - Click `SNAP (F3)`: toggle master snap on/off.
    - Click `▼`: open Material popover menu with checkboxes for each snap type.
  - Elevation & Z-Lock button:
    - `[Z: ∇+0.000 м 🔒]`: click lock icon to toggle Z-Lock; click text to enter elevation.
  - Quick toggle button for Z-Plane Grid:
    - `[Сетка Z: ВКЛ/ВЫКЛ]`.

- [ ] **Step 1: Replace status bar snap button with CAD split button and popover menu**
  - In `_buildBottomStatusBar()`:
    - Implement split button for `SNAP (F3)`:
      - Main chip: toggle master snap.
      - Arrow `▼`: `PopupMenuButton<String>` with `CheckedPopupMenuItem`:
        - ☑ Узлы и концы (Endpoint / Node)
        - ☑ Пересечения (Intersection)
        - ☑ Середины (Midpoint)
        - ☑ Перпендикуляр 90° (Perpendicular)
        - ☐ Ближайшая к телу трубы (Nearest)
        - ☑ Объектное отслеживание (OTRACK 3D)
        - ☐ Сетка активной плоскости Z
  - Add `Z-Lock` toggle chip:
    - Shows `Z: ∇${elevM} 🔒` when locked (indigo/blue color) or `🔓` when unlocked.
  - Add `Сетка Z` toggle chip.

- [ ] **Step 2: Verify with `flutter analyze`**

Run: `flutter analyze`  
Expected: 0 issues found.

- [ ] **Step 3: Commit**

```bash
git add lib/ui/features/editor/widgets/desktop_cad_layout.dart
git commit -m "feat(ui): add Osnap settings popover menu and Z-Lock controls to bottom status bar"
```

---

### Task 6: Verification, Project Memory & Graph Update

**Files:**
- Modify: `PROJECT_MEMORY.md`

- [ ] **Step 1: Run static analysis**
  - Run: `flutter analyze`
  - Ensure 0 errors, 0 warnings.

- [ ] **Step 2: Update `PROJECT_MEMORY.md`**
  - Document the CAD Snapping Engine overhaul, 3D OTRACK, Working Plane Z-Lock, and Drafting Settings UI.

- [ ] **Step 3: Update knowledge graph**
  - Run: `graphify update .`

- [ ] **Step 4: Commit**

```bash
git add PROJECT_MEMORY.md
git commit -m "docs: update project memory with CAD snapping, 3D OTRACK, and working planes"
```
