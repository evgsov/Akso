# Адаптивные умные выноски (Adaptive Smart Callouts) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Реализовать физически корректную и гибкую систему масштабирования умных выносок (Smart Callouts) в миллиметрах чертежного листа с возможностью произвольной ручной настройки высоты текста (2.1 мм, 2.3 мм, 3.5 мм и т.д.), динамической адаптации в 3D и устранением бага раздувания ножек в видовых экранах и PDF.

**Architecture:** 
1. Перевод базовой единицы `Callout.textHeight` из сырых пикселей в физические миллиметры листа бумаги (по умолчанию 2.5 мм, с поддержкой любых дробных значений вроде 2.1, 2.3 мм и миграцией старых файлов).
2. Нормализация экранного смещения выносок на листе бумаги в диапазоне 10–25 мм листа вместо раздувания в 25–50 раз формулой `1.0 / (vp.viewScale * 4.0)`.
3. Разделение рендеринга `CalloutPainter`: на листе бумаги (`SheetCanvasPainter`) рендеринг строго в масштабе листа (`textHeight * sheetZoom`), а в 3D-пространстве (`PipingCanvas`) адаптивный экранный размер с защитой от гигантских «транспарантов» при отдалении камеры.
4. Экспорт в PDF со строгим пересчетом миллиметров в типографские пункты ($1 \text{ мм} = 2.83465 \text{ pt}$).
5. Пользовательский интерфейс: добавление настройки высоты шрифта (мм) в диалог редактирования выноски, в таблицу менеджера выносок и создание карточки инспектора выбранной выноски в боковой панели CAD.

**Tech Stack:** Flutter, Dart, PDF package, CustomPainter.

## Global Constraints
- DO NOT run `flutter test` or `dart test` on Windows (hangs due to native assets hook). Use `flutter analyze` for verification.
- Always use `git push || git push`.
- All UI labels in Russian, conforming to CAD/СПДС conventions.

---

### Task 1: Доменная модель Callout и миграция legacy textHeight

**Files:**
- Modify: `lib/domain/models/callout.dart`
- Modify: `lib/domain/models/piping_network.dart:3350-3460`

- [ ] **Step 1: Обновить модель `Callout`**
  - Установить значение по умолчанию `textHeight = 2.5` (мм бумаги вместо legacy 12.0 px).
  - В `Callout.fromJson`: если значение `textHeight >= 10.0` (старые проекты с дефолтными 12.0), автоматически мигрировать в `2.5` мм. Если значение меньше 10 (например, 2.1, 2.3, 3.5) — сохранять точное пользовательское значение.
  - В `piping_network.dart` в `generateMissingCallouts`: изменить дефолтное `textHeight` с `12.0` на `2.5` мм.
- [ ] **Step 2: Проверить компиляцию**
  - Выполнить `flutter analyze`.
- [ ] **Step 3: Закоммитить изменения**
  - `git commit -m "feat(callout): migrate callout textHeight to millimeters with legacy compatibility"`

---

### Task 2: Исправление масштабирования ножек и полочек на листе и в PDF

**Files:**
- Modify: `lib/domain/services/sheet_geometry_builder.dart:925-975`
- Modify: `lib/data/services/pdf_export_service.dart:535-635`

- [ ] **Step 1: Исправить формулу смещения выноски в `SheetGeometryBuilder`**
  - Заменить ошибочную формулу `final offsetScale = 1.0 / (vp.viewScale * 4.0);` на фиксированную нормализацию смещения на листе бумаги:
    `final offsetScale = 0.35;` (что переводит 50 px 3D-смещения в эргономичные 17.5 мм на листе бумаги).
  - Использовать `callout.textHeight` для расчета длины полки:
    `double shelfLengthMm = math.max(8.0, topText.length * (callout.textHeight * 0.65) + 3.0);`
- [ ] **Step 2: Исправить рендеринг выносок в `PdfExportService`**
  - Заменить `final offsetScale = 1.0 / (vp.viewScale * 4.0);` на `final offsetScale = 0.35;`.
  - Заменить жестко зашитые размеры шрифтов `fontSize: 6.5` и `fontSize: 5.5` на физически точный расчет из `callout.textHeight`:
    - Основной текст: `fontSize: callout.textHeight * 2.83465` (1 мм = 2.83465 pt). Например, 2.3 мм = 6.52 pt, 3.5 мм = 9.92 pt.
    - Дополнительный текст (под полкой): `fontSize: (callout.textHeight * 0.85) * 2.83465`.
    - Вертикальное позиционирование текста над/под полкой рассчитать от `callout.textHeight`.
- [ ] **Step 3: Проверить компиляцию**
  - Выполнить `flutter analyze`.
- [ ] **Step 4: Закоммитить изменения**
  - `git commit -m "fix(callout): correct viewport and PDF callout offset scaling and mm-to-pt font sizes"`

---

### Task 3: Раздельный рендеринг в CalloutPainter для листа и 3D-сцены

**Files:**
- Modify: `lib/ui/canvas/painters/callout_painter.dart`
- Modify: `lib/ui/canvas/sheet_canvas_painter.dart:1003-1015`
- Modify: `lib/ui/canvas/piping_canvas.dart:224-234`

- [ ] **Step 1: Обновить `CalloutPainter.paint` и `_paintSingleCallout`**
  - Добавить параметр `bool isPaperSpace = false`.
  - В режиме `isPaperSpace == true` (на чертежном листе):
    - `fontSize = callout.textHeight * annotationScale;` (где `annotationScale` равен `sheetZoom`).
    - Толщина линий: `math.max(0.8, 0.25 * annotationScale)`.
    - Высота флажка отметки: `(callout.textHeight * 2.0) * annotationScale`.
    - Смещение: `Offset(callout.screenOffsetX * 0.35 * annotationScale, callout.screenOffsetY * 0.35 * annotationScale)`.
  - В режиме `isPaperSpace == false` (3D-холст модели):
    - Базовый размер на экране: `fontSize = (callout.textHeight * 4.2) * annotationScale;`.
    - Динамическая адаптация при зуме: ограничить минимальный и максимальный экранный размер, чтобы при сильном отдалении выноски не закрывали всю модель.
- [ ] **Step 2: Обновить вызовы в `sheet_canvas_painter.dart` и `piping_canvas.dart`**
  - В `sheet_canvas_painter.dart`: передать `isPaperSpace: true` и `annotationScale: sheetZoom`.
  - В `piping_canvas.dart`: передать `isPaperSpace: false`.
- [ ] **Step 3: Проверить компиляцию**
  - Выполнить `flutter analyze`.
- [ ] **Step 4: Закоммитить изменения**
  - `git commit -m "feat(callout): split callout painter into paper-space and model-space adaptive rendering"`

---

### Task 4: UI управления высотой выносок (ручная правка 2.1, 2.3 мм и панель инспектора)

**Files:**
- Modify: `lib/ui/canvas/input_controller.dart`
- Modify: `lib/ui/features/editor/widgets/callout_manager_panel.dart:1050-1205`
- Modify: `lib/ui/features/editor/widgets/desktop_cad_layout.dart`

- [ ] **Step 1: Добавить метод `updateCalloutTextHeight` в `PipingInputController`**
  - `void updateCalloutTextHeight(String calloutId, double textHeightMm)`:
    - Обновляет `callout.copyWith(textHeight: textHeightMm)`.
    - Записывает состояние в `history.recordState(network)`.
    - Вызывает `notifyListeners()`.
- [ ] **Step 2: Расширить диалог редактирования выноски `_showEditCalloutDialog` в `CalloutManagerPanel`**
  - Добавить поле ввода `TextField` для высоты шрифта (мм):
    - Начальное значение: `callout.textHeight.toString()`.
    - Кнопки быстрых пресетов: `[2.1, 2.3, 2.5, 3.0, 3.5]`.
    - Сохранение введенного значения в контроллер.
  - В таблицу выносок добавить колонку/индикатор текущей высоты шрифта (например, `2.3 мм`).
- [ ] **Step 3: Добавить инспектор свойств выноски в `desktop_cad_layout.dart`**
  - Когда на холсте выбрана выноска (`controller.selectedCalloutId != null`):
    - Отображать в правой панели блок «Параметры выноски»:
      - Название цели (сегмент, задвижка, отметка и т.д.).
      - Быстрое поле ввода высоты текста (мм) с шагом `0.1` и быстрыми кнопками `2.1`, `2.3`, `2.5`, `3.5`.
      - Переключатель направления полки (Влево / Вправо / Авто).
      - Кнопка фиксации позиции (Pin).
- [ ] **Step 4: Проверить компиляцию и отсутствие ошибок**
  - Выполнить `flutter analyze`.
- [ ] **Step 5: Закоммитить изменения**
  - `git commit -m "feat(ui): add manual textHeight mm editing and callout property inspector"`

---

### Task 5: Финальная валидация, синхронизация и проверка

- [ ] **Step 1: Проверить проект через `flutter analyze`**
  - Убедиться в 0 errors / 0 warnings.
- [ ] **Step 2: Запустить `graphify update .`**
- [ ] **Step 3: Отправить коммиты на сервер**
  - Выполнить `git push || git push`.
