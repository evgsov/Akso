# Дизайн-документ: Адаптивные листовые выноски, динамический фильтр категорий и листовая авторасстановка

**Дата:** 26 сентября 2026 г.  
**Статус:** Согласован с пользователем, готов к разработке плана  
**Область:** Доменные модели (`Callout`, `DrawingSheet`), алгоритм расстановки (`CalloutLayoutEngine`), интерактивный ввод (`PipingInputController`), рендеринг листа и экспорт PDF (`SheetCanvasPainter`, `SheetGeometryBuilder`, `PdfExportService`), интерфейс (`SheetToolbar`, `DesktopCadLayout`).

---

## 1. Цели и решаемые проблемы

### 1.1. Проблема
- **Скученность выносок на чертежах:** В исполнительной документации и СПДС схемы строго разделяются:
  1. **Монтажная схема (технологическая):** диаметры $D_y$, уклоны, длины катушек, арматура, отметки уровня, оборудование.
  2. **Схема сварных стыков:** номера швов, клейма сварщиков, категории швов по ГОСТ 16037-80.
  Когда все типы выносок включены одновременно, плотность на чертеже превышает допустимую в 3-4 раза.
- **Глобальный пул без контекста листа:** Выноски сейчас хранятся в общем словаре `network.callouts` с единственной парой смещения `(screenOffsetX, screenOffsetY)`. Невозможно сдвинуть выноску на Листе 1 без того, чтобы она не сдвинулась на Листе 2 или в 3D модели.
- **Улёт выносок на «километры»:** Существующий `CalloutLayoutEngine` работает в абстрактных координатах 3D-модели с большими радиусами (до 150 px) и не знает физических границ чертежного листа (`SheetViewport`), расположения штампа (185×55 мм) и примечаний.

### 1.2. Решение
- **Динамический фильтр категорий (без хардкода):** Лист определяет, какие категории выносок на нем отображаются. Фильтр динамически сканирует существующие выноски сети, выводит реально присутствующие категории с количеством элементов (`Сварные стыки (24)`, `Трубы (8)` и т.д.) и предлагает пресеты («Монтажная», «Сварка», «Все», «Пользовательский»).
- **Гибридная модель позиционирования (`sheetOffsets`):** Базовое смещение `(screenOffsetX, screenOffsetY)` используется по умолчанию, но каждый лист чертежа может хранить независимые переопределения `sheetOffsets[sheetId]`.
- **Ручная расстановка на листе:** Перетаскивание выноски мышью/пальцем на чертежном листе обновляет только `sheetOffsets` активного листа.
- **Листовая авторасстановка (Sheet-Aware Auto-Layout):** Авторасстановка для активного листа учитывает масштаб видового экрана, компактный чертежный радиус (12–35 мм бумаги) и физические границы листа за вычетом штампа и таблиц.

---

## 2. Модель данных (Domain Models)

### 2.1. Расширение `Callout` ([lib/domain/models/callout.dart](file:///c:/Budget/Akso/lib/domain/models/callout.dart))
```dart
class Callout {
  // ... существующие поля (id, targetType, targetId, textHeight, screenOffsetX, screenOffsetY, isPinned) ...

  /// Индивидуальные смещения выноски для конкретных листов чертежа (sheetId -> Offset(dx, dy))
  final Map<String, Offset> sheetOffsets;

  /// Получение эффективного смещения с учетом активного листа
  Offset getEffectiveOffset(String? sheetId) {
    if (sheetId != null && sheetOffsets.containsKey(sheetId)) {
      return sheetOffsets[sheetId]!;
    }
    return Offset(screenOffsetX, screenOffsetY);
  }

  /// Эффективный X для указанного листа
  double getEffectiveOffsetX(String? sheetId) => getEffectiveOffset(sheetId).dx;

  /// Эффективный Y для указанного листа
  double getEffectiveOffsetY(String? sheetId) => getEffectiveOffset(sheetId).dy;
}
```
*Сериализация:*
- `toJson`: добавляется `'sheetOffsets': sheetOffsets.map((k, v) => MapEntry(k, {'dx': v.dx, 'dy': v.dy}))`.
- `fromJson`: безопасный парсинг карты, по умолчанию `sheetOffsets = const {}`. Полная обратная совместимость со старыми файлами `.akso`.

### 2.2. Расширение `DrawingSheet` ([lib/domain/models/drawing_sheet.dart](file:///c:/Budget/Akso/lib/domain/models/drawing_sheet.dart))
```dart
class DrawingSheet {
  // ... существующие поля (id, name, sheetNumber, format, viewport, tables, etc.) ...

  /// Разрешенные категории выносок на листе (null = показывать все)
  final Set<CalloutTargetType>? enabledCalloutTypes;

  /// Показывать ли высотные отметки на этом листе (по умолчанию true)
  final bool showElevationCallouts;
}
```
- Метод `bool isCalloutVisible(Callout callout)`:
  1. Если `callout.elevationStyle != null` и `!showElevationCallouts` -> `false`.
  2. Если `enabledCalloutTypes != null && !enabledCalloutTypes!.contains(callout.targetType)` -> `false`.
  3. Иначе `true`.

---

## 3. Динамический сбор существующих категорий (Dynamic Categories)

Вместо жестко закодированного списка категорий, система динамически инспектирует проект:
```dart
class CalloutCategoryStats {
  final CalloutTargetType type;
  final int count;
  final bool isElevationOnly;

  const CalloutCategoryStats({required this.type, required this.count, this.isElevationOnly = false});
}

extension PipingNetworkCalloutExt on PipingNetwork {
  /// Возвращает статистику только по реально существующим в проекте категориям выносок
  List<CalloutCategoryStats> getExistingCalloutCategories() {
    final counts = <CalloutTargetType, int>{};
    for (final c in callouts.values) {
      counts[c.targetType] = (counts[c.targetType] ?? 0) + 1;
    }
    return counts.entries
        .map((e) => CalloutCategoryStats(type: e.key, count: e.value))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
  }
}
```
*В UI:* пользователь видит чекбоксы только для тех категорий, которые реально есть в его проекте, со счетчиками элементов (например: `☑ Сварные стыки (18)`, `☑ Трубы (12)`, `☑ Арматура (4)`).

---

## 4. Листовая авторасстановка (Sheet-Aware Auto-Layout)

В `CalloutLayoutEngine` ([lib/domain/services/callout_layout_engine.dart](file:///c:/Budget/Akso/lib/domain/services/callout_layout_engine.dart)) добавляется метод:

```dart
static Map<String, Offset> calculateSheetLayout({
  required DrawingSheet sheet,
  required PipingNetwork network,
  required AxonometryProjector projector,
  bool onlyUnpinned = true,
  DrawingStyleConfig styleConfig = const DrawingStyleConfig(),
})
```

### Алгоритм:
1. **Отбор выносок листа:**
   - Фильтруются выноски по `sheet.isCalloutVisible(callout)`.
   - Проверяется принадлежность объекта к видимым системам листа `sheet.viewport.visibleSystemIds`.
2. **Координатное пространство чертежа (мм бумаги):**
   - Точки привязки проецируются на лист с учетом `sheet.viewport`:
     `anchorMm = _projectToSheet(anchor3D, projector, sheet.viewport)`.
   - Препятствия труб вычисляются в миллиметрах листа.
3. **Ограничивающий контур и запретные зоны (Keep-out Zones):**
   - Зона видового экрана: `[xMm, yMm, widthMm, heightMm]`.
   - Штамп ГОСТ (Форма 3): `[widthPaper - 185 - 5, heightPaper - 55 - 5, 185, 55]` (запретная зона для полочек выносок).
   - Встроенные таблицы (`sheet.tables`): габариты спецификации или журнала сварки также регистрируются как прямоугольные препятствия.
4. **Компактный веер и гребенки:**
   - Радиусы веера в миллиметрах: `[12.0, 16.0, 20.0, 26.0, 32.0] мм`.
   - Приоритет естественных направлений чертежа (вверх-вправо под 45°/30°).
   - Штраф за выход за пределы видового экрана: `100 000` (абсолютный запрет).
   - Выравнивание полочек в колонки (вертикальный шаг `textHeight + 3.0 мм`).
5. **Сохранение:**
   - Полученные смещения сохраняются в `sheetOffsets[sheet.id]`.

---

## 5. Интерактивная ручная подгонка на листе

1. **Захват и перетаскивание на холсте листа (`SheetCanvasPainter` / `InputController`):**
   - При взаимодействии на листе (`isModelSpaceActive == false`), если пользователь тянет полку выноски:
     ```dart
     void updateCalloutOffsetForActiveSheet(String calloutId, Offset offset) {
       final sheetId = activeSheetId;
       if (sheetId == null) {
         updateCalloutOffset(calloutId, offset);
         return;
       }
       final callout = network.callouts[calloutId];
       if (callout == null) return;
       final newOffsets = Map<String, Offset>.from(callout.sheetOffsets);
       newOffsets[sheetId] = offset;
       network.callouts[calloutId] = callout.copyWith(sheetOffsets: newOffsets);
       history.recordState(network);
       notifyListeners();
     }
     ```
2. **Инспектор свойств ([DesktopCadLayout](file:///c:/Budget/Akso/lib/ui/features/editor/widgets/desktop_cad_layout.dart)):**
   - При активном листе отображается плашка:
     - `Лист: [Имя листа]`
     - Кнопка `Сбросить положение на листе` (удаляет ключ `activeSheetId` из `sheetOffsets`, возвращая выноску к базовой 3D-позиции).

---

## 6. Пользовательский интерфейс (UI)

### 6.1. Тулбар листа (`SheetToolbar`)
В тулбар листа добавляется секция управления выносками:
1. **Кнопка-меню «Выноски листа» (`Icons.filter_list` / `Icons.label_outline`):**
   - Заголовок с индикатором: *«Выносок на листе: X из Y»*.
   - **Быстрые пресеты в один клик:**
     - `Монтажная схема` (автоматически включает все категории, кроме сварки).
     - `Схема сварки` (включает только сварные стыки).
     - `Все` (включает все существующие категории).
   - **Динамический список чекбоксов:**
     - Итерирует `network.getExistingCalloutCategories()`.
     - Показывает значок категории, имя и счетчик.
     - Чекбокс «Высотные отметки уровня».
2. **Кнопка «Авторасстановка листа» (`Icons.auto_fix_high`):**
   - Запускает `calculateSheetLayout` для активного листа.
   - Показывает `SnackBar`: *«Расставлено X выносок в границах листа»*.
3. **Кнопка «Сброс выносок листа» (`Icons.restore`):**
   - Очищает `sheetOffsets` текущего листа, возвращая к исходным положениям.

---

## 7. Сквозная синхронизация рендеринга и экспорта

1. **`SheetCanvasPainter`:**
   - Отображает только выноски, удовлетворяющие `sheet.isCalloutVisible(c)`.
   - Берет смещение через `c.getEffectiveOffset(sheet.id)`.
2. **`SheetGeometryBuilder`:**
   - При построении `VectorScene` для листа фильтрует выноски по `sheet.isCalloutVisible(c)` и применяет `c.getEffectiveOffset(sheet.id)`.
3. **`PdfExportService`:**
   - При экспорте в PDF схема в точности соответствует тому, что видит пользователь на экране листа.

---

## 8. План валидации и тестирования

1. **Юнит-тесты модели данных:**
   - Сериализация и десериализация `Callout.sheetOffsets` (включая обратную совместимость старых файлов без этого поля).
   - Сериализация и десериализация `DrawingSheet.enabledCalloutTypes` и `showElevationCallouts`.
2. **Юнит-тесты фильтрации и динамических категорий:**
   - Проверка извлечения существующих категорий из сети.
   - Проверка метода `sheet.isCalloutVisible(callout)`.
3. **Юнит-тесты алгоритма листовой авторасстановки:**
   - Проверка, что выноски не выходят за границы `SheetViewport`.
   - Проверка, что полочки выносок не пересекают штамп 185×55 мм.
   - Проверка раздельной расстановки (на листе монтажа нет стыков, на листе сварки нет диаметров).
4. **Статический анализ:**
   - `flutter analyze` — 0 ошибок и предупреждений.
