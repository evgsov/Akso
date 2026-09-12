# Akso Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Устранить критические недостатки сырого прототипа (сохранение на диск, баги layout), провести архитектурный рефакторинг (God-object PipingNetwork) и добавить защиту от коллизий ID (UUID).

**Architecture:** 
1. **I/O Слой:** Подключим `file_picker` (выбор пути) и `dart:io`/`dart:html` для записи `.akso` (JSON) файлов из `ProjectModel`. 
2. **UI Фиксы:** Уберём `controller.lastViewportSize` из `build()` в `addPostFrameCallback`, очистим `fitting_settings_dialog.dart`.
3. **Генерация ID:** Заменим `DateTime.millisecondsSinceEpoch` на `Uuid().v4()` во всём проекте, чтобы избежать коллизий при пакетном создании элементов.
4. **Рефакторинг Domain:** Извлечем бизнес-логику из `PipingNetwork` (1055 строк) в `FittingDetector` и `SpoolCalculator`.

**Tech Stack:** Dart, Flutter, `uuid`, `file_picker`.

**Spec:** Устранение проблем, выявленных в отчёте анализа кодовой базы от 2026-09-11.

## Global Constraints

- Код должен работать на всех платформах (Windows/Android/Web). Для File I/O использовать кроссплатформенный подход (file_picker возвращает пути/байты).
- Изменения в `PipingNetwork` не должны ломать существующие тесты (выделение сервисов — это чисто структурный рефакторинг, тесты продолжат тестировать публичный фасад `PipingNetwork`, если сервисы инкапсулированы или тесты будут слегка адаптированы).

---

### Task 1: Подготовка пакетов и UI-очистка (Fix Build Phase Mutation & Dead Code)

**Files:**
- Modify: `lib/ui/features/editor/editor_screen.dart`
- Delete: `lib/ui/features/editor/widgets/fitting_settings_dialog.dart`

**Interfaces:**
- Убираем мутацию состояния из фазы `build()`.

- [ ] **Step 1: Исправление `editor_screen.dart`**

Откройте `lib/ui/features/editor/editor_screen.dart`. Найдите строку `controller.lastViewportSize = constraints.biggest;` внутри `LayoutBuilder`.

Замените её на асинхронное обновление:
```dart
      builder: (context, constraints) {
        // Синхронизируем размер области рисования с контроллером для корректного Fit to Screen
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (controller.lastViewportSize != constraints.biggest) {
            controller.lastViewportSize = constraints.biggest;
          }
        });
```

- [ ] **Step 2: Удаление мёртвого файла**

Удалите файл `lib/ui/features/editor/widgets/fitting_settings_dialog.dart` (он содержит только заглушку `export`).

- [ ] **Step 3: Проверка**

Запустите `flutter analyze`. Ошибок быть не должно.

- [ ] **Step 4: Commit**
```bash
git rm lib/ui/features/editor/widgets/fitting_settings_dialog.dart
git add lib/ui/features/editor/editor_screen.dart
git commit -m "fix: move controller mutation to postFrameCallback and remove dead file"
```

---

### Task 2: Внедрение UUID вместо Date.now() для генерации ID

**Files:**
- Modify: `lib/domain/models/piping_network.dart`
- Modify: `lib/ui/canvas/input_controller.dart`

**Interfaces:**
- `PipingNetwork` методы (`splitSegmentAtRatio`, `addWeldJoint`, `addValve` и т.д.) теперь используют `Uuid().v4()`.

- [ ] **Step 1: Добавление импорта UUID**

В `lib/domain/models/piping_network.dart` добавьте:
```dart
import 'package:uuid/uuid.dart';
const _uuid = Uuid();
```

- [ ] **Step 2: Замена в `PipingNetwork`**

Пройдитесь поиском по файлу `PipingNetwork` на строку `DateTime.now().millisecondsSinceEpoch`. 
Замените каждый такой вызов на `_uuid.v4()`.

Примеры:
- `weld_${DateTime.now().millisecondsSinceEpoch}_$nextNumber` -> `weld_${_uuid.v4()}_$nextNumber`
- `valve_${DateTime.now().millisecondsSinceEpoch}` -> `valve_${_uuid.v4()}`
- `node_split_${DateTime.now().millisecondsSinceEpoch}` -> `node_${_uuid.v4()}`
- `seg_branch_${DateTime.now().millisecondsSinceEpoch}` -> `seg_${_uuid.v4()}`

- [ ] **Step 3: Замена в `input_controller.dart`**

В `lib/ui/canvas/input_controller.dart` добавьте:
```dart
import 'package:uuid/uuid.dart';
const _uuid = Uuid();
```
Пройдитесь поиском по файлу `input_controller.dart` на строку `DateTime.now().millisecondsSinceEpoch`. 
Замените на `_uuid.v4()`.
Внимание: там есть `DateTime.now().millisecondsSinceEpoch` внутри `Node3D`, `ConstructionAxis`, `PipeSegment`.

- [ ] **Step 4: Запуск тестов**

```bash
flutter test test/network_topology_test.dart
flutter test test/auto_branching_and_flanges_test.dart
```
Ожидается: PASS

- [ ] **Step 5: Commit**
```bash
git add lib/domain/models/piping_network.dart lib/ui/canvas/input_controller.dart
git commit -m "refactor: replace DateTime timestamps with UUIDv4 for all network entities"
```

---

### Task 3: Извлечение логики расчёта катушек (SpoolCalculator)

**Files:**
- Create: `lib/domain/services/spool_calculator.dart`
- Modify: `lib/domain/models/piping_network.dart`

**Interfaces:**
- `SpoolCalculator` предоставляет метод `static void recalculateSpools(PipingNetwork network)`

- [ ] **Step 1: Создание `SpoolCalculator`**

Создайте `lib/domain/services/spool_calculator.dart`. Перенесите туда метод `recalculateSpools` из `PipingNetwork` и сделайте его статическим, принимающим `PipingNetwork`.
```dart
import 'dart:math' as math;
import '../models/piping_network.dart';
import '../models/pipe_spool.dart';
import '../enums/fitting_type.dart';

class SpoolCalculator {
  static void recalculateSpools(PipingNetwork network) {
    network.autoDetectAllFittings();
    network.spools.clear();
    int spoolCounter = 1;

    // ... вставьте тело функции recalculateSpools из PipingNetwork. 
    // Везде где было просто spools, nodes, segments, обращайтесь через network.spools, network.nodes и т.д.
    // ...
  }
}
```

- [ ] **Step 2: Обновление `PipingNetwork`**

В `lib/domain/models/piping_network.dart`:
1. Импортируйте `import '../services/spool_calculator.dart';`
2. Замените тело `recalculateSpools()` на:
```dart
  void recalculateSpools() {
    SpoolCalculator.recalculateSpools(this);
  }
```

- [ ] **Step 3: Проверка**

```bash
flutter test test/network_topology_test.dart
```
Ожидается: PASS

- [ ] **Step 4: Commit**
```bash
git add lib/domain/services/spool_calculator.dart lib/domain/models/piping_network.dart
git commit -m "refactor: extract spool calculation logic to SpoolCalculator service"
```

---

### Task 4: Извлечение логики детектирования фитингов (FittingDetector)

**Files:**
- Create: `lib/domain/services/fitting_detector.dart`
- Modify: `lib/domain/models/piping_network.dart`

**Interfaces:**
- `FittingDetector` предоставляет методы `static void autoDetectAll(PipingNetwork network)` и `static void autoDetectForNode(PipingNetwork network, String nodeId)`

- [ ] **Step 1: Создание `FittingDetector`**

Создайте `lib/domain/services/fitting_detector.dart`. Перенесите туда методы `autoDetectAllFittings` и `_autoDetectFittingsForNode` из `PipingNetwork`.

```dart
import 'dart:math' as math;
import '../models/piping_network.dart';
import '../models/fitting.dart';
import '../enums/fitting_type.dart';
import '../enums/weld_type.dart';

class FittingDetector {
  static void autoDetectAll(PipingNetwork network) {
    for (final nodeId in network.nodes.keys.toList()) {
      autoDetectForNode(network, nodeId);
    }
  }

  static void autoDetectForNode(PipingNetwork network, String nodeId) {
    // Вставьте тело функции _autoDetectFittingsForNode из PipingNetwork.
    // Везде обращайтесь к коллекциям через network.fittings, network.catalog, и т.д.
    // Метод getConnectedSegments: network.getConnectedSegments(nodeId)
  }
}
```

- [ ] **Step 2: Обновление `PipingNetwork`**

В `lib/domain/models/piping_network.dart`:
1. Импортируйте `import '../services/fitting_detector.dart';`
2. Замените методы:
```dart
  void autoDetectAllFittings() {
    FittingDetector.autoDetectAll(this);
  }

  void _autoDetectFittingsForNode(String nodeId) {
    FittingDetector.autoDetectForNode(this, nodeId);
  }
```

- [ ] **Step 3: Проверка тестов**

```bash
flutter test test/fitting_elements_interaction_test.dart
```
Ожидается: PASS. Если есть ошибки типов или доступа — исправьте в `FittingDetector`.

- [ ] **Step 4: Commit**
```bash
git add lib/domain/services/fitting_detector.dart lib/domain/models/piping_network.dart
git commit -m "refactor: extract fitting detection logic to FittingDetector service"
```

---

### Task 5: Строгая типизация в DXF Writer

**Files:**
- Modify: `lib/data/dxf/dxf_writer.dart`

**Interfaces:**
- Убираем `dynamic`

- [ ] **Step 1: Замена типа**

В `lib/data/dxf/dxf_writer.dart` найдите метод `_projectTo2d` (около строки 546).

Измените сигнатуру с:
```dart
static Offset _projectTo2d(AxonometryProjector projector, dynamic node)
```
на:
```dart
static Offset _projectTo2d(AxonometryProjector projector, Node3D node)
```

- [ ] **Step 2: Проверка**

```bash
flutter analyze
flutter test test/dxf_export_test.dart
```
Ожидается: PASS, никаких ошибок типов.

- [ ] **Step 3: Commit**
```bash
git add lib/data/dxf/dxf_writer.dart
git commit -m "refactor: enforce strong typing for Node3D in DxfWriter"
```

---

### Task 6: Реализация сохранения и загрузки проектов (File I/O)

**Files:**
- Modify: `lib/domain/models/project_model.dart`
- Create: `lib/data/repositories/project_repository.dart`
- Modify: `lib/ui/features/editor/widgets/top_bar.dart`

**Interfaces:**
- Интеграция `file_picker` (позволяет пользователю выбрать место сохранения или файл для открытия).

- [ ] **Step 1: Создание репозитория File I/O**

Создайте `lib/data/repositories/project_repository.dart`.
Мы используем `file_picker` для выбора пути, и `dart:io` для записи (Web не поддерживается нативно `dart:io`, но для Desktop работает).
```dart
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../../domain/models/project_model.dart';

class ProjectRepository {
  /// Сохранение на диск с диалогом выбора места
  static Future<bool> saveProjectInteractive(ProjectModel project) async {
    try {
      final jsonString = jsonEncode(project.toJson());
      
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить проект Akso',
        fileName: '${project.title.isNotEmpty ? project.title : 'akso_project'}.akso',
        type: FileType.custom,
        allowedExtensions: ['akso', 'json'],
      );

      if (outputFile == null) return false; // Пользователь отменил

      final file = File(outputFile);
      await file.writeAsString(jsonString);
      return true;
    } catch (e) {
      print('Ошибка при сохранении: $e');
      return false;
    }
  }

  /// Загрузка с диска с диалогом выбора файла
  static Future<ProjectModel?> openProjectInteractive() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Открыть проект Akso',
        type: FileType.custom,
        allowedExtensions: ['akso', 'json'],
      );

      if (result == null || result.files.single.path == null) return null;

      final file = File(result.files.single.path!);
      final jsonString = await file.readAsString();
      final Map<String, dynamic> json = jsonDecode(jsonString);
      
      return ProjectModel.fromJson(json);
    } catch (e) {
      print('Ошибка при открытии: $e');
      return null;
    }
  }
}
```

- [ ] **Step 2: Добавление поддержки сохранения в `TopBar`**

В `lib/ui/features/editor/widgets/top_bar.dart`:
1. Добавьте импорт `import '../../../../data/repositories/project_repository.dart';`
2. Импорт `import '../../../../domain/models/project_model.dart';`
3. В Row после «Логотип и заголовок», добавьте кнопки "Сохранить" и "Открыть":
```dart
            // Кнопка Открыть
            IconButton(
              tooltip: 'Открыть проект',
              icon: const Icon(Icons.folder_open, color: Colors.indigo),
              onPressed: () async {
                final project = await ProjectRepository.openProjectInteractive();
                if (project != null && context.mounted) {
                  controller.network.loadFromJson(project.network.toJson());
                  controller.refresh();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Проект успешно загружен')),
                  );
                }
              },
            ),
            
            // Кнопка Сохранить
            IconButton(
              tooltip: 'Сохранить проект',
              icon: const Icon(Icons.save, color: Colors.indigo),
              onPressed: () async {
                // Создаем временную модель для сохранения
                final currentProject = ProjectModel(
                  id: 'current',
                  title: 'Чертеж',
                  network: controller.network,
                );
                final success = await ProjectRepository.saveProjectInteractive(currentProject);
                if (success && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Проект сохранен')),
                  );
                }
              },
            ),
            const SizedBox(width: 16),
```

- [ ] **Step 3: Проверка компиляции**

```bash
flutter analyze
```

- [ ] **Step 4: Commit**
```bash
git add lib/data/repositories/project_repository.dart lib/ui/features/editor/widgets/top_bar.dart
git commit -m "feat: add interactive save/load for .akso project files"
```
