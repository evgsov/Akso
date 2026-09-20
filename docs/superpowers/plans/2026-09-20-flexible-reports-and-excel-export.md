# Гибкий конструктор шаблонов ведомостей, спецификаций и сварочного журнала с чипами, топологической связностью элементов и прямым экспортом в Excel (.xlsx)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Создать полнофункциональный гибкий конструктор шаблонов для Сварочного журнала (реестра стыков по форме Транснефти и СПДС), Спецификаций оборудования и материалов (ГОСТ 21.110) и Ведомостей заготовок/катушек на основе чипов-токенов, с топологическим анализом соединений элементов («что с чем стыкуется»), прямым экспортом в Excel (`.xlsx`) со стилями и двухуровневым сохранением шаблонов (в файле `.akso` + локальный кэш).

**Architecture:** 
- Доменный слой: `ReportType`, `ReportColumn`, `ReportTemplate`, `ReportTokenDefinition`.
- Сервисный слой: `ReportEngine` (вычисление топологических связей Side 1 / Side 2, типа соединения `труба-деталь`, `труба-труба`, `труба-арматура`, проектных отметок $Z$, вычисление формул токенов) и `ExcelExportService` (бинарная генерация `.xlsx` на базе `package:excel` со стилизацией шапок, объединением ячеек и автоподбором колонок).
- Хранилище: `ReportTemplateRepository` с гибридным хранением (проект `.akso` + кэш `report_templates.json`).
- UI слой: `ReportTemplateBuilderWidget` с библиотекой чипов, перетаскиванием столбцов и живым предпросмотром, интегрированный вкладками в `WeldJournalDialog` и `MaterialsSpecificationDialog`.

**Tech Stack:** Flutter, Dart, `excel: ^4.0.6`, `file_picker`, `share_plus`, `path_provider`.

---

## Global Constraints
- Код должен работать на всех платформах: Windows, Android, Web.
- Сохранение 100% прохождения всех существующих 554+ тестов и `flutter analyze` 0 замечаний.
- Прямое сохранение бинарных `.xlsx` файлов через `FilePicker.saveFile` (Desktop) и `share_plus` (Mobile/Web).
- Совместимость с форматом файлов проектов `.akso`.

---

### Task 1: Зависимости и базовая доменная модель отчетов

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/domain/enums/report_type.dart`
- Create: `lib/domain/models/report_template.dart`
- Create: `lib/domain/models/report_token_definition.dart`
- Test: `test/report_template_model_test.dart`

- [ ] **Step 1: Write the failing test**
- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Implement minimal code**
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

---

### Task 2: Топологический резолвер примыканий и движок отчетов (`ReportEngine`)

**Files:**
- Create: `lib/domain/services/report_engine.dart`
- Test: `test/report_engine_test.dart`

- [ ] **Step 1: Write the failing test for element connection pairs (труба-деталь, труба-труба, труба-арматура) and tokens**
- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Implement ReportEngine with Side 1 / Side 2 resolution**
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

---

### Task 3: Экспорт в Microsoft Excel (`.xlsx`) со стилями и двухуровневыми шапками

**Files:**
- Create: `lib/data/services/excel_export_service.dart`
- Test: `test/excel_export_service_test.dart`

- [ ] **Step 1: Write the failing test for .xlsx generation, merged group headers, and column widths**
- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Implement ExcelExportService**
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

---

### Task 4: Хранилище шаблонов и интеграция с ProjectModel (Вариант А)

**Files:**
- Create: `lib/data/repositories/report_template_repository.dart`
- Modify: `lib/domain/models/project_model.dart`
- Modify: `lib/ui/canvas/input_controller.dart`
- Test: `test/report_template_repository_test.dart`

- [ ] **Step 1: Write the failing test for ProjectModel serialization and local caching**
- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Implement repository and model updates**
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

---

### Task 5: Конструктор шаблонов с палитрой чипов и живым предпросмотром (`ReportTemplateBuilderWidget`)

**Files:**
- Create: `lib/ui/features/editor/widgets/report_template_builder_widget.dart`
- Test: `test/report_template_builder_widget_test.dart`

- [ ] **Step 1: Write widget test for column reordering, chip insertion, and preview**
- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Implement ReportTemplateBuilderWidget**
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

---

### Task 6: Интеграция конструктора и Excel-экспорта в Сварочный журнал и Спецификацию

**Files:**
- Modify: `lib/ui/features/editor/widgets/weld_journal_dialog.dart`
- Modify: `lib/ui/features/editor/widgets/materials_specification_dialog.dart`
- Test: `test/weld_journal_and_specification_dialogs_test.dart`

- [ ] **Step 1: Write widget test for TabBar navigation, template switching, and Excel export trigger**
- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Implement tabs and export actions in both dialogs**
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

---

### Task 7: Комплексная верификация, тесты, документация

- [ ] **Step 1: Run full test suite (`flutter test`)**
- [ ] **Step 2: Run static analysis (`flutter analyze`)**
- [ ] **Step 3: Update `PROJECT_MEMORY.md`**
- [ ] **Step 4: Run `graphify update .`**
