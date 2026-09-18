# Project Lifecycle & Wi-Fi Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a robust project lifecycle subsystem for Akso (reliable file saving/loading on Desktop & Mobile, Recent Projects list, Project Properties dialog, unsaved changes tracking) and a local P2P Wi-Fi bridge (Akso QuickBridge) for instant project transfer between PC and tablet.

**Architecture:** 
- `ProjectModel` expanded with metadata (`projectCode`, `notes`, `lastModifiedDate`).
- `RecentProjectsManager` stores recent file paths and metadata locally in JSON config.
- `ProjectRepository` performs direct atomic file writes and file picking with fallback across platforms.
- `QuickBridgeService` runs an ephemeral local `HttpServer` with UDP discovery and 4-digit PIN protection for zero-config transfer.
- `PipingInputController` tracks `currentFilePath` and `hasUnsavedChanges`, exposing `save()`, `saveAs()`, `open()`, and `newProject()`.
- UI dialogs (`ProjectPropertiesDialog`, `QuickBridgeDialog`, `RecentProjectsMenu`) integrated into `TopBar` and `DesktopCadLayout`.

**Tech Stack:** Flutter, Dart, `dart:io` (`HttpServer`, `RawDatagramSocket`, `File`), `path_provider`, `file_picker`, `share_plus`, `uuid`, `intl`.

**Spec:** `docs/superpowers/specs/2026-09-18-project-lifecycle-and-wifi-sync-design.md`

## Global Constraints
- Target platforms: Windows Desktop, Android tablet, iOS, Web.
- Formats: `.akso` JSON project format, UTF-8 encoding.
- Offline-first: QuickBridge must function without internet access on local Wi-Fi or mobile hotspots.
- Non-destructive: Existing networks and history managers must not lose connectivity or state during saves/loads.

---

### Task 1: Extend `ProjectModel` with metadata and tests

**Files:**
- Modify: `lib/domain/models/project_model.dart`
- Test: `test/project_lifecycle_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class ProjectModel {
    final String id;
    final String title;
    final String projectCode;
    final String objectAddress;
    final String engineerName;
    final String notes;
    final String creationDate;
    final String lastModifiedDate;
    final ProjectionType projectionType;
    final String activeSystemId;
    final int activeDn;
    final double currentElevationZ;
    final PipingNetwork network;
    final Map<String, String> calloutTemplates;
    // copyWith, toJson, fromJson
  }
  ```

- [ ] **Step 1: Write the failing test for ProjectModel metadata serialization**
- [ ] **Step 2: Run test to verify it fails**
  Run: `flutter test test/project_lifecycle_test.dart`
- [ ] **Step 3: Update `ProjectModel` with `projectCode`, `notes`, `lastModifiedDate`**
- [ ] **Step 4: Run test to verify it passes**
  Run: `flutter test test/project_lifecycle_test.dart`
- [ ] **Step 5: Commit**
  Run: `git add lib/domain/models/project_model.dart test/project_lifecycle_test.dart; git commit -m "feat: extend ProjectModel with projectCode, notes, and lastModifiedDate"`

---

### Task 2: Implement `RecentProjectsManager`

**Files:**
- Create: `lib/data/repositories/recent_projects_manager.dart`
- Test: `test/recent_projects_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class RecentProjectEntry {
    final String title;
    final String filePath;
    final String projectCode;
    final DateTime lastOpened;
    Map<String, dynamic> toJson();
    factory RecentProjectEntry.fromJson(Map<String, dynamic> json);
  }

  class RecentProjectsManager {
    Future<List<RecentProjectEntry>> getRecentProjects();
    Future<void> addRecentProject(RecentProjectEntry entry);
    Future<void> removeRecentProject(String filePath);
    Future<void> clearRecentProjects();
  }
  ```

- [ ] **Step 1: Write unit tests for `RecentProjectsManager`**
- [ ] **Step 2: Run test to verify it fails**
  Run: `flutter test test/recent_projects_test.dart`
- [ ] **Step 3: Implement `RecentProjectEntry` and `RecentProjectsManager`**
- [ ] **Step 4: Run test to verify it passes**
  Run: `flutter test test/recent_projects_test.dart`
- [ ] **Step 5: Commit**
  Run: `git add lib/data/repositories/recent_projects_manager.dart test/recent_projects_test.dart; git commit -m "feat: implement RecentProjectsManager for tracking recently opened files"`

---

### Task 3: Overhaul `ProjectRepository` for robust cross-platform file I/O

**Files:**
- Modify: `lib/data/repositories/project_repository.dart`
- Test: `test/project_repository_test.dart`

**Interfaces:**
- Produces:
  ```dart
  abstract class IProjectRepository {
    Future<String?> saveProject(ProjectModel project, {String? targetPath});
    Future<({ProjectModel project, String filePath})?> loadProject({String? filePath});
    Future<void> shareProjectFile(ProjectModel project);
  }
  ```

- [ ] **Step 1: Write failing tests for `ProjectRepository` saving and loading with file paths**
- [ ] **Step 2: Run test to verify it fails**
  Run: `flutter test test/project_repository_test.dart`
- [ ] **Step 3: Implement direct atomic write, file extension validation, and share fallback**
- [ ] **Step 4: Run test to verify it passes**
  Run: `flutter test test/project_repository_test.dart`
- [ ] **Step 5: Commit**
  Run: `git add lib/data/repositories/project_repository.dart test/project_repository_test.dart; git commit -m "feat: robust file writing and path handling in ProjectRepository"`

---

### Task 4: Implement `QuickBridgeService` (Local Wi-Fi P2P Transfer)

**Files:**
- Create: `lib/data/services/quick_bridge_service.dart`
- Test: `test/quick_bridge_service_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class QuickBridgeSession {
    final String localIp;
    final int port;
    final String pin;
    final String serverUrl;
    Future<void> stop();
  }

  class QuickBridgeDiscoveredHost {
    final String hostName;
    final String ip;
    final int port;
    final String pin;
  }

  class QuickBridgeService {
    Future<QuickBridgeSession> startSender({required ProjectModel project, Function(String clientIp)? onTransferred});
    Stream<QuickBridgeDiscoveredHost> discoverHosts({Duration timeout = const Duration(seconds: 5)});
    Future<ProjectModel> downloadProject({required String hostIp, required int port, required String pin});
    Future<bool> uploadProject({required String hostIp, required int port, required String pin, required ProjectModel project});
  }
  ```

- [ ] **Step 1: Write integration tests for QuickBridge server, PIN validation, and project transfer**
- [ ] **Step 2: Run test to verify it fails**
  Run: `flutter test test/quick_bridge_service_test.dart`
- [ ] **Step 3: Implement `QuickBridgeService` using `HttpServer` and UDP broadcast**
- [ ] **Step 4: Run test to verify it passes**
  Run: `flutter test test/quick_bridge_service_test.dart`
- [ ] **Step 5: Commit**
  Run: `git add lib/data/services/quick_bridge_service.dart test/quick_bridge_service_test.dart; git commit -m "feat: implement QuickBridgeService for local P2P Wi-Fi transfer"`

---

### Task 5: Controller integration (`PipingInputController`)

**Files:**
- Modify: `lib/ui/canvas/input_controller.dart`
- Test: `test/project_controller_integration_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class PipingInputController extends ChangeNotifier {
    String? currentFilePath;
    bool hasUnsavedChanges = false;
    RecentProjectsManager recentProjectsManager;

    Future<bool> saveProject();
    Future<bool> saveProjectAs();
    Future<bool> openProject({String? filePath});
    Future<bool> newProject({bool force = false});
    void updateProjectMetadata({String? title, String? projectCode, String? objectAddress, String? engineerName, String? notes});
    Future<void> shareCurrentProject();
  }
  ```

- [ ] **Step 1: Write tests for controller save, saveAs, unsaved changes flag, and recent projects integration**
- [ ] **Step 2: Run test to verify it fails**
  Run: `flutter test test/project_controller_integration_test.dart`
- [ ] **Step 3: Implement controller methods and mark `hasUnsavedChanges = true` on network mutations**
- [ ] **Step 4: Run test to verify it passes**
  Run: `flutter test test/project_controller_integration_test.dart`
- [ ] **Step 5: Commit**
  Run: `git add lib/ui/canvas/input_controller.dart test/project_controller_integration_test.dart; git commit -m "feat: add project lifecycle and dirty state tracking to PipingInputController"`

---

### Task 6: UI Implementation (Properties Dialog, QuickBridge Dialog, TopBar & Layout)

**Files:**
- Create: `lib/ui/features/editor/widgets/project_properties_dialog.dart`
- Create: `lib/ui/features/editor/widgets/quick_bridge_dialog.dart`
- Modify: `lib/ui/features/editor/widgets/desktop_cad_layout.dart`
- Modify: `lib/ui/features/editor/widgets/top_bar.dart`
- Test: `test/project_ui_test.dart`

- [ ] **Step 1: Write widget tests for `ProjectPropertiesDialog` and `QuickBridgeDialog`**
- [ ] **Step 2: Run test to verify it fails**
  Run: `flutter test test/project_ui_test.dart`
- [ ] **Step 3: Implement `ProjectPropertiesDialog` with form fields (title, code, address, engineer, notes)**
- [ ] **Step 4: Implement `QuickBridgeDialog` with QR code / PIN display, mode toggle (Send / Receive), and auto-discovery list**
- [ ] **Step 5: Integrate into `TopBar` & `DesktopCadLayout` (Title with `*`, Recent Files menu, Ctrl+S / Ctrl+Shift+S / Ctrl+O / Ctrl+N shortcuts, Wi-Fi sync button)**
- [ ] **Step 6: Run widget tests to verify they pass**
  Run: `flutter test test/project_ui_test.dart`
- [ ] **Step 7: Commit**
  Run: `git add lib/ui/ test/project_ui_test.dart; git commit -m "feat: add ProjectPropertiesDialog, QuickBridgeDialog, and TopBar project controls"`

---

### Task 7: Full Verification & Documentation

**Files:**
- Modify: `PROJECT_MEMORY.md`
- Graph update: `graphify update .`

- [ ] **Step 1: Run all unit and widget tests**
  Run: `flutter test`
- [ ] **Step 2: Run static analysis**
  Run: `dart analyze lib test`
- [ ] **Step 3: Update knowledge graph**
  Run: `graphify update .`
- [ ] **Step 4: Update `PROJECT_MEMORY.md` with Phase 48 documentation**
- [ ] **Step 5: Commit**
  Run: `git commit -am "docs: update PROJECT_MEMORY.md and graph for Phase 48"`
