# Адаптивные листовые выноски, динамический фильтр категорий и листовая авторасстановка — План реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Разделить выноски по чертежным листам (монтажные схемы с элементами vs схемы сварных соединений со стыками), дать полную свободу динамической фильтрации категорий проекта со счетчиками, обеспечить независимое сохранение ручного перетаскивания выносок для каждого листа и компактную авторасстановку в границах видового экрана листа без улета за края.

**Architecture:** 
1. В `Callout` добавляется `sheetOffsets: Map<String, Offset>` для независимого переопределения координат на каждом листе при сохранении базового смещения для 3D модели.
2. В `DrawingSheet` добавляется фильтр категорий `enabledCalloutTypes: Set<CalloutTargetType>?` и `showElevationCallouts: bool`.
3. В `PipingNetwork` реализуется метод `getExistingCalloutCategories()`, динамически сканирующий присутствующие в сети типы выносок со счетчиками.
4. В `CalloutLayoutEngine` реализуется `calculateSheetLayout(...)`, работающий в координатах миллиметров листа с ограничением видовым экраном и запретом наезда на штамп и таблицы.
5. Интерактивный контроллер `PipingInputController` обеспечивает контекстное перетаскивание на листе (в `sheetOffsets`), а `SheetToolbar` и инспектор `DesktopCadLayout` предоставляют удобные элементы управления.

**Tech Stack:** Dart / Flutter, custom CAD geometric layout engine, canvas vector rendering, PDF export.

**Spec:** [docs/superpowers/specs/2026-09-26-adaptive-sheet-callouts-and-layout-design.md](file:///c:/Budget/Akso/docs/superpowers/specs/2026-09-26-adaptive-sheet-callouts-and-layout-design.md)

---

### Task 1: Модель данных `Callout.sheetOffsets`, `DrawingSheet` фильтрация и динамические категории

**Files:**
- Modify: `lib/domain/models/callout.dart`
- Modify: `lib/domain/models/drawing_sheet.dart`
- Modify: `lib/domain/models/piping_network.dart`
- Create: `test/sheet_callout_model_test.dart`

**Interfaces:**
- `Callout.sheetOffsets: Map<String, Offset>`
- `Callout.getEffectiveOffset(String? sheetId): Offset`
- `DrawingSheet.enabledCalloutTypes: Set<CalloutTargetType>?`
- `DrawingSheet.showElevationCallouts: bool`
- `DrawingSheet.isCalloutVisible(Callout callout): bool`
- `PipingNetwork.getExistingCalloutCategories(): List<CalloutCategoryStats>`

- [ ] **Step 1: Написать юнит-тесты в `test/sheet_callout_model_test.dart`**
  - Проверка `Callout.getEffectiveOffset`: возвращает базовый оффсет при отсутствии `sheetId` или оверрайда, и листовой оффсет при наличии.
  - Проверка сериализации `Callout.toJson` и `fromJson` с `sheetOffsets`.
  - Проверка обратной совместимости старого JSON без `sheetOffsets`.
  - Проверка `DrawingSheet.isCalloutVisible` для фильтров: монтажная схема, сварка, отметки.
  - Проверка `network.getExistingCalloutCategories()`.
- [ ] **Step 2: Обновить `lib/domain/models/callout.dart`**
  - Добавить поле `sheetOffsets: Map<String, Offset>`.
  - Добавить методы `getEffectiveOffset`, `getEffectiveOffsetX`, `getEffectiveOffsetY`.
  - Обновить `copyWith`, `toJson`, `fromJson`.
- [ ] **Step 3: Обновить `lib/domain/models/drawing_sheet.dart`**
  - Добавить поля `enabledCalloutTypes: Set<CalloutTargetType>?` и `showElevationCallouts: bool`.
  - Реализовать метод `bool isCalloutVisible(Callout callout)`.
  - Обновить `copyWith`, `toJson`, `fromJson`.
- [ ] **Step 4: Обновить `lib/domain/models/piping_network.dart`**
  - Создать класс `CalloutCategoryStats(CalloutTargetType type, int count, {bool isElevationOnly})`.
  - Реализовать `List<CalloutCategoryStats> getExistingCalloutCategories()`.
- [ ] **Step 5: Проверить через `flutter analyze`**
- [ ] **Step 6: Закоммитить изменения**
  - `git commit -m "feat(domain): add sheetOffsets to Callout, callout filter to DrawingSheet, and dynamic categories"`

---

### Task 2: Листовая авторасстановка в `CalloutLayoutEngine`

**Files:**
- Modify: `lib/domain/services/callout_layout_engine.dart`
- Create: `test/callout_sheet_layout_test.dart`

**Interfaces:**
- `CalloutLayoutEngine.calculateSheetLayout(...) -> Map<String, Offset>`

- [ ] **Step 1: Написать юнит-тесты в `test/callout_sheet_layout_test.dart`**
  - Тест: выноски распределяются только для видимых на листе категорий.
  - Тест: полочки выносок строго находятся внутри прямоугольника видового экрана листа.
  - Тест: полочки не накладываются на зону штампа 185×55 мм.
- [ ] **Step 2: Реализовать `calculateSheetLayout` в `CalloutLayoutEngine`**
  - Фильтровать выноски через `sheet.isCalloutVisible(c)`.
  - Фильтровать объекты сети по `sheet.viewport.visibleSystemIds`.
  - Вычислять 2D проекцию точек привязки на листе в миллиметрах чертежа.
  - Регистрировать коридоры труб видового экрана как линейные препятствия в масштабе листа.
  - Добавить прямоугольные препятствия запретных зон: штамп (Форма 3: 185×55 мм) и таблицы спецификаций/сварки.
  - Использовать компактный веер радиусов (12, 16, 20, 26, 32 мм) и выравнивание в гребенки с вертикальным шагом `textHeight + 3.0 мм`.
  - Ограничивать координаты границами видового экрана листа со штрафом `100 000` за выход за пределы.
  - Возвращать найденные смещения `Map<String, Offset>` в миллиметрах листа.
- [ ] **Step 3: Проверить через `flutter analyze`**
- [ ] **Step 4: Закоммитить изменения**
  - `git commit -m "feat(layout): implement sheet-aware auto-layout with viewport boundary clamping and stamp protection"`

---

### Task 3: Интерактивное управление и оверрайды на листе в `PipingInputController`

**Files:**
- Modify: `lib/ui/canvas/input_controller.dart`

**Interfaces:**
- `controller.updateCalloutSheetOffset(String calloutId, String sheetId, Offset offset)`
- `controller.resetCalloutSheetOffset(String calloutId, String sheetId)`
- `controller.resetAllSheetCalloutOffsets(String sheetId)`
- `controller.runSheetCalloutAutoLayout(String sheetId)`
- `controller.setSheetCalloutFilter(String sheetId, {Set<CalloutTargetType>? types, bool? showElevations})`

- [ ] **Step 1: Реализовать методы работы с листовыми выносками в `PipingInputController`**
  - `updateCalloutSheetOffset`: записывает новое смещение в `sheetOffsets[sheetId]` выноски, пишет в `history`, уведомляет слушателей.
  - `resetCalloutSheetOffset`: удаляет `sheetOffsets[sheetId]`, возвращая выноску к базовой позиции.
  - `resetAllSheetCalloutOffsets`: очищает оверрайды всех выносок для конкретного листа.
  - `runSheetCalloutAutoLayout`: вызывает `CalloutLayoutEngine.calculateSheetLayout` для активного листа и сохраняет полученные оверрайды в `sheetOffsets[sheetId]`.
  - `setSheetCalloutFilter`: обновляет `enabledCalloutTypes` и `showElevationCallouts` у листа `currentSheet`.
- [ ] **Step 2: Адаптировать перетаскивание выносок (drag)**
  - В методах перетаскивания выноски на холсте: проверять `isModelSpaceActive`.
  - Если мы на листе (`!isModelSpaceActive` и `currentSheetId != null`), перетаскивание обновляет именно `sheetOffsets[currentSheetId]`!
- [ ] **Step 3: Проверить через `flutter analyze`**
- [ ] **Step 4: Закоммитить изменения**
  - `git commit -m "feat(controller): add sheet callout offset overrides, sheet auto-layout, and interactive drag"`

---

### Task 4: Сквозной рендеринг и экспорт (`CalloutPainter`, `SheetCanvasPainter`, `SheetGeometryBuilder`, `PdfExportService`)

**Files:**
- Modify: `lib/ui/canvas/painters/callout_painter.dart`
- Modify: `lib/ui/canvas/sheet_canvas_painter.dart`
- Modify: `lib/domain/services/sheet_geometry_builder.dart`
- Modify: `lib/data/services/pdf_export_service.dart`

- [ ] **Step 1: Обновить `CalloutPainter`**
  - Добавить параметр `String? activeSheetId` в `paint`, `hitTest`, `getCalloutBounds`, `_paintSingleCallout`.
  - Использовать `callout.getEffectiveOffset(activeSheetId)` вместо чистого `screenOffsetX / screenOffsetY`.
- [ ] **Step 2: Обновить `SheetCanvasPainter`**
  - Фильтровать выноски по `sheet.isCalloutVisible(c)`.
  - Передавать `activeSheetId: sheet.id` в `CalloutPainter.paint` и `CalloutPainter.hitTest`.
- [ ] **Step 3: Обновить `SheetGeometryBuilder`**
  - В методе `_buildCallouts`: фильтровать выноски по `sheet.isCalloutVisible(callout)`.
  - Использовать `final effectiveOffset = callout.getEffectiveOffset(sheet.id);`.
- [ ] **Step 4: Обновить `PdfExportService`**
  - Проверить, что `_drawPdfNetworkInViewport` или векторная сцена используют отфильтрованные выноски листа с эффективными смещениями `getEffectiveOffset(sheet.id)`.
- [ ] **Step 5: Проверить через `flutter analyze`**
- [ ] **Step 6: Закоммитить изменения**
  - `git commit -m "feat(render): integrate sheet callout visibility filter and sheetOffsets in SheetCanvasPainter and PDF export"`

---

### Task 5: Пользовательский интерфейс (`SheetToolbar` и инспектор свойств `DesktopCadLayout`)

**Files:**
- Modify: `lib/ui/features/editor/widgets/sheet_toolbar.dart`
- Modify: `lib/ui/features/editor/widgets/desktop_cad_layout.dart`

- [ ] **Step 1: Добавить блок управления выносками в `SheetToolbar`**
  - Кнопка «Выноски листа» с выпадающим диалогом/меню:
    - Индикатор: *«Выносок на листе: X из Y»*.
    - Быстрые кнопки пресетов:
      - «Монтажная схема» (элементы, трубы, арматура, отметки — без сварки).
      - «Схема сварки» (только сварные стыки).
      - «Все» (все категории).
    - Динамический список чекбоксов существующих категорий проекта (`network.getExistingCalloutCategories()`):
      - Имя типа, иконка и бейдж количества (напр., `Сварные стыки (18)`, `Трубы (8)`).
      - Чекбокс «Высотные отметки уровня».
  - Кнопка «Авторасстановка листа» (`Icons.auto_fix_high`):
    - Запускает `controller.runSheetCalloutAutoLayout(currentSheet.id)`.
    - Выводит `SnackBar` с информацией о количестве расставленных выносок.
  - Кнопка «Сбросить выноски листа» (`Icons.restore`).
- [ ] **Step 2: Обновить инспектор выноски в `DesktopCadLayout` (`_buildCalloutInspector`)**
  - Если активен режим листа (`!controller.isModelSpaceActive`):
    - Показывать статус расположения: *«Позиция: Индивидуальная для листа [№1]»* или *«Позиция: Из 3D-модели»*.
    - Если для этого листа задан оверрайд — показывать кнопку «Сбросить к позиции 3D-модели».
- [ ] **Step 3: Проверить через `flutter analyze`**
- [ ] **Step 4: Закоммитить изменения**
  - `git commit -m "feat(ui): add dynamic callout filter menu and sheet auto-layout button to SheetToolbar and CAD inspector"`

---

### Task 6: Финальная валидация, синхронизация и завершение

- [ ] **Step 1: Проверить весь проект через `flutter analyze`** (0 ошибок, 0 предупреждений).
- [ ] **Step 2: Обновить граф знаний через `graphify update .`**
- [ ] **Step 3: Зафиксировать историю в `PROJECT_MEMORY.md`**
- [ ] **Step 4: Отправить коммиты в репозиторий: `git push || git push`**
- [ ] **Step 5: Предоставить отчет пользователю**
