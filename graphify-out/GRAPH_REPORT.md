# Graph Report - Akso  (2026-09-12)

## Corpus Check
- 184 files · ~146,699 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1990 nodes · 2425 edges · 147 communities (130 shown, 17 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 25 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `6a844504`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- Win32Window
- server.cjs
- input_controller.dart
- fitting.dart
- Testing Skills With Subagents
- AppDelegate
- valve.dart
- piping_network.dart
- Subagent-Driven Development
- Test-Driven Development (TDD)
- package:akso/domain/models/piping_network.dart
- my_application.cc
- piping_canvas.dart
- Visual Companion Guide
- Creation Log: Systematic Debugging Skill
- Advanced Validation for Business Logic
- fitting_catalog.dart
- dxf_writer.dart
- weld_joint.dart
- piping_systems_dialog.dart
- custom_pipe_dimension_dialog.dart
- Firestore Web SDK Usage Guide
- Code Review Reception
- Testing CLAUDE.md Skills Documentation
- Root Cause Tracing
- Systematic Debugging
- Persuasion Principles for Skill Design
- pipe_dimension.dart
- Finishing a Development Branch
- ⛔️ CRITICAL RULE: NO INLINE INITIALIZATION ⛔️
- Firestore Indexes Reference
- fitting_properties_sheet.dart
- Using Git Worktrees
- Writing Skills
- fitting_catalog_dialog.dart
- PipingNetwork
- Dispatching Parallel Agents
- Writing Data
- Advanced Validation for Business Logic
- fitting_definition.dart
- pipe_spool.dart
- Architecting Flutter Applications
- axonometry_projector.dart
- pipe_segment.dart
- Defense-in-Depth Validation
- Writing Plans
- [Analysis Title]
- wWinMain
- 3. Basic CRUD Operations
- ⛔️ CRITICAL RULE: NO INLINE INITIALIZATION ⛔️
- Returns: "OK" or lists conflicts
- project_serialization_test.dart
- manifest.json
- Brainstorming Ideas Into Designs
- Analyzing and Fixing Dart Code
- Executing Plans
- Cloud Firestore on Android (Kotlin)
- Resolving Flutter Layout Errors
- Condition-Based Waiting
- Verification Before Completion
- Skill structure
- package:flutter/material.dart
- project_model.dart
- helper.js
- Document Data Model
- Index Structure
- Web SDK Usage (Enterprise Native Mode)
- Skill authoring best practices
- Manual Initialization
- stop-server.sh
- Cloud Firestore in Flutter
- Cloud Firestore in Flutter
- Manual Initialization
- 1. Instance Selection and Edition Detection
- Assessment: Security Validator (Red Team Edition)
- Hermes Agent Tool Mapping
- dart:math
- firebase-firestore/SKILL.md
- using-superpowers/SKILL.md
- render-graphs.js
- Skill Discovery Optimization (SDO)
- Bulletproofing Skills Against Rationalization
- PROJECT MEMORY: Akso (3D Axonometric Piping CAD)
- Pressure Test 1: Emergency Production Fix
- Pressure Test 2: Sunk Cost + Exhaustion
- Pressure Test 3: Authority + Social Pressure
- anthropic-best-practices.md
- Anti-Patterns
- Testing All Skill Types
- RED-GREEN-REFACTOR for Skills
- Pi Tool Mapping
- top_bar.dart
- Checklist for effective Skills
- Core principles
- File Organization
- Skill Types
- start-server.sh
- Antigravity CLI (`agy`) Tool Mapping
- MainActivity.kt
- GEMINI.md
- touch_distance_entry_dialog.dart
- akso
- rules/graphify.md
- spec-document-reviewer-prompt.md
- review-package
- sdd-workspace
- task-brief
- find-polluter.sh
- test-academic.md
- plan-document-reviewer-prompt.md
- workflows/graphify.md
- Спецификация: Редизайн UI, адаптивные стили (Desktop / Tablet), расширенные инструменты трассировки и диспетчер систем
- LaunchImage.imageset/README.md
- String?
- snap_engine.dart
- editor_screen.dart
- FlangeConnectionType
- desktop_cad_layout.dart
- dxf_export_dialog.dart
- pipe_assortment_dialog.dart
- Global Constraints
- State
- Global Constraints
- StatelessWidget
- tools_panel.dart
- package:flutter_test/flutter_test.dart
- recovery_repository.dart
- construction_axis.dart
- tablet_touch_layout.dart
- fitting_detector.dart
- pipe_painter.dart
- fitting_painter.dart
- PipingInputController
- package:akso/domain/models/node_3d.dart
- trace_length_input.dart
- piping_system.dart
- ../../../../domain/models/piping_network.dart
- node_3d.dart
- package:akso/ui/canvas/input_controller.dart
- ../../../../domain/enums/valve_type.dart
- Evaluation and iteration
- PipingCanvasPainter

## God Nodes (most connected - your core abstractions)
1. `Win32Window` - 24 edges
2. `Writing Skills` - 22 edges
3. `Testing Skills With Subagents` - 16 edges
4. `handleRequest()` - 14 edges
5. `Code Review Reception` - 14 edges
6. `Test-Driven Development (TDD)` - 13 edges
7. `MessageHandler` - 12 edges
8. `Visual Companion Guide` - 12 edges
9. `startServer()` - 11 edges
10. `PipingNetwork` - 11 edges

## Surprising Connections (you probably didn't know these)
- `MockProjectRepository` --implements--> `IProjectRepository`  [EXTRACTED]
  test/project_serialization_test.dart → lib/data/repositories/project_repository.dart
- `FakeProjectRepository` --inherits--> `ProjectRepository`  [EXTRACTED]
  test/project_identity_test.dart → lib/data/repositories/project_repository.dart
- `wWinMain()` --calls--> `CreateAndAttachConsole()`  [INFERRED]
  windows/runner/main.cpp → windows/runner/utils.cpp
- `Win32Window::Win32Window()` --calls--> `Destroy`  [INFERRED]
  windows/runner/win32_window.cpp → windows/runner/win32_window.h
- `my_application_activate()` --calls--> `fl_register_plugins()`  [INFERRED]
  linux/runner/my_application.cc → linux/flutter/generated_plugin_registrant.cc

## Import Cycles
- None detected.

## Communities (147 total, 17 thin omitted)

### Community 0 - "Win32Window"
Cohesion: 0.05
Nodes (57): PluginRegistry, RECT, unique_ptr, RegisterPlugins(), DartProject, HWND, LPARAM, LRESULT (+49 more)

### Community 1 - "server.cjs"
Cohesion: 0.06
Nodes (57): bootstrapPage(), brandMarkup(), broadcast(), browserLauncherForPlatform(), chmodOwnerOnly(), clients, companionUrl(), computeAcceptKey() (+49 more)

### Community 2 - "input_controller.dart"
Cohesion: 0.02
Nodes (109): dart:async, ../../data/repositories/project_repository.dart, ../../data/repositories/recovery_repository.dart, ../../domain/models/construction_axis.dart, ../../domain/models/network_history_manager.dart, activeDn, activeMaterial, activeSystemId (+101 more)

### Community 3 - "fitting.dart"
Cohesion: 0.07
Nodes (27): double get, branchLengthMm, buildingLengthMm, copyWith, customRadiusMm, customWeldCount, cutsMainPipe, definitionId (+19 more)

### Community 4 - "Testing Skills With Subagents"
Cohesion: 0.04
Nodes (41): Codex App Finishing, Environment Detection, Model routing on spawns, Subagent dispatch requires multi-agent support, Waiting on children, Additional Gemini CLI tools, Gemini CLI Tool Mapping, Instructions file (+33 more)

### Community 5 - "AppDelegate"
Cohesion: 0.06
Nodes (28): Any, Cocoa, file_picker_darwin, Flutter, FlutterAppDelegate, FlutterImplicitEngineBridge, FlutterImplicitEngineDelegate, FlutterMacOS (+20 more)

### Community 6 - "valve.dart"
Cohesion: 0.11
Nodes (18): defaultLengthMm, ValveType, ValveTypeExt, calculatePosition, copyWith, dn, fromJson, handleAngleDeg (+10 more)

### Community 7 - "piping_network.dart"
Cohesion: 0.04
Nodes (44): construction_axis.dart, fitting_catalog.dart, fitting.dart, addSegment, addValve, addWeldJoint, autoDetectAllFittings, axes (+36 more)

### Community 8 - "Subagent-Driven Development"
Cohesion: 0.06
Nodes (26): Code Reviewer Prompt Template, Example Output, Common Rationalizations, Example, How to Request, Red Flags, Requesting Code Review, When to Request Review (+18 more)

### Community 9 - "Test-Driven Development (TDD)"
Cohesion: 0.06
Nodes (29): Common Rationalizations, Debugging Integration, Example: Bug Fix, Final Rule, Good Tests, GREEN - Minimal Code, Overview, Red Flags - STOP and Start Over (+21 more)

### Community 10 - "package:akso/domain/models/piping_network.dart"
Cohesion: 0.15
Nodes (14): dart:io, package:akso/data/dxf/dxf_writer.dart, package:akso/domain/enums/valve_type.dart, package:akso/domain/models/construction_axis.dart, package:akso/domain/models/network_history_manager.dart, package:akso/domain/models/pipe_dimension.dart, package:akso/domain/models/pipe_segment.dart, package:akso/domain/models/piping_network.dart (+6 more)

### Community 11 - "my_application.cc"
Cohesion: 0.09
Nodes (22): FlPluginRegistry, FlView, GApplication, gboolean, gchar, GObject, GtkApplication, fl_register_plugins() (+14 more)

### Community 12 - "piping_canvas.dart"
Cohesion: 0.06
Nodes (34): activeAxisStart, activeSystemId, activeTraceEnd, activeTraceStart, angleDegrees, computeBadgePosition, computeTraceHudInfo, currentElevationZ (+26 more)

### Community 13 - "Visual Companion Guide"
Cohesion: 0.10
Nodes (19): Browser Events Format, Cards (visual designs), Cleaning Up, CSS Classes Available, Design Tips, File Naming, How It Works, Mock elements (wireframe building blocks) (+11 more)

### Community 14 - "Creation Log: Systematic Debugging Skill"
Cohesion: 0.10
Nodes (19): Bulletproofing Elements, Creation Log: Systematic Debugging Skill, Enhancement 1: TDD Reference, Extraction Decisions, Final Outcome, Initial Version, Iterations, Key Insight (+11 more)

### Community 15 - "Advanced Validation for Business Logic"
Cohesion: 0.14
Nodes (14): 1. Generate Firestore Rules, 3. Strict Path and Relationship Scoping, 4. Secure Counter Updates, 5. **CRITICAL** Ensure Application Validity, Advanced Validation for Business Logic, Critical Constraints, Critical Directives for Secure Generation, **CRITICAL** RBAC Guidelines (+6 more)

### Community 16 - "fitting_catalog.dart"
Cohesion: 0.10
Nodes (20): fitting_definition.dart, addCustomDefinition, allDefinitions, createFromBase, customDefinitions, defaultBranchId, defaultElbowId, defaultFlangeConnectionType (+12 more)

### Community 17 - "dxf_writer.dart"
Cohesion: 0.10
Nodes (20): DxfWriter, generate2dGostAxonometryDxf, generate3dDxf, generateMtoCsv, generateSpoolsCsv, generateWeldJournalCsv, _getConnectedNodes, _projectTo2d (+12 more)

### Community 18 - "weld_joint.dart"
Cohesion: 0.10
Nodes (19): ../enums/inspection_method.dart, InspectionMethod, InspectionMethodExt, calculatePosition, copyWith, date, electrodeGrade, fromJson (+11 more)

### Community 19 - "piping_systems_dialog.dart"
Cohesion: 0.12
Nodes (15): ../../../../domain/models/piping_system.dart, activeSystemId, build, _confirmDeleteSystem, createState, _getAciColor, network, onSystemsChanged (+7 more)

### Community 20 - "custom_pipe_dimension_dialog.dart"
Cohesion: 0.10
Nodes (20): double?, FormState, int?, build, createState, CustomPipeDimensionDialog, _CustomPipeDimensionDialogState, dispose (+12 more)

### Community 21 - "Firestore Web SDK Usage Guide"
Cohesion: 0.12
Nodes (16): Add a Document with Auto-ID (`addDoc`), Firestore Web SDK Usage Guide, Get a Single Document (`getDoc`), Get Multiple Documents (`getDocs`), Handle Changes (Added/Modified/Removed), Initialization, Listen to a Document/Query (`onSnapshot`), Order and Limit (+8 more)

### Community 22 - "Code Review Reception"
Cohesion: 0.12
Nodes (16): Acknowledging Correct Feedback, Code Review Reception, Common Mistakes, Forbidden Responses, From External Reviewers, From your human partner, GitHub Thread Replies, Gracefully Correcting Your Pushback (+8 more)

### Community 23 - "Testing CLAUDE.md Skills Documentation"
Cohesion: 0.12
Nodes (16): Documentation Variants to Test, Expected Results, Next Steps, NULL (Baseline - no skills doc), Scenario 1: Time Pressure + Confidence, Scenario 2: Sunk Cost + Works Already, Scenario 3: Authority + Speed Bias, Scenario 4: Familiarity + Efficiency (+8 more)

### Community 24 - "Root Cause Tracing"
Cohesion: 0.12
Nodes (15): 1. Observe the Symptom, 2. Find Immediate Cause, 3. Ask: What Called This?, 4. Keep Tracing Up, 5. Find Original Trigger, Adding Stack Traces, Finding Which Test Causes Pollution, Key Principle (+7 more)

### Community 25 - "Systematic Debugging"
Cohesion: 0.12
Nodes (15): Common Rationalizations, Overview, Phase 1: Root Cause Investigation, Phase 2: Pattern Analysis, Phase 3: Hypothesis and Testing, Phase 4: Implementation, Quick Reference, Red Flags - STOP and Follow Process (+7 more)

### Community 26 - "Persuasion Principles for Skill Design"
Cohesion: 0.12
Nodes (15): 1. Authority, 2. Commitment, 3. Scarcity, 4. Social Proof, 5. Unity, 6. Reciprocity, 7. Liking, Ethical Use (+7 more)

### Community 27 - "pipe_dimension.dart"
Cohesion: 0.10
Nodes (20): addCustomDimension, addWallThickness, copyWith, defaultWallThicknessMm, _dimensions, dn, formatLabel, fromJson (+12 more)

### Community 28 - "Finishing a Development Branch"
Cohesion: 0.13
Nodes (14): Common Rationalizations, Finishing a Development Branch, If your human partner asks to discard the work, Option 1: Merge Locally, Option 2: Push and Create PR, Option 3: Keep As-Is, Overview, Quick Reference (+6 more)

### Community 29 - "⛔️ CRITICAL RULE: NO INLINE INITIALIZATION ⛔️"
Cohesion: 0.13
Nodes (14): 1. Import and Initialize, 2. Type-Safe Data Models (Codable), 3. Basic CRUD Operations, 4. Pipeline Queries, 5. Realtime Listeners in SwiftUI (Lifecycle Best Practices), ⛔️ CRITICAL RULE: NO FirebaseFirestoreSwift ⛔️, ⛔️ CRITICAL RULE: NO INLINE INITIALIZATION ⛔️, Examples (+6 more)

### Community 30 - "Firestore Indexes Reference"
Cohesion: 0.13
Nodes (15): 1. High Write Rates (Sequential Values), 2. Large String/Map/Array Fields, 3. TTL Fields, Automatic vs. Manual Management, Best Practices & Exemptions, CLI Commands, Composite Indexes, Config files (+7 more)

### Community 31 - "fitting_properties_sheet.dart"
Cohesion: 0.12
Nodes (16): ../../../../domain/models/fitting_definition.dart, build, _buildBadge, _buildRadiusChip, createState, FittingPropertiesSheet, _FittingPropertiesSheetState, _getFittingIcon (+8 more)

### Community 32 - "Using Git Worktrees"
Cohesion: 0.13
Nodes (14): 1a. Native Worktree Tools (preferred), 1b. Git Worktree Fallback, Common Rationalizations, Create the Worktree, Directory Selection, Overview, Quick Reference, Report (+6 more)

### Community 33 - "Writing Skills"
Cohesion: 0.13
Nodes (15): Code Examples, Common Rationalizations for Skipping Testing, Directory Structure, Discovery Workflow, Flowchart Usage, Match the Form to the Failure, Overview, Skill Creation Checklist (TDD Adapted) (+7 more)

### Community 34 - "fitting_catalog_dialog.dart"
Cohesion: 0.08
Nodes (27): _applyDefinitionToSelectedNode, build, _buildCollectionTab, _buildRoutingRulesTab, _buildSectionHeader, createState, dispose, FittingCatalogDialog (+19 more)

### Community 35 - "PipingNetwork"
Cohesion: 0.20
Nodes (10): ../../../../data/dxf/dxf_writer.dart, ../../../../domain/enums/inspection_method.dart, ../../../../domain/enums/weld_type.dart, PipingNetwork, build, network, _parseCsvRows, build (+2 more)

### Community 36 - "Dispatching Parallel Agents"
Cohesion: 0.14
Nodes (13): 1. Identify Independent Domains, 2. Create Focused Agent Tasks, 3. Dispatch in Parallel, 4. Review and Integrate, Agent Prompt Structure, Common Mistakes, Dispatching Parallel Agents, Overview (+5 more)

### Community 37 - "Writing Data"
Cohesion: 0.14
Nodes (13): Add a Document with Auto-ID, Get a Single Document, Get Multiple Documents, Order and Limit, Pipeline Queries, Python SDK Usage, Queries, Reading Data (+5 more)

### Community 38 - "Advanced Validation for Business Logic"
Cohesion: 0.14
Nodes (14): 1. Generate Firestore Rules, 3. Strict Path and Relationship Scoping, 4. Secure Counter Updates, 5. **CRITICAL** Ensure Application Validity, Advanced Validation for Business Logic, Critical Constraints, Critical Directives for Secure Generation, **CRITICAL** RBAC Guidelines (+6 more)

### Community 39 - "fitting_definition.dart"
Cohesion: 0.09
Nodes (23): archetype, branchLengthMm, calculateDeduction, copyWith, cutsMainPipe, defaultMaterial, defaultWeldCount, FittingArchetype (+15 more)

### Community 40 - "pipe_spool.dart"
Cohesion: 0.14
Nodes (13): copyWith, cutLengthMm, dn, endWeldId, fromJson, id, material, number (+5 more)

### Community 41 - "Architecting Flutter Applications"
Cohesion: 0.15
Nodes (12): Architecting Flutter Applications, Architectural Layers, Contents, Data Layer, Data Layer: Service and Repository, Examples, Logic Layer (Domain - Optional), Project Structure (+4 more)

### Community 42 - "axonometry_projector.dart"
Cohesion: 0.12
Nodes (15): AxonometryProjector, computeRawBoundingBox, copyWith, orbitAzimuth, orbitElevation, panOffset, project, projectCoordinates (+7 more)

### Community 43 - "pipe_segment.dart"
Cohesion: 0.12
Nodes (16): calculateActualSlope, calculateLength, copyWith, dn, endNodeId, fromJson, id, isVertical (+8 more)

### Community 44 - "Defense-in-Depth Validation"
Cohesion: 0.17
Nodes (11): Applying the Pattern, Defense-in-Depth Validation, Example from Session, Key Insight, Layer 1: Entry Point Validation, Layer 2: Business Logic Validation, Layer 3: Environment Guards, Layer 4: Debug Instrumentation (+3 more)

### Community 45 - "Writing Plans"
Cohesion: 0.17
Nodes (11): Bite-Sized Task Granularity, Execution Handoff, File Structure, No Placeholders, Overview, Plan Document Header, Scope Check, Self-Review (+3 more)

### Community 46 - "[Analysis Title]"
Cohesion: 0.17
Nodes (12): Advanced: Skills with executable code, [Analysis Title], Anti-patterns to avoid, Avoid offering too many options, Avoid Windows-style paths, Conditional workflow pattern, Examples pattern, Executive summary (+4 more)

### Community 47 - "wWinMain"
Cohesion: 0.24
Nodes (9): _In_, _In_opt_, vector, wWinMain(), string, wchar_t, CreateAndAttachConsole(), GetCommandLineArguments() (+1 more)

### Community 48 - "3. Basic CRUD Operations"
Cohesion: 0.18
Nodes (10): 1. Add Dependencies, 2. Initialize Firestore, 3. Basic CRUD Operations, Add Data, Delete Data, Enable Firestore via CLI, Firestore Enterprise Native Mode on Android (Kotlin), Jetpack Compose (Modern) (+2 more)

### Community 49 - "⛔️ CRITICAL RULE: NO INLINE INITIALIZATION ⛔️"
Cohesion: 0.18
Nodes (10): 1. Import and Initialize, 2. Type-Safe Data Models (Codable), 3. Writing Data (Modern Concurrency & Codable), 4. Reading Data (Modern Concurrency & Codable), 5. Realtime Listeners in SwiftUI (Lifecycle Best Practices), ⛔️ CRITICAL RULE: NO FirebaseFirestoreSwift ⛔️, ⛔️ CRITICAL RULE: NO INLINE INITIALIZATION ⛔️, Firebase Firestore iOS Setup Guide (+2 more)

### Community 50 - "Returns: "OK" or lists conflicts"
Cohesion: 0.18
Nodes (11): Avoid assuming tools are installed, Create verifiable intermediate outputs, MCP tool references, Next steps, Package dependencies, Returns: "OK" or lists conflicts, Runtime environment, Technical notes (+3 more)

### Community 51 - "project_serialization_test.dart"
Cohesion: 0.11
Nodes (18): ProjectModel, package:akso/data/repositories/project_repository.dart, package:akso/domain/models/project_model.dart, package:akso/domain/models/valve.dart, lastSavedProject, loadCount, loadProject, main (+10 more)

### Community 52 - "manifest.json"
Cohesion: 0.18
Nodes (10): background_color, description, display, icons, name, orientation, prefer_related_applications, short_name (+2 more)

### Community 53 - "Brainstorming Ideas Into Designs"
Cohesion: 0.20
Nodes (9): After the Design (architectural path), Anti-Pattern: "Too Simple To Need Approval", Brainstorming Ideas Into Designs, Checklist, Process Flow, Red Flags, The Process, Three Paths (+1 more)

### Community 54 - "Analyzing and Fixing Dart Code"
Cohesion: 0.20
Nodes (9): Analysis Configuration, Analyzing and Fixing Dart Code, Comprehensive `analysis_options.yaml`, Contents, Diagnostic Suppression, Examples, Inline Diagnostic Suppression, Workflow: Applying Automated Fixes (+1 more)

### Community 55 - "Executing Plans"
Cohesion: 0.20
Nodes (9): Executing Plans, Overview, Remember, Step 1: Load and Review Plan, Step 2: Execute Tasks, Step 3: Complete Development, The Process, When to Revisit Earlier Steps (+1 more)

### Community 56 - "Cloud Firestore on Android (Kotlin)"
Cohesion: 0.20
Nodes (9): 1. Add Dependencies, 2. Initialize Firestore, 3. Add Data, 4. Read Data, 5. Update Data, 6. Delete Data, Cloud Firestore on Android (Kotlin), Enable Firestore via CLI (+1 more)

### Community 57 - "Resolving Flutter Layout Errors"
Cohesion: 0.20
Nodes (9): Constraint Violation Diagnostics, Contents, Examples, Fixing RenderFlex Overflow, Fixing Unbounded Height (ListView in Column), Fixing Unbounded Width (TextField in Row), Layout Error Resolution Workflow, Resolving Flutter Layout Errors (+1 more)

### Community 58 - "Condition-Based Waiting"
Cohesion: 0.20
Nodes (9): Common Mistakes, Condition-Based Waiting, Core Pattern, Implementation, Overview, Quick Patterns, Real-World Impact, When Arbitrary Timeout IS Correct (+1 more)

### Community 59 - "Verification Before Completion"
Cohesion: 0.20
Nodes (9): Common Failures, Key Patterns, Overview, Rationalization Prevention, Red Flags - STOP, The Gate Function, The Iron Law, Verification Before Completion (+1 more)

### Community 60 - "Skill structure"
Cohesion: 0.20
Nodes (10): Avoid deeply nested references, Naming conventions, Pattern 1: High-level guide with references, Pattern 2: Domain-specific organization, Pattern 3: Conditional details, Progressive disclosure patterns, Skill structure, Structure longer reference files with table of contents (+2 more)

### Community 61 - "package:flutter/material.dart"
Cohesion: 0.12
Nodes (14): ../../../../domain/enums/projection_type.dart, build, controller, main, network, projector, _drawScaleBar, GridPainter (+6 more)

### Community 62 - "project_model.dart"
Cohesion: 0.07
Nodes (27): bool get, ../enums/projection_type.dart, canRedo, canUndo, clear, maxSnapshots, NetworkHistoryManager, recordState (+19 more)

### Community 63 - "helper.js"
Cohesion: 0.42
Nodes (7): connect(), nextReconnectDelay(), reloadAfterRecovery(), sessionKey(), setStatus(), showTombstone(), websocketUrl()

### Community 64 - "Document Data Model"
Cohesion: 0.22
Nodes (8): Collection Group Support, Collections, Document Data Model, Documents, Examples, Firestore Data Model Reference, Subcollections, Use Cases

### Community 65 - "Index Structure"
Cohesion: 0.50
Nodes (4): Index Density, Index Ordering, Index Structure, Unique Indexes

### Community 66 - "Web SDK Usage (Enterprise Native Mode)"
Cohesion: 0.22
Nodes (8): 1. Initialization, 2. Decision Framework: Pipelines vs. Standard Queries, 3. Pipeline Examples, 4. Real-Time Listener & Document Operations, Full-Text Search, Relational Joins Pattern, Rules & Accountability, Web SDK Usage (Enterprise Native Mode)

### Community 67 - "Skill authoring best practices"
Cohesion: 0.22
Nodes (9): Avoid time-sensitive information, Common patterns, Content guidelines, Implement feedback loops, Skill authoring best practices, Template pattern, Use consistent terminology, Use workflows for complex tasks (+1 more)

### Community 68 - "Manual Initialization"
Cohesion: 0.25
Nodes (8): 1. Create a Firestore Enterprise Database, 2. Create `firebase.json`, 2. Create `firestore.rules`, 3. Create `firestore.indexes.json`, Deploy rules and indexes, Local Emulation, Manual Initialization, Provisioning Firestore Enterprise Native Mode

### Community 69 - "stop-server.sh"
Cohesion: 0.52
Nodes (6): command_has_server_id(), command_line_for_pid(), is_brainstorm_server(), mark_stopped(), read_expected_server_id(), stop-server.sh script

### Community 70 - "Cloud Firestore in Flutter"
Cohesion: 0.29
Nodes (6): 1. Setup, 2. Best Practices: Type-Safe Models, 3. The Service Layer, 4. Listening to Streams in the UI (`StreamBuilder`), Cloud Firestore in Flutter, Initialization & References

### Community 71 - "Cloud Firestore in Flutter"
Cohesion: 0.29
Nodes (6): 1. Setup, 2. Best Practices: Type-Safe Models, 3. The Service Layer, 4. Listening to Streams in the UI (`StreamBuilder`), Cloud Firestore in Flutter, Initialization & References

### Community 72 - "Manual Initialization"
Cohesion: 0.29
Nodes (7): 1. Create `firebase.json`, 2. Create `firestore.rules`, 3. Create `firestore.indexes.json`, Deploy database, rules and indexes, Local Emulation, Manual Initialization, Provisioning Cloud Firestore

### Community 73 - "1. Instance Selection and Edition Detection"
Cohesion: 0.29
Nodes (7): 1. Instance Selection and Edition Detection, 2. Specialized Guides, A. Instance Found, B. No Instance Found (or New Requested), Cloud Firestore Database and Operations, Enterprise Edition / Native Mode (`references/enterprise/`), Standard Edition (`references/standard/`)

### Community 74 - "Assessment: Security Validator (Red Team Edition)"
Cohesion: 0.29
Nodes (6): Admin Bootstrapping & Privileges:, Assessment: Security Validator (Red Team Edition), Mandatory Audit Checklist:, Overview, Scoring Criteria, Scoring Criteria (1-5):

### Community 75 - "Hermes Agent Tool Mapping"
Cohesion: 0.29
Nodes (6): Hermes Agent Tool Mapping, Instructions file, Invoking a skill, Subagent dispatch, Task tracking, Tools

### Community 76 - "dart:math"
Cohesion: 0.29
Nodes (6): dart:math, drawDiameterCallout, drawElevationCallout, drawSlopeCallout, drawWeldCallout, SmartCallout

### Community 77 - "firebase-firestore/SKILL.md"
Cohesion: 0.23
Nodes (5): CLI Commands, Config files, Firestore Indexes Reference, Management, Query Support Examples

### Community 78 - "using-superpowers/SKILL.md"
Cohesion: 0.33
Nodes (5): Platform Adaptation, Red Flags, Skill Priority, The Rule, User Instructions

### Community 79 - "render-graphs.js"
Cohesion: 0.60
Nodes (5): combineGraphs(), extractDotBlocks(), extractGraphBody(), main(), renderToSvg()

### Community 80 - "Skill Discovery Optimization (SDO)"
Cohesion: 0.33
Nodes (6): 1. Rich Description Field, 2. Keyword Coverage, 3. Descriptive Naming, 4. Token Efficiency (Critical), 5. Cross-Referencing Other Skills, Skill Discovery Optimization (SDO)

### Community 81 - "Bulletproofing Skills Against Rationalization"
Cohesion: 0.33
Nodes (6): Address "Spirit vs Letter" Arguments, Build Rationalization Table, Bulletproofing Skills Against Rationalization, Close Every Loophole Explicitly, Create Red Flags List, Update SDO for Violation Symptoms

### Community 82 - "PROJECT MEMORY: Akso (3D Axonometric Piping CAD)"
Cohesion: 0.33
Nodes (5): 1. Project Overview & Vision, 2. Standards & Math Conventions, 3. Engineering Data Model, 4. Implemented Features & Current Status, PROJECT MEMORY: Akso (3D Axonometric Piping CAD)

### Community 83 - "Pressure Test 1: Emergency Production Fix"
Cohesion: 0.40
Nodes (4): Choose A, B, or C, Pressure Test 1: Emergency Production Fix, Scenario, Your Options

### Community 84 - "Pressure Test 2: Sunk Cost + Exhaustion"
Cohesion: 0.40
Nodes (4): Choose A, B, or C, Pressure Test 2: Sunk Cost + Exhaustion, Scenario, Your Options

### Community 85 - "Pressure Test 3: Authority + Social Pressure"
Cohesion: 0.40
Nodes (4): Choose A, B, or C, Pressure Test 3: Authority + Social Pressure, Scenario, Your Options

### Community 86 - "anthropic-best-practices.md"
Cohesion: 0.40
Nodes (4): [Analysis Title], Executive summary, Key findings, Recommendations

### Community 87 - "Anti-Patterns"
Cohesion: 0.40
Nodes (5): Anti-Patterns, ❌ Code in Flowcharts, ❌ Generic Labels, ❌ Multi-Language Dilution, ❌ Narrative Example

### Community 88 - "Testing All Skill Types"
Cohesion: 0.40
Nodes (5): Discipline-Enforcing Skills (rules/requirements), Pattern Skills (mental models), Reference Skills (documentation/APIs), Technique Skills (how-to guides), Testing All Skill Types

### Community 89 - "RED-GREEN-REFACTOR for Skills"
Cohesion: 0.40
Nodes (5): GREEN: Write Minimal Skill, Micro-Test Wording Before Full Scenarios, RED-GREEN-REFACTOR for Skills, RED: Write Failing Test (Baseline), REFACTOR: Close Loopholes

### Community 91 - "Pi Tool Mapping"
Cohesion: 0.50
Nodes (3): Pi Tool Mapping, Subagents, Task lists

### Community 92 - "top_bar.dart"
Cohesion: 0.18
Nodes (9): ../../../../domain/models/node_3d.dart, dxf_export_dialog.dart, fitting_catalog_dialog.dart, ProjectionType, build, controller, _loadDemoNetwork, materials_specification_dialog.dart (+1 more)

### Community 93 - "Checklist for effective Skills"
Cohesion: 0.50
Nodes (4): Checklist for effective Skills, Code and scripts, Core quality, Testing

### Community 94 - "Core principles"
Cohesion: 0.50
Nodes (4): Concise is key, Core principles, Set appropriate degrees of freedom, Test with all models you plan to use

### Community 95 - "File Organization"
Cohesion: 0.50
Nodes (4): File Organization, Self-Contained Skill, Skill with Heavy Reference, Skill with Reusable Tool

### Community 96 - "Skill Types"
Cohesion: 0.50
Nodes (4): Pattern, Reference, Skill Types, Technique

### Community 101 - "touch_distance_entry_dialog.dart"
Cohesion: 0.09
Nodes (23): IconData, _angleController, build, createState, dirX, dirY, dirZ, dispose (+15 more)

### Community 112 - "Спецификация: Редизайн UI, адаптивные стили (Desktop / Tablet), расширенные инструменты трассировки и диспетчер систем"
Cohesion: 0.09
Nodes (21): 1. Контекст и цели, 2.1 Переключатель режима (`UiLayoutMode`), 2.2 Десктопный CAD-стиль (`DesktopCadLayout`), 2.3 Планшетный сенсорный стиль (`TabletTouchLayout`), 2. Архитектура UI и стили компоновки, 3.1 Модель истории (`NetworkHistoryManager`), 3.2 Отмена операции (`cancelCurrentOperation()`), 3. Отмена действий и стек Undo / Redo (+13 more)

### Community 119 - "snap_engine.dart"
Cohesion: 0.09
Nodes (21): axonometry_projector.dart, AngleSnapMode, angleSnapToleranceDegrees, _calcSegmentRatio, distanceLengthMm, _distanceToLineSegment, findSnap, _getAllowedAngles (+13 more)

### Community 120 - "editor_screen.dart"
Cohesion: 0.07
Nodes (26): ../../canvas/piping_canvas.dart, DateTime?, _baseScale, build, _buildCanvas, _buildLengthInputOverlay, controller, createState (+18 more)

### Community 121 - "FlangeConnectionType"
Cohesion: 0.47
Nodes (5): defaultDeductionMm, FittingType, FittingTypeExt, FlangeConnectionType, FlangeConnectionTypeExt

### Community 122 - "desktop_cad_layout.dart"
Cohesion: 0.08
Nodes (24): ../../../../core/math/snap_engine.dart, _applyLength, build, _buildHeader, _buildLeftToolPalette, _buildOptionsBar, _buildPropertyInspector, _buildStatusBar (+16 more)

### Community 123 - "dxf_export_dialog.dart"
Cohesion: 0.17
Nodes (12): build, createState, currentProjection, DxfExportDialog, _DxfExportDialogState, _exportDxf, initState, is3dMode (+4 more)

### Community 124 - "pipe_assortment_dialog.dart"
Cohesion: 0.13
Nodes (15): ../../../../domain/models/pipe_dimension.dart, build, controller, createState, dispose, _filter, network, onCatalogChanged (+7 more)

### Community 125 - "Global Constraints"
Cohesion: 0.18
Nodes (10): Global Constraints, Task 1: Network History & State Management (Undo / Redo + Action Cancellation), Task 2: Snapping Engine & Polar Angle Tracking, Task 3: Construction Lines & Building Grid Axes (`ConstructionAxis`), Task 4: Revit-Style Piping Systems Model & Manager Dialog, Task 5: Custom Fitting Constructor Improvements («Создать на основе...»), Task 6: Viewport Navigation & Mouse/Touch Gesture Engine, Task 7: Two UI Layout Styles: Desktop CAD Layout & Tablet Touch Layout (+2 more)

### Community 126 - "State"
Cohesion: 0.32
Nodes (8): EditorScreen, _EditorScreenState, PipingSystemsDialog, _PipingSystemsDialogState, TraceLengthInput, _TraceLengthInputState, State, StatefulWidget

### Community 127 - "Global Constraints"
Cohesion: 0.22
Nodes (8): Akso Improvements Implementation Plan, Global Constraints, Task 1: Подготовка пакетов и UI-очистка (Fix Build Phase Mutation & Dead Code), Task 2: Внедрение UUID вместо Date.now() для генерации ID, Task 3: Извлечение логики расчёта катушек (SpoolCalculator), Task 4: Извлечение логики детектирования фитингов (FittingDetector), Task 5: Строгая типизация в DXF Writer, Task 6: Реализация сохранения и загрузки проектов (File I/O)

### Community 128 - "StatelessWidget"
Cohesion: 0.25
Nodes (8): AksoApp, DesktopCadLayout, MaterialsSpecificationDialog, TabletTouchLayout, EditorToolsPanel, EditorTopBar, WeldJournalDialog, StatelessWidget

### Community 129 - "tools_panel.dart"
Cohesion: 0.25
Nodes (7): custom_pipe_dimension_dialog.dart, WeldType, WeldTypeExt, CanvasTool, build, controller, pipe_assortment_dialog.dart

### Community 130 - "package:flutter_test/flutter_test.dart"
Cohesion: 0.17
Nodes (11): package:akso/domain/enums/fitting_type.dart, package:akso/domain/enums/weld_type.dart, package:akso/domain/models/fitting_catalog.dart, package:akso/domain/models/piping_system.dart, package:akso/ui/features/editor/widgets/fitting_catalog_dialog.dart, package:akso/ui/features/editor/widgets/fitting_properties_sheet.dart, package:flutter_test/flutter_test.dart, main (+3 more)

### Community 131 - "recovery_repository.dart"
Cohesion: 0.14
Nodes (15): dart:convert, ../../domain/models/project_model.dart, IProjectRepository, loadProject, ProjectRepository, saveProject, _getRecoveryFile, loadRecovery (+7 more)

### Community 132 - "construction_axis.dart"
Cohesion: 0.17
Nodes (11): ConstructionAxis, copyWith, endPoint, fromJson, id, isBuildingGrid, label, startPoint (+3 more)

### Community 133 - "tablet_touch_layout.dart"
Cohesion: 0.13
Nodes (14): elevation_panel.dart, fitting_properties_sheet.dart, build, canvasWidget, controller, _showChangeDnSheet, _showChangeLengthDialog, _showChangeMaterialSheet (+6 more)

### Community 134 - "fitting_detector.dart"
Cohesion: 0.17
Nodes (11): ../enums/fitting_type.dart, ../enums/valve_type.dart, ../enums/weld_type.dart, autoDetectAllFittings, autoDetectFittingsForNode, FittingDetector, recalculateSpools, SpoolCalculator (+3 more)

### Community 135 - "pipe_painter.dart"
Cohesion: 0.20
Nodes (9): ../../../../domain/enums/fitting_type.dart, ../../../../domain/models/pipe_segment.dart, calcElbowTangentLength, calcPipeTrimmedPoint, calcStrokeWidth, drawSelectedDimensionBadge, isTeeBranchSegment, paint (+1 more)

### Community 136 - "fitting_painter.dart"
Cohesion: 0.18
Nodes (10): ../../../../domain/models/fitting.dart, _drawDirectBranchSymbol, _drawElbowSymbol, _drawFlangeSymbol, _drawReducerSymbol, _drawTeeSymbol, _drawWeldTickAt, FittingPainter (+2 more)

### Community 137 - "PipingInputController"
Cohesion: 0.25
Nodes (7): ../../../canvas/input_controller.dart, ChangeNotifier, PipingInputController, build, controller, ElevationPanel, _showElevationInputDialog

### Community 138 - "package:akso/domain/models/node_3d.dart"
Cohesion: 0.16
Nodes (14): dart:ui, package:akso/core/math/axonometry_projector.dart, package:akso/core/math/snap_engine.dart, package:akso/domain/enums/projection_type.dart, package:akso/domain/models/node_3d.dart, package:akso/ui/canvas/piping_canvas.dart, package:akso/ui/features/editor/editor_screen.dart, package:akso/ui/features/editor/widgets/trace_length_input.dart (+6 more)

### Community 139 - "trace_length_input.dart"
Cohesion: 0.13
Nodes (14): FocusNode, build, _controller, createState, didUpdateWidget, dispose, _focusNode, initialValue (+6 more)

### Community 140 - "piping_system.dart"
Cohesion: 0.11
Nodes (18): availableDns, code, colorValue, copyWith, defaultBranchId, defaultDn, defaultElbowId, defaultFlangeId (+10 more)

### Community 141 - "../../../../domain/models/piping_network.dart"
Cohesion: 0.20
Nodes (9): ../../core/math/axonometry_projector.dart, ../../../../domain/models/piping_network.dart, AnnotationPainter, paint, _calcValveSize, paint, ValvePainter, ../smart_callout.dart (+1 more)

### Community 142 - "node_3d.dart"
Cohesion: 0.15
Nodes (12): int get, copyWith, customElevation, distanceTo, fromJson, hashCode, id, operator (+4 more)

### Community 143 - "package:akso/ui/canvas/input_controller.dart"
Cohesion: 0.20
Nodes (8): package:akso/main.dart, package:akso/ui/canvas/input_controller.dart, package:akso/ui/features/editor/widgets/tablet_touch_layout.dart, package:akso/ui/features/editor/widgets/top_bar.dart, package:akso/ui/features/editor/widgets/touch_distance_entry_dialog.dart, main, main, main

### Community 144 - "../../../../domain/enums/valve_type.dart"
Cohesion: 0.40
Nodes (4): ../../../../domain/enums/valve_type.dart, _drawTwoTriangles, drawValve, ValveSymbolPainter

### Community 145 - "Evaluation and iteration"
Cohesion: 0.50
Nodes (4): Build evaluations first, Develop Skills iteratively with the agent, Evaluation and iteration, Observe how agents navigate Skills

## Knowledge Gaps
- **1274 isolated node(s):** `crypto`, `http`, `fs`, `path`, `OPCODES` (+1269 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **17 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `WeldType` connect `tools_panel.dart` to `input_controller.dart`, `fitting.dart`, `fitting_catalog_dialog.dart`, `fitting_definition.dart`, `weld_joint.dart`, `desktop_cad_layout.dart`, `fitting_properties_sheet.dart`?**
  _High betweenness centrality (0.021) - this node is a cross-community bridge._
- **Why does `PipingNetwork` connect `PipingNetwork` to `input_controller.dart`, `fitting_catalog_dialog.dart`, `piping_network.dart`, `piping_canvas.dart`, `piping_systems_dialog.dart`, `dxf_export_dialog.dart`, `pipe_assortment_dialog.dart`, `project_model.dart`, `fitting_properties_sheet.dart`?**
  _High betweenness centrality (0.020) - this node is a cross-community bridge._
- **Why does `ProjectModel` connect `project_serialization_test.dart` to `input_controller.dart`, `project_model.dart`?**
  _High betweenness centrality (0.007) - this node is a cross-community bridge._
- **What connects `crypto`, `http`, `fs` to the rest of the system?**
  _1274 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Win32Window` be split into smaller, more focused modules?**
  _Cohesion score 0.05311676909569798 - nodes in this community are weakly interconnected._
- **Should `server.cjs` be split into smaller, more focused modules?**
  _Cohesion score 0.05628415300546448 - nodes in this community are weakly interconnected._
- **Should `input_controller.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.01818181818181818 - nodes in this community are weakly interconnected._