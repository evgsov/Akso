# CAD Snapping Engine, 3D Object Snap Tracking (OTRACK), and Working Planes (Z-Lock)

**Date**: 2026-09-22  
**Status**: Draft / Pending Review  
**Target Subsystems**: `SnapEngine`, `TracingController`, `InputController`, Canvas Painters (`InteractivePainter`, `PipePainter`), Status Bar UI (`DesktopCadLayout`)

---

## 1. Overview and Problem Statement

During pipeline tracing in Akso, dense isometric drawings with multiple pipes, fittings, and construction reference lines suffer from three major usability issues:
1. **Snap Chaos / Cursor Stickiness**:
   - `SnapEngine._findObjectTrackingSnap()` globally scans *all* pipes and nodes across the entire drawing in every frame, casting projection rays in all directions.
   - The "Nearest to pipe body" snap (`SnapType.segmentAxis`) is permanently enabled with an 18 px radius, capturing the cursor whenever it moves near any pipe.
2. **Z-Axis Spatial Ambiguity & Elevation Jumps**:
   - In 2.5D axonometry, screen $Y$ represents both horizontal depth and vertical elevation $Z$.
   - Without working plane constraints, the snap engine evaluates nodes on distant elevations (e.g. $Z = 3000$ when drawing at $Z = 0$), mistakenly triggering vertical transitions (`🔀 Соединение со стояком`) and jumping elevations.
3. **Lack of Granular Osnap Controls**:
   - Users cannot selectively disable "Nearest" or individual snap modes from a drafting settings menu without disabling snapping altogether.

### Goals
- Implement **AutoCAD-style Hover-to-Acquire Point Tracking (OTRACK)**: rays emit only from points explicitly acquired by dwelling cursor/stylus over a node for $\ge 350\text{ ms}$ (marked with a CAD `+` crosshair).
- Support **Full 3D Tracking Rays**: horizontal orthogonal axes ($X, Y$), pipe axial extensions, and a vertical riser ray ($\pm Z$) with dynamic height difference delta badges ($\Delta Z$) and planar projection.
- Introduce **Working Plane Isolation (Z-Lock)**: strict filtering of planar elements within $|Z - currentElevationZ| \le 15\text{ mm}$ to prevent accidental jumps, accompanied by an optional toggleable subtle axonometric grid plane and level dimming for out-of-plane pipes.
- Provide a **Compact Osnap Popover Menu**: accessible via `SNAP (F3) ▼` in the bottom status bar, with independent toggles for Endpoints/Nodes, Intersections, Midpoints, Perpendiculars, Nearest (disabled by default during tracing), OTRACK, and Z-Plane Grid.

---

## 2. Architecture and Data Models

### 2.1 `DraftingSettings` Model
File: `lib/core/math/drafting_settings.dart`

An immutable settings data class:
```dart
class DraftingSettings {
  final bool snapNodes;          // Node/Endpoint snapping (default: true)
  final bool snapIntersections;  // Pipe/Axis intersection snapping (default: true)
  final bool snapMidpoints;      // Pipe/Axis midpoint snapping (default: true)
  final bool snapPerpendicular;  // 90° Perpendicular snapping (default: true)
  final bool snapNearest;        // Nearest to pipe body (default: false to eliminate stickiness)
  final bool enableOtrack;       // Object snap tracking rays (default: true)
  final bool isZLocked;          // Constrain planar snaps to currentElevationZ (default: true)
  final bool showZPlaneGrid;     // Visual axonometric grid at currentElevationZ (default: false)
  final double nodeSnapRadius;   // Radius for discrete points (default: 20.0 px)
  final double nearestSnapRadius;// Tight radius for nearest point (default: 8.0 px)

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
  }) { ... }
}
```

### 2.2 `AcquiredTrackingPoint` Model
File: `lib/domain/models/acquired_tracking_point.dart`

```dart
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

---

## 3. Component Details and Algorithms

### 3.1 Point Acquisition Logic (`TracingController` & `InputController`)
- In `TracingController`:
  - Maintains `List<AcquiredTrackingPoint> acquiredPoints = []` (maximum 2 points).
  - Hover Timer (`Timer? _hoverDwellTimer`):
    - On pointer hover, if cursor is within 15 px of a node or pipe endpoint for $\ge 350\text{ ms}$:
      - If node is already acquired: remove it (toggle off).
      - If new: add to `acquiredPoints` (if already 2 points, drop the oldest FIFO).
      - Request canvas repaint.
  - Reset triggers:
    - Left-click (placing next pipe vertex) clears `acquiredPoints`.
    - `Escape` key clears `acquiredPoints`.
    - Switching tools or canceling trace clears `acquiredPoints`.

### 3.2 Enhanced `SnapEngine.findSnap()`
File: `lib/core/math/snap_engine.dart`

`findSnap()` receives `DraftingSettings settings` and `List<AcquiredTrackingPoint> acquiredPoints`:

1. **Working Plane Z-Lock Isolation**:
   - When `settings.isZLocked == true`:
     - Nodes, midpoints, and segments are evaluated only if `(item.z - currentElevationZ).abs() <= 15.0`.
     - Out-of-plane elements are completely skipped for planar snaps.
     - Riser transitions are allowed only when actively snapping to an acquired vertical tracking ray or hovering over a designated vertical connection node.
2. **Granular Snap Filtering**:
   - `snapNodes`: checks network nodes and axis endpoints.
   - `snapIntersections`: checks axis-axis and pipe-axis 2D intersections on the working plane.
   - `snapMidpoints`: checks midpoints of pipes and axes on the working plane.
   - `snapPerpendicular`: checks 90° projections from the tracing start point.
   - `snapNearest`: checks distance to line segments using `nearestSnapRadius` (8 px). If `snapNearest == false`, this entire pass is skipped.
3. **Acquired 3D OTRACK Rays**:
   - If `settings.enableOtrack == false` or `acquiredPoints.isEmpty`, OTRACK execution is skipped.
   - **Single Acquired Point**:
     - *Horizontal Rays*: along world axes $X$ ($[1, 0, 0]$), $Y$ ($[0, 1, 0]$), and axial direction of any pipe connected to the acquired node.
     - *Vertical Riser Ray*: along world vector $[0, 0, \pm 1]$. On screen, in axonometry, this renders as a true vertical ray.
     - When snapping to the vertical ray:
       - If tracing vertically or cursor elevation diverges: snaps along the vertical line with label:  
         `⬆ Стояк по створу [ΔZ: +X мм | ∇+Y.YYY]`.
       - If tracing horizontally on working plane: projects the vertical ray to intersect $Z = currentElevationZ$ (e.g. placing an elbow directly beneath an overhead nozzle).
   - **Dual Acquired Points**:
     - Calculates the 3D / planar ray intersection between Point A and Point B.
     - If cursor is within 14 px of the intersection: returns `SnapType.intersection` with label:  
       `⤧ Пересечение створов`.

### 3.3 Visual Presentation and Canvas Painters
1. **`InteractivePainter`**:
   - For each `acquiredPoint`: renders a crisp CAD tracking cross `+` (color: `Colors.amber.shade700`, size: 12 px, stroke: 1.6 px).
   - For active tracking rays: renders dashed projection lines (`dashPattern: [6, 4]`, color: `Colors.cyanAccent.shade700` or `Colors.amber`).
   - For vertical tracking: draws vertical dashed line with a floating badge at cursor:  
     `⬆ Стояк: ΔZ +1200 мм [∇+3.200]`.
2. **`BackgroundGridPainter`**:
   - When `settings.showZPlaneGrid == true`: renders a subtle axonometric grid on plane $Z = currentElevationZ$ (spacing: 1000 mm, line color: soft slate blue with 12% opacity).
3. **`PipePainter` (Level Dimming)**:
   - When `settings.isZLocked == true`:
     - Elements with $|Z - currentElevationZ| \le 15\text{ mm}$ are drawn at 100% opacity.
     - Elements with $|Z - currentElevationZ| > 15\text{ mm}$ are drawn with 45% opacity, creating clean visual depth and highlighting the active level.

### 3.4 UI Status Bar Controls (`DesktopCadLayout`)
File: `lib/ui/features/editor/widgets/desktop_cad_layout.dart`

1. **Split Button `SNAP (F3) ▼`**:
   - Clicking `SNAP (F3)`: toggles master snap on/off.
   - Clicking `▼`: opens a Material popup menu containing checkable items:
     - ☑ Узлы и концы (Endpoint / Node)
     - ☑ Пересечения (Intersection)
     - ☑ Середины (Midpoint)
     - ☑ Перпендикуляр 90° (Perpendicular)
     - ☐ Тело трубы / Ближайшая (Nearest — off by default)
     - ☑ Объектное отслеживание (OTRACK 3D)
     - ☐ Сетка активной плоскости Z
2. **Working Plane Button `[Z: ∇+0.000 м 🔒]`**:
   - Toggles Z-Lock on/off.
   - Clicking opens quick level selector / elevation input.
3. **Z-Grid Quick Toggle**:
   - A dedicated icon button to quickly toggle the working plane grid without entering the menu.

---

## 4. Verification and Testing Plan

1. **Unit Tests (`test/snap_engine_test.dart`)**:
   - Verify `DraftingSettings` defaults and filtering.
   - Verify out-of-plane nodes are ignored when `isZLocked == true`.
   - Verify `snapNearest == false` ignores nearby pipe bodies.
   - Verify single-point horizontal and vertical 3D OTRACK ray calculations.
   - Verify dual-point ray intersection calculation.
2. **Static Analysis**:
   - Run `flutter analyze` to ensure 0 linter issues, 0 warnings, and complete type safety.
3. **Manual CAD Usability Verification**:
   - Verify dwelling for 350 ms acquires node with orange `+` crosshair.
   - Verify vertical riser ray displays `ΔZ` badge correctly.
   - Verify multi-level drawings remain clear with non-active levels dimmed.
   - Verify popover menu toggles in status bar update behavior immediately.
