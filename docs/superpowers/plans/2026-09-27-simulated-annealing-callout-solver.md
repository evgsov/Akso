# План реализации: Глобальный оптимизатор расстановки выносок (Dense Simulated Annealing + 1D Spring Align) с отладочным слоем и анимацией

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Разработать интеллектуальный глобальный оптимизатор расстановки выносок на чертежных листах на базе имитации отжига (Simulated Annealing) с плотной $5^\circ$-сеткой направлений, пружинным каскадным выравниванием (1D Spring Align), отладочным визуальным слоем препятствий (Debug Overlay) и плавной анимацией процесса распутывания.

**Architecture:** 
1. `CalloutCandidateGenerator` формирует для каждой выноски пул из 30–50 валидных слотов на основе 64 направлений (шаг $5^\circ$) и радиальных колец (6–35 мм).
2. `SimulatedAnnealingCalloutSolver` производит $30\,000$ быстрых стохастических итераций с быстрым инкрементальным расчетом глобальной энергии чертежа $E$, устраняя все наложения полочек, перехлесты стрелок и коллизии с трубами.
3. `CascadeSpringAligner` производит 1D-пружинное выравнивание соседних полочек в строгие вертикальные каскады («друг под другом») с идеальным шагом строки.
4. `SheetCanvasPainter` получает слой `debugShowObstacles` для подсветки карты препятствий и кандидатов, а `InputController` поддерживает опциональный анимированный расчет.

**Tech Stack:** Dart, Flutter Canvas, CustomPainter, Ticker/Timer animation.

**Spec:** `docs/superpowers/specs/2026-09-27-simulated-annealing-callout-solver-design.md`

## Global Constraints
- Operating System: Windows (pwsh shell).
- Verification Rule: NEVER run `flutter test` or `dart test` directly on Windows (process hangs on hooks). Always verify via `flutter analyze`.
- Push command rule: always run `git push || git push`.
- Sheet Offset Coordinate System: Sheet mm. Projector transforms 3D model coords to sheet mm via `ViewportTransformService.model2dToSheetMm(projector.projectRaw(x, y, z), vp)`. Stored offset: `offsetMm / 0.35`.
- Stamp & Table Protection: Stamp (Форма 3: 185×55 mm in bottom-right corner) and specification tables are absolute forbidden zones.

---

### Task 1: Отладочный визуальный слой препятствий (Debug Canvas Overlay)

**Files:**
- Modify: `lib/domain/models/drawing_sheet.dart` (добавить флаг `debugShowObstacles`)
- Modify: `lib/ui/canvas/sheet_canvas_painter.dart` (отрисовка слоя препятствий в `paint`)
- Modify: `lib/ui/canvas/input_controller.dart` (метод переключения `toggleDebugObstacles`)
- Test: `test/callout_debug_overlay_test.dart`

**Interfaces:**
- Consumes: `CalloutObstacleMap.buildSheetMap`
- Produces: `sheet.debugShowObstacles`, визуальный рендеринг коридоров труб (красные линии), боксов деталей (желтые прямоугольники), штампа и таблиц (пурпурные зоны).

- [ ] **Step 1: Write test for debugShowObstacles flag in DrawingSheet**
  Создать `test/callout_debug_overlay_test.dart`, проверяющий сериализацию/десериализацию и `copyWith` для `debugShowObstacles`.
- [ ] **Step 2: Add debugShowObstacles to DrawingSheet**
  В `lib/domain/models/drawing_sheet.dart` добавить поле `final bool debugShowObstacles;` (по умолчанию `false`), `copyWith`, `toJson`, `fromJson`.
- [ ] **Step 3: Implement debug overlay painting in SheetCanvasPainter**
  В `lib/ui/canvas/sheet_canvas_painter.dart` внутри `paint()` при `sheet.debugShowObstacles == true`:
  Строить `CalloutObstacleMap.buildSheetMap(sheet, network, vp)` и рисовать:
  - Коридоры труб: полупрозрачные красные линии (`strokeWidth = 2.0`, `color = Colors.red.withOpacity(0.3)`);
  - Боксы деталей: полупрозрачные желтые прямоугольники (`Colors.amber.withOpacity(0.35)`);
  - Штамп и таблицы: полупрозрачный фиолетовый (`Colors.purple.withOpacity(0.25)`).
- [ ] **Step 4: Add toggle in InputController**
  В `lib/ui/canvas/input_controller.dart` добавить `void toggleDebugObstacles()`, переключающий флаг на активном листе и вызывающий `notifyListeners()`.
- [ ] **Step 5: Verify with flutter analyze and commit**
  Запустить `flutter analyze`. Закоммитить: `feat: add debugShowObstacles canvas overlay and controller toggle`.

---

### Task 2: Модель слота кандидата и генератор плотного пула (CalloutCandidateGenerator)

**Files:**
- Create: `lib/domain/models/callout_candidate_slot.dart`
- Create: `lib/domain/services/callout_candidate_generator.dart`
- Test: `test/callout_candidate_generator_test.dart`

**Interfaces:**
- Consumes: `CalloutObstacleMap`, `PipingNetwork`, `DrawingSheet`, `SheetViewport`
- Produces: `CalloutCandidateGenerator.generateCandidatePools(sheet, network, vp, obstacleMap) -> Map<String, List<CalloutCandidateSlot>>`

- [ ] **Step 1: Create CalloutCandidateSlot model**
  Создать `lib/domain/models/callout_candidate_slot.dart`:
  - `final Offset entryShelf;`
  - `final Offset shelfEnd;`
  - `final bool isRight;`
  - `final Rect boundingBox;`
  - `final double radius;`
  - `final double angleRad;`
  - `final double localStaticCost;`
- [ ] **Step 2: Write unit test for candidate generator**
  Создать `test/callout_candidate_generator_test.dart`, проверяющий:
  - Генерацию 64 углов (шаг $5^\circ$);
  - Отсев слотов, накладывающихся на штамп или выходящих за границы листа;
  - Отсев слотов, накладывающихся на ось трубы с зазором $< 0.8$ мм.
- [ ] **Step 3: Implement CalloutCandidateGenerator**
  В `lib/domain/services/callout_candidate_generator.dart`:
  - Вычислять размеры выноски с учетом верхнего и нижнего текста (`generateCalloutBottomText`);
  - Генерировать веер углов с шагом $5^\circ$;
  - Проверять радиусы $r \in [6.0, 8.0, 10.0, 12.5, 15.5, 19.0, 23.5, 29.0, 35.0]$ мм;
  - Отсекать слоты с жесткими коллизиями с границами листа, штампом и таблицами;
  - Сортировать и возвращать лучшие 30–50 слотов для каждой выноски.
- [ ] **Step 4: Verify with flutter analyze and commit**
  Запустить `flutter analyze`. Закоммитить: `feat: implement dense 5-degree CalloutCandidateGenerator and slot model`.

---

### Task 3: Глобальный оптимизатор отжига (SimulatedAnnealingCalloutSolver)

**Files:**
- Create: `lib/domain/services/simulated_annealing_callout_solver.dart`
- Test: `test/simulated_annealing_solver_test.dart`

**Interfaces:**
- Consumes: `Map<String, List<CalloutCandidateSlot>> pools`, `CalloutObstacleMap obstacleMap`, `Map<String, Offset> anchors`
- Produces: `SimulatedAnnealingCalloutSolver.solve(pools, obstacleMap, anchors) -> Map<String, CalloutCandidateSlot>`

- [ ] **Step 1: Write unit tests for SimulatedAnnealingCalloutSolver**
  Создать `test/simulated_annealing_solver_test.dart`:
  - Тест на разрешение конфликта между двумя близкими выносками: они должны выбрать слоты, смотрящие в разные стороны или на разных высотах без наложения полок и пересечения стрелок.
  - Тест на сходимость энергии: глобальная энергия $E$ уменьшается в процессе отжига.
- [ ] **Step 2: Implement energy and conflict calculation**
  В `lib/domain/services/simulated_annealing_callout_solver.dart`:
  - Функция конфликта между двумя слотами $i$ и $j$:
    - Наложение полок (`rectA.overlaps(rectB)`): $+100\,000\,000$;
    - Пересечение стрелок (`CalloutObstacleMap.segmentsIntersect(anchorA, entryA, anchorB, entryB)`): $+50\,000\,000$;
    - Пересечение стрелки с полкой: $+30\,000\,000$;
    - Бонус за каскадность (одинаковый $X$ и разнесение по $Y$): $-50.0$.
  - Проверка пересечения стрелки слота с трубами сети: $+2\,000\,000$.
- [ ] **Step 3: Implement Simulated Annealing loop**
  - Инициализация случайными слотами из пула;
  - Расчет базовой энергии $E$;
  - Цикл охлаждения: $T = 1000.0 \dots 0.1$, $30\,000$ итераций;
  - На каждом шаге: выбирается случайная выноска, выбирается новый слот, вычисляется инкрементальный $\Delta E$;
  - Если $\Delta E < 0$ или $\text{random}() < \exp(-\Delta E / T)$ — принимаем изменение;
  - Возврат наилучшей зафиксированной конфигурации $S_{best}$.
- [ ] **Step 4: Verify with flutter analyze and commit**
  Запустить `flutter analyze`. Закоммитить: `feat: implement SimulatedAnnealingCalloutSolver with incremental energy function`.

---

### Task 4: 1D-пружинное каскадное выравнивание (CascadeSpringAligner) и интеграция в движок

**Files:**
- Create: `lib/domain/services/cascade_spring_aligner.dart`
- Modify: `lib/domain/services/callout_layout_engine.dart` (добавить вызов глобального SA-решателя в `calculateSheetLayout`)
- Test: `test/cascade_spring_aligner_test.dart`
- Test: `test/simulated_annealing_integration_test.dart`

**Interfaces:**
- Consumes: Результат `SimulatedAnnealingCalloutSolver`
- Produces: Идеально выровненные по вертикали каскады полочек с одинаковым шагом строки `pitch`

- [ ] **Step 1: Write test for CascadeSpringAligner**
  Создать `test/cascade_spring_aligner_test.dart`:
  - Проверить, что 3 выноски с близкими $X$-координатами выравниваются строго под одной вертикальной чертой ($X_1 = X_2 = X_3$) с шагом $\Delta Y$.
- [ ] **Step 2: Implement CascadeSpringAligner**
  В `lib/domain/services/cascade_spring_aligner.dart`:
  - Находить группы полочек в окрестности $|\Delta X| \le 4.0$ мм с одинаковым направлением полочки (`isRight`);
  - Вычислять единый $X_{\text{cascade}} = \text{median}(X_i)$;
  - Равномерно упорядочивать их по вертикали с шагом $\Delta Y_{\text{pitch}} = \text{textHeight} \times 2.1$.
- [ ] **Step 3: Integrate with CalloutLayoutEngine.calculateSheetLayout**
  В `lib/domain/services/callout_layout_engine.dart`:
  - Добавить ветку вызова глобального решателя:
    `CalloutCandidateGenerator` $\to$ `SimulatedAnnealingCalloutSolver` $\to$ `CascadeSpringAligner`;
  - Сохранять вычисленные смещения в `sheetOffsets` листа чертежа: `Offset(dxMm / 0.35, dyMm / 0.35)`.
- [ ] **Step 4: Verify with flutter analyze and commit**
  Запустить `flutter analyze`. Закоммитить: `feat: implement CascadeSpringAligner and integrate SA solver into CalloutLayoutEngine`.

---

### Task 5: UI Интеграция, Анимация процесса, Документация и Пуш

**Files:**
- Modify: `lib/ui/canvas/widgets/sheet_toolbar.dart` (добавить пункты «Умная оптимизация» и «Сетка препятствий»)
- Modify: `lib/ui/canvas/input_controller.dart` (добавить метод анимированного решения `runAnimatedSheetCalloutOptimization`)
- Modify: `PROJECT_MEMORY.md`
- Test: ручная проверка и `flutter analyze`

**Interfaces:**
- Consumes: `InputController`, `SimulatedAnnealingCalloutSolver`
- Produces: Кнопки в UI и плавная анимация отжига на холсте

- [ ] **Step 1: Add animated solver execution in InputController**
  В `lib/ui/canvas/input_controller.dart` добавить метод `runAnimatedSheetCalloutOptimization(String sheetId)`:
  - Запускает SA-решатель батчами по 1000 итераций с `Timer.periodic(Duration(milliseconds: 30))` (30 кадров $\approx 1$ сек);
  - На каждом шаге обновляет промежуточные смещения выносок и вызывает `notifyListeners()`;
  - По завершении применяет `CascadeSpringAligner` и финально фиксирует результат.
- [ ] **Step 2: Add UI actions in SheetToolbar**
  В `lib/ui/canvas/widgets/sheet_toolbar.dart`:
  - В меню авторасстановки добавить пункт: *«Умная оптимизация (с анимацией)»*;
  - В меню вида добавить тумблер: *«Сетка препятствий (Debug)»*.
- [ ] **Step 3: Update documentation and graphify**
  - Обновить `PROJECT_MEMORY.md` описанием архитектуры глобального отжига и отладочного слоя;
  - Запустить `graphify update .`.
- [ ] **Step 4: Final verification and push**
  - Запустить `flutter analyze` (0 ошибок, 0 замечаний);
  - Закоммитить: `feat: UI integration and animation for Simulated Annealing callout solver`;
  - Запушить: `git push || git push`.
