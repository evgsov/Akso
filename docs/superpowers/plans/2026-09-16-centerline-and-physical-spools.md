# Centerline & Physical Spools Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a true 2-level CAD/BIM piping architecture in Akso, separating the mathematical route axis (Centerline) from physical fabricated pipe spools (`PipeSpool`), eliminating phantom pipes at butt joints, enabling honest pipe cutting by valves and pipe-to-pipe welds, independent spool selection, cascading length editing, and smart callout adaptation.

**Architecture:** 
- Level 1 (Centerline): Topological 3D route skeleton of nodes and segments (`Node3D`, `PipeSegment`), with optional ГОСТ dash-dot rendering and axis-level manipulation.
- Level 2 (Physical Components): Fabricated components (`PipeSpool`, `Valve`, `Fitting`, `WeldJoint`). Spools are first-class interactive domain objects with exact 3D endpoints, physical cut lengths, names, and serial numbers.
- Hit-Testing: Default mode targets physical spools and components. Butt joints have 0 spools and hit-test only the weld or fitting. Centerline mode targets route segments.
- Editing: Cascading downstream length shift along the axis when changing spool cut length.

**Tech Stack:** Dart 3, Flutter, Vector Math, CustomPainter, AutoCAD DXF.

**Spec:** [`docs/superpowers/specs/2026-09-16-centerline-and-physical-spools-architecture-design.md`](file:///d:/Git/Akso/docs/superpowers/specs/2026-09-16-centerline-and-physical-spools-architecture-design.md)

## Global Constraints
- Preserve backward compatibility with existing saved project JSON files (`loadFromJson` / `toJson`).
- Preserve 100% pass rate of all existing 314 tests across the project.
- Keep `dart analyze` at 0 errors and warnings.
- Keep `PROJECT_MEMORY.md` updated and run `graphify update .` upon completion.

---

### Task 1: Domain Model `PipeSpool` & Physical Spool Generation in `PipingNetwork`

**Files:**
- Modify: `lib/domain/models/pipe_spool.dart`
- Modify: `lib/domain/services/spool_calculator.dart`
- Modify: `lib/domain/models/piping_network.dart`
- Test: `test/centerline_and_physical_spools_test.dart`

**Interfaces:**
- Consumes: `Node3D`, `PipeSegment`, `Valve`, `WeldJoint`, `Fitting`.
- Produces: `PipeSpool` with `startPoint`, `endPoint`, `cutLengthMm`, `name`, `serialNumber`, `segmentId`, and `PipingNetwork.recalculateSpools()` updating `network.spools`.

- [ ] **Step 1: Write failing unit test for `PipeSpool` and physical spool generation**
  - Verify butt joint ($L \le T_1 + T_2 + 1.0$) produces 0 spools.
  - Verify valve on segment produces 2 spools with exact endpoints and cut lengths.
  - Verify pipe-to-pipe weld produces 2 spools.
  - Verify spool `copyWith`, `toJson`, `fromJson` with 3D endpoints.
- [ ] **Step 2: Run test to confirm failure**
- [ ] **Step 3: Update `PipeSpool` model** in `lib/domain/models/pipe_spool.dart` with `startPoint`, `endPoint`, `segmentId`, `name`, `serialNumber`.
- [ ] **Step 4: Update `SpoolCalculator` & `PipingNetwork.recalculateSpools()`** to compute exact 3D coordinates `startPoint` and `endPoint` for each spool, skipping 0-length spools on butt joints.
- [ ] **Step 5: Run tests and ensure they pass**
- [ ] **Step 6: Commit changes to Git**

---

### Task 2: Canvas Rendering of Physical Spools & Centerline Toggle Mode

**Files:**
- Modify: `lib/ui/canvas/input_controller.dart`
- Modify: `lib/ui/canvas/painters/pipe_painter.dart`
- Modify: `lib/ui/features/editor/widgets/top_bar.dart`
- Modify: `lib/ui/features/editor/widgets/desktop_cad_layout.dart`
- Test: `test/centerline_rendering_test.dart`

**Interfaces:**
- Consumes: `PipingNetwork.spools`, `PipingInputController.isCenterlineMode`, `PipingInputController.selectedSpoolId`.
- Produces: `PipePainter` drawing only physical spools and rendering ГОСТ dash-dot centerlines when `isCenterlineMode == true`.

- [ ] **Step 1: Write test for centerline toggle and spool rendering intervals**
- [ ] **Step 2: Run test to confirm failure**
- [ ] **Step 3: Add `bool isCenterlineMode`** to `PipingInputController` with toggle method and notification.
- [ ] **Step 4: Add toggle button `[ - · - Осевая трасса ]`** to `top_bar.dart` and `desktop_cad_layout.dart`.
- [ ] **Step 5: Refactor `PipePainter`** to render physical spools from `network.spools`, drawing dash-dot centerlines when `isCenterlineMode == true`, and drawing dimension badges per selected spool.
- [ ] **Step 6: Run tests and ensure they pass**
- [ ] **Step 7: Commit changes to Git**

---

### Task 3: Selection Controller & Hit-Testing (`SelectionController`, `PipingInputController`)

**Files:**
- Modify: `lib/ui/canvas/controllers/selection_controller.dart`
- Modify: `lib/ui/canvas/input_controller.dart`
- Test: `test/spool_selection_and_hit_test.dart`

**Interfaces:**
- Consumes: `PipingNetwork.spools`, screen coordinates from pointer events.
- Produces: `selectedSpoolId`, `selectedSpoolIds`, `selectSpool(String? id)`.

- [ ] **Step 1: Write test for hit-testing spools, butt joint immunity from phantom pipe selection, and centerline mode selection**
- [ ] **Step 2: Run test to confirm failure**
- [ ] **Step 3: Add `selectedSpoolId` and `selectedSpoolIds`** to `SelectionController` and proxy getters/setters in `PipingInputController`.
- [ ] **Step 4: Update hit-testing in `PipingInputController`**:
  - In normal mode: test `_findSpoolAtScreenPos` (checking distance to projected spool endpoints).
  - On butt joint: clicks hit weld joint or fitting, not pipe.
  - In centerline mode: clicks hit `selectedSegmentId`.
- [ ] **Step 5: Run tests and ensure they pass**
- [ ] **Step 6: Commit changes to Git**

---

### Task 4: Inspector & Cascading Length Shift

**Files:**
- Modify: `lib/domain/models/piping_network.dart`
- Modify: `lib/ui/canvas/input_controller.dart`
- Modify: `lib/ui/features/editor/widgets/desktop_cad_layout.dart`
- Test: `test/cascading_spool_length_test.dart`

**Interfaces:**
- Consumes: `selectedSpoolId`, `PipingNetwork.changeSpoolLength`.
- Produces: `_DesktopSpoolInspector` widget, cascading shift of downstream nodes/valves/welds.

- [ ] **Step 1: Write test for cascading length shift `changeSpoolLength`**
  - Verify lengthening a spool before a valve shifts the valve forward.
  - Verify lengthening a spool before an elbow shifts the end node and connected downstream branch forward along the axis.
- [ ] **Step 2: Run test to confirm failure**
- [ ] **Step 3: Implement `PipingNetwork.changeSpoolLength` and `PipingInputController.changeSelectedSpoolLength`** with cascading vector translation.
- [ ] **Step 4: Create `_DesktopSpoolInspector`** in `desktop_cad_layout.dart` with cut length editing, name, serial number, and steel grade.
- [ ] **Step 5: Run tests and ensure they pass**
- [ ] **Step 6: Commit changes to Git**

---

### Task 5: Callout Adaptation & DXF Export

**Files:**
- Modify: `lib/domain/models/callout.dart`
- Modify: `lib/domain/models/piping_network.dart`
- Modify: `lib/ui/canvas/painters/callout_painter.dart`
- Modify: `lib/data/dxf/dxf_writer.dart`
- Test: `test/spool_callout_and_dxf_test.dart`

**Interfaces:**
- Consumes: `CalloutTargetType.spool` (or spool resolution for segment callouts), `DxfWriter`.
- Produces: Callout `{L}` / `{LENGTH}` resolving to `spool.cutLengthMm.round()`, arrow targeting spool center, and DXF layers `АКСО_КАТУШКИ` and `АКСО_ОСИ_ТРАССЫ`.

- [ ] **Step 1: Write test for callout resolution with true spool cut length and DXF export layers**
- [ ] **Step 2: Run test to confirm failure**
- [ ] **Step 3: Update `formatCalloutTemplate`** to resolve `{L}`, `{LENGTH}`, `{NAME}`, `{SERIAL}` based on the targeted spool.
- [ ] **Step 4: Update `CalloutPainter`** to anchor leader lines to the center of the targeted physical spool.
- [ ] **Step 5: Update `DxfWriter`** to output fabricated spools on `АКСО_ТРУБЫ` and centerlines on `АКСО_ОСИ_ТРАССЫ` (`DASHDOT`).
- [ ] **Step 6: Run tests and ensure they pass**
- [ ] **Step 7: Commit changes to Git**

---

### Task 6: Full System Verification & Knowledge Graph Sync

- [ ] **Step 1: Run full test suite (`flutter test`)** — verify 100% pass across all 314+ tests.
- [ ] **Step 2: Run static analysis (`dart analyze`)** — verify 0 errors and warnings.
- [ ] **Step 3: Update `PROJECT_MEMORY.md`** with Phase 28 details.
- [ ] **Step 4: Update graphify knowledge graph** (`uv tool run --from graphifyy graphify update .`).
- [ ] **Step 5: Update walkthrough artifact**.
