# Revit-Style Editable Coordinate Grids Design Specification

## Overview & Goals
This specification defines the architecture, data models, rendering engine, and interaction mechanics for interactive, Revit-style building coordinate grids (оси здания) in Akso. 

Key capabilities:
1. **Full Revit Grip & Alignment Experience**:
   - Individual start and end bubble visibility toggles (`showStartBubble`, `showEndBubble`).
   - Automatic alignment detection (chains) for parallel grid endpoints with alignment lock/unlock toggles.
   - Temporary inter-axis dimensions showing distances to nearest parallel grids, with direct displacement by entered distance.
   - Elbow break shoulder (излом марки) to prevent label collisions when grids are close.
   - In-place renaming & inspector editing with GOST 21.101-2020 auto-increment (1->2->3, А->Б->В skipping prohibited letters).
   - Pinning (`isPinned`) to lock grids against accidental edits.
2. **3D In-Plane ("Лежачие") Marks**:
   - Bubbles and labels projected directly within the 3D horizontal coordinate plane ($XY$) at the working elevation $Z$, forming true isometric/axonometric ellipses and skewed text.
   - Optional toggle between 3D in-plane and 2D billboard screen-oriented rendering.
3. **Z-Elevation Binding**:
   - Grids reside on active working planes ($Z$) with full elevation editing in the inspector.

---

## 1. Domain Data Model (`ConstructionAxis`)

`lib/domain/models/construction_axis.dart` is extended with immutable properties:

```dart
class ConstructionAxis {
  final String id;
  final String label; // "1", "2", "А", "Б"
  final Node3D startPoint;
  final Node3D endPoint;
  final bool isBuildingGrid; // true = building grid with marks, false = reference guide line

  // Revit-style properties
  final bool showStartBubble;      // Bubble at startPoint (End 1)
  final bool showEndBubble;        // Bubble at endPoint (End 2)
  final double elevationZ;         // Elevation of working plane (Z)
  final Offset? startElbowOffset;  // 2D screen/world shoulder offset for start mark
  final Offset? endElbowOffset;    // 2D screen/world shoulder offset for end mark
  final bool isPinned;             // Lock position
  final bool is3dPlaneOriented;    // true = 3D lying in XY plane, false = 2D billboard
  final bool isStartLocked;        // Aligned chain lock at start
  final bool isEndLocked;          // Aligned chain lock at end

  const ConstructionAxis({
    required this.id,
    required this.label,
    required this.startPoint,
    required this.endPoint,
    this.isBuildingGrid = true,
    this.showStartBubble = true,
    this.showEndBubble = false,
    this.elevationZ = 0.0,
    this.startElbowOffset,
    this.endElbowOffset,
    this.isPinned = false,
    this.is3dPlaneOriented = true,
    this.isStartLocked = true,
    this.isEndLocked = true,
  });

  ConstructionAxis copyWith({...});
  Map<String, dynamic> toJson();
  factory ConstructionAxis.fromJson(Map<String, dynamic> json);
}
```

Backward compatibility: Missing fields default to `showStartBubble: true`, `showEndBubble: false`, `elevationZ: 0.0`, `isPinned: false`, `is3dPlaneOriented: true`, `isStartLocked: true`, `isEndLocked: true`.

---

## 2. Grid System Engine (`GridSystemEngine`)

`lib/domain/services/grid_system_engine.dart` encapsulates all pure geometric and algorithmic logic:

1. **Auto-Increment Label Generator (`generateNextLabel`)**:
   - Numerical: `1` -> `2`, `9` -> `10`, etc.
   - Cyrillic GOST 21.101-2020 (Clause 5.3.3):
     `А, Б, В, Г, Д, Е, Ж, И, К, Л, М, Н, П, Р, С, Т, У, Ф, Ш, Э, Ю, Я`
     *(Excludes Ё, З, Й, О, Х, Ц, Ч, Щ, Ъ, Ы, Ь)*.
   - Latin: `A` -> `B` ... (excluding I, O).

2. **Alignment Chain Detection (`findAlignmentChains`)**:
   - Detects parallel axes whose start or end points align along the normal within a tolerance (e.g. 50 mm).
   - Returns chain groupings of axis IDs.
   - `stretchChainedEndpoints`: When dragging a locked endpoint, computes and applies equal collinear delta to all locked axes in the chain.

3. **Temporary Dimension Calculation (`calculateTemporaryDimensions`)**:
   - Finds immediate parallel neighbors before and after the selected axis.
   - Calculates perpendicular distance $D$ in millimeters.
   - `moveAxisByDistance`: Shifts the selected axis along its normal to establish the exact desired distance.

4. **Offset Axis Generation (`createOffsetAxis`)**:
   - Offsets an existing axis by distance $d$ along its normal vector.
   - Automatically increments the label.

---

## 3. Rendering Engine (`GridPainter` & `PipingCanvas`)

1. **ГОСТ 2.303 Dash-Dot-Dot Line**:
   - Long dash (14 px) - gap (4 px) - dot (2 px) - gap (3 px) - dot (2 px) - gap (4 px).
2. **3D In-Plane Marks (Лежачие марки)**:
   - For `is3dPlaneOriented == true`:
     - Sample 32 points on horizontal circle $C(\theta) = (x_0 + R \cos\theta, y_0 + R \sin\theta, z_0)$.
     - Project through `projector.project(C(\theta))` to form an exact axonometric ellipse.
     - Project unit vectors $\vec{e}_x$ and $\vec{e}_y$ to construct a 2D affine matrix (`Matrix4`) for `canvas.transform()`, orienting text flat on the ground plane.
   - For `is3dPlaneOriented == false`:
     - Standard 2D circular billboard with horizontal text.
3. **Elbow Break (Излом марки)**:
   - If `startElbowOffset != null`, draws a dogleg shoulder line from `startPoint` to `startPoint + offset`, placing the bubble at the shoulder tip.
4. **Temporary Dimensions & Grips Overlay**:
   - Endpoint grip handle (square).
   - Padlock icon (locked/unlocked) when part of an alignment chain.
   - Bubble toggle icon (checkbox).
   - Elbow break squiggle handle.
   - Temporary dimension line with dimension text and click-to-edit hit box.

---

## 4. User Interaction & Canvas Controller (`InputController`)

1. **Selection & Hit-Testing**:
   - `GripHitType.axisStartGrip`, `GripHitType.axisEndGrip`
   - `GripHitType.axisStartBubbleToggle`, `GripHitType.axisEndBubbleToggle`
   - `GripHitType.axisStartLockToggle`, `GripHitType.axisEndLockToggle`
   - `GripHitType.axisStartElbowGrip`, `GripHitType.axisEndElbowGrip`
   - `GripHitType.axisTemporaryDimension`
2. **Shortcuts & Gestures**:
   - `Ctrl + Drag`: Quick duplicate axis with offset and auto-increment.
   - Click on Temporary Dimension: Opens numeric input to shift axis.
   - Double-click on mark bubble: In-place text editor for label.

---

## 5. Inspector Panel Integration (`DesktopCadLayout`)

Inspector section for selected axis:
- Label field with quick auto-increment button.
- Checkboxes: Start Mark, End Mark.
- Elevation $Z$ input.
- Toggle: 3D In-Plane / 2D Screen.
- Pin button.
- "Создать смещение" (Offset) button with distance input.
- "Сбросить изломы" (Reset Elbows) button.
