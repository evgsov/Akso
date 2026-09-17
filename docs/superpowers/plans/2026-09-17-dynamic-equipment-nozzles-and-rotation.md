# План реализации: Динамические штуцеры оборудования, привязка к граням, умный жизненный цикл и поворот в 3D

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Реализовать чистое создание оборудования без висящих узлов, динамическое создание штуцеров при привязке труб к граням аппарата, автоматическое удаление неиспользуемых штуцеров, поворот оборудования на 90°/180°/270°, корректное обновление штуцеров при изменении габаритов и экспорт в DXF.

**Architecture:** Оборудование хранит габариты, угол поворота `rotationAngleDeg` и динамические штуцеры `Nozzle`. При наведении курсора в режиме трассировки трубы `PipingInputController` ловит грань аппарата и при клике вызывает `attachNozzleAtWorldPoint`. Штуцер регистрируется как `Node3D` и соединяется с трубой. При удалении трубы неиспользуемые штуцеры автоматически зачищаются (`cleanupUnusedEquipmentNozzles`). Отрисовщик `EquipmentPainter` рендерит повернутый корпус и патрубки штуцеров с фланцами.

**Tech Stack:** Dart 3.x, Flutter, Vector Math, AutoCAD DXF Writer.

**Spec:** `docs/superpowers/specs/2026-09-17-dynamic-equipment-nozzles-and-rotation-design.md`

## Global Constraints
- Никаких `!` (force unwrap) при обращении к `network.nodes[...]` или `network.equipments[...]`.
- Полная обратная совместимость сериализации JSON (старые схемы без `rotationAngleDeg` должны читаться с дефолтом 0.0).
- Штуцеры по умолчанию комплектные (`includeInMto == false`) и не дублируются в ведомости материалов MTO CSV.

---

### Task 1: Обновление модели данных (`Equipment` и `Nozzle`)

**Files:**
- Modify: `lib/domain/models/equipment.dart`
- Test: `test/equipment_dynamic_nozzles_and_rotation_test.dart`

**Interfaces:**
- Produces: `Equipment.rotationAngleDeg`, `Nozzle.face`, `Nozzle.includeInMto`, enum `EquipmentFace`.

- [ ] **Step 1: Написать падающий тест на новые поля модели `Equipment` и `Nozzle`**
- [ ] **Step 2: Добавить enum `EquipmentFace { top, bottom, left, right, front, back, cylindrical }`**
- [ ] **Step 3: Добавить `rotationAngleDeg` в `Equipment` и `face`, `includeInMto` в `Nozzle` с обновлением `copyWith`, `toJson`, `fromJson`, `operator==`, `hashCode`**
- [ ] **Step 4: Убедиться, что тесты проходят**
- [ ] **Step 5: Коммит изменений Task 1**

---

### Task 2: Топологическое управление в `PipingNetwork`

**Files:**
- Modify: `lib/domain/models/piping_network.dart`
- Test: `test/equipment_dynamic_nozzles_and_rotation_test.dart`

**Interfaces:**
- Produces:
  - `Node3D attachNozzleAtWorldPoint(String eqId, Node3D worldPoint, {int dn = 50, EquipmentFace? face, String? name})`
  - `void rotateEquipment(String eqId, double angleDeltaDeg)`
  - `void cleanupUnusedEquipmentNozzles()`
  - Обновленный `updateEquipment(Equipment updatedEq)` с подтягиванием координат штуцеров к новым размерам граней.

- [ ] **Step 1: Написать тесты на `attachNozzleAtWorldPoint`, `rotateEquipment`, `updateEquipment` и `cleanupUnusedEquipmentNozzles`**
- [ ] **Step 2: Реализовать `attachNozzleAtWorldPoint` с вычислением нормали грани и регистрацией `Node3D`**
- [ ] **Step 3: Реализовать `rotateEquipment`: поворот на угол, трансформация координат штуцеров и смещение присоединенных сегментов**
- [ ] **Step 4: Обновить `updateEquipment`: перерасчет положения штуцеров на гранях при изменении `width`, `length`, `height`**
- [ ] **Step 5: Реализовать `cleanupUnusedEquipmentNozzles`**
- [ ] **Step 6: Убедиться, что все тесты проходят**
- [ ] **Step 7: Коммит изменений Task 2**

---

### Task 3: Привязка курсора к граням оборудования и жизненный цикл в `PipingInputController`

**Files:**
- Modify: `lib/ui/canvas/input_controller.dart`
- Test: `test/equipment_dynamic_nozzles_and_rotation_test.dart`

- [ ] **Step 1: Написать тест на привязку трассировки трубы к грани оборудования и автоматическое удаление штуцера при удалении трубы**
- [ ] **Step 2: В `CanvasTool.insertEquipment` создавать оборудование без штуцеров (`nozzles: const []`)**
- [ ] **Step 3: Реализовать привязку `_detectEquipmentFaceSnap` при трассировке трубы (магнит к центру грани или произвольной точке поверхности)**
- [ ] **Step 4: В `handlePointerDown` для `CanvasTool.pipe` поддержать начало и завершение трассировки на грани оборудования через `attachNozzleAtWorldPoint`**
- [ ] **Step 5: В `deleteSelected` и удалении сегментов вызывать `cleanupUnusedEquipmentNozzles`**
- [ ] **Step 6: Убедиться, что тесты проходят**
- [ ] **Step 7: Коммит изменений Task 3**

---

### Task 4: Отрисовка повернутого оборудования и патрубков штуцеров (`EquipmentPainter`)

**Files:**
- Modify: `lib/ui/canvas/painters/equipment_painter.dart`
- Test: `test/equipment_dynamic_nozzles_and_rotation_test.dart`

- [ ] **Step 1: Применить матрицу поворота `rotationAngleDeg` при расчете вершин параллелепипеда, вертикального и горизонтального цилиндров в `EquipmentPainter`**
- [ ] **Step 2: Реализовать отрисовку штуцеров `_paintNozzles`: отрисовка патрубка вдоль нормали, фланца и маркировки `Ш-1 Ду50`**
- [ ] **Step 3: Проверить визуальное отображение и тесты**
- [ ] **Step 4: Коммит изменений Task 4**

---

### Task 5: Инспектор оборудования (`desktop_cad_layout.dart` и `equipment_properties_sheet.dart`)

**Files:**
- Modify: `lib/ui/features/editor/widgets/desktop_cad_layout.dart`
- Modify: `lib/ui/features/editor/widgets/equipment_properties_sheet.dart`
- Test: `test/equipment_dynamic_nozzles_and_rotation_test.dart`

- [ ] **Step 1: Добавить в инспектор оборудования кнопку «Повернуть на 90°» с отображением текущего угла**
- [ ] **Step 2: Добавить отображение списка подключенных штуцеров с кнопкой удаления и тумблером «Ответный фланец в МТО»**
- [ ] **Step 3: Проверить работу инспектора и тесты**
- [ ] **Step 4: Коммит изменений Task 5**

---

### Task 6: Экспорт оборудования и штуцеров в AutoCAD DXF (`dxf_writer.dart`)

**Files:**
- Modify: `lib/data/dxf/dxf_writer.dart`
- Test: `test/equipment_dynamic_nozzles_and_rotation_test.dart`

- [ ] **Step 1: Написать тест на экспорт оборудования в 2D/3D DXF на слой `АКСО_ОБОРУДОВАНИЕ`**
- [ ] **Step 2: Реализовать экспорт ребер повернутого оборудования и штуцеров в `dxf_writer.dart`**
- [ ] **Step 3: Добавить учет ответных фланцев штуцеров в `generateMtoCsv` при `includeInMto == true`**
- [ ] **Step 4: Убедиться, что тесты проходят**
- [ ] **Step 5: Коммит изменений Task 6**

---

### Task 7: Полная верификация, актуализация графа и памяти проекта

**Files:**
- Modify: `PROJECT_MEMORY.md`

- [ ] **Step 1: Выполнить полный запуск тестов `flutter test`**
- [ ] **Step 2: Выполнить статический анализ `dart analyze lib test` (0 замечаний)**
- [ ] **Step 3: Запустить `graphify update .`**
- [ ] **Step 4: Обновить `PROJECT_MEMORY.md`**
- [ ] **Step 5: Финальный коммит изменений**
